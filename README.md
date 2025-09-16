# Advisory Node Service

A standalone service for managing quorum availability and assignment in the RubixGo platform. This service replaces the database-driven quorum selection with a scalable API-based approach, providing better load balancing and availability management.

## Features

- **Quorum Registration**: Quorums can register their availability with the advisory node
- **Availability Management**: Track and confirm quorum availability in real-time
- **Load Balancing**: Automatically distribute transaction requests across available quorums
- **Health Monitoring**: Heartbeat mechanism to track quorum liveness
- **RESTful API**: Easy integration with RubixGo platform

## API Endpoints

### Registration and Management

#### POST /api/quorum/register
Register a new quorum or update existing one.

**Request Body:**
```json
{
  "did": "bafybmihash1test...",
  "peer_id": "12D3KooWPeer1",
  "balance": 0,
  "did_type": 1
}
```

#### POST /api/quorum/confirm-availability
Confirm quorum availability (called by setupquorum command).

**Request Body:**
```json
{
  "did": "bafybmihash1test..."
}
```

#### POST /api/quorum/heartbeat
Update quorum heartbeat to maintain availability status.

**Request Body:**
```json
{
  "did": "bafybmihash1test..."
}
```

#### DELETE /api/quorum/unregister/:did
Unregister a quorum from the pool.

**Response:**
```json
{
  "status": true,
  "message": "Quorum unregistered successfully"
}
```

#### PUT /api/quorum/balance
Update the balance of a specific quorum.

**Request Body:**
```json
{
  "did": "bafybmihash1test...",
  "balance": 150.5
}
```

**Response:**
```json
{
  "status": true,
  "message": "Balance updated to 150.5000 RBT"
}
```

### Query Endpoints

#### GET /api/quorum/available
Get available quorums with balance validation for transactions.

**IMPORTANT:** This endpoint now requires `transaction_amount` parameter for balance validation.

**Query Parameters:**
- `count` (optional): Number of quorums needed (default: 7)
- `transaction_amount` (required): Transaction amount in RBT for balance validation
- `last_char_tid` (optional): For type-1 quorum filtering
- `type` (optional): Quorum type (default: 2)

**Example Request:**
```bash
curl "https://advisory-node-service.onrender.com/api/quorum/available?count=5&transaction_amount=100"
```

**Response (Success):**
```json
{
  "status": true,
  "message": "Found 5 quorums with minimum balance of 20.0000 RBT",
  "quorums": [
    {
      "type": 2,
      "address": "12D3KooWPeer1.bafybmihash1test..."
    }
  ]
}
```

**Response (Insufficient Balance):**
```json
{
  "status": false,
  "message": "Not enough quorums with required balance (20.0000 RBT): not enough quorums with required balance. Found 2, need 5 (required balance: 20.0000)",
  "quorums": null
}
```

**Balance Calculation:** Required balance per quorum = `transaction_amount / count`

#### GET /api/quorum/info/:did
Get detailed information about a specific quorum.

**Response:**
```json
{
  "status": true,
  "quorum": {
    "did": "bafybmi...",
    "peer_id": "12D3KooW...",
    "balance": 150.5,
    "did_type": 4,
    "available": true,
    "last_ping": "2025-09-16T09:06:49Z",
    "assignment_count": 4,
    "registration_time": "2025-09-16T07:30:48Z"
  }
}
```

#### GET /api/quorum/health
Get health status of the advisory node service.

#### GET /api/quorum/transactions
Get transaction history and quorum assignments.

**Query Parameters:**
- `limit` (optional): Number of transactions to return (default: 100)

**Response:**
```json
{
  "status": true,
  "history": [
    {
      "transaction_id": "txn_1726484409067614000",
      "transaction_amount": 100.0,
      "quorum_dids": "[\"did1\", \"did2\", \"did3\"]",
      "required_balance": 20.0,
      "timestamp": "2025-09-16T09:06:49Z"
    }
  ]
}
```

## Balance Validation System

### How Balance Validation Works

The Advisory Node implements a **balance validation system** to ensure quorums have sufficient funds before participating in transactions:

1. **Required Balance Calculation**: `required_balance = transaction_amount / quorum_count`
2. **Validation**: Only quorums with `balance >= required_balance` are eligible
3. **Example**: 100 RBT transaction with 5 quorums requires each to have at least 20 RBT

### Balance Requirements

| Transaction Amount | Quorum Count | Required Balance per Quorum |
|-------------------|--------------|----------------------------|
| 100 RBT           | 5            | 20.0000 RBT               |
| 100 RBT           | 7            | 14.2857 RBT               |
| 50 RBT            | 5            | 10.0000 RBT               |
| 10 RBT            | 7            | 1.4286 RBT                |

