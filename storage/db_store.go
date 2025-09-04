package storage

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/gklps/advisory-node/models"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// DBStore implements database storage for quorums
type DBStore struct {
	db *gorm.DB
}

// DBConfig holds database configuration
type DBConfig struct {
	Type     string // "sqlite" or "postgres"
	Host     string
	Port     int
	Database string
	Username string
	Password string
	SSLMode  string
}

// NewDBStore creates a new database store
func NewDBStore(config DBConfig) (*DBStore, error) {
	var db *gorm.DB
	var err error

	gormConfig := &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	}

	switch config.Type {
	case "sqlite":
		// Use SQLite for development/testing
		dbPath := config.Database
		if dbPath == "" {
			dbPath = "advisory_node.db"
		}
		db, err = gorm.Open(sqlite.Open(dbPath), gormConfig)
		
	case "postgres":
		// Use PostgreSQL for production
		dsn := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
			config.Host, config.Port, config.Username, config.Password, config.Database, config.SSLMode)
		db, err = gorm.Open(postgres.Open(dsn), gormConfig)
		
	default:
		return nil, fmt.Errorf("unsupported database type: %s", config.Type)
	}

	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %v", err)
	}

	// Auto migrate schemas
	err = db.AutoMigrate(
		&QuorumDB{},
		&TransactionHistory{},
		&QuorumStats{},
		&BalanceHistory{},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to migrate database: %v", err)
	}

	return &DBStore{db: db}, nil
}

// RegisterQuorum registers a new quorum or updates an existing one
func (ds *DBStore) RegisterQuorum(req *models.QuorumRegistrationRequest) error {
	var existingQuorum QuorumDB
	
	// Check if quorum exists
	result := ds.db.Where("did = ?", req.DID).First(&existingQuorum)
	
	if result.Error == nil {
		// Update existing quorum
		updates := map[string]interface{}{
			"peer_id":   req.PeerID,
			"balance":   req.Balance,
			"did_type":  req.DIDType,
			"available": true,
			"last_ping": time.Now(),
		}
		
		// Track balance change if different
		if existingQuorum.Balance != req.Balance {
			balanceHistory := BalanceHistory{
				QuorumDID:    req.DID,
				OldBalance:   existingQuorum.Balance,
				NewBalance:   req.Balance,
				ChangeReason: "Registration update",
				Timestamp:    time.Now(),
			}
			ds.db.Create(&balanceHistory)
		}
		
		return ds.db.Model(&existingQuorum).Updates(updates).Error
	}
	
	// Create new quorum
	quorum := QuorumDB{
		DID:              req.DID,
		PeerID:           req.PeerID,
		Balance:          req.Balance,
		DIDType:          req.DIDType,
		Available:        true,
		LastPing:         time.Now(),
		RegistrationTime: time.Now(),
	}
	
	return ds.db.Create(&quorum).Error
}

// GetAvailableQuorums returns available quorums with balance validation
func (ds *DBStore) GetAvailableQuorums(count int, lastCharTID string, transactionAmount float64) ([]models.QuorumData, error) {
	if count <= 0 {
		count = 7
	}

	// Calculate required balance (transaction amount divided by number of quorums)
	requiredBalance := transactionAmount / float64(count)

	// Build query
	query := ds.db.Model(&QuorumDB{}).
		Where("available = ?", true).
		Where("last_ping > ?", time.Now().Add(-5*time.Minute)).
		Where("balance >= ?", requiredBalance) // Only quorums with sufficient balance

	// Filter by last character if provided
	if lastCharTID != "" {
		query = query.Where("did LIKE ?", "%"+lastCharTID)
	}

	// Get quorums ordered by assignment count (load balancing)
	var quorums []QuorumDB
	err := query.Order("assignment_count ASC, last_assignment ASC").
		Limit(count).
		Find(&quorums).Error

	if err != nil {
		return nil, err
	}

	if len(quorums) < count {
		return nil, fmt.Errorf("not enough quorums with required balance. Found %d, need %d (required balance: %.4f)",
			len(quorums), count, requiredBalance)
	}

	// Update assignment metadata and create response
	result := make([]models.QuorumData, 0, count)
	quorumDIDs := make([]string, 0, count)
	
	for _, q := range quorums {
		// Update assignment count and time
		ds.db.Model(&q).Updates(map[string]interface{}{
			"assignment_count": q.AssignmentCount + 1,
			"last_assignment":  time.Now(),
		})

		result = append(result, models.QuorumData{
			Type:    2,
			Address: q.PeerID + "." + q.DID,
		})
		
		quorumDIDs = append(quorumDIDs, q.DID)
	}

	// Record transaction history
	quorumDIDsJSON, _ := json.Marshal(quorumDIDs)
	history := TransactionHistory{
		TransactionID:     fmt.Sprintf("txn_%d", time.Now().UnixNano()),
		TransactionAmount: transactionAmount,
		QuorumDIDs:       string(quorumDIDsJSON),
		RequiredBalance:  requiredBalance,
		Timestamp:        time.Now(),
	}
	ds.db.Create(&history)

	return result, nil
}

