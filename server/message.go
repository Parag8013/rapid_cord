package main

import (
	"encoding/json"
	"time"
)

// Event type constants — the "type" field of every Message envelope.
// The Flutter client and this server both key off these strings.
const (
	// Chat
	EventChatMessage = "chat_message"

	// WebRTC signaling — always targeted (TargetID must be set).
	// The server accepts both the namespaced ("webrtc_offer") and the
	// canonical ("offer") forms so Flutter clients need no extra mapping.
	EventWebRTCOffer  = "webrtc_offer"
	EventWebRTCAnswer = "webrtc_answer"
	EventOffer        = "offer"
	EventAnswer       = "answer"
	EventICECandidate = "ice_candidate"

	// Presence / state
	EventUserJoin   = "user_join"
	EventUserLeave  = "user_leave"
	EventUserMute   = "user_mute"
	EventUserDeafen = "user_deafen"

	// Connection handoff — transfers an active session between isolates.
	// handoff_start   : sender is leaving BUT keep their roster slot alive.
	// handoff_resume  : broadcast to existing peers when the handoff completes,
	//                   so they know to re-negotiate the peer connection.
	EventHandoffStart  = "handoff_start"
	EventHandoffResume = "handoff_resume"

	// WireGuard control-plane events.
	// wg_announce   : client sends its WG public key + virtual IP + endpoint.
	// wg_peer_update: server broadcasts the full WG peer list for the room.
	EventWGAnnounce   = "wg_announce"
	EventWGPeerUpdate = "wg_peer_update"

	// Server → client only.
	EventRoomState = "room_state"
	EventError     = "error"
)

// Message is the canonical wire envelope for all frames exchanged over the
// WebSocket connection.
//
// Routing rules (enforced in Hub.route):
//   - TargetID != "" → unicast to that peer within the same room.
//   - TargetID == "" → broadcast to every client in RoomID.
//
// Payload carries event-specific data as raw JSON so each handler can
// unmarshal only what it needs without a giant discriminated union type.
type Message struct {
	Type      string          `json:"type"`
	RoomID    string          `json:"room_id"`
	SenderID  string          `json:"sender_id,omitempty"`
	TargetID  string          `json:"target_id,omitempty"`
	Payload   json.RawMessage `json:"payload,omitempty"`
	Timestamp time.Time       `json:"timestamp"`
}

// RoomStatePayload is the Payload body for EventRoomState messages.
// It gives a newly joined client a snapshot of existing peers.
type RoomStatePayload struct {
	Members []MemberInfo `json:"members"`
}

// MemberInfo is a point-in-time snapshot of one peer's A/V state.
type MemberInfo struct {
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	Muted    bool   `json:"muted"`
	Deafened bool   `json:"deafened"`
}

// JoinPayload is the Payload body for EventUserJoin messages.
type JoinPayload struct {
	Username string `json:"username"`
}

// ErrorPayload is the Payload body for EventError messages.
type ErrorPayload struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// WGAnnouncePayload is sent by a client to announce its WireGuard identity.
// The server stores these fields on the Client and distributes them to peers.
type WGAnnouncePayload struct {
	WGPubKey       string `json:"wg_pub_key"`
	VirtualIP      string `json:"virtual_ip"`
	PublicEndpoint string `json:"public_endpoint"`
}

// WGPeerInfo describes one WireGuard peer as broadcast by the server.
type WGPeerInfo struct {
	UserID         string `json:"user_id"`
	Username       string `json:"username"`
	WGPubKey       string `json:"wg_pub_key"`
	VirtualIP      string `json:"virtual_ip"`
	PublicEndpoint string `json:"public_endpoint"`
}

// WGPeerUpdatePayload is the Payload body for EventWGPeerUpdate messages.
// It carries the complete peer list for the room so clients can diff against
// their local routing state.
type WGPeerUpdatePayload struct {
	Peers []WGPeerInfo `json:"peers"`
}
