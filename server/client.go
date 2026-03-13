package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

const (
	// writeWait is the maximum time allowed to write a single frame.
	writeWait = 10 * time.Second

	// pongWait is the maximum time between pong replies from the peer.
	// The connection is dropped if no pong arrives within this window.
	pongWait = 60 * time.Second

	// pingPeriod is how often the server sends a ping. Must be < pongWait.
	pingPeriod = (pongWait * 9) / 10

	// maxMessageSize caps inbound frame size. Signaling frames are small;
	// 64 KiB is generous enough for even the largest SDP blobs.
	maxMessageSize = 64 * 1024

	// sendBufSize is the number of outbound frames that can be queued
	// per client before the Hub treats the client as unresponsive.
	sendBufSize = 256
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	// TODO: restrict to trusted origins before production deployment.
	CheckOrigin: func(r *http.Request) bool { return true },
}

// Client is the bridge between a single WebSocket connection and the Hub.
// It owns no mutable shared state; all state mutations flow through the Hub.
type Client struct {
	hub  *Hub
	conn *websocket.Conn

	// send is a buffered channel of outbound serialised JSON frames.
	// The Hub writes here; writePump drains it.
	send chan []byte

	// Immutable after registration.
	userID   string
	username string // human-readable name from the JWT "username" claim
	roomID   string

	// isHandoff is true when the client connected with ?handoff=true.
	// The Hub uses this flag to treat the registration as a handoff-complete
	// rather than a fresh join (no user_join broadcast, no duplicate check).
	isHandoff bool

	// A/V state — written only by Hub.Run via Hub.index, never by the
	// client goroutines themselves.
	muted    bool
	deafened bool

	// WireGuard control-plane fields — set when the client sends wg_announce.
	// Written only by the Hub.Run goroutine via Hub.route.
	wgPubKey       string
	virtualIP      string
	publicEndpoint string
}

// readPump pumps inbound frames from the WebSocket to the Hub's broadcast
// channel. It enforces one reader per connection as required by gorilla.
// When it returns (network error or clean close), it triggers unregistration.
func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		return c.conn.SetReadDeadline(time.Now().Add(pongWait))
	})

	for {
		_, data, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err,
				websocket.CloseGoingAway,
				websocket.CloseAbnormalClosure,
			) {
				log.Printf("ws read error user=%s: %v", c.userID, err)
			}
			return
		}

		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("invalid json from user=%s: %v", c.userID, err)
			continue
		}

		// Overwrite sender/room/time with server-authoritative values so
		// clients cannot spoof each other's identity or timestamps.
		msg.SenderID = c.userID
		msg.RoomID = c.roomID
		msg.Timestamp = time.Now().UTC()

		c.hub.broadcast <- &msg
	}
}

// writePump drains the send channel and writes frames to the WebSocket.
// gorilla requires a single concurrent writer, which this goroutine provides.
//
// As an optimisation, any frames that have accumulated in the send buffer
// while the previous write was in flight are coalesced into one WebSocket
// frame separated by newlines. Receivers should split on '\n' and parse
// each line as an independent JSON object.
func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	newline := []byte{'\n'}

	for {
		select {
		case data, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// Hub closed the channel — send a clean close frame.
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			_, _ = w.Write(data)

			// Drain any additional queued frames into the same write window.
			n := len(c.send)
			for i := 0; i < n; i++ {
				_, _ = w.Write(newline)
				_, _ = w.Write(<-c.send)
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// serveWs upgrades an HTTP request to a WebSocket connection and registers
// the resulting Client with the Hub.
//
// Expected query parameters:
//   - token:   signed JWT issued by POST /login (encodes sub=userID, username).
//   - room_id: the channel or voice room to join.
//   - handoff: optional "true"; treats this connection as the completing half
//     of a handoff rather than a fresh join.
func serveWs(hub *Hub, w http.ResponseWriter, r *http.Request) {
	tokenStr := r.URL.Query().Get("token")
	roomID := r.URL.Query().Get("room_id")

	if tokenStr == "" || roomID == "" {
		http.Error(w, "missing required query params: token, room_id", http.StatusBadRequest)
		return
	}

	userID, username, err := validateToken(tokenStr)
	if err != nil {
		http.Error(w, "unauthorized: "+err.Error(), http.StatusUnauthorized)
		return
	}

	isHandoff := r.URL.Query().Get("handoff") == "true"

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("upgrade error user=%s: %v", userID, err)
		return
	}

	c := &Client{
		hub:       hub,
		conn:      conn,
		send:      make(chan []byte, sendBufSize),
		userID:    userID,
		username:  username,
		roomID:    roomID,
		isHandoff: isHandoff,
	}

	hub.register <- c

	// writePump owns its own goroutine; readPump runs on the current goroutine
	// and blocks until the connection is closed.
	go c.writePump()
	c.readPump()
}
