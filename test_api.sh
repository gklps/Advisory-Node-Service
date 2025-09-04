#!/bin/bash

# Test script for Advisory Node API endpoints
# Usage: ./test_api.sh

BASE_URL="http://localhost:8080"

echo "Testing Advisory Node API..."
echo "============================"

# Function to generate a valid DID (59 chars starting with bafybmi)
generate_did() {
    echo "bafybmi$(openssl rand -hex 26 | cut -c1-52)"
}

# Test health endpoint
echo -e "\n1. Testing health endpoint..."
curl -s "$BASE_URL/api/quorum/health" | jq .

# Register multiple quorums
echo -e "\n2. Registering test quorums..."
for i in {1..10}; do
    DID=$(generate_did)
    PEER_ID="12D3KooWTestPeer$i"
    
    echo "   Registering quorum $i with DID: $DID"
    
    curl -s -X POST "$BASE_URL/api/quorum/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"did\": \"$DID\",
            \"peer_id\": \"$PEER_ID\",
            \"balance\": 0,
            \"did_type\": 1
        }" | jq -c .
        
    # Save first DID for later tests
    if [ $i -eq 1 ]; then
        TEST_DID=$DID
    fi
done

# Confirm availability for first quorum
echo -e "\n3. Confirming availability for first quorum..."
curl -s -X POST "$BASE_URL/api/quorum/confirm-availability" \
    -H "Content-Type: application/json" \
    -d "{\"did\": \"$TEST_DID\"}" | jq .

# Get available quorums
echo -e "\n4. Getting 7 available quorums..."
curl -s "$BASE_URL/api/quorum/available?count=7" | jq .

# Update heartbeat
echo -e "\n5. Updating heartbeat for first quorum..."
curl -s -X POST "$BASE_URL/api/quorum/heartbeat" \
    -H "Content-Type: application/json" \
    -d "{\"did\": \"$TEST_DID\"}" | jq .

# Get quorum info
echo -e "\n6. Getting info for first quorum..."
curl -s "$BASE_URL/api/quorum/info/$TEST_DID" | jq .

# Test with last_char_tid filter
echo -e "\n7. Testing with last_char_tid filter..."
LAST_CHAR="${TEST_DID: -1}"
echo "   Filtering by last character: $LAST_CHAR"
curl -s "$BASE_URL/api/quorum/available?count=5&last_char_tid=$LAST_CHAR" | jq .

# Check health again
echo -e "\n8. Final health check..."
curl -s "$BASE_URL/api/quorum/health" | jq .

# Unregister first quorum
echo -e "\n9. Unregistering first quorum..."
curl -s -X DELETE "$BASE_URL/api/quorum/unregister/$TEST_DID" | jq .

# Verify unregistration
echo -e "\n10. Verifying quorum was unregistered (should fail)..."
curl -s "$BASE_URL/api/quorum/info/$TEST_DID" | jq .

echo -e "\n============================"
echo "Test completed!"