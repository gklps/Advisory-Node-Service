#!/bin/bash

# Script to populate advisory node with test quorum data
ADVISORY_URL="http://localhost:8082"

echo "Populating Advisory Node with test quorum data..."
echo "=========================================="

# Array of test DIDs (59 character bafybmi format)
DIDS=(
    "bafybmibpoc7btbpw7gztgmya5tzofcndem5jgewhtd5yl32kjxzst5flje"
    "bafybmiabc1234567890abcdefghijklmnopqrstuvwxyz12345678901234"
    "bafybmidef4567890123456789abcdefghijklmnopqrstuvwxyz1234567"
    "bafybmighi7890123456789012345abcdefghijklmnopqrstuvwxyz12345"
    "bafybmijkl0123456789012345678901abcdefghijklmnopqrstuvwxyz12"
    "bafybmimno3456789012345678901234567abcdefghijklmnopqrstuvwx"
    "bafybmipqr6789012345678901234567890123abcdefghijklmnopqrstu"
    "bafybmistu9012345678901234567890123456789abcdefghijklmnopqr"
    "bafybmivwx2345678901234567890123456789012345abcdefghijklmno"
    "bafybmiyza5678901234567890123456789012345678901abcdefghijkl"
)

# Array of peer IDs
PEER_IDS=(
    "12D3KooWHwsKu3GS9rh5X5eS9RTKGFy6NcdX1bV1UHcH8sQ8WqCM"
    "12D3KooWQ2as3FNtvL1MKTeo7XAuBZxSv8QqobxX4AmURxyNe5mX"
    "12D3KooWJUJz2ipK78LAiwhc1QUVDvSMjZNBHt4vSAeVAq6FsneA"
    "12D3KooWC5fHUg2yzAHydgenodN52MYPKhpK4DKRfS8TSm3idSUV"
    "12D3KooWDd7c7DAVb38a9vfCFpqxh5nHbDQ4CYjMJuFfBgzpiagK"
    "12D3KooWLmKiYg5JrVHJGHKkWSSNXDKqh8sYFASK4KjM87L8tFv2"
    "12D3KooWRqVnNFYjFKkPFRgHpVjgR8ipLMXqRApnQKkbRq9gVNxc"
    "12D3KooWFGDqgQMFnJHkxjKJrYNq8GpbHsGg3FnQfNbAQkYkWQvM"
    "12D3KooWPjKPqFpLVHJNhg8qVKhGYnXGJkjhQvQ3rBNxYTNjKFvS"
    "12D3KooWNRxLmKiYg5JrVH4GHKkWSSNMKqh8sYGASK4KjM87LqPv5"
)

# Array of balances (varied amounts)
BALANCES=(100.5 250.75 500.0 1000.25 750.0 325.50 450.75 600.0 800.25 150.0)

# Array of DID types (0-4)
DID_TYPES=(0 1 2 3 4 0 1 2 3 0)

# Function to register a quorum
register_quorum() {
    local did=$1
    local peer_id=$2
    local balance=$3
    local did_type=$4
    
    echo "Registering quorum: $peer_id (Balance: $balance RBT, Type: $did_type)"
    
    curl -X POST "$ADVISORY_URL/api/quorum/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"did\": \"$did\",
            \"peer_id\": \"$peer_id\",
            \"balance\": $balance,
            \"did_type\": $did_type
        }" \
        -s -o /dev/null
    
    # Confirm availability
    curl -X POST "$ADVISORY_URL/api/quorum/confirm-availability" \
        -H "Content-Type: application/json" \
        -d "{\"did\": \"$did\"}" \
        -s -o /dev/null
        
    # Send heartbeat
    curl -X POST "$ADVISORY_URL/api/quorum/heartbeat" \
        -H "Content-Type: application/json" \
        -d "{\"did\": \"$did\"}" \
        -s -o /dev/null
    
    echo "✓ Registered and confirmed"
}

# Register all test quorums
for i in {0..9}; do
    register_quorum "${DIDS[$i]}" "${PEER_IDS[$i]}" "${BALANCES[$i]}" "${DID_TYPES[$i]}"
    sleep 0.1  # Small delay to avoid overwhelming the server
done

echo ""
echo "=========================================="
echo "Test data population complete!"
echo ""

# Check health status
echo "Checking advisory node status..."
curl -s "$ADVISORY_URL/api/quorum/health" | jq .

echo ""
echo "Test quorum fetch (5 quorums, 100 RBT transaction):"
curl -s "$ADVISORY_URL/api/quorum/available?count=5&transaction_amount=100" | jq .