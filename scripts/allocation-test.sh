#!/bin/bash

# Quorum Allocation Testing Script
# Tests allocation fairness, balance validation, and assignment logic

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/allocation-test-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Configuration
BASE_URL="${1:-http://localhost:8080}"
TEST_QUORUMS=20
TEST_ROUNDS=50

mkdir -p "$RESULTS_DIR"

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

# Function to create test quorums with different balance levels
setup_test_quorums() {
    print_header "Setting up Test Quorums"
    
    local quorum_data_file="$RESULTS_DIR/test_quorums_$TIMESTAMP.json"
    echo "[]" > "$quorum_data_file"
    
    print_status "Creating $TEST_QUORUMS test quorums with varying balances..."
    
    for i in $(seq 1 $TEST_QUORUMS); do
        # Create different balance tiers for testing
        local balance
        if [[ $i -le 5 ]]; then
            balance=$((200 + i * 10))  # High balance: 210-250 RBT
        elif [[ $i -le 10 ]]; then
            balance=$((100 + (i-5) * 10))  # Medium balance: 110-150 RBT
        elif [[ $i -le 15 ]]; then
            balance=$((50 + (i-10) * 5))   # Low balance: 55-75 RBT
        else
            balance=$((10 + (i-15) * 2))   # Very low balance: 12-18 RBT
        fi
        
        # Generate valid DID (59 chars total: bafybmi + 52 chars)
        local did_suffix=$(printf "%052x" $((i + 3000000)))
        local did="bafybmi${did_suffix}"
        
        # Generate valid PeerID
        local peer_suffix=$(printf "%044x" $((i + 4000000)))
        local peer_id="12D3KooW${peer_suffix}"
        
        local quorum_data=$(cat << EOF
{
  "did": "$did",
  "peer_id": "$peer_id",
  "balance": $balance,
  "did_type": 1
}
EOF
)
        
        # Register quorum
        local response=$(curl -s -w "%{http_code}" -o /tmp/register_response.json \
            -X POST "$BASE_URL/api/quorum/register" \
            -H "Content-Type: application/json" \
            -d "$quorum_data")
        
        if [[ "$response" == "200" ]]; then
            # Store quorum info for analysis
            echo "$quorum_data" | jq ". + {\"registered\": true}" >> "$RESULTS_DIR/quorum_$i.json"
            print_status "✅ Registered quorum $i (Balance: $balance RBT)"
        else
            print_warning "❌ Failed to register quorum $i (HTTP: $response)"
            echo "$quorum_data" | jq ". + {\"registered\": false}" >> "$RESULTS_DIR/quorum_$i.json"
        fi
        
        # Small delay to avoid overwhelming the service
        sleep 0.1
    done
    
    # Combine all quorum data
    jq -s '.' "$RESULTS_DIR"/quorum_*.json > "$quorum_data_file"
    rm -f "$RESULTS_DIR"/quorum_*.json
    
    print_status "Test quorums setup completed"
    sleep 2  # Let the system settle
}

# Function to test allocation for different transaction amounts
test_allocation_patterns() {
    print_header "Testing Allocation Patterns"
    
    local allocation_log="$RESULTS_DIR/allocation_patterns_$TIMESTAMP.csv"
    echo "round,transaction_amount,quorum_count,requested_quorums,actual_quorums,success,required_balance,allocated_quorums" > "$allocation_log"
    
    # Test different transaction amounts
    local transaction_amounts=(10 25 50 100 200 500 1000)
    local quorum_counts=(3 5 7)
    
    for amount in "${transaction_amounts[@]}"; do
        for count in "${quorum_counts[@]}"; do
            local required_balance=$(echo "scale=2; $amount / $count" | bc)
            
            print_status "Testing: $amount RBT with $count quorums (required balance: $required_balance RBT per quorum)"
            
            for round in $(seq 1 10); do
                local response=$(curl -s "$BASE_URL/api/quorum/available?count=$count&transaction_amount=$amount")
                local status=$(echo "$response" | jq -r '.status // false')
                local actual_count=$(echo "$response" | jq -r '.quorums | length // 0')
                local quorum_addresses=$(echo "$response" | jq -r '.quorums[]?.address // empty' | tr '\n' ';')
                
                echo "$round,$amount,$count,$count,$actual_count,$status,$required_balance,\"$quorum_addresses\"" >> "$allocation_log"
                
                if [[ "$status" == "true" ]]; then
                    echo -n "✅"
                else
                    echo -n "❌"
                fi
                
                sleep 0.5  # Small delay between requests
            done
            echo ""  # New line after each test set
        done
    done
    
    print_status "Allocation pattern testing completed"
}