// UpdateQuorumBalance updates the balance for a quorum
func (ds *DBStore) UpdateQuorumBalance(did string, newBalance float64) error {
	var quorum QuorumDB
	
	if err := ds.db.Where("did = ?", did).First(&quorum).Error; err != nil {
		return fmt.Errorf("quorum not found: %v", err)
	}

	// Track balance change
	if quorum.Balance != newBalance {
		balanceHistory := BalanceHistory{
			QuorumDID:    did,
			OldBalance:   quorum.Balance,
			NewBalance:   newBalance,
			ChangeReason: "Balance update",
			Timestamp:    time.Now(),
		}
		ds.db.Create(&balanceHistory)
	}

	return ds.db.Model(&quorum).Update("balance", newBalance).Error
}

// ConfirmAvailability confirms that a quorum is available
func (ds *DBStore) ConfirmAvailability(did string) error {
	// First check if the quorum exists
	var quorum QuorumDB
	if err := ds.db.Where("did = ?", did).First(&quorum).Error; err != nil {
		return fmt.Errorf("quorum not found: %v", err)
	}
	
	// Update the quorum availability
	return ds.db.Model(&QuorumDB{}).
		Where("did = ?", did).
		Updates(map[string]interface{}{
			"available": true,
			"last_ping": time.Now(),
		}).Error
}

// UpdateHeartbeat updates the last ping time for a quorum
func (ds *DBStore) UpdateHeartbeat(did string) error {
	return ds.db.Model(&QuorumDB{}).
		Where("did = ?", did).
		Update("last_ping", time.Now()).Error
}

// UnregisterQuorum removes a quorum from the pool
func (ds *DBStore) UnregisterQuorum(did string) error {
	return ds.db.Where("did = ?", did).Delete(&QuorumDB{}).Error
}

// GetQuorumByDID returns a specific quorum by DID
func (ds *DBStore) GetQuorumByDID(did string) (*models.QuorumInfo, error) {
	var quorum QuorumDB
	
	if err := ds.db.Where("did = ?", did).First(&quorum).Error; err != nil {
		return nil, errors.New("quorum not found")
	}

	return &models.QuorumInfo{
		DID:              quorum.DID,
		PeerID:           quorum.PeerID,
		Balance:          quorum.Balance,
		DIDType:          quorum.DIDType,
		Available:        quorum.Available,
		LastPing:         quorum.LastPing,
		AssignmentCount:  int(quorum.AssignmentCount),
		LastAssignment:   quorum.LastAssignment,
		RegistrationTime: quorum.RegistrationTime,
	}, nil
}

// GetHealthStatus returns the health status of the storage
func (ds *DBStore) GetHealthStatus() models.HealthStatus {
	var totalQuorums int64
	var availableQuorums int64
	
	ds.db.Model(&QuorumDB{}).Count(&totalQuorums)
	ds.db.Model(&QuorumDB{}).
		Where("available = ?", true).
		Where("last_ping > ?", time.Now().Add(-5*time.Minute)).
		Count(&availableQuorums)

	return models.HealthStatus{
		Status:           "healthy",
		TotalQuorums:     int(totalQuorums),
		AvailableQuorums: int(availableQuorums),
		LastCheck:        time.Now(),
	}
}

// CleanupStaleQuorums removes quorums that haven't pinged in a while
func (ds *DBStore) CleanupStaleQuorums() int {
	staleThreshold := 10 * time.Minute
	
	result := ds.db.Model(&QuorumDB{}).
		Where("last_ping < ?", time.Now().Add(-staleThreshold)).
		Update("available", false)
	
	return int(result.RowsAffected)
}

// GetQuorumStats returns statistics for a quorum
func (ds *DBStore) GetQuorumStats(did string) (*QuorumStats, error) {
	var stats QuorumStats
	
	err := ds.db.Where("quorum_did = ?", did).First(&stats).Error
	if err == gorm.ErrRecordNotFound {
		// Create new stats record
		stats = QuorumStats{
			QuorumDID: did,
		}
		ds.db.Create(&stats)
	}
	
	return &stats, nil
}

// GetTransactionHistory returns transaction history
func (ds *DBStore) GetTransactionHistory(limit int) ([]TransactionHistory, error) {
	var history []TransactionHistory
	
	query := ds.db.Order("created_at DESC")
	if limit > 0 {
		query = query.Limit(limit)
	}
	
	err := query.Find(&history).Error
	return history, err
}