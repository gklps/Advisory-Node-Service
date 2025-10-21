package handlers

import (
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/gklps/advisory-node/models"
	"github.com/gklps/advisory-node/storage"
)

// DBQuorumHandler handles all quorum-related API endpoints with database storage
type DBQuorumHandler struct {
	store *storage.DBStore
}

// NewDBQuorumHandler creates a new database-backed quorum handler
func NewDBQuorumHandler(store *storage.DBStore) *DBQuorumHandler {
	return &DBQuorumHandler{
		store: store,
	}
}

// RegisterQuorum handles POST /api/quorum/register
func (h *DBQuorumHandler) RegisterQuorum(c *gin.Context) {
	var req models.QuorumRegistrationRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid request format: " + err.Error(),
		})
		return
	}

	// Validate DID format
	if !isValidDID(req.DID) {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid DID format. DID must start with 'bafybmi' and be 59 characters long",
		})
		return
	}

	// Validate DID type (0-4, where 4 is lite mode in RubixGo)
	if req.DIDType < 0 || req.DIDType > 4 {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid DID type. Must be between 0 and 4",
		})
		return
	}

	// Register the quorum
	if err := h.store.RegisterQuorum(&req); err != nil {
		c.JSON(http.StatusInternalServerError, models.BasicResponse{
			Status:  false,
			Message: "Failed to register quorum: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.BasicResponse{
		Status:  true,
		Message: fmt.Sprintf("Quorum registered successfully with balance: %.4f", req.Balance),
	})
}

// GetAvailableQuorums handles GET /api/quorum/available
func (h *DBQuorumHandler) GetAvailableQuorums(c *gin.Context) {
	var req models.QuorumListRequest

	// Parse query parameters
	if countStr := c.Query("count"); countStr != "" {
		if count, err := strconv.Atoi(countStr); err == nil {
			req.Count = count
		}
	}

	if req.Count <= 0 {
		req.Count = 7 // Default to 7 quorums
	}

	// Parse transaction amount
	if amountStr := c.Query("transaction_amount"); amountStr != "" {
		if amount, err := strconv.ParseFloat(amountStr, 64); err == nil {
			req.TransactionAmount = amount
		}
	}

	// If no transaction amount provided, default to 0 (no balance check)
	if req.TransactionAmount <= 0 {
		c.JSON(http.StatusBadRequest, models.QuorumListResponse{
			Status:  false,
			Message: "Transaction amount must be provided and greater than 0",
			Quorums: nil,
		})
		return
	}

	req.LastCharTID = c.Query("last_char_tid")
	req.FTName = c.Query("ft_name") // Get token type parameter

	// Parse type parameter
	if typeStr := c.Query("type"); typeStr != "" {
		if qtype, err := strconv.Atoi(typeStr); err == nil {
			req.Type = qtype
		}
	}

	if req.Type == 0 {
		req.Type = 2 // Default to type 2 (private subnet)
	}

	// Calculate required balance (transaction amount divided by number of quorums)
	requiredBalance := req.TransactionAmount / float64(req.Count)

	// Get available quorums with balance validation and token filtering
	quorums, err := h.store.GetAvailableQuorums(req.Count, req.LastCharTID, req.TransactionAmount, req.FTName)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, models.QuorumListResponse{
			Status:  false,
			Message: fmt.Sprintf("Not enough quorums with required balance (%.4f RBT): %v", requiredBalance, err),
			Quorums: nil,
		})
		return
	}

	// Create appropriate message based on token type
	message := fmt.Sprintf("Found %d quorums with minimum balance of %.4f RBT", len(quorums), requiredBalance)
	if req.FTName == "TRI" {
		message = fmt.Sprintf("Found %d TRI-compatible quorums (consistent set)", len(quorums))
	} else if req.FTName != "" {
		message = fmt.Sprintf("Found %d quorums supporting %s token", len(quorums), req.FTName)
	}

	c.JSON(http.StatusOK, models.QuorumListResponse{
		Status:  true,
		Message: message,
		Quorums: quorums,
	})
}