# Function to test load balancing fairness
test_load_balancing() {
    print_header "Testing Load Balancing Fairness"
    
    local fairness_log="$RESULTS_DIR/load_balancing_$TIMESTAMP.csv"
    echo "request_id,quorum_addresses,assignment_count" > "$fairness_log"
    
    print_status "Making $TEST_ROUNDS requests to analyze load distribution..."
    
    # Make multiple requests with same parameters
    local transaction_amount=100
    local quorum_count=5
    
    for i in $(seq 1 $TEST_ROUNDS); do
        local response=$(curl -s "$BASE_URL/api/quorum/available?count=$quorum_count&transaction_amount=$transaction_amount")
        local status=$(echo "$response" | jq -r '.status // false')
        
        if [[ "$status" == "true" ]]; then
            local quorum_addresses=$(echo "$response" | jq -r '.quorums[]?.address // empty' | tr '\n' ';')
            echo "$i,\"$quorum_addresses\",$quorum_count" >> "$fairness_log"
            echo -n "✅"
        else
            echo "$i,\"FAILED\",0" >> "$fairness_log"
            echo -n "❌"
        fi
        
        # Small delay to allow system to process
        sleep 1
    done
    echo ""
    
    # Analyze fairness
    analyze_load_balancing_fairness "$fairness_log"
}

# Function to analyze load balancing fairness
analyze_load_balancing_fairness() {
    local fairness_log=$1
    local analysis_file="$RESULTS_DIR/fairness_analysis_$TIMESTAMP.txt"
    
    print_header "Analyzing Load Balancing Fairness"
    
    # Extract all quorum addresses and count assignments
    grep -v "^request_id" "$fairness_log" | grep -v "FAILED" | \
        awk -F',' '{print $2}' | tr -d '"' | tr ';' '\n' | \
        grep -v '^$' | sort | uniq -c | sort -nr > "$analysis_file"
    
    local total_assignments=$(grep -v "^request_id" "$fairness_log" | grep -v "FAILED" | \
        awk -F',' '{sum+=$3} END {print sum}')
    local unique_quorums=$(wc -l < "$analysis_file")
    
    print_status "Load Balancing Analysis:"
    print_status "  Total Assignments: $total_assignments"
    print_status "  Unique Quorums Used: $unique_quorums"
    
    if [[ $unique_quorums -gt 0 ]]; then
        local avg_assignments=$(echo "scale=2; $total_assignments / $unique_quorums" | bc)
        print_status "  Average Assignments per Quorum: $avg_assignments"
        
        print_status "  Top 10 Most Used Quorums:"
        head -10 "$analysis_file" | while read count address; do
            local percentage=$(echo "scale=2; $count * 100 / $total_assignments" | bc)
            print_status "    $address: $count assignments ($percentage%)"
        done
        
        # Calculate fairness coefficient (standard deviation / mean)
        local std_dev=$(awk '{print $1}' "$analysis_file" | \
            awk -v mean="$avg_assignments" '{sum+=($1-mean)^2} END {print sqrt(sum/NR)}')
        local fairness_coeff=$(echo "scale=4; $std_dev / $avg_assignments" | bc)
        
        print_status "  Fairness Coefficient (lower = more fair): $fairness_coeff"
        
        if (( $(echo "$fairness_coeff < 0.3" | bc -l) )); then
            print_status "  ✅ Load balancing is EXCELLENT (very fair distribution)"
        elif (( $(echo "$fairness_coeff < 0.5" | bc -l) )); then
            print_status "  ✅ Load balancing is GOOD (fair distribution)"
        elif (( $(echo "$fairness_coeff < 0.8" | bc -l) )); then
            print_warning "  ⚠️  Load balancing is MODERATE (some imbalance)"
        else
            print_error "  ❌ Load balancing is POOR (significant imbalance)"
        fi
    fi
}

# Function to test balance validation edge cases
test_balance_validation() {
    print_header "Testing Balance Validation Edge Cases"
    
    local validation_log="$RESULTS_DIR/balance_validation_$TIMESTAMP.csv"
    echo "test_case,transaction_amount,quorum_count,required_balance,success,message" > "$validation_log"
    
    # Test cases: [transaction_amount, quorum_count, expected_result, description]
    local test_cases=(
        "10,5,true,Low amount with few quorums"
        "1000,5,false,High amount requiring high balance per quorum"
        "100,10,true,Medium amount with many quorums"
        "500,3,false,High amount with few quorums"
        "50,7,true,Medium amount with optimal quorum count"
        "2000,10,false,Very high amount"
        "1,1,true,Minimal transaction"
    )
    
    for test_case in "${test_cases[@]}"; do
        IFS=',' read -r amount count expected description <<< "$test_case"
        
        local required_balance=$(echo "scale=2; $amount / $count" | bc)
        print_status "Testing: $description ($amount RBT ÷ $count = $required_balance RBT per quorum)"
        
        local response=$(curl -s "$BASE_URL/api/quorum/available?count=$count&transaction_amount=$amount")
        local status=$(echo "$response" | jq -r '.status // false')
        local message=$(echo "$response" | jq -r '.message // "No message"')
        
        echo "\"$description\",$amount,$count,$required_balance,$status,\"$message\"" >> "$validation_log"
        
        if [[ "$status" == "$expected" ]]; then
            print_status "  ✅ Expected result: $status"
        else
            print_warning "  ⚠️  Unexpected result: got $status, expected $expected"
        fi
        
        sleep 0.5
    done
}

