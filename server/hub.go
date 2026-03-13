package main

import (
	"encoding/json"
	"log"
	"time"
)

// handoffKey uniquely identifies a user's slot reservation during a
// connection handoff (window pop-out or pop-in).
type handoffKey struct {
	userID string
	roomID string
}

// Hub is the single source of truth for all room membership and message
// routing. A dedicated goroutine (Run) owns every mutable field, so the
// maps are never accessed from multiple goroutines concurrently — no
// additional locking is required on the hot path.
type Hub struct {
	// rooms maps roomID → the set of clients currently in that room.
	rooms map[string]map[*Client]bool

	// index maps userID → client for O(1) unicast delivery.
	// A user is expected to hold exactly one active session; a second
	// connection with the same userID is rejected (see onRegister).
	index map[string]*Client

	// handoffTimers tracks active handoff grace periods.
	// Key present  → user is mid-handoff; user_leave must be suppressed.
	// Key absent   → normal session.
	handoffTimers map[handoffKey]*time.Timer

	register         chan *Client
	unregister       chan *Client
	broadcast        chan *Message
	handoffTimeoutCh chan handoffKey
	// presenceReqCh is used by GetVoicePresence to safely query h.rooms
	// from outside the Run goroutine without a data race.
	presenceReqCh chan chan map[string][]string
}

func newHub() *Hub {
	return &Hub{
		rooms:            make(map[string]map[*Client]bool),
		index:            make(map[string]*Client),
		handoffTimers:    make(map[handoffKey]*time.Timer),
		register:         make(chan *Client, 16),
		unregister:       make(chan *Client, 16),
		broadcast:        make(chan *Message, 256),
		handoffTimeoutCh: make(chan handoffKey, 16),
		presenceReqCh:    make(chan chan map[string][]string, 8),
	}
}

// Run is the Hub's event loop. Start it exactly once in a dedicated
// goroutine before accepting any connections.
func (h *Hub) Run() {
	for {
		select {
		case c := <-h.register:
			h.onRegister(c)
		case c := <-h.unregister:
			h.onUnregister(c)
		case msg := <-h.broadcast:
			h.route(msg)
		case key := <-h.handoffTimeoutCh:
			h.onHandoffTimeout(key)
		case replyCh := <-h.presenceReqCh:
			// Build presence snapshot inside the Run goroutine so h.rooms is
			// only ever touched by one goroutine at a time (no data race).
			presence := make(map[string][]string, len(h.rooms))
			for roomID, clients := range h.rooms {
				names := make([]string, 0, len(clients))
				for c := range clients {
					name := c.username
					if name == "" {
						name = c.userID
					}
					names = append(names, name)
				}
				presence[roomID] = names
			}
			replyCh <- presence
		}
	}
}

// ── registration ──────────────────────────────────────────────────────────────

