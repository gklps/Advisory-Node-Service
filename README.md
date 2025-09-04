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

### Query Endpoints

#### GET /api/quorum/available
Get available quorums with load balancing.

**Query Parameters:**
- `count` (optional): Number of quorums needed (default: 7)
- `last_char_tid` (optional): For type-1 quorum filtering
- `type` (optional): Quorum type (default: 2)

**Response:**
```json
{
  "status": true,
  "message": "Quorums retrieved successfully",
  "quorums": [
    {
      "type": 2,
      "address": "12D3KooWPeer1.bafybmihash1test..."
    }
  ]
}
```

#### GET /api/quorum/info/:did
Get detailed information about a specific quorum.

#### GET /api/quorum/health
Get health status of the advisory node service.

## Installation

1. Clone the repository:
```bash
cd /Users/gokul/Library/CloudStorage/OneDrive-RubixNetworkingSolutionsPvtLtd/Documents/GitHub/advisory-node
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

### Basic Usage
```bash
./advisory-node
```

### With Custom Configuration
```bash
./advisory-node -port=8080 -mode=debug -cors="http://localhost:3000"
```

### Command Line Options
- `-port`: Server port (default: 8080)
- `-mode`: Server mode - debug/release (default: release)
- `-cors`: CORS allowed origins (default: *)



## Load Balancing Algorithm

The advisory node implements a fair load balancing algorithm:

1. **Assignment Tracking**: Tracks the number of assignments per quorum
2. **Time-based Rotation**: Considers the last assignment time
3. **Availability Filtering**: Only returns quorums that have pinged within the last 5 minutes
4. **Fair Distribution**: Sorts quorums by assignment count (ascending) to ensure even distribution

## Monitoring

The service includes:
- Health endpoint for monitoring service status
- Automatic cleanup of stale quorums (not pinged in 10+ minutes)
- Request logging with latency metrics
- Graceful shutdown handling

## Architecture

```
┌─────────────────┐
│  RubixGo Node   │
│                 │
│  ┌───────────┐  │
│  │setupquorum│  │──────► POST /api/quorum/confirm-availability
│  └───────────┘  │
│                 │
│  ┌───────────┐  │
│  │ Transfer  │  │──────► GET /api/quorum/available
│  │ Initiator │  │
│  └───────────┘  │
└─────────────────┘
         ▲
         │
         ▼
┌─────────────────┐
│ Advisory Node   │
│                 │
│ ┌─────────────┐ │
│ │Memory Store │ │
│ │             │ │
│ │ - Quorums   │ │
│ │ - Metadata  │ │
│ │ - LB State  │ │
│ └─────────────┘ │
└─────────────────┘
```

## Development

### Project Structure
```
advisory-node/
├── main.go              # Application entry point
├── models/
│   └── quorum.go        # Data models
├── storage/
│   └── memory_store.go  # In-memory storage implementation
├── handlers/
│   └── quorum_handler.go # API request handlers
├── go.mod               # Go module definition
├── go.sum               # Dependency checksums
└── README.md            # Documentation
```

### Testing

Run the service and test with curl:

```bash
# Register a quorum
curl -X POST http://localhost:8080/api/quorum/register \
  -H "Content-Type: application/json" \
  -d '{
    "did": "bafybmi123456789012345678901234567890123456789012345678901234",
    "peer_id": "12D3KooWTest",
    "balance": 0,
    "did_type": 1
  }'

# Get available quorums
curl http://localhost:8080/api/quorum/available?count=7

# Check health
curl http://localhost:8080/api/quorum/health
```

## Future Enhancements

- Persistence layer (database support)
- Metrics and monitoring (Prometheus)
- WebSocket support for real-time updates
- Quorum reputation scoring
- Geographic distribution awareness
- Rate limiting and authentication
- Cluster mode for high availability

## License

This project is part of the RubixGo platform ecosystem.
