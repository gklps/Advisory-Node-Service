package examples

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// Integration with balance validation for RubixGo platform

// GetQuorumsWithBalanceCheck fetches quorums that have sufficient balance
// This replaces the old GetQuorum function in RubixGo
func GetQuorumsWithBalanceCheck(advisoryURL string, transactionAmount float64, count int, lastCharTID string) ([]string, error) {
	// Calculate minimum required balance per quorum (transaction amount / number of quorums)
	requiredBalance := transactionAmount / float64(count)
	
	// Build request URL with transaction amount and count
	url := fmt.Sprintf("%s/api/quorum/available?count=%d&transaction_amount=%.4f",
		advisoryURL, count, transactionAmount)
	
	if lastCharTID != "" {
		url += "&last_char_tid=" + lastCharTID
	}

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to get quorums: %v", err)
	}
	defer resp.Body.Close()

	var result struct {
		Status  bool   `json:"status"`
		Message string `json:"message"`
		Quorums []struct {
			Type    int    `json:"type"`
			Address string `json:"address"`
		} `json:"quorums"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %v", err)
	}

	if !result.Status {
		return nil, fmt.Errorf("failed to get quorums with required balance %.4f RBT: %s", 
			requiredBalance, result.Message)
	}

	// Extract addresses
	addresses := make([]string, len(result.Quorums))
	for i, q := range result.Quorums {
		addresses[i] = q.Address
	}

	return addresses, nil
}

// RegisterQuorumWithBalance registers a quorum with its current balance
func RegisterQuorumWithBalance(advisoryURL, did, peerID string, balance float64, didType int) error {
	registration := map[string]interface{}{
		"did":      did,
		"peer_id":  peerID,
		"balance":  balance,
		"did_type": didType,
	}

	jsonData, err := json.Marshal(registration)
	if err != nil {
		return fmt.Errorf("failed to marshal registration: %v", err)
	}

	resp, err := http.Post(
		advisoryURL+"/api/quorum/register",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return fmt.Errorf("failed to register quorum: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		return fmt.Errorf("registration failed: %v", result["message"])
	}

	return nil
}

// UpdateQuorumBalance updates the balance of a quorum
func UpdateQuorumBalance(advisoryURL, did string, newBalance float64) error {
	update := map[string]interface{}{
		"did":     did,
		"balance": newBalance,
	}

	jsonData, err := json.Marshal(update)
	if err != nil {
		return fmt.Errorf("failed to marshal update: %v", err)
	}

	req, err := http.NewRequest(
		"PUT",
		advisoryURL+"/api/quorum/balance",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to update balance: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		return fmt.Errorf("balance update failed: %v", result["message"])
	}

	return nil
}

// Example integration in RubixGo's transfer.go
/*
func (c *Core) InitiateTransferWithBalanceCheck(req *TransferRequest) error {
    // ... existing code ...
    
    // Get quorums with balance validation
    quorums, err := GetQuorumsWithBalanceCheck(
        c.advisoryNodeURL, 
        req.Amount,        // Transaction amount
        lastCharTID,
    )
    if err != nil {
        // If not enough quorums with balance, fail the transaction
        return fmt.Errorf("cannot proceed with transaction: %v", err)
    }
    
    // Proceed with transaction using selected quorums
    c.log.Info("Got quorums with sufficient balance", 
        "count", len(quorums),
        "requiredBalance", req.Amount/5.0)
    
    // ... continue with consensus ...
}
*/

// Example: How to update balance when node's balance changes
/*
func (c *Core) OnBalanceChange(did string, newBalance float64) {
    if c.advisoryNodeURL != "" {
        // Update balance in advisory node
        err := UpdateQuorumBalance(c.advisoryNodeURL, did, newBalance)
        if err != nil {
            c.log.Error("Failed to update balance in advisory node", "err", err)
        }
    }
}
*/

// Example: SetupQuorum with balance
/*
func (c *Core) SetupQuorumWithBalance(didStr string, pwd string, pvtKeyPwd string) error {
    // ... existing setup logic ...
    
    // Get current balance for this DID
    balance := c.GetAccountBalance(didStr)
    
    // Register with advisory node including balance
    err := RegisterQuorumWithBalance(
        c.advisoryNodeURL,
        didStr,
        c.peerID,
        balance,
        dt.Type,
    )
    if err != nil {
        c.log.Error("Failed to register with advisory node", "err", err)
    }
    
    // Start periodic balance updates
    go c.periodicBalanceUpdate(didStr)
    
    return nil
}

func (c *Core) periodicBalanceUpdate(did string) {
    ticker := time.NewTicker(5 * time.Minute)
    defer ticker.Stop()
    
    for range ticker.C {
        balance := c.GetAccountBalance(did)
        UpdateQuorumBalance(c.advisoryNodeURL, did, balance)
    }
}
*/

// TransactionValidation shows the validation logic
func TransactionValidation(transactionAmount float64, quorumCount int) {
	fmt.Printf("Transaction Amount: %.4f RBT\n", transactionAmount)
	fmt.Printf("Number of Quorums: %d\n", quorumCount)
	fmt.Printf("Required Balance per Quorum: %.4f RBT (amount/count)\n", transactionAmount/float64(quorumCount))
	fmt.Printf("Examples:\n")
	fmt.Printf("  - 100 RBT transaction with 7 quorums → Each needs ≥ 14.29 RBT\n")
	fmt.Printf("  - 100 RBT transaction with 5 quorums → Each needs ≥ 20.00 RBT\n")
	fmt.Printf("  - 50 RBT transaction with 7 quorums → Each needs ≥ 7.14 RBT\n")
	fmt.Printf("  - 10 RBT transaction with 5 quorums → Each needs ≥ 2.00 RBT\n")
}