func (h *Hub) onRegister(c *Client) {
	key := handoffKey{c.userID, c.roomID}

	// ── Handoff-complete path ────────────────────────────────────────────────
	// The new isolate (pop-out or main window) reconnected after a handoff_start.
	// We skip the duplicate-session check, cancel the timeout, and broadcast
	// handoff_resume instead of user_join so existing peers know to
	// re-negotiate the peer connection without showing a leave/rejoin in the UI.
	if c.isHandoff {
		if t, ok := h.handoffTimers[key]; ok {
			t.Stop()
			delete(h.handoffTimers, key)
		}

		room, ok := h.rooms[c.roomID]
		if !ok {
			room = make(map[*Client]bool)
			h.rooms[c.roomID] = room
		}

		// Snapshot existing peers and send room_state to the new client.
		members := h.snapshotMembers(c.roomID)
		h.sendRoomState(c, members)

		// Tell existing peers to re-negotiate — send BEFORE adding the new
		// client to the room so it does not receive its own handoff_resume.
		h.broadcastToRoom(c.roomID, &Message{
			Type:      EventHandoffResume,
			RoomID:    c.roomID,
			SenderID:  c.userID,
			Timestamp: time.Now().UTC(),
		})

		room[c] = true
		h.index[c.userID] = c

		log.Printf("handoff_complete user=%-20s room=%-16s peers=%d", c.userID, c.roomID, len(room))
		return
	}

	// ── Normal registration path ─────────────────────────────────────────────
	// Reject duplicate sessions within the same room only.
	if existingRoom, ok := h.rooms[c.roomID]; ok {
		for existing := range existingRoom {
			if existing.userID == c.userID {
				log.Printf("reject: user=%s already in room=%s", c.userID, c.roomID)
				h.sendError(c, "DUPLICATE_SESSION", "you are already in this room")
				close(c.send)
				return
			}
		}
	}

	room, ok := h.rooms[c.roomID]
	if !ok {
		room = make(map[*Client]bool)
		h.rooms[c.roomID] = room
	}

	// Snapshot existing peers *before* adding the joiner so the room_state
	// payload only lists pre-existing members.
	members := h.snapshotMembers(c.roomID)

	// 1. Tell the new client who is already present.
	h.sendRoomState(c, members)

	// 2. Announce the arrival to the EXISTING peers only — the joiner must
	//    never receive their own user_join, otherwise the client would treat
	//    itself as a remote peer and attempt to offer/answer with itself.
	//    We do this BEFORE adding the joiner to the room so broadcastToRoom
	//    iterates only the pre-existing members.
	joinPayload, _ := json.Marshal(JoinPayload{Username: c.username})
	joinMsg := &Message{
		Type:      EventUserJoin,
		RoomID:    c.roomID,
		SenderID:  c.userID,
		Payload:   json.RawMessage(joinPayload),
		Timestamp: time.Now().UTC(),
	}
	h.broadcastToRoom(c.roomID, joinMsg)

	// 3. Now add the joiner so they appear in subsequent broadcasts.
	room[c] = true
	h.index[c.userID] = c

	log.Printf("register  user=%-20s room=%-16s peers=%d", c.userID, c.roomID, len(room))
}

func (h *Hub) onUnregister(c *Client) {
	room, ok := h.rooms[c.roomID]
	if !ok {
		return
	}
	if _, member := room[c]; !member {
		return
	}

	delete(room, c)
	// Only evict from the global unicast index if this is still the indexed
	// client. A newer connection in a different room may have overwritten it.
	if h.index[c.userID] == c {
		delete(h.index, c.userID)
	}
	close(c.send)

	if len(room) == 0 {
		delete(h.rooms, c.roomID)
	}

	key := handoffKey{c.userID, c.roomID}
	if _, handoff := h.handoffTimers[key]; handoff {
		// Handoff in progress — keep the user visible in the roster and
		// suppress the user_leave broadcast. The new window will complete
		// the handoff (or the 5 s timer will clean up).
		log.Printf("unregister (handoff) user=%-20s room=%-16s peers=%d", c.userID, c.roomID, len(room))
		return
	}

	log.Printf("unregister user=%-20s room=%-16s peers=%d", c.userID, c.roomID, len(room))

	h.broadcastToRoom(c.roomID, &Message{
		Type:      EventUserLeave,
		RoomID:    c.roomID,
		SenderID:  c.userID,
		Timestamp: time.Now().UTC(),
	})

	// Notify remaining peers to remove this user from their WireGuard
	// routing table. Only fired for a real leave, not during handoffs.
	h.broadcastWGPeers(c.roomID)
}

func (h *Hub) onHandoffTimeout(key handoffKey) {
	if _, ok := h.handoffTimers[key]; !ok {
		// Timer was already stopped during a successful handoff_complete —
		// the timer.Stop() race; just ignore.
		return
	}
	delete(h.handoffTimers, key)
	log.Printf("handoff timeout user=%s room=%s — broadcasting leave", key.userID, key.roomID)
	h.broadcastToRoom(key.roomID, &Message{
		Type:      EventUserLeave,
		RoomID:    key.roomID,
		SenderID:  key.userID,
		Timestamp: time.Now().UTC(),
	})
	// Notify remaining peers to remove this user from their WireGuard
	// routing table.
	h.broadcastWGPeers(key.roomID)
}

// ── message routing ───────────────────────────────────────────────────────────

