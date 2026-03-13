package main

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
)

// db is the package-level SQLite connection pool.
// Initialised once by initDB; accessed only from HTTP handler goroutines.
var db *sql.DB

// jwtSecret is loaded from the JWT_SECRET env var.
// Falls back to a development secret so the server starts without extra
// configuration during local testing.
var jwtSecret []byte

// initDB opens (or creates) auth.db, applies recommended pragmas, and
// ensures the users table exists. Call this once before any HTTP handlers
// start accepting requests.
func initDB() error {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "change-me-in-production"
	}
	jwtSecret = []byte(secret)

	var err error
	db, err = sql.Open("sqlite", "./auth.db")
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}

	// WAL mode gives better read concurrency on a low-RAM server; the
	// busy_timeout lets writers retry for 5 s instead of returning SQLITE_BUSY.
	if _, err = db.Exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;`); err != nil {
		return fmt.Errorf("pragma: %w", err)
	}

	// Limit open connections — SQLite serialises writes regardless and a
	// small pool caps memory usage on the 1 GB server.
	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)

	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS users (
		id            INTEGER PRIMARY KEY AUTOINCREMENT,
		username      TEXT    NOT NULL UNIQUE,
		password_hash TEXT    NOT NULL
	)`)
	if err != nil {
		return fmt.Errorf("create users table: %w", err)
	}

	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS messages (
		id          INTEGER  PRIMARY KEY AUTOINCREMENT,
		channel_id  TEXT     NOT NULL,
		sender_id   TEXT     NOT NULL,
		sender_name TEXT     NOT NULL,
		content     TEXT     NOT NULL,
		timestamp   DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
	); CREATE INDEX IF NOT EXISTS idx_messages_channel ON messages(channel_id, id);`)
	if err != nil {
		return fmt.Errorf("create messages table: %w", err)
	}
	return nil
}

// StoredMessage is the shape returned by GetChannelMessages and serialised
// directly to the REST response JSON.
type StoredMessage struct {
	ID         int64  `json:"id"`
	ChannelID  string `json:"channel_id"`
	SenderID   string `json:"sender_id"`
	SenderName string `json:"sender_name"`
	Content    string `json:"content"`
	Timestamp  string `json:"timestamp"`
}

// SaveChatMessage persists a chat message to the database. Errors are logged
// but not propagated — a DB hiccup must not interrupt live WebSocket delivery.
func SaveChatMessage(channelID, senderID, senderName, content string) {
	_, err := db.Exec(
		`INSERT INTO messages (channel_id, sender_id, sender_name, content) VALUES (?, ?, ?, ?)`,
		channelID, senderID, senderName, content,
	)
	if err != nil {
		log.Printf("SaveChatMessage: %v", err)
		return
	}
	log.Printf("[chat] saved   channel=%-20s sender=%-20s msg=%q", channelID, senderName, content)
}

// GetChannelMessages returns up to [limit] messages for the channel ordered
// chronologically (oldest first so the client can append them in order).
func GetChannelMessages(channelID string, limit int) ([]StoredMessage, error) {
	rows, err := db.Query(`
		SELECT id, channel_id, sender_id, sender_name, content,
		       strftime('%Y-%m-%dT%H:%M:%fZ', timestamp) AS ts
		FROM (
			SELECT * FROM messages WHERE channel_id = ?
			ORDER BY id DESC LIMIT ?
		) ORDER BY id ASC`,
		channelID, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("query messages: %w", err)
	}
	defer rows.Close()

	var msgs []StoredMessage
	for rows.Next() {
		var m StoredMessage
		if err := rows.Scan(&m.ID, &m.ChannelID, &m.SenderID, &m.SenderName, &m.Content, &m.Timestamp); err != nil {
			return nil, fmt.Errorf("scan message: %w", err)
		}
		msgs = append(msgs, m)
	}
	return msgs, rows.Err()
}

// RegisterUser hashes the password with bcrypt (cost 10) and inserts a new
// user row. Returns an error if the username is already taken or inputs are
// empty.
func RegisterUser(username, password string) error {
	if username == "" || password == "" {
		return errors.New("username and password are required")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash password: %w", err)
	}
	_, err = db.Exec(
		`INSERT INTO users (username, password_hash) VALUES (?, ?)`,
		username, string(hash),
	)
	if err != nil {
		return fmt.Errorf("insert user: %w", err)
	}
	return nil
}

// LoginUser verifies the supplied password against the stored bcrypt hash.
// On success it returns a signed HS256 JWT that embeds the numeric database
// ID (as "sub") and the username. The token is valid for 30 days.
func LoginUser(username, password string) (string, error) {
	var id int64
	var hash string
	err := db.QueryRow(
		`SELECT id, password_hash FROM users WHERE username = ?`, username,
	).Scan(&id, &hash)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			// Use a constant-time-ish response to avoid username enumeration.
			return "", errors.New("invalid credentials")
		}
		return "", fmt.Errorf("query user: %w", err)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)); err != nil {
		return "", errors.New("invalid credentials")
	}

	claims := jwt.MapClaims{
		"sub":      fmt.Sprintf("%d", id),
		"username": username,
		"exp":      time.Now().Add(30 * 24 * time.Hour).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(jwtSecret)
	if err != nil {
		return "", fmt.Errorf("sign token: %w", err)
	}
	return signed, nil
}

// validateToken parses and validates a JWT string. On success it returns the
// userID (the numeric "sub" claim as a string) and the username claim.
// Used by serveWs to authenticate WebSocket upgrade requests.
func validateToken(tokenStr string) (userID, username string, err error) {
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return jwtSecret, nil
	})
	if err != nil || !token.Valid {
		return "", "", errors.New("invalid or expired token")
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", "", errors.New("invalid token claims")
	}
	sub, ok := claims["sub"].(string)
	if !ok || sub == "" {
		return "", "", errors.New("missing sub claim")
	}
	uname, _ := claims["username"].(string)
	return sub, uname, nil
}
