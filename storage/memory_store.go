package storage

import (
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/gklps/advisory-node/models"
)

// MemoryStore implements in-memory storage for quorums with thread safety
type MemoryStore struct {
	mu           sync.RWMutex
	quorums      map[string]*models.QuorumInfo // Key: DID
	peerIndex    map[string]string              // Key: PeerID, Value: DID
	startTime    time.Time
}

// NewMemoryStore creates a new in-memory storage instance
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		quorums:   make(map[string]*models.QuorumInfo),
		peerIndex: make(map[string]string),
		startTime: time.Now(),
	}
}

// RegisterQuorum registers a new quorum or updates an existing one
func (ms *MemoryStore) RegisterQuorum(req *models.QuorumRegistrationRequest) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	// Check if quorum already exists
	if existing, ok := ms.quorums[req.DID]; ok {
		// Update existing quorum
		existing.PeerID = req.PeerID
		existing.Balance = req.Balance
		existing.DIDType = req.DIDType
		existing.LastPing = time.Now()
		existing.Available = true
		
		// Update peer index
		ms.peerIndex[req.PeerID] = req.DID
		return nil
	}

	// Create new quorum entry
	quorum := &models.QuorumInfo{
		DID:              req.DID,
		PeerID:           req.PeerID,
		Balance:          req.Balance,
		DIDType:          req.DIDType,
		Available:        true,
		LastPing:         time.Now(),
		AssignmentCount:  0,
		RegistrationTime: time.Now(),
	}

	ms.quorums[req.DID] = quorum
	ms.peerIndex[req.PeerID] = req.DID

	return nil
}

// ConfirmAvailability confirms that a quorum is available for assignments
func (ms *MemoryStore) ConfirmAvailability(did string) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	quorum, ok := ms.quorums[did]
	if !ok {
		return errors.New("quorum not found")
	}

	quorum.Available = true
	quorum.LastPing = time.Now()
	
	return nil
}

// GetAvailableQuorums returns available quorums with load balancing
func (ms *MemoryStore) GetAvailableQuorums(count int, lastCharTID string) ([]models.QuorumData, error) {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	if count <= 0 {
		count = 7 // Default to 7 quorums as per RubixGo requirement
	}

	// Filter available quorums
	var availableQuorums []*models.QuorumInfo
	for _, q := range ms.quorums {
		// Check if quorum is available and was pinged recently (within last 5 minutes)
		if q.Available && time.Since(q.LastPing) < 5*time.Minute {
			// If lastCharTID is provided, filter by last character of DID
			if lastCharTID != "" {
				if len(q.DID) > 0 && string(q.DID[len(q.DID)-1]) == lastCharTID {
					availableQuorums = append(availableQuorums, q)
				}
			} else {
				availableQuorums = append(availableQuorums, q)
			}
		}
	}

	if len(availableQuorums) < count {
		return nil, errors.New("not enough available quorums")
	}

	// Sort by assignment count (ascending) and last assignment time (oldest first)
	// This implements load balancing
	sort.Slice(availableQuorums, func(i, j int) bool {
		if availableQuorums[i].AssignmentCount == availableQuorums[j].AssignmentCount {
			return availableQuorums[i].LastAssignment.Before(availableQuorums[j].LastAssignment)
		}
		return availableQuorums[i].AssignmentCount < availableQuorums[j].AssignmentCount
	})

	// Select the required number of quorums
	result := make([]models.QuorumData, 0, count)
	for i := 0; i < count && i < len(availableQuorums); i++ {
		q := availableQuorums[i]
		
		// Update assignment metadata
		q.AssignmentCount++
		q.LastAssignment = time.Now()
		
		// Format as expected by RubixGo (PeerID.DID)
		result = append(result, models.QuorumData{
			Type:    2, // Type 2 for private subnet quorums
			Address: q.PeerID + "." + q.DID,
		})
	}

	return result, nil
}

// UnregisterQuorum removes a quorum from the pool
func (ms *MemoryStore) UnregisterQuorum(did string) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	quorum, ok := ms.quorums[did]
	if !ok {
		return errors.New("quorum not found")
	}

	// Remove from peer index
	delete(ms.peerIndex, quorum.PeerID)
	
	// Remove from quorums map
	delete(ms.quorums, did)
	
	return nil
}

// GetHealthStatus returns the health status of the storage
func (ms *MemoryStore) GetHealthStatus() models.HealthStatus {
	ms.mu.RLock()
	defer ms.mu.RUnlock()

	totalQuorums := len(ms.quorums)
	availableQuorums := 0
	
	for _, q := range ms.quorums {
		if q.Available && time.Since(q.LastPing) < 5*time.Minute {
			availableQuorums++
		}
	}

	return models.HealthStatus{
		Status:           "healthy",
		TotalQuorums:     totalQuorums,
		AvailableQuorums: availableQuorums,
		Uptime:           time.Since(ms.startTime).String(),
		LastCheck:        time.Now(),
	}
}

// UpdateHeartbeat updates the last ping time for a quorum
func (ms *MemoryStore) UpdateHeartbeat(did string) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	quorum, ok := ms.quorums[did]
	if !ok {
		return errors.New("quorum not found")
	}

	quorum.LastPing = time.Now()
	return nil
}

// CleanupStaleQuorums removes quorums that haven't pinged in a while
func (ms *MemoryStore) CleanupStaleQuorums() int {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	staleThreshold := 10 * time.Minute
	removedCount := 0
	
	for did, q := range ms.quorums {
		if time.Since(q.LastPing) > staleThreshold {
			delete(ms.peerIndex, q.PeerID)
			delete(ms.quorums, did)
			removedCount++
		}
	}
	
	return removedCount
}

// GetQuorumByDID returns a specific quorum by DID
func (ms *MemoryStore) GetQuorumByDID(did string) (*models.QuorumInfo, error) {
	ms.mu.RLock()
	defer ms.mu.RUnlock()

	quorum, ok := ms.quorums[did]
	if !ok {
		return nil, errors.New("quorum not found")
	}

	return quorum, nil
}