// route dispatches an inbound message from a client to its destination(s).
//
// Routing policy:
//   - webrtc_offer / webrtc_answer / ice_candidate → unicast to TargetID.
//     These frames contain SDP / ICE data that is only meaningful to one peer.
//   - user_mute / user_deafen → update server-side state, then room broadcast
//     so every peer can reflect the change in its UI.
//   - Everything else (chat_message and any future events) → room broadcast.
func (h *Hub) route(msg *Message) {
	switch msg.Type {
	case EventChatMessage:
		// Persist before broadcasting so history is available immediately.
		var p struct {
			ChannelID  string `json:"channel_id"`
			Content    string `json:"content"`
			SenderName string `json:"sender_name"`
		}
		if err := json.Unmarshal(msg.Payload, &p); err == nil && p.Content != "" {
			SaveChatMessage(p.ChannelID, msg.SenderID, p.SenderName, p.Content)
		}
		h.broadcastToRoom(msg.RoomID, msg)

	case EventUserMute:
		if c, ok := h.index[msg.SenderID]; ok {
			c.muted = muteStateFromPayload(msg.Payload)
		}
		h.broadcastToRoom(msg.RoomID, msg)

	case EventUserDeafen:
		if c, ok := h.index[msg.SenderID]; ok {
			c.deafened = deafenStateFromPayload(msg.Payload)
		}
		h.broadcastToRoom(msg.RoomID, msg)

	// handoff_start: the sender is vacating its connection so a new isolate
	// can take over the session without a visible leave/rejoin in the room.
	// We store a 5 s timer; if no handoff_complete arrives the slot is freed
	// and user_leave is broadcast normally.
	case EventHandoffStart:
		key := handoffKey{msg.SenderID, msg.RoomID}
		// Cancel any pre-existing timer for this user (idempotent).
		if existing, ok := h.handoffTimers[key]; ok {
			existing.Stop()
		}
		t := time.AfterFunc(5*time.Second, func() {
			h.handoffTimeoutCh <- key
		})
		h.handoffTimers[key] = t
		log.Printf("handoff_start user=%s room=%s — 5 s grace period started", msg.SenderID, msg.RoomID)
		// No broadcast — this message stays server-internal.

	// wg_announce: client is declaring its WireGuard identity. Store the
	// fields on the Client, then broadcast the updated peer list to the
	// whole room so every peer can re-sync its routing table.
	case EventWGAnnounce:
		var p WGAnnouncePayload
		if err := json.Unmarshal(msg.Payload, &p); err != nil {
			log.Printf("wg_announce: invalid payload from %s: %v", msg.SenderID, err)
			return
		}
		if c, ok := h.index[msg.SenderID]; ok {
			c.wgPubKey = p.WGPubKey
			c.virtualIP = p.VirtualIP
			c.publicEndpoint = p.PublicEndpoint
		}
		h.broadcastWGPeers(msg.RoomID)

	// Accept both the namespaced form ("webrtc_offer") used internally and
	// the canonical WebRTC form ("offer"/"answer") sent by the Flutter client.
	case EventWebRTCOffer, EventWebRTCAnswer, EventICECandidate, EventOffer, EventAnswer:
		if msg.TargetID == "" {
			log.Printf("warn: %s from %s missing target_id — dropping", msg.Type, msg.SenderID)
			return
		}
		h.unicast(msg)

	default:
		h.broadcastToRoom(msg.RoomID, msg)
	}
}

// broadcastWGPeers gathers WireGuard info for every client in the room that
// has announced a public key, then broadcasts an EventWGPeerUpdate so all
// peers can update their routing tables.
//
// Must only be called from within the Hub.Run goroutine.
func (h *Hub) broadcastWGPeers(roomID string) {
	room, ok := h.rooms[roomID]
	if !ok {
		return
	}
	peers := make([]WGPeerInfo, 0, len(room))
	for c := range room {
		if c.wgPubKey == "" {
			continue
		}
		peers = append(peers, WGPeerInfo{
			UserID:         c.userID,
			Username:       c.username,
			WGPubKey:       c.wgPubKey,
			VirtualIP:      c.virtualIP,
			PublicEndpoint: c.publicEndpoint,
		})
	}
	payload, err := json.Marshal(WGPeerUpdatePayload{Peers: peers})
	if err != nil {
		log.Printf("broadcastWGPeers marshal error: %v", err)
		return
	}
	h.broadcastToRoom(roomID, &Message{
		Type:      EventWGPeerUpdate,
		RoomID:    roomID,
		Payload:   json.RawMessage(payload),
		Timestamp: time.Now().UTC(),
	})
}

