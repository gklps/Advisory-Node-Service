package examples

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// AdvisoryNodeClient provides methods to interact with the Advisory Node service
type AdvisoryNodeClient struct {
	BaseURL string
	Client  *http.Client
}

// NewAdvisoryNodeClient creates a new client for the Advisory Node
func NewAdvisoryNodeClient(baseURL string) *AdvisoryNodeClient {
	return &AdvisoryNodeClient{
		BaseURL: baseURL,
		Client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// QuorumRegistration represents the registration request
type QuorumRegistration struct {
	DID     string  `json:"did"`
	PeerID  string  `json:"peer_id"`
	Balance float64 `json:"balance"`
	DIDType int     `json:"did_type"`
}

// QuorumListResponse represents the response with available quorums
type QuorumListResponse struct {
	Status  bool         `json:"status"`
	Message string       `json:"message"`
	Quorums []QuorumData `json:"quorums"`
}

// QuorumData represents individual quorum data
type QuorumData struct {
	Type    int    `json:"type"`
	Address string `json:"address"`
}

// RegisterQuorum registers a new quorum with the advisory node
func (c *AdvisoryNodeClient) RegisterQuorum(did, peerID string, balance float64, didType int) error {
	registration := QuorumRegistration{
		DID:     did,
		PeerID:  peerID,
		Balance: balance,
		DIDType: didType,
	}

	jsonData, err := json.Marshal(registration)
	if err != nil {
		return fmt.Errorf("failed to marshal registration: %v", err)
	}

	resp, err := c.Client.Post(
		c.BaseURL+"/api/quorum/register",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return fmt.Errorf("failed to register quorum: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("registration failed with status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// ConfirmAvailability confirms that a quorum is available
func (c *AdvisoryNodeClient) ConfirmAvailability(did string) error {
	reqBody := map[string]string{"did": did}
	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %v", err)
	}

	resp, err := c.Client.Post(
		c.BaseURL+"/api/quorum/confirm-availability",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return fmt.Errorf("failed to confirm availability: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("confirmation failed with status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// GetAvailableQuorums retrieves available quorums from the advisory node
func (c *AdvisoryNodeClient) GetAvailableQuorums(count int, lastCharTID string) ([]string, error) {
	url := fmt.Sprintf("%s/api/quorum/available?count=%d", c.BaseURL, count)
	if lastCharTID != "" {
		url += "&last_char_tid=" + lastCharTID
	}

	resp, err := c.Client.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to get quorums: %v", err)
	}
	defer resp.Body.Close()

	var result QuorumListResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %v", err)
	}

	if !result.Status {
		return nil, fmt.Errorf("failed to get quorums: %s", result.Message)
	}

	// Extract addresses
	addresses := make([]string, len(result.Quorums))
	for i, q := range result.Quorums {
		addresses[i] = q.Address
	}

	return addresses, nil
}

// UpdateHeartbeat sends a heartbeat for a quorum
func (c *AdvisoryNodeClient) UpdateHeartbeat(did string) error {
	reqBody := map[string]string{"did": did}
	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %v", err)
	}

	resp, err := c.Client.Post(
		c.BaseURL+"/api/quorum/heartbeat",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return fmt.Errorf("failed to update heartbeat: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("heartbeat failed with status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// UnregisterQuorum removes a quorum from the advisory node
func (c *AdvisoryNodeClient) UnregisterQuorum(did string) error {
	req, err := http.NewRequest(
		"DELETE",
		c.BaseURL+"/api/quorum/unregister/"+did,
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to create request: %v", err)
	}

	resp, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to unregister quorum: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("unregistration failed with status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// Example usage for RubixGo platform integration
func ExampleIntegration() {
	// Create client
	client := NewAdvisoryNodeClient("http://localhost:8080")

	// Example 1: Register a quorum when node starts
	did := "bafybmi123456789012345678901234567890123456789012345678901234"
	peerID := "12D3KooWExample"
	
	err := client.RegisterQuorum(did, peerID, 0, 1)
	if err != nil {
		fmt.Printf("Failed to register quorum: %v\n", err)
		return
	}
	fmt.Println("Quorum registered successfully")

	// Example 2: Confirm availability during setupquorum
	err = client.ConfirmAvailability(did)
	if err != nil {
		fmt.Printf("Failed to confirm availability: %v\n", err)
		return
	}
	fmt.Println("Availability confirmed")

	// Example 3: Get quorums for transaction
	quorums, err := client.GetAvailableQuorums(7, "")
	if err != nil {
		fmt.Printf("Failed to get quorums: %v\n", err)
		return
	}
	fmt.Printf("Retrieved %d quorums: %v\n", len(quorums), quorums)

	// Example 4: Start heartbeat goroutine
	go func() {
		ticker := time.NewTicker(2 * time.Minute)
		defer ticker.Stop()

		for range ticker.C {
			if err := client.UpdateHeartbeat(did); err != nil {
				fmt.Printf("Heartbeat failed: %v\n", err)
			}
		}
	}()
}

// RubixGoQuorumManager shows how to replace the existing GetQuorum function
type RubixGoQuorumManager struct {
	advisoryClient *AdvisoryNodeClient
}

// NewRubixGoQuorumManager creates a new quorum manager that uses the advisory node
func NewRubixGoQuorumManager(advisoryNodeURL string) *RubixGoQuorumManager {
	return &RubixGoQuorumManager{
		advisoryClient: NewAdvisoryNodeClient(advisoryNodeURL),
	}
}

// GetQuorum replaces the original database-based GetQuorum function
func (m *RubixGoQuorumManager) GetQuorum(t int, lastCharTID string, selfPeer string) []string {
	// Determine count based on type
	count := 7 // Default for most operations
	
	// Get quorums from advisory node
	quorums, err := m.advisoryClient.GetAvailableQuorums(count, lastCharTID)
	if err != nil {
		fmt.Printf("Failed to get quorums from advisory node: %v\n", err)
		return nil
	}

	return quorums
}