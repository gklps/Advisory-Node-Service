#!/bin/bash

# Advisory Node Load Testing Script
# Tests quorum allocation, balance validation, and concurrent request handling

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS_DIR="$SCRIPT_DIR/test-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEST_LOG="$TEST_RESULTS_DIR/load_test_$TIMESTAMP.log"

# Test configuration
TESTNET_URL="https://mainnet-pool.universe.rubix.net"
MAINNET_URL="https://mainnet-pool.universe.rubix.net"
CONCURRENT_REQUESTS=1000
TEST_DURATION=60  # seconds
QUORUM_COUNT=5
TRANSACTION_AMOUNTS=(10 50 100 500 1000)

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$TEST_LOG"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$TEST_LOG"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$TEST_LOG"
}

print_header() {
    echo -e "${BLUE}[TEST]${NC} $1" | tee -a "$TEST_LOG"
}

# Create test results directory
mkdir -p "$TEST_RESULTS_DIR"

echo "=========================================" | tee "$TEST_LOG"
echo "Advisory Node Load Testing Suite" | tee -a "$TEST_LOG"
echo "Started: $(date)" | tee -a "$TEST_LOG"
echo "=========================================" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Test environment selection
echo "Select test environment:"
echo "1) Testnet (localhost:8080)"
echo "2) Mainnet (localhost:8081)"
echo "3) Both environments"
read -p "Enter choice (1-3): " ENV_CHOICE

case $ENV_CHOICE in
    1) TEST_URLS=("$TESTNET_URL"); ENV_NAMES=("testnet") ;;
    2) TEST_URLS=("$MAINNET_URL"); ENV_NAMES=("mainnet") ;;
    3) TEST_URLS=("$TESTNET_URL" "$MAINNET_URL"); ENV_NAMES=("testnet" "mainnet") ;;
    *) print_error "Invalid choice. Defaulting to testnet."; TEST_URLS=("$TESTNET_URL"); ENV_NAMES=("testnet") ;;
esac

# Function to generate a valid DID (59 characters total: bafybmi + 52 chars)
generate_valid_did() {
    local index=$1
    # Generate 52 character suffix using base conversion to stay within alphanumeric
    local hex_suffix=$(printf "%052x" $((index + 1000000)))
    echo "bafybmi${hex_suffix}"
}

# Function to generate a valid PeerID
generate_valid_peer_id() {
    local index=$1
    # Generate a realistic PeerID format (52 chars after 12D3KooW)
    local hex_suffix=$(printf "%044x" $((index + 2000000)))
    echo "12D3KooW${hex_suffix}"
}

# Function to generate test quorum data
generate_test_quorum() {
    local index=$1
    local balance=$2
    
    local did=$(generate_valid_did $index)
    local peer_id=$(generate_valid_peer_id $index)
    
    cat << EOF
{
  "did": "$did",
  "peer_id": "$peer_id",
  "balance": $balance,
  "did_type": 1
}
EOF
}

# Function to register test quorums
register_test_quorums() {
    local base_url=$1
    local env_name=$2
    local count=$3
    
    print_header "Registering $count test quorums for $env_name"
    
    local success_count=0
    local failed_count=0
    
    for i in $(seq 1 $count); do
        # Vary balances to test different scenarios
        local balance=$((50 + (i % 10) * 10))  # Balances from 50 to 140
        
        local response=$(curl -s -w "%{http_code}" -o /tmp/register_response_$i.json \
            -X POST "$base_url/api/quorum/register" \
            -H "Content-Type: application/json" \
            -d "$(generate_test_quorum $i $balance)")
        
        if [[ "$response" == "200" ]]; then
            ((success_count++))
        else
            ((failed_count++))
            print_warning "Failed to register quorum $i (HTTP: $response)"
        fi
        
        # Progress indicator
        if (( i % 10 == 0 )); then
            echo -n "." | tee -a "$TEST_LOG"
        fi
    done
    
    echo "" | tee -a "$TEST_LOG"
    print_status "Registered $success_count quorums successfully, $failed_count failed"
    
    # Wait for registration to settle
    sleep 2
}

# Function to test quorum availability
test_quorum_availability() {
    local base_url=$1
    local env_name=$2
    local transaction_amount=$3
    local count=$4
    
    print_header "Testing quorum availability: $transaction_amount RBT, $count quorums ($env_name)"
    
    local response=$(curl -s "$base_url/api/quorum/available?count=$count&transaction_amount=$transaction_amount")
    local status=$(echo "$response" | jq -r '.status // false')
    local message=$(echo "$response" | jq -r '.message // "No message"')
    local quorum_count=$(echo "$response" | jq -r '.quorums | length // 0')
    
    if [[ "$status" == "true" ]]; then
        print_status "✅ Found $quorum_count quorums for $transaction_amount RBT"
        echo "   Required balance per quorum: $((transaction_amount / count)) RBT" | tee -a "$TEST_LOG"
    else
        print_warning "❌ Insufficient quorums: $message"
    fi
    
    echo "$response" > "$TEST_RESULTS_DIR/${env_name}_availability_${transaction_amount}RBT_${count}quorums.json"
}