// UpdateQuorumBalance handles PUT /api/quorum/balance
func (h *DBQuorumHandler) UpdateQuorumBalance(c *gin.Context) {
	var req struct {
		DID     string  `json:"did" binding:"required"`
		Balance float64 `json:"balance" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid request format: " + err.Error(),
		})
		return
	}

	if !isValidDID(req.DID) {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid DID format",
		})
		return
	}

	if req.Balance < 0 {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Balance cannot be negative",
		})
		return
	}

	if err := h.store.UpdateQuorumBalance(req.DID, req.Balance); err != nil {
		c.JSON(http.StatusNotFound, models.BasicResponse{
			Status:  false,
			Message: "Failed to update balance: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.BasicResponse{
		Status:  true,
		Message: fmt.Sprintf("Balance updated to %.4f RBT", req.Balance),
	})
}

// ConfirmAvailability handles POST /api/quorum/confirm-availability
func (h *DBQuorumHandler) ConfirmAvailability(c *gin.Context) {
	var req models.ConfirmAvailabilityRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid request format: " + err.Error(),
		})
		return
	}

	if !isValidDID(req.DID) {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid DID format",
		})
		return
	}

	if err := h.store.ConfirmAvailability(req.DID); err != nil {
		c.JSON(http.StatusNotFound, models.BasicResponse{
			Status:  false,
			Message: "Quorum not found: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.BasicResponse{
		Status:  true,
		Message: "Availability confirmed",
	})
}

// UnregisterQuorum handles DELETE /api/quorum/unregister/:did
func (h *DBQuorumHandler) UnregisterQuorum(c *gin.Context) {
	did := c.Param("did")

	if !isValidDID(did) {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid DID format",
		})
		return
	}

	if err := h.store.UnregisterQuorum(did); err != nil {
		c.JSON(http.StatusNotFound, models.BasicResponse{
			Status:  false,
			Message: "Failed to unregister quorum: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.BasicResponse{
		Status:  true,
		Message: "Quorum unregistered successfully",
	})
}

// GetHealth handles GET /api/quorum/health
func (h *DBQuorumHandler) GetHealth(c *gin.Context) {
	health := h.store.GetHealthStatus()
	c.JSON(http.StatusOK, health)
}

// Heartbeat handles POST /api/quorum/heartbeat
func (h *DBQuorumHandler) Heartbeat(c *gin.Context) {
	var req struct {
		DID string `json:"did" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid request format: " + err.Error(),
		})
		return
	}

	if !isValidDID(req.DID) {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid DID format",
		})
		return
	}

	if err := h.store.UpdateHeartbeat(req.DID); err != nil {
		c.JSON(http.StatusNotFound, models.BasicResponse{
			Status:  false,
			Message: "Quorum not found: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.BasicResponse{
		Status:  true,
		Message: "Heartbeat updated",
	})
}

// GetQuorumInfo handles GET /api/quorum/info/:did
func (h *DBQuorumHandler) GetQuorumInfo(c *gin.Context) {
	did := c.Param("did")

	if !isValidDID(did) {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid DID format",
		})
		return
	}

	quorum, err := h.store.GetQuorumByDID(did)
	if err != nil {
		c.JSON(http.StatusNotFound, models.BasicResponse{
			Status:  false,
			Message: "Quorum not found: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status": true,
		"quorum": quorum,
	})
}

// GetTransactionHistory handles GET /api/quorum/transactions
func (h *DBQuorumHandler) GetTransactionHistory(c *gin.Context) {
	limitStr := c.DefaultQuery("limit", "100")
	limit, _ := strconv.Atoi(limitStr)

	history, err := h.store.GetTransactionHistory(limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"status":  false,
			"message": "Failed to get transaction history: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  true,
		"history": history,
	})
}

// isValidDID validates DID format (matching RubixGo validation)
func isValidDID(did string) bool {
	// Check if DID starts with "bafybmi" and has exactly 59 characters
	if !strings.HasPrefix(did, "bafybmi") || len(did) != 59 {
		return false
	}

	// Check if DID is alphanumeric
	isAlphanumeric := regexp.MustCompile(`^[a-zA-Z0-9]*$`).MatchString(did)
	return isAlphanumeric
}
