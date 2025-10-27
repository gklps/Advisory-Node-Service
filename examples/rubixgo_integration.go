package examples

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// RubixGoIntegration shows how to integrate the advisory node with RubixGo platform
// This code should be added to the RubixGo platform codebase

// AdvisoryNodeConfig holds the configuration for advisory node
type AdvisoryNodeConfig struct {
	Enabled bool   `json:"enabled"`
	URL     string `json:"url"`
}

// RegisterQuorumsOnStartup should be called when the RubixGo node starts
// This should be added to the Core initialization in rubixgoplatform/core/core.go
func RegisterQuorumsOnStartup(c *Core, advisoryURL string) error {
	// Check if advisory node is configured
	if advisoryURL == "" {
		c.log.Info("Advisory node not configured, using local quorum management")
		return nil
	}

	// Get all quorum DIDs that this node has setup
	// This reads from the quorummanager table
	var quorumData []QuorumData
	err := c.s.Read(QuorumStorage, &quorumData, "type=?", QuorumTypeTwo)
	if err != nil {
		c.log.Info("No quorums configured on this node")
		return nil
	}

	// For each quorum DID, register with advisory node
	for _, qd := range quorumData {
		// Get DID details to find the type
		dt, err := c.w.GetDID(qd.Address)
		if err != nil {
			c.log.Error("Failed to get DID details", "did", qd.Address)
			continue
		}

		// Prepare registration request
		registration := map[string]interface{}{
			"did":      qd.Address,
			"peer_id":  c.peerID,
			"balance":  0, // You can fetch actual balance if needed
			"did_type": dt.Type,
		}

		jsonData, _ := json.Marshal(registration)
		
		// Register with advisory node
		resp, err := http.Post(
			advisoryURL+"/api/quorum/register",
			"application/json",
			bytes.NewBuffer(jsonData),
		)
		if err != nil {
			c.log.Error("Failed to register quorum with advisory node", "did", qd.Address, "err", err)
			continue
		}
		resp.Body.Close()

		c.log.Info("Registered quorum with advisory node", "did", qd.Address)
	}

	// Start heartbeat goroutine for all registered quorums
	go c.startQuorumHeartbeat(advisoryURL, quorumData)

	return nil
}

// startQuorumHeartbeat sends periodic heartbeats to keep quorum active
func (c *Core) startQuorumHeartbeat(advisoryURL string, quorums []QuorumData) {
	ticker := time.NewTicker(2 * time.Minute) // Send heartbeat every 2 minutes
	defer ticker.Stop()

	for range ticker.C {
		for _, qd := range quorums {
			reqBody := map[string]string{"did": qd.Address}
			jsonData, _ := json.Marshal(reqBody)
			
			resp, err := http.Post(
				advisoryURL+"/api/quorum/heartbeat",
				"application/json",
				bytes.NewBuffer(jsonData),
			)
			if err != nil {
				c.log.Error("Failed to send heartbeat", "did", qd.Address, "err", err)
				continue
			}
			resp.Body.Close()
		}
	}
}

// Modified SetupQuorum function
func (c *Core) SetupQuorumWithAdvisory(didStr string, pwd string, pvtKeyPwd string) error {
	// First, do the original setup quorum logic
	err := c.SetupQuorum(didStr, pwd, pvtKeyPwd)
	if err != nil {
		return err
	}

	// If advisory node is configured, register and confirm availability
	if c.advisoryNodeURL != "" {
		// Get DID type
		dt, _ := c.w.GetDID(didStr)
		
		// Register with advisory node
		registration := map[string]interface{}{
			"did":      didStr,
			"peer_id":  c.peerID,
			"balance":  0,
			"did_type": dt.Type,
		}
		
		jsonData, _ := json.Marshal(registration)
		resp, err := http.Post(
			c.advisoryNodeURL+"/api/quorum/register",
			"application/json",
			bytes.NewBuffer(jsonData),
		)
		if err != nil {
			c.log.Error("Failed to register new quorum with advisory node", "err", err)
		} else {
			resp.Body.Close()
			
			// Confirm availability immediately
			confirmReq := map[string]string{"did": didStr}
			jsonData, _ = json.Marshal(confirmReq)
			
			resp, err = http.Post(
				c.advisoryNodeURL+"/api/quorum/confirm-availability",
				"application/json",
				bytes.NewBuffer(jsonData),
			)
			if err != nil {
				c.log.Error("Failed to confirm availability", "err", err)
			} else {
				resp.Body.Close()
				c.log.Info("Quorum registered and confirmed with advisory node", "did", didStr)
			}
		}
	}

	return nil
}

// Modified GetQuorum to use advisory node
func (c *Core) GetQuorumFromAdvisory(t int, lastCharTID string) []string {
	// If advisory node is not configured, fall back to local DB
	if c.advisoryNodeURL == "" {
		return c.qm.GetQuorum(t, lastCharTID, c.peerID)
	}

	// Get quorums from advisory node
	url := fmt.Sprintf("%s/api/quorum/available?count=7&type=%d", c.advisoryNodeURL, t)
	if lastCharTID != "" {
		url += "&last_char_tid=" + lastCharTID
	}

	resp, err := http.Get(url)
	if err != nil {
		c.log.Error("Failed to get quorums from advisory node, falling back to local", "err", err)
		return c.qm.GetQuorum(t, lastCharTID, c.peerID)
	}
	defer resp.Body.Close()

	var result struct {
		Status  bool `json:"status"`
		Message string `json:"message"`
		Quorums []struct {
			Type    int    `json:"type"`
			Address string `json:"address"`
		} `json:"quorums"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		c.log.Error("Failed to decode response from advisory node", "err", err)
		return c.qm.GetQuorum(t, lastCharTID, c.peerID)
	}

	if !result.Status {
		c.log.Error("Advisory node returned error", "message", result.Message)
		return c.qm.GetQuorum(t, lastCharTID, c.peerID)
	}

	// Extract addresses
	addresses := make([]string, len(result.Quorums))
	for i, q := range result.Quorums {
		addresses[i] = q.Address
	}

	return addresses
}

// Example: How to modify Core struct in rubixgoplatform/core/core.go
/*
type Core struct {
	// ... existing fields ...
	
	// Add advisory node configuration
	advisoryNodeURL string
	
	// ... rest of the fields ...
}

// In NewCore function, add:
func NewCore(cfg *Config, ...) (*Core, error) {
	// ... existing initialization ...
	
	c := &Core{
		// ... existing fields ...
		advisoryNodeURL: cfg.AdvisoryNodeURL, // Add this from config
	}
	
	// After core is initialized, register existing quorums
	if err := RegisterQuorumsOnStartup(c, c.advisoryNodeURL); err != nil {
		c.log.Error("Failed to register quorums with advisory node", "err", err)
		// Don't fail - just log the error and continue with local management
	}
	
	return c, nil
}
*/

// Example config.yaml addition:
/*
advisory_node:
  enabled: true
  url: "http://advisory-node:8080"
*/