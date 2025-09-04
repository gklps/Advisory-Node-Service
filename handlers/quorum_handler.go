package handlers

import (
	"fmt"
	"net/http"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/gklps/advisory-node/models"
	"github.com/gklps/advisory-node/storage"
)

// QuorumHandler handles all quorum-related API endpoints
type QuorumHandler struct {
	store *storage.MemoryStore
}

// NewQuorumHandler creates a new quorum handler
func NewQuorumHandler(store *storage.MemoryStore) *QuorumHandler {
	return &QuorumHandler{
		store: store,
	}
}

// RegisterQuorum handles POST /api/quorum/register
func (h *QuorumHandler) RegisterQuorum(c *gin.Context) {
	var req models.QuorumRegistrationRequest
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.BasicResponse{
			Status:  false,
			Message: "Invalid request format: " + err.Error(),
		})
		return
	}

	// Validate DID format (matching RubixGo validation)
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
		Message: "Quorum registered successfully",
	})
}

// ConfirmAvailability handles POST /api/quorum/confirm-availability
func (h *QuorumHandler) ConfirmAvailability(c *gin.Context) {
	var req models.ConfirmAvailabilityRequest
	
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
			Message: "Invalid DID format",
		})
		return
	}

	// Confirm availability
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

// GetAvailableQuorums handles GET /api/quorum/available
func (h *QuorumHandler) GetAvailableQuorums(c *gin.Context) {
	var req models.QuorumListRequest
	
	// Parse query parameters
	if countStr := c.Query("count"); countStr != "" {
		var count int
		if _, err := fmt.Sscanf(countStr, "%d", &count); err == nil {
			req.Count = count
		}
	}
	
	if req.Count <= 0 {
		req.Count = 7 // Default to 7 quorums
	}
	
	req.LastCharTID = c.Query("last_char_tid")
	
	// Parse type parameter
	if typeStr := c.Query("type"); typeStr != "" {
		var qtype int
		if _, err := fmt.Sscanf(typeStr, "%d", &qtype); err == nil {
			req.Type = qtype
		}
	}
	
	if req.Type == 0 {
		req.Type = 2 // Default to type 2 (private subnet)
	}

	// Get available quorums with load balancing
	quorums, err := h.store.GetAvailableQuorums(req.Count, req.LastCharTID)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, models.QuorumListResponse{
			Status:  false,
			Message: "Not enough available quorums: " + err.Error(),
			Quorums: nil,
		})
		return
	}

	c.JSON(http.StatusOK, models.QuorumListResponse{
		Status:  true,
		Message: "Quorums retrieved successfully",
		Quorums: quorums,
	})
}

// UnregisterQuorum handles DELETE /api/quorum/unregister/:did
func (h *QuorumHandler) UnregisterQuorum(c *gin.Context) {
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
			Message: "Quorum not found: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.BasicResponse{
		Status:  true,
		Message: "Quorum unregistered successfully",
	})
}

// GetHealth handles GET /api/quorum/health
func (h *QuorumHandler) GetHealth(c *gin.Context) {
	health := h.store.GetHealthStatus()
	c.JSON(http.StatusOK, health)
}

// Heartbeat handles POST /api/quorum/heartbeat
func (h *QuorumHandler) Heartbeat(c *gin.Context) {
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
func (h *QuorumHandler) GetQuorumInfo(c *gin.Context) {
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