// broadcastToRoom delivers msg to every client currently in roomID.
// If a client's send buffer is full it is evicted inline rather than blocking
// the Hub goroutine.
func (h *Hub) broadcastToRoom(roomID string, msg *Message) {
	room, ok := h.rooms[roomID]
	if !ok {
		return
	}
	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("broadcast marshal error: %v", err)
		return
	}
	for c := range room {
		select {
		case c.send <- data:
		default:
			// Slow / unresponsive client: evict immediately.
			log.Printf("evicting slow client user=%s room=%s", c.userID, c.roomID)
			delete(room, c)
			delete(h.index, c.userID)
			close(c.send)
		}
	}
}

// unicast delivers msg exclusively to msg.TargetID within msg.RoomID.
// Searching per-room guarantees correctness when the same userID is connected
// to several rooms at once (e.g. voice + chat).
func (h *Hub) unicast(msg *Message) {
	room, ok := h.rooms[msg.RoomID]
	if !ok {
		log.Printf("unicast: room %q not found (type=%s)", msg.RoomID, msg.Type)
		return
	}
	for c := range room {
		if c.userID == msg.TargetID {
			data, err := json.Marshal(msg)
			if err != nil {
				log.Printf("unicast marshal error: %v", err)
				return
			}
			select {
			case c.send <- data:
			default:
				log.Printf("unicast: buffer full for user=%s — dropping %s", msg.TargetID, msg.Type)
			}
			return
		}
	}
	log.Printf("unicast: target %q not in room %q (type=%s)", msg.TargetID, msg.RoomID, msg.Type)
}

// sendRoomState pushes the current member list directly to a single client.
func (h *Hub) sendRoomState(c *Client, members []MemberInfo) {
	payload, _ := json.Marshal(RoomStatePayload{Members: members})
	msg := &Message{
		Type:      EventRoomState,
		RoomID:    c.roomID,
		Payload:   json.RawMessage(payload),
		Timestamp: time.Now().UTC(),
	}
	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("room_state marshal error: %v", err)
		return
	}
	select {
	case c.send <- data:
	default:
	}
}

// sendError pushes an error frame directly to a single client's send channel.
func (h *Hub) sendError(c *Client, code, message string) {
	payload, _ := json.Marshal(ErrorPayload{Code: code, Message: message})
	msg := &Message{
		Type:      EventError,
		Payload:   json.RawMessage(payload),
		Timestamp: time.Now().UTC(),
	}
	data, _ := json.Marshal(msg)
	select {
	case c.send <- data:
	default:
	}
}

// ── state helpers ─────────────────────────────────────────────────────────────

// snapshotMembers returns the current peer list for a room.
// Must only be called from within the Run goroutine.
func (h *Hub) snapshotMembers(roomID string) []MemberInfo {
	room := h.rooms[roomID] // may be nil for a brand-new room
	members := make([]MemberInfo, 0, len(room))
	for c := range room {
		members = append(members, MemberInfo{
			UserID:   c.userID,
			Username: c.username,
			Muted:    c.muted,
			Deafened: c.deafened,
		})
	}
	return members
}

func muteStateFromPayload(raw json.RawMessage) bool {
	var p struct {
		Muted bool `json:"muted"`
	}
	_ = json.Unmarshal(raw, &p)
	return p.Muted
}

func deafenStateFromPayload(raw json.RawMessage) bool {
	var p struct {
		Deafened bool `json:"deafened"`
	}
	_ = json.Unmarshal(raw, &p)
	return p.Deafened
}

// GetVoicePresence returns a snapshot of every room and the usernames present.
// It is safe to call from any goroutine — the actual map read happens inside
// the Run goroutine via presenceReqCh to avoid data races.
func (h *Hub) GetVoicePresence() map[string][]string {
	replyCh := make(chan map[string][]string, 1)
	h.presenceReqCh <- replyCh
	return <-replyCh
}