### Why Balance Validation?

- **Prevents Failed Transactions**: Ensures quorums can complete transactions
- **Protects Network**: Maintains network integrity and reliability
- **Fair Distribution**: Balances load based on available funds

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd advisory-node
```

2. Install dependencies:
```bash
go mod download
```

3. Build the application:
```bash
go build -o advisory-node
```

## Running the Service

### Database Configuration

The service supports both SQLite and PostgreSQL databases:

#### SQLite (Default)
```bash
./advisory-node -db-type=sqlite -db-file=advisory.db
```

#### PostgreSQL
```bash
# Using connection string
./advisory-node -db-type=postgres -db-url="postgresql://user:password@host:5432/advisory_db"

# Using individual parameters
./advisory-node -db-type=postgres -db-host=localhost -db-port=5432 -db-name=advisory_db -db-user=user -db-password=password
```

#### Environment Variables
Create an `.env` file or set environment variables:
```bash
# Database configuration
DB_TYPE=postgres
DATABASE_URL=postgresql://user:password@host:5432/advisory_db

# Server configuration
PORT=8080
GIN_MODE=release
CORS_ORIGIN=*
```

### Basic Usage
```bash
# Default SQLite setup
./advisory-node

# With custom port and debug mode
./advisory-node -port=8080 -mode=debug

# Production PostgreSQL setup
./advisory-node -db-type=postgres -db-url=$DATABASE_URL -port=8080
```

### Command Line Options
- `-port`: Server port (default: 8080)
- `-mode`: Server mode - debug/release (default: release)
- `-cors`: CORS allowed origins (default: *)
- `-db-type`: Database type - sqlite/postgres (default: sqlite)
- `-db-file`: SQLite database file path (default: advisory.db)
- `-db-url`: PostgreSQL connection URL
- `-db-host`: Database host (default: localhost)
- `-db-port`: Database port (default: 5432)
- `-db-name`: Database name (default: advisory)
- `-db-user`: Database username
- `-db-password`: Database password



## Load Balancing Algorithm

The advisory node implements a sophisticated load balancing algorithm with balance validation:

1. **Balance Validation**: Filters quorums with `balance >= required_balance`
2. **Assignment Tracking**: Tracks the number of assignments per quorum
3. **Time-based Rotation**: Considers the last assignment time
4. **Availability Filtering**: Only returns quorums that have pinged within the last 5 minutes
5. **Fair Distribution**: Sorts quorums by assignment count (ascending) to ensure even distribution
6. **Transaction History**: Records all assignments for analytics and monitoring

## Monitoring & Analytics

The service includes comprehensive monitoring capabilities:

### Health & Status
- Health endpoint for monitoring service status
- Real-time quorum availability tracking
- Database connection monitoring

### Automatic Maintenance
- Automatic cleanup of stale quorums (not pinged in 5+ minutes)
- Balance history tracking for audit trails
- Transaction history for analytics

### Logging & Metrics
- Request logging with latency metrics
- Balance change tracking
- Assignment statistics
- Graceful shutdown handling

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    RubixGo Ecosystem                        │
│                                                             │
│  ┌───────────┐     ┌─────────────┐     ┌─────────────┐    │
│  │setupquorum│     │  Transfer   │     │   Balance   │    │
│  │  Command  │     │  Initiator  │     │   Monitor   │    │
│  └─────┬─────┘     └──────┬──────┘     └──────┬──────┘    │
│        │                  │                   │           │
│        │ POST /confirm    │ GET /available    │ PUT /balance│
│        │ -availability    │ ?transaction_amt  │            │
└────────┼──────────────────┼───────────────────┼─────────────┘
         │                  │                   │
         ▼                  ▼                   ▼
┌─────────────────────────────────────────────────────────────┐
│                Advisory Node Service v2.0                   │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │    API      │  │Load Balancer│  │   Database Layer    │ │
│  │  Handlers   │  │   Engine    │  │                     │ │
│  │             │  │             │  │ ┌─────────────────┐ │ │
│  │ - Register  │  │ - Balance   │  │ │   PostgreSQL    │ │ │
│  │ - Available │  │   Check     │  │ │      OR         │ │ │
│  │ - Balance   │  │ - Fair      │  │ │     SQLite      │ │ │
│  │ - Health    │  │   Rotation  │  │ │                 │ │ │
│  │ - History   │  │ - Analytics │  │ │ • Quorums       │ │ │
│  └─────────────┘  └─────────────┘  │ │ • History       │ │ │
│                                    │ │ • Analytics     │ │ │
│  ┌─────────────────────────────────┐ │ └─────────────────┘ │ │
│  │       Background Services       │ └─────────────────────┘ │
│  │                                 │                       │
│  │ • Stale Quorum Cleanup (5 min)  │                       │
│  │ • Health Monitoring             │                       │
│  │ • Transaction Recording         │                       │
│  │ • Balance History Tracking      │                       │
│  └─────────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

## Development

### Project Structure
```
advisory-node/
├── main.go                    # Application entry point (database version)
├── main_memory.go             # Memory-only version
├── main_db.go                 # Database version entry point
├── models/
│   └── quorum.go              # Data models and API structures
├── storage/
│   ├── db_store.go            # Database storage implementation
│   ├── db_models.go           # Database table models
│   └── memory_store.go        # In-memory storage implementation
├── handlers/
│   ├── db_quorum_handler.go   # Database-backed API handlers
│   └── quorum_handler.go      # Memory-backed API handlers
├── examples/                  # Integration examples
├── docs/                      # Additional documentation
├── go.mod                     # Go module definition
├── go.sum                     # Dependency checksums
├── Dockerfile                 # Container configuration
├── render.yaml                # Deployment configuration
└── README.md                  # Documentation
```

## Testing and Examples

### Basic API Testing

```bash
# Register a quorum with balance
curl -X POST https://advisory-node-service.onrender.com/api/quorum/register \
  -H "Content-Type: application/json" \
  -d '{
    "did": "bafybmi123456789012345678901234567890123456789012345678901234",
    "peer_id": "12D3KooWTest",
    "balance": 50.0,
    "did_type": 4
  }'