# Function to test concurrent allocation conflicts
test_concurrent_allocation() {
    print_header "Testing Concurrent Allocation Conflicts"
    
    local concurrent_log="$RESULTS_DIR/concurrent_allocation_$TIMESTAMP.csv"
    echo "batch,request_id,success,quorum_count,response_time,conflicts" > "$concurrent_log"
    
    print_status "Testing concurrent requests for same resources..."
    
    # Launch 20 concurrent requests for the same transaction parameters
    local temp_dir="/tmp/concurrent_test_$$"
    mkdir -p "$temp_dir"
    
    for batch in $(seq 1 5); do
        print_status "Batch $batch: Launching 10 concurrent requests..."
        
        for i in $(seq 1 10); do
            {
                local start_time=$(date +%s.%N)
                local response=$(curl -s "$BASE_URL/api/quorum/available?count=5&transaction_amount=100")
                local end_time=$(date +%s.%N)
                local response_time=$(echo "$end_time - $start_time" | bc)
                
                local status=$(echo "$response" | jq -r '.status // false')
                local quorum_count=$(echo "$response" | jq -r '.quorums | length // 0')
                local quorums=$(echo "$response" | jq -r '.quorums[]?.address // empty' | tr '\n' ';')
                
                echo "$batch,$i,$status,$quorum_count,$response_time,\"$quorums\"" >> "$temp_dir/batch_$batch.csv"
            } &
        done
        
        wait  # Wait for batch to complete
        
        # Analyze conflicts in this batch
        if [[ -f "$temp_dir/batch_$batch.csv" ]]; then
            cat "$temp_dir/batch_$batch.csv" >> "$concurrent_log"
            
            # Check for quorum conflicts (same quorum assigned to multiple requests)
            local conflicts=$(awk -F',' '{print $6}' "$temp_dir/batch_$batch.csv" | \
                tr ';' '\n' | grep -v '^$' | sort | uniq -d | wc -l)
            
            if [[ $conflicts -gt 0 ]]; then
                print_warning "  Batch $batch: $conflicts potential quorum conflicts detected"
            else
                print_status "  Batch $batch: No conflicts detected"
            fi
        fi
        
        sleep 2  # Delay between batches
    done
    
    rm -rf "$temp_dir"
    print_status "Concurrent allocation testing completed"
}

# Function to generate comprehensive report
generate_allocation_report() {
    print_header "Generating Allocation Test Report"
    
    local report_file="$RESULTS_DIR/allocation_test_report_$TIMESTAMP.html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Quorum Allocation Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; }
        .header { text-align: center; color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        .section { margin: 20px 0; padding: 15px; background-color: #f8f9fa; border-radius: 5px; }
        .success { color: #28a745; }
        .warning { color: #ffc107; }
        .error { color: #dc3545; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #007bff; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Quorum Allocation Test Report</h1>
            <p>Generated: $(date)</p>
            <p>Base URL: $BASE_URL</p>
            <p>Test Quorums: $TEST_QUORUMS | Test Rounds: $TEST_ROUNDS</p>
        </div>
        
        <div class="section">
            <h2>Test Summary</h2>
            <p>This report analyzes quorum allocation fairness, balance validation, and concurrent request handling.</p>
        </div>
        
        <div class="section">
            <h2>Files Generated</h2>
            <ul>
                <li><strong>Allocation Patterns:</strong> allocation_patterns_$TIMESTAMP.csv</li>
                <li><strong>Load Balancing:</strong> load_balancing_$TIMESTAMP.csv</li>
                <li><strong>Balance Validation:</strong> balance_validation_$TIMESTAMP.csv</li>
                <li><strong>Concurrent Tests:</strong> concurrent_allocation_$TIMESTAMP.csv</li>
                <li><strong>Fairness Analysis:</strong> fairness_analysis_$TIMESTAMP.txt</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF
    
    print_status "Report generated: $report_file"
}

# Main execution
main() {
    print_header "Quorum Allocation Testing Suite"
    print_status "Testing URL: $BASE_URL"
    
    # Verify service is accessible
    if ! curl -s --connect-timeout 5 "$BASE_URL/api/quorum/health" >/dev/null; then
        print_error "Service not accessible at $BASE_URL"
        exit 1
    fi
    
    print_status "Service is accessible, starting allocation tests..."
    
    # Run test suites
    setup_test_quorums
    test_allocation_patterns
    test_load_balancing
    test_balance_validation
    test_concurrent_allocation
    generate_allocation_report
    
    print_header "Allocation Testing Completed!"
    print_status "Results saved in: $RESULTS_DIR"
    
    # Show quick summary
    print_status "Quick Summary:"
    print_status "  Test Quorums Created: $TEST_QUORUMS"
    print_status "  Load Balancing Rounds: $TEST_ROUNDS"
    print_status "  Check the HTML report for detailed analysis"
}

# Cleanup
cleanup() {
    print_status "Test completed. Check results in $RESULTS_DIR"
}

trap cleanup EXIT

# Run main function
main "$@"
