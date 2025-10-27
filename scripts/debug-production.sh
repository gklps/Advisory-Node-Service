#!/bin/bash

# Debug Production Advisory Node Service
# Investigates why quorums are not available

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

print_header "Production Advisory Node Debug"
print_status "URL: $PRODUCTION_URL"
echo ""

# Check service health
print_header "1. Service Health Check"
health_response=$(curl -s "$PRODUCTION_URL/api/quorum/health")
echo "Raw response: $health_response"
echo ""

if echo "$health_response" | jq . >/dev/null 2>&1; then
    status=$(echo "$health_response" | jq -r '.status // "unknown"')
    total_quorums=$(echo "$health_response" | jq -r '.total_quorums // 0')
    available_quorums=$(echo "$health_response" | jq -r '.available_quorums // 0')
    last_check=$(echo "$health_response" | jq -r '.last_check // "unknown"')
    
    print_status "Service Status: $status"
    print_status "Total Quorums: $total_quorums"
    print_status "Available Quorums: $available_quorums"
    print_status "Last Check: $last_check"
else
    print_error "Invalid JSON response from health endpoint"
fi

echo ""

# Test availability endpoint with different parameters
print_header "2. Testing Availability Endpoint"

test_scenarios=(
    "1,1"      # Minimal request
    "10,3"     # Small transaction
    "50,5"     # Medium transaction  
    "100,7"    # Large transaction
    "1,10"     # Many quorums, small amount
)

for scenario in "${test_scenarios[@]}"; do
    IFS=',' read -r amount count <<< "$scenario"
    
    print_status "Testing: $amount RBT with $count quorums"
    
    response=$(curl -s "$PRODUCTION_URL/api/quorum/available?count=$count&transaction_amount=$amount")
    
    if echo "$response" | jq . >/dev/null 2>&1; then
        status=$(echo "$response" | jq -r '.status // false')
        message=$(echo "$response" | jq -r '.message // "No message"')
        quorum_count=$(echo "$response" | jq -r '.quorums | length // 0')
        
        if [[ "$status" == "true" ]]; then
            print_status "  ✅ Success: Got $quorum_count quorums"
        else
            print_warning "  ❌ Failed: $message"
        fi
    else
        print_error "  Invalid JSON response"
        echo "  Raw response: $response"
    fi
    
    echo ""
done

# Check if transaction history endpoint exists
print_header "3. Transaction History Check"
history_response=$(curl -s -w "%{http_code}" "$PRODUCTION_URL/api/quorum/transactions?limit=5")
history_body=$(echo "$history_response" | head -n -1)
history_code=$(echo "$history_response" | tail -n 1)

print_status "HTTP Code: $history_code"

if [[ "$history_code" == "200" ]]; then
    if echo "$history_body" | jq . >/dev/null 2>&1; then
        transaction_count=$(echo "$history_body" | jq -r '.history | length // 0')
        print_status "Recent transactions found: $transaction_count"
        
        if [[ "$transaction_count" -gt 0 ]]; then
            print_status "Recent transaction details:"
            echo "$history_body" | jq -r '.history[] | "  Amount: \(.transaction_amount) RBT, Required: \(.required_balance) per quorum"' | head -3
        fi
    else
        print_warning "Invalid JSON in transaction history response"
    fi
else
    print_warning "Transaction history endpoint returned HTTP $history_code"
fi

echo ""

# Test root endpoint
print_header "4. Root Endpoint Check"
root_response=$(curl -s "$PRODUCTION_URL/")
print_status "Root endpoint response:"
echo "$root_response"

echo ""

# Test with curl verbose to see what's happening
print_header "5. Detailed Connection Test"
print_status "Testing connection with verbose output..."
curl -v -s "$PRODUCTION_URL/api/quorum/health" 2>&1 | head -20

echo ""

# Summary and recommendations
print_header "6. Summary & Recommendations"

if [[ "$available_quorums" -eq 0 ]]; then
    print_warning "Issue: No quorums are currently available"
    print_status "Possible reasons:"
    print_status "  1. All quorums haven't sent heartbeat recently (>5 min)"
    print_status "  2. All quorums are marked as unavailable"
    print_status "  3. All quorums have insufficient balance for any transaction"
    print_status "  4. Database connectivity issues"
    
    echo ""
    print_status "Recommendations:"
    print_status "  1. Check if quorums are sending heartbeats"
    print_status "  2. Verify quorum balances in database"
    print_status "  3. Check database connectivity"
    print_status "  4. Review service logs for errors"
    
    echo ""
    print_status "For testing purposes, you can:"
    print_status "  1. Use the production-test.sh script (doesn't register new quorums)"
    print_status "  2. Test against your local VM deployment instead"
    print_status "  3. Check if quorums need to be re-registered or have balances updated"
fi

print_status "Debug completed!"