# Get available quorums for a 100 RBT transaction
curl "https://advisory-node-service.onrender.com/api/quorum/available?count=5&transaction_amount=100"

# Update quorum balance
curl -X PUT https://advisory-node-service.onrender.com/api/quorum/balance \
  -H "Content-Type: application/json" \
  -d '{
    "did": "bafybmi123456789012345678901234567890123456789012345678901234",
    "balance": 75.0
  }'

# Get transaction history
curl "https://advisory-node-service.onrender.com/api/quorum/transactions?limit=50"

# Check health
curl https://advisory-node-service.onrender.com/api/quorum/health

# Unregister a quorum
curl -X DELETE "https://advisory-node-service.onrender.com/api/quorum/unregister/bafybmi123456789012345678901234567890123456789012345678901234"
```

### Production Deployment

The service is currently deployed at: `https://advisory-node-service.onrender.com`

For local testing, replace the URL with `http://localhost:8080`

## Troubleshooting

### Common Issues

#### "Not enough quorums with required balance" Error

**Problem**: When calling `/api/quorum/available`, you get an error about insufficient balance.

**Cause**: Quorums don't have enough RBT balance to participate in the transaction.

**Solution**:
1. Check current quorum balances: `GET /api/quorum/info/:did`
2. Update quorum balances: `PUT /api/quorum/balance`
3. Reduce transaction amount or increase quorum balances
4. Consider using fewer quorums (increases individual balance requirement)

**Example**:
```bash
# Check what balance quorums currently have
curl "https://advisory-node-service.onrender.com/api/quorum/info/bafybmi..."

# Update balance if needed
curl -X PUT https://advisory-node-service.onrender.com/api/quorum/balance \
  -H "Content-Type: application/json" \
  -d '{"did": "bafybmi...", "balance": 50.0}'
```

#### No Available Quorums

**Problem**: No quorums returned even with sufficient balance.

**Possible Causes**:
1. All quorums are offline (haven't sent heartbeat in 5+ minutes)
2. No quorums registered
3. All quorums marked as unavailable

**Solution**:
1. Check quorum heartbeats: `POST /api/quorum/heartbeat`
2. Confirm availability: `POST /api/quorum/confirm-availability`
3. Register new quorums: `POST /api/quorum/register`

#### Database Connection Issues

**Problem**: Service fails to start with database errors.

**Solution**:
1. Verify database configuration
2. Check DATABASE_URL format
3. Ensure database exists and is accessible
4. Check network connectivity to database

### Performance Considerations

- **Balance Updates**: Update quorum balances regularly to avoid transaction failures
- **Heartbeats**: Send heartbeats every 2-3 minutes to maintain availability
- **Database**: Use PostgreSQL for production, SQLite for development
- **Monitoring**: Monitor `/api/quorum/health` endpoint for service status

## Future Enhancements

- Enhanced metrics and monitoring (Prometheus integration)
- WebSocket support for real-time balance updates
- Quorum reputation scoring based on transaction success
- Geographic distribution awareness for network optimization
- Advanced rate limiting and authentication mechanisms
- High availability cluster mode
- Advanced analytics and reporting dashboard

## License

This project is part of the RubixGo platform ecosystem.
