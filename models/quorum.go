package models

import (
	"time"
)

// DID Types matching RubixGo platform
const (
	BasicDIDMode int = iota
	LiteDIDMode
	ChildDIDMode
	StandardDIDMode
)

// QuorumRegistrationRequest represents the request to register a quorum
type QuorumRegistrationRequest struct {
	DID             string   `json:"did" binding:"required"`
	PeerID          string   `json:"peer_id" binding:"required"`
	Balance         float64  `json:"balance"`
	DIDType         int      `json:"did_type" binding:"required"`
	SupportedTokens []string `json:"supported_tokens"` // List of supported token types (e.g., ["RBT", "TRI"])
}

// QuorumInfo represents a registered quorum with additional metadata
type QuorumInfo struct {
	DID              string    `json:"did"`
	PeerID           string    `json:"peer_id"`
	Balance          float64   `json:"balance"`
	DIDType          int       `json:"did_type"`
	Available        bool      `json:"available"`
	LastPing         time.Time `json:"last_ping"`
	AssignmentCount  int       `json:"assignment_count"`
	LastAssignment   time.Time `json:"last_assignment"`
	RegistrationTime time.Time `json:"registration_time"`
	SupportedTokens  []string  `json:"supported_tokens"` // List of supported token types
}

// QuorumListRequest represents a request to get available quorums
type QuorumListRequest struct {
	Count             int     `json:"count"`              // Number of quorums needed (default 7)
	LastCharTID       string  `json:"last_char_tid"`      // Optional: for type-1 quorum selection
	Type              int     `json:"type"`               // Quorum type (1 or 2)
	TransactionAmount float64 `json:"transaction_amount"` // Transaction amount for balance validation
	FTName            string  `json:"ft_name"`            // Token type for filtering (e.g., "TRI", "RBT")
}

// QuorumListResponse represents the response with available quorums
type QuorumListResponse struct {
	Status  bool         `json:"status"`
	Message string       `json:"message"`
	Quorums []QuorumData `json:"quorums"`
}

// QuorumData represents the quorum data format expected by RubixGo
type QuorumData struct {
	Type    int    `json:"type"`
	Address string `json:"address"` // Format: "PeerID.DID"
}

// ConfirmAvailabilityRequest represents the request to confirm quorum availability
type ConfirmAvailabilityRequest struct {
	DID string `json:"did" binding:"required"`
}

// HealthStatus represents the health status of the advisory node
type HealthStatus struct {
	Status           string    `json:"status"`
	TotalQuorums     int       `json:"total_quorums"`
	AvailableQuorums int       `json:"available_quorums"`
	Uptime           string    `json:"uptime"`
	LastCheck        time.Time `json:"last_check"`
}

// BasicResponse represents a basic API response
type BasicResponse struct {
	Status  bool   `json:"status"`
	Message string `json:"message"`
}