# Function to perform concurrent requests
concurrent_request_test() {
    local base_url=$1
    local env_name=$2
    local num_requests=$3
    local transaction_amount=$4
    
    print_header "Concurrent Request Test: $num_requests requests for $transaction_amount RBT ($env_name)"
    
    local temp_dir="/tmp/advisory_test_$$"
    mkdir -p "$temp_dir"
    
    local start_time=$(date +%s.%N)
    
    # Launch concurrent requests
    for i in $(seq 1 $num_requests); do
        {
            local response=$(curl -s -w "%{time_total},%{http_code}" \
                "$base_url/api/quorum/available?count=$QUORUM_COUNT&transaction_amount=$transaction_amount")
            echo "$i,$response" >> "$temp_dir/results.csv"
        } &
        
        # Limit concurrent processes to avoid overwhelming the system
        if (( i % 50 == 0 )); then
            wait
        fi
    done
    
    # Wait for all requests to complete
    wait
    
    local end_time=$(date +%s.%N)
    local total_time=$(echo "$end_time - $start_time" | bc)
    
    # Analyze results
    local total_requests=$(wc -l < "$temp_dir/results.csv")
    local successful_requests=$(grep ",200$" "$temp_dir/results.csv" | wc -l)
    local failed_requests=$((total_requests - successful_requests))
    local avg_response_time=$(awk -F',' '{sum+=$2} END {print sum/NR}' "$temp_dir/results.csv")
    
    print_status "Concurrent test completed in ${total_time}s"
    print_status "Total requests: $total_requests"
    print_status "Successful: $successful_requests ($(( successful_requests * 100 / total_requests ))%)"
    print_status "Failed: $failed_requests"
    print_status "Average response time: ${avg_response_time}s"
    
    # Copy results to test results directory
    cp "$temp_dir/results.csv" "$TEST_RESULTS_DIR/${env_name}_concurrent_${num_requests}req_${transaction_amount}RBT.csv"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    # Cool down period
    sleep 5
}

# Function to test quorum allocation fairness
test_allocation_fairness() {
    local base_url=$1
    local env_name=$2
    
    print_header "Testing Quorum Allocation Fairness ($env_name)"
    
    local allocation_data="$TEST_RESULTS_DIR/${env_name}_allocation_fairness.json"
    echo "[]" > "$allocation_data"
    
    # Make multiple requests and track which quorums are allocated
    for i in $(seq 1 20); do
        local response=$(curl -s "$base_url/api/quorum/available?count=3&transaction_amount=30")
        local quorums=$(echo "$response" | jq -r '.quorums[]?.address // empty')
        
        if [[ -n "$quorums" ]]; then
            echo "$response" | jq '.quorums[]?.address' >> "$TEST_RESULTS_DIR/${env_name}_allocations.txt"
        fi
        
        sleep 1  # Small delay between requests
    done
    
    # Analyze allocation distribution
    if [[ -f "$TEST_RESULTS_DIR/${env_name}_allocations.txt" ]]; then
        print_status "Allocation distribution analysis:"
        sort "$TEST_RESULTS_DIR/${env_name}_allocations.txt" | uniq -c | sort -nr | head -10 | tee -a "$TEST_LOG"
    fi
}

# Function to test transaction history
test_transaction_history() {
    local base_url=$1
    local env_name=$2
    
    print_header "Testing Transaction History ($env_name)"
    
    local response=$(curl -s "$base_url/api/quorum/transactions?limit=50")
    local status=$(echo "$response" | jq -r '.status // false')
    
    if [[ "$status" == "true" ]]; then
        local transaction_count=$(echo "$response" | jq -r '.history | length // 0')
        print_status "✅ Retrieved $transaction_count transaction records"
        
        # Save transaction history
        echo "$response" > "$TEST_RESULTS_DIR/${env_name}_transaction_history.json"
        
        # Analyze transaction patterns
        if [[ "$transaction_count" -gt 0 ]]; then
            print_status "Recent transaction analysis:"
            echo "$response" | jq -r '.history[] | "\(.transaction_amount) RBT - \(.required_balance) per quorum"' | head -5 | tee -a "$TEST_LOG"
        fi
    else
        print_warning "❌ Failed to retrieve transaction history"
    fi
}

