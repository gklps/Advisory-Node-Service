#!/bin/bash

# Test Quorum Registration Script
# Tests the fixed DID generation and registration API

set -e

PRODUCTION_URL="${1:-https://mainnet-pool.universe.rubix.net}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}=== $1 ===${NC}"; }

# Function to generate a valid DID (59 characters total: bafybmi + 52 chars)
generate_valid_did() {
    local index=$1
    # Generate 52 character suffix using hex
    local hex_suffix=$(printf "%052x" $((index + 5000000)))
    echo "bafybmi${hex_suffix}"
}

# Function to generate a valid PeerID
generate_valid_peer_id() {
    local index=$1
    # Generate a realistic PeerID format (52 chars after 12D3KooW)
    local hex_suffix=$(printf "%044x" $((index + 6000000)))
    echo "12D3KooW${hex_suffix}"
}

# Function to validate DID format
validate_did() {
    local did=$1
    
    print_status "Validating DID: $did"
    
    # Check length
    if [[ ${#did} -ne 59 ]]; then
        print_error "DID length is ${#did}, expected 59"
        return 1
    fi
    
    # Check prefix
    if [[ ! "$did" =~ ^bafybmi ]]; then
        print_error "DID doesn't start with 'bafybmi'"
        return 1
    fi
    
    # Check alphanumeric
    if [[ ! "$did" =~ ^[a-zA-Z0-9]+$ ]]; then
        print_error "DID contains non-alphanumeric characters"
        return 1
    fi
    
    print_status "✅ DID format is valid"
    return 0
}

# Function to test quorum registration
test_registration() {
    local index=$1
    local balance=$2
    
    print_header "Testing Quorum Registration #$index"
    
    local did=$(generate_valid_did $index)
    local peer_id=$(generate_valid_peer_id $index)
    
    # Validate DID format
    if ! validate_did "$did"; then
        return 1
    fi
    
    print_status "Generated DID: $did"
    print_status "Generated PeerID: $peer_id"
    print_status "Balance: $balance RBT"
    
    # Create registration payload
    local payload=$(cat << EOF
{
  "did": "$did",
  "peer_id": "$peer_id",
  "balance": $balance,
  "did_type": 1
}
EOF
)
    
    print_status "Registration payload:"
    echo "$payload" | jq .
    
    # Attempt registration
    print_status "Attempting registration..."
    
    local response=$(curl -s -w "%{http_code}" "$PRODUCTION_URL/api/quorum/register" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    # Parse response (handle curl -w format)
    local body=$(echo "$response" | sed '$d')
    local http_code=$(echo "$response" | tail -n 1)
    
    print_status "HTTP Status: $http_code"
    print_status "Response body:"
    echo "$body" | jq . 2>/dev/null || echo "$body"
    
    # Check if registration was successful
    if [[ "$http_code" == "200" ]]; then
        local status=$(echo "$body" | jq -r '.status // false')
        if [[ "$status" == "true" ]]; then
            print_status "✅ Registration successful!"
            
            # Test heartbeat
            print_status "Testing heartbeat..."
            local heartbeat_response=$(curl -s -w "%{http_code}" "$PRODUCTION_URL/api/quorum/heartbeat" \
                -X POST \
                -H "Content-Type: application/json" \
                -d "{\"did\": \"$did\"}")
            
            local hb_body=$(echo "$heartbeat_response" | head -n -1)
            local hb_code=$(echo "$heartbeat_response" | tail -n 1)
            
            if [[ "$hb_code" == "200" ]]; then
                print_status "✅ Heartbeat successful!"
            else
                print_warning "❌ Heartbeat failed (HTTP $hb_code): $hb_body"
            fi
            
            return 0
        else
            local message=$(echo "$body" | jq -r '.message // "Unknown error"')
            print_error "❌ Registration failed: $message"
            return 1
        fi
    else
        print_error "❌ Registration failed with HTTP $http_code"
        echo "$body"
        return 1
    fi
}

# Function to test balance update
test_balance_update() {
    local did=$1
    local new_balance=$2
    
    print_header "Testing Balance Update"
    
    local payload=$(cat << EOF
{
  "did": "$did",
  "balance": $new_balance
}
EOF
)
    
    print_status "Updating balance for DID: $did"
    print_status "New balance: $new_balance RBT"
    
    local response=$(curl -s -w "%{http_code}" "$PRODUCTION_URL/api/quorum/balance" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    # Parse response (handle curl -w format)
    local body=$(echo "$response" | sed '$d')
    local http_code=$(echo "$response" | tail -n 1)
    
    print_status "HTTP Status: $http_code"
    print_status "Response: $body"
    
    if [[ "$http_code" == "200" ]]; then
        print_status "✅ Balance update successful!"
        return 0
    else
        print_error "❌ Balance update failed"
        return 1
    fi
}

# Function to test quorum availability after registration
test_availability() {
    local transaction_amount=$1
    local quorum_count=$2
    
    print_header "Testing Quorum Availability"
    
    print_status "Requesting $quorum_count quorums for $transaction_amount RBT transaction"
    
    local response=$(curl -s "$PRODUCTION_URL/api/quorum/available?count=$quorum_count&transaction_amount=$transaction_amount")
    
    print_status "Availability response:"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    
    local status=$(echo "$response" | jq -r '.status // false')
    if [[ "$status" == "true" ]]; then
        local available_count=$(echo "$response" | jq -r '.quorums | length // 0')
        print_status "✅ Found $available_count available quorums"
        return 0
    else
        local message=$(echo "$response" | jq -r '.message // "Unknown error"')
        print_warning "❌ No quorums available: $message"
        return 1
    fi
}

# Main execution
main() {
    print_header "Quorum Registration Testing"
    print_status "Production URL: $PRODUCTION_URL"
    echo ""
    
    # Test 1: Register a quorum with sufficient balance
    if test_registration 1 1000.0; then
        local test_did=$(generate_valid_did 1)
        
        echo ""
        
        # Test 2: Update balance
        test_balance_update "$test_did" 2000.0
        
        echo ""
        
        # Test 3: Test availability
        test_availability 100.0 5
        
        echo ""
        
        # Test 4: Check health after registration
        print_header "Final Health Check"
        local health=$(curl -s "$PRODUCTION_URL/api/quorum/health")
        print_status "Service health after registration:"
        echo "$health" | jq . 2>/dev/null || echo "$health"
        
    else
        print_error "Registration test failed. Check the error messages above."
    fi
    
    echo ""
    print_header "Testing Complete!"
}

# Cleanup function
cleanup() {
    print_status "Registration testing completed"
}

trap cleanup EXIT

# Run main function
main "$@"
