package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

func main() {
	// Database must be ready before any requests are accepted.
	if err := initDB(); err != nil {
		log.Fatalf("database init failed: %v", err)
	}

	hub := newHub()
	go hub.Run()

	mux := http.NewServeMux()

	// POST /register — create a new user account.
	// Body: {"username": "...", "password": "..."}
	mux.HandleFunc("POST /register", handleRegister)

	// POST /login — verify credentials and return a JWT.
	// Body: {"username": "...", "password": "..."}
	// Response: {"token": "<jwt>"}
	mux.HandleFunc("POST /login", handleLogin)

	// /ws — WebSocket upgrade endpoint.
	// Query params: token=<jwt>&room_id=<id>[&handoff=true]
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		serveWs(hub, w, r)
	})

	// GET /channels/{id}/messages — return up to 100 persisted chat messages.
	// Requires: Authorization: Bearer <jwt>
	mux.HandleFunc("GET /channels/{id}/messages", handleGetMessages)

	// POST /channels/{id}/messages — persist a chat message from a text channel.
	// Requires: Authorization: Bearer <jwt>
	// Body: {"content": "...", "sender_name": "..."}
	mux.HandleFunc("POST /channels/{id}/messages", handlePostMessage)

	// GET /presence — returns current voice channel occupancy as {roomID: [userID, ...]}.
	// Requires: Authorization: Bearer <jwt>
	mux.HandleFunc("GET /presence", func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if len(authHeader) < 8 || authHeader[:7] != "Bearer " {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		if _, _, err := validateToken(authHeader[7:]); err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		presence := hub.GetVoicePresence()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(presence)
	})

	// /health — lightweight liveness probe (no auth required).
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	addr := os.Getenv("ADDR")
	if addr == "" {
		addr = "0.0.0.0:8080"
	}

	log.Printf("rapid_cord signaling server — listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

// authRequest is the JSON body expected by /register and /login.
type authRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	var req authRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	if err := RegisterUser(req.Username, req.Password); err != nil {
		// Map all insertion errors to 409 — avoids leaking DB internals
		// while still signalling a username conflict to the client.
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	var req authRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	token, err := LoginUser(req.Username, req.Password)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"token": token})
}

func handleGetMessages(w http.ResponseWriter, r *http.Request) {
	// Validate JWT from the Authorization: Bearer <token> header.
	authHeader := r.Header.Get("Authorization")
	if len(authHeader) < 8 || authHeader[:7] != "Bearer " {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	if _, _, err := validateToken(authHeader[7:]); err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	channelID := r.PathValue("id")
	if channelID == "" {
		http.Error(w, "missing channel id", http.StatusBadRequest)
		return
	}

	msgs, err := GetChannelMessages(channelID, 100)
	if err != nil {
		log.Printf("handleGetMessages: %v", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	// Return an empty JSON array instead of null when there are no messages.
	if msgs == nil {
		msgs = []StoredMessage{}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(msgs)
}

func handlePostMessage(w http.ResponseWriter, r *http.Request) {
	// Validate JWT.
	authHeader := r.Header.Get("Authorization")
	if len(authHeader) < 8 || authHeader[:7] != "Bearer " {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	senderID, senderName, err := validateToken(authHeader[7:])
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	channelID := r.PathValue("id")
	if channelID == "" {
		http.Error(w, "missing channel id", http.StatusBadRequest)
		return
	}

	var body struct {
		Content    string `json:"content"`
		SenderName string `json:"sender_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Content == "" {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}
	// Prefer the name from the JWT; fall back to what the client supplied.
	name := senderName
	if name == "" {
		name = body.SenderName
	}

	SaveChatMessage(channelID, senderID, name, body.Content)
	w.WriteHeader(http.StatusCreated)
}