# Function to test service health under load
test_service_health() {
    local base_url=$1
    local env_name=$2
    
    print_header "Testing Service Health Under Load ($env_name)"
    
    # Test health endpoint responsiveness during load
    local health_start=$(date +%s.%N)
    local health_response=$(curl -s -w "%{time_total}" "$base_url/api/quorum/health")
    local health_time=$(echo "$health_response" | tail -1)
    local health_end=$(date +%s.%N)
    
    print_status "Health endpoint response time: ${health_time}s"
    
    # Check if service is still responsive
    local status=$(echo "$health_response" | head -n -1 | jq -r '.status // "unknown"')
    if [[ "$status" == "running" ]]; then
        print_status "✅ Service health check passed"
    else
        print_warning "❌ Service health check failed or degraded"
    fi
}

# Function to generate load test report
generate_report() {
    local report_file="$TEST_RESULTS_DIR/load_test_report_$TIMESTAMP.html"
    
    print_header "Generating Load Test Report"
    
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Advisory Node Load Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .success { color: green; }
        .warning { color: orange; }
        .error { color: red; }
        .test-section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Advisory Node Load Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Test Duration: $(date -d @$SECONDS -u +%H:%M:%S)</p>
    </div>
EOF

    # Add test results to report
    echo "    <div class='test-section'>" >> "$report_file"
    echo "        <h2>Test Summary</h2>" >> "$report_file"
    echo "        <p>Concurrent Requests: $CONCURRENT_REQUESTS</p>" >> "$report_file"
    echo "        <p>Environments Tested: ${ENV_NAMES[*]}</p>" >> "$report_file"
    echo "        <p>Transaction Amounts: ${TRANSACTION_AMOUNTS[*]} RBT</p>" >> "$report_file"
    echo "    </div>" >> "$report_file"
    
    # Add log content
    echo "    <div class='test-section'>" >> "$report_file"
    echo "        <h2>Test Log</h2>" >> "$report_file"
    echo "        <pre>" >> "$report_file"
    cat "$TEST_LOG" >> "$report_file"
    echo "        </pre>" >> "$report_file"
    echo "    </div>" >> "$report_file"
    
    echo "</body></html>" >> "$report_file"
    
    print_status "Report generated: $report_file"
}

# Main test execution
main() {
    print_header "Starting Advisory Node Load Testing"
    
    # Test each environment
    for i in "${!TEST_URLS[@]}"; do
        local base_url="${TEST_URLS[$i]}"
        local env_name="${ENV_NAMES[$i]}"
        
        print_header "Testing Environment: $env_name ($base_url)"
        
        # Check if service is accessible
        if ! curl -s --connect-timeout 5 "$base_url/api/quorum/health" >/dev/null; then
            print_error "Service not accessible at $base_url"
            continue
        fi
        
        print_status "Service is accessible, starting tests..."
        
        # Register test quorums
        register_test_quorums "$base_url" "$env_name" 50
        
        # Test quorum availability for different transaction amounts
        for amount in "${TRANSACTION_AMOUNTS[@]}"; do
            test_quorum_availability "$base_url" "$env_name" "$amount" "$QUORUM_COUNT"
        done
        
        # Test allocation fairness
        test_allocation_fairness "$base_url" "$env_name"
        
        # Concurrent load testing
        for amount in "${TRANSACTION_AMOUNTS[@]}"; do
            concurrent_request_test "$base_url" "$env_name" "$CONCURRENT_REQUESTS" "$amount"
        done
        
        # Test transaction history
        test_transaction_history "$base_url" "$env_name"
        
        # Test service health after load
        test_service_health "$base_url" "$env_name"
        
        print_status "Completed testing for $env_name"
        echo "" | tee -a "$TEST_LOG"
    done
    
    # Generate final report
    generate_report
    
    print_header "Load Testing Completed!"
    print_status "Results saved in: $TEST_RESULTS_DIR"
    print_status "Test log: $TEST_LOG"
    print_status "HTML report: $TEST_RESULTS_DIR/load_test_report_$TIMESTAMP.html"
}

# Cleanup function
cleanup() {
    print_status "Cleaning up test data..."
    
    for base_url in "${TEST_URLS[@]}"; do
        # Unregister test quorums (if needed)
        # This would require implementing an unregister endpoint or database cleanup
        print_status "Test quorums remain in database for analysis"
    done
}

# Signal handlers
trap cleanup EXIT
trap 'print_error "Test interrupted"; exit 1' INT TERM

# Run main test suite
main "$@"
