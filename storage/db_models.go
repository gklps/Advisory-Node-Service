package storage

import (
	"time"
)

// QuorumDB represents the database model for quorum information
type QuorumDB struct {
	ID               uint      `gorm:"primaryKey"`
	DID              string    `gorm:"column:did;uniqueIndex;not null;size:59"`
	PeerID           string    `gorm:"column:peer_id;index;not null"`
	Balance          float64   `gorm:"column:balance;default:0"`
	DIDType          int       `gorm:"column:did_type;not null"`
	Available        bool      `gorm:"column:available;default:true;index"`
	LastPing         time.Time `gorm:"column:last_ping;index"`
	AssignmentCount  int64     `gorm:"column:assignment_count;default:0"`
	LastAssignment   time.Time `gorm:"column:last_assignment"`
	RegistrationTime time.Time `gorm:"column:registration_time"`
	CreatedAt        time.Time `gorm:"column:created_at"`
	UpdatedAt        time.Time `gorm:"column:updated_at"`
}

// TransactionHistory tracks quorum assignments for transactions
type TransactionHistory struct {
	ID              uint      `gorm:"primaryKey"`
	TransactionID   string    `gorm:"index;not null"`
	TransactionAmount float64  `gorm:"not null"`
	QuorumDIDs      string    `gorm:"type:text"` // JSON array of assigned quorum DIDs
	RequiredBalance float64   // 1/5th of transaction amount
	Timestamp       time.Time
	CreatedAt       time.Time
}

// QuorumStats for analytics and monitoring
type QuorumStats struct {
	ID                uint      `gorm:"primaryKey"`
	QuorumDID         string    `gorm:"index;not null"`
	TotalTransactions int64
	TotalAmount       float64
	LastActive        time.Time
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

// BalanceHistory tracks balance changes
type BalanceHistory struct {
	ID            uint      `gorm:"primaryKey"`
	QuorumDID     string    `gorm:"index;not null"`
	OldBalance    float64
	NewBalance    float64
	ChangeReason  string
	Timestamp     time.Time
	CreatedAt     time.Time
}

// TableName specifies the table name for QuorumDB
func (QuorumDB) TableName() string {
	return "quorums"
}

// TableName specifies the table name for TransactionHistory
func (TransactionHistory) TableName() string {
	return "transaction_history"
}

// TableName specifies the table name for QuorumStats
func (QuorumStats) TableName() string {
	return "quorum_stats"
}

// TableName specifies the table name for BalanceHistory
func (BalanceHistory) TableName() string {
	return "balance_history"
}