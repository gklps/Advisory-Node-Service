#!/bin/bash

# Production Advisory Node Testing Script
# Tests against existing cloud deployment without registering new quorums

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/production-test-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Production configuration
PRODUCTION_URL="${1:-https://mainnet-pool.universe.rubix.net}"
CONCURRENT_REQUESTS="${2:-1000}"
TEST_ROUNDS="${3:-50}"

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

# Function to check production service health
check_production_health() {
    print_header "Checking Production Service Health"
    
    local health_response=$(curl -s "$PRODUCTION_URL/api/quorum/health")
    local status=$(echo "$health_response" | jq -r '.status // "unknown"')
    local total_quorums=$(echo "$health_response" | jq -r '.total_quorums // 0')
    local available_quorums=$(echo "$health_response" | jq -r '.available_quorums // 0')
    local last_check=$(echo "$health_response" | jq -r '.last_check // "unknown"')
    
    print_status "Production URL: $PRODUCTION_URL"
    print_status "Service Status: $status"
    print_status "Total Quorums: $total_quorums"
    print_status "Available Quorums: $available_quorums"
    print_status "Last Check: $last_check"
    
    # Save health info
    echo "$health_response" > "$RESULTS_DIR/production_health_$TIMESTAMP.json"
    
    if [[ "$status" != "healthy" ]]; then
        print_error "Production service is not healthy!"
        return 1
    fi
    
    if [[ "$available_quorums" -eq 0 ]]; then
        print_warning "No quorums currently available - testing will show expected 'insufficient quorums' responses"
    fi
    
    return 0
}

# Function to test quorum availability with different scenarios
test_quorum_availability_scenarios() {
    print_header "Testing Quorum Availability Scenarios"
    
    local availability_log="$RESULTS_DIR/availability_test_$TIMESTAMP.csv"
    echo "scenario,transaction_amount,quorum_count,success,message,response_time" > "$availability_log"
    
    # Test different scenarios
    local scenarios=(
        "small_transaction,10,3"
        "medium_transaction,50,5"
        "large_transaction,100,7"
        "very_large_transaction,500,5"
        "minimal_transaction,1,1"
        "high_quorum_count,100,10"
    )
    
    for scenario_data in "${scenarios[@]}"; do
        IFS=',' read -r scenario_name amount count <<< "$scenario_data"
        
        print_status "Testing scenario: $scenario_name ($amount RBT, $count quorums)"
        
        local start_time=$(date +%s.%N)
        local response=$(curl -s "$PRODUCTION_URL/api/quorum/available?count=$count&transaction_amount=$amount")
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc)
        
        local status=$(echo "$response" | jq -r '.status // false')
        local message=$(echo "$response" | jq -r '.message // "No message"')
        
        echo "$scenario_name,$amount,$count,$status,\"$message\",$response_time" >> "$availability_log"
        
        if [[ "$status" == "true" ]]; then
            local quorum_count=$(echo "$response" | jq -r '.quorums | length // 0')
            print_status "  ✅ Success: Got $quorum_count quorums"
        else
            print_warning "  ❌ Expected failure: $message"
        fi
        
        # Save individual response
        echo "$response" > "$RESULTS_DIR/response_${scenario_name}_$TIMESTAMP.json"
        
        sleep 1  # Small delay between tests
    done
}

# Function to perform concurrent load testing
concurrent_load_test() {
    print_header "Concurrent Load Testing ($CONCURRENT_REQUESTS requests)"
    
    local temp_dir="/tmp/production_test_$$"
    mkdir -p "$temp_dir"
    
    local concurrent_log="$RESULTS_DIR/concurrent_test_$TIMESTAMP.csv"
    echo "request_id,http_code,response_time,success,message" > "$concurrent_log"
    
    print_status "Launching $CONCURRENT_REQUESTS concurrent requests..."
    
    local overall_start=$(date +%s.%N)
    
    # Launch requests in batches to avoid overwhelming the production service
    local batch_size=50
    local batches=$(( (CONCURRENT_REQUESTS + batch_size - 1) / batch_size ))
    
    for batch in $(seq 1 $batches); do
        local batch_start=$(( (batch - 1) * batch_size + 1 ))
        local batch_end=$(( batch * batch_size ))
        if [[ $batch_end -gt $CONCURRENT_REQUESTS ]]; then
            batch_end=$CONCURRENT_REQUESTS
        fi
        
        print_status "Batch $batch/$batches (requests $batch_start-$batch_end)"
        
        # Launch batch requests
        for i in $(seq $batch_start $batch_end); do
            {
                local start_time=$(date +%s.%N)
                local response=$(curl -s -w "%{http_code}" "$PRODUCTION_URL/api/quorum/available?count=5&transaction_amount=100")
                local end_time=$(date +%s.%N)
                
                local body=$(echo "$response" | head -n -1)
                local http_code=$(echo "$response" | tail -n 1)
                local response_time=$(echo "$end_time - $start_time" | bc)
                
                local status=$(echo "$body" | jq -r '.status // false' 2>/dev/null || echo "false")
                local message=$(echo "$body" | jq -r '.message // "Parse error"' 2>/dev/null || echo "Parse error")
                
                echo "$i,$http_code,$response_time,$status,\"$message\"" >> "$temp_dir/batch_$batch.csv"
            } &
        done
        
        # Wait for batch to complete
        wait
        
        # Append batch results to main log
        if [[ -f "$temp_dir/batch_$batch.csv" ]]; then
            cat "$temp_dir/batch_$batch.csv" >> "$concurrent_log"
        fi
        
        # Small delay between batches to be respectful to production service
        sleep 2
    done
    
    local overall_end=$(date +%s.%N)
    local total_duration=$(echo "$overall_end - $overall_start" | bc)
    
    # Analyze concurrent test results
    analyze_concurrent_results "$concurrent_log" "$total_duration"
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Function to analyze concurrent test results
analyze_concurrent_results() {
    local results_file=$1
    local total_duration=$2
    
    print_header "Concurrent Test Analysis"
    
    local total_requests=$(tail -n +2 "$results_file" | wc -l)
    local successful_requests=$(tail -n +2 "$results_file" | grep ",200," | wc -l)
    local failed_requests=$(( total_requests - successful_requests ))
    
    print_status "Total Duration: ${total_duration}s"
    print_status "Total Requests: $total_requests"
    print_status "Successful HTTP: $successful_requests"
    print_status "Failed HTTP: $failed_requests"
    print_status "Requests per Second: $(echo "scale=2; $total_requests / $total_duration" | bc)"
    
    if [[ $successful_requests -gt 0 ]]; then
        local avg_response_time=$(tail -n +2 "$results_file" | grep ",200," | \
            awk -F',' '{sum+=$3} END {printf "%.3f", sum/NR}')
        print_status "Average Response Time: ${avg_response_time}s"
    fi
    
    # HTTP status code distribution
    print_status "HTTP Status Code Distribution:"
    tail -n +2 "$results_file" | awk -F',' '{print $2}' | sort | uniq -c | \
        while read count code; do
            print_status "  HTTP $code: $count requests"
        done
    
    # Response message analysis
    print_status "Response Message Analysis:"
    tail -n +2 "$results_file" | awk -F',' '{print $5}' | sort | uniq -c | sort -nr | head -5 | \
        while read count message; do
            print_status "  $message: $count times"
        done
}

# Function to test service stability over time
test_service_stability() {
    print_header "Service Stability Test ($TEST_ROUNDS rounds)"
    
    local stability_log="$RESULTS_DIR/stability_test_$TIMESTAMP.csv"
    echo "round,timestamp,response_time,http_code,status,available_quorums" > "$stability_log"
    
    print_status "Testing service stability over $TEST_ROUNDS rounds (1 request per 10 seconds)..."
    
    for round in $(seq 1 $TEST_ROUNDS); do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local start_time=$(date +%s.%N)
        
        # Test both health and availability endpoints
        local health_response=$(curl -s -w "%{http_code}" "$PRODUCTION_URL/api/quorum/health")
        local health_body=$(echo "$health_response" | head -n -1)
        local health_code=$(echo "$health_response" | tail -n 1)
        
        local avail_response=$(curl -s -w "%{http_code}" "$PRODUCTION_URL/api/quorum/available?count=5&transaction_amount=100")
        local avail_body=$(echo "$avail_response" | head -n -1)
        local avail_code=$(echo "$avail_response" | tail -n 1)
        
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc)
        
        local available_quorums=$(echo "$health_body" | jq -r '.available_quorums // 0' 2>/dev/null || echo "0")
        local status=$(echo "$health_body" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
        
        echo "$round,\"$timestamp\",$response_time,$health_code,$status,$available_quorums" >> "$stability_log"
        
        # Progress indicator
        if [[ $((round % 10)) -eq 0 ]]; then
            print_status "Completed $round/$TEST_ROUNDS rounds"
        else
            echo -n "."
        fi
        
        sleep 10  # Wait 10 seconds between stability checks
    done
    
    echo ""  # New line after progress dots
    print_status "Stability test completed"
}

# Function to generate production test report
generate_production_report() {
    print_header "Generating Production Test Report"
    
    local report_file="$RESULTS_DIR/production_test_report_$TIMESTAMP.html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Production Advisory Node Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; margin-bottom: 30px; }
        .section { margin: 20px 0; padding: 15px; background-color: #f8f9fa; border-radius: 5px; border-left: 4px solid #007bff; }
        .metric { display: inline-block; margin: 10px; padding: 15px; background-color: #e9ecef; border-radius: 5px; text-align: center; }
        .metric-value { font-size: 24px; font-weight: bold; color: #007bff; }
        .metric-label { font-size: 12px; color: #666; }
        .success { color: #28a745; }
        .warning { color: #ffc107; }
        .error { color: #dc3545; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Production Advisory Node Test Report</h1>
            <p>Generated: $(date)</p>
            <p>Production URL: <a href="$PRODUCTION_URL">$PRODUCTION_URL</a></p>
        </div>
        
        <div class="section">
            <h2>Test Configuration</h2>
            <div class="metric">
                <div class="metric-value">$CONCURRENT_REQUESTS</div>
                <div class="metric-label">Concurrent Requests</div>
            </div>
            <div class="metric">
                <div class="metric-value">$TEST_ROUNDS</div>
                <div class="metric-label">Stability Test Rounds</div>
            </div>
        </div>
        
        <div class="section">
            <h2>Production Service Health</h2>
EOF

    # Add health information if available
    if [[ -f "$RESULTS_DIR/production_health_$TIMESTAMP.json" ]]; then
        local health_data=$(cat "$RESULTS_DIR/production_health_$TIMESTAMP.json")
        local status=$(echo "$health_data" | jq -r '.status')
        local total_quorums=$(echo "$health_data" | jq -r '.total_quorums')
        local available_quorums=$(echo "$health_data" | jq -r '.available_quorums')
        
        cat >> "$report_file" << EOF
            <div class="metric">
                <div class="metric-value $([[ "$status" == "healthy" ]] && echo "success" || echo "error")">$status</div>
                <div class="metric-label">Service Status</div>
            </div>
            <div class="metric">
                <div class="metric-value">$total_quorums</div>
                <div class="metric-label">Total Quorums</div>
            </div>
            <div class="metric">
                <div class="metric-value $([[ "$available_quorums" -gt 0 ]] && echo "success" || echo "warning")">$available_quorums</div>
                <div class="metric-label">Available Quorums</div>
            </div>
EOF
    fi
    
    cat >> "$report_file" << EOF
        </div>
        
        <div class="section">
            <h2>Test Results Files</h2>
            <ul>
                <li><strong>Availability Test:</strong> availability_test_$TIMESTAMP.csv</li>
                <li><strong>Concurrent Load Test:</strong> concurrent_test_$TIMESTAMP.csv</li>
                <li><strong>Stability Test:</strong> stability_test_$TIMESTAMP.csv</li>
                <li><strong>Service Health:</strong> production_health_$TIMESTAMP.json</li>
            </ul>
        </div>
        
        <div class="section">
            <h2>Key Findings</h2>
            <p>This test validates the production Advisory Node service performance and behavior:</p>
            <ul>
                <li><strong>Service Availability:</strong> Tests if the production service responds correctly</li>
                <li><strong>Load Handling:</strong> Validates concurrent request processing capability</li>
                <li><strong>Response Consistency:</strong> Ensures consistent behavior under load</li>
                <li><strong>Error Handling:</strong> Verifies proper error responses for insufficient quorums</li>
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
    print_header "Production Advisory Node Testing"
    print_status "Testing URL: $PRODUCTION_URL"
    print_status "Concurrent Requests: $CONCURRENT_REQUESTS"
    print_status "Stability Test Rounds: $TEST_ROUNDS"
    
    # Check production service health
    if ! check_production_health; then
        print_error "Cannot proceed with testing - production service issues detected"
        exit 1
    fi
    
    echo ""
    
    # Run test suites
    test_quorum_availability_scenarios
    echo ""
    
    concurrent_load_test
    echo ""
    
    test_service_stability
    echo ""
    
    # Generate report
    generate_production_report
    
    print_header "Production Testing Completed!"
    print_status "Results saved in: $RESULTS_DIR"
    print_status "HTML Report: $RESULTS_DIR/production_test_report_$TIMESTAMP.html"
    
    # Final health check
    echo ""
    print_status "Final health check after testing:"
    check_production_health
}

# Cleanup function
cleanup() {
    print_status "Production testing completed. Results saved in $RESULTS_DIR"
}

trap cleanup EXIT

# Run main function
main "$@"

