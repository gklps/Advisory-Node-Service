#!/bin/bash

# High-Performance Concurrent Testing Script
# Specifically designed for 1000+ parallel requests

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/performance-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Test parameters
BASE_URL="${1:-http://localhost:8080}"
CONCURRENT_REQUESTS="${2:-1000}"
TRANSACTION_AMOUNT="${3:-100}"
QUORUM_COUNT="${4:-5}"

# Performance tracking
TEMP_DIR="/tmp/advisory_perf_test_$$"
mkdir -p "$TEMP_DIR" "$RESULTS_DIR"

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

# Function to make a single API request and measure performance
make_request() {
    local request_id=$1
    local url="$BASE_URL/api/quorum/available?count=$QUORUM_COUNT&transaction_amount=$TRANSACTION_AMOUNT"
    
    local start_time=$(date +%s.%N)
    local response=$(curl -s -w "%{http_code},%{time_total},%{time_connect},%{time_starttransfer}" "$url" 2>/dev/null)
    local end_time=$(date +%s.%N)
    
    local body=$(echo "$response" | head -n -1)
    local metrics=$(echo "$response" | tail -n 1)
    
    # Parse response
    local status=$(echo "$body" | jq -r '.status // false' 2>/dev/null || echo "false")
    local quorum_count=$(echo "$body" | jq -r '.quorums | length // 0' 2>/dev/null || echo "0")
    local message=$(echo "$body" | jq -r '.message // "No message"' 2>/dev/null || echo "Parse error")
    
    # Calculate total time
    local total_time=$(echo "$end_time - $start_time" | bc)
    
    # Output CSV format: request_id,status,quorum_count,http_code,total_time,connect_time,transfer_time,message
    echo "$request_id,$status,$quorum_count,$metrics,$total_time,\"$message\"" >> "$TEMP_DIR/results.csv"
    
    # Track quorum allocations for fairness analysis
    if [[ "$status" == "true" ]]; then
        echo "$body" | jq -r '.quorums[]?.address // empty' >> "$TEMP_DIR/allocations.txt" 2>/dev/null || true
    fi
}

# Function to run concurrent performance test
run_concurrent_test() {
    print_header "Starting Concurrent Performance Test"
    print_status "URL: $BASE_URL"
    print_status "Concurrent Requests: $CONCURRENT_REQUESTS"
    print_status "Transaction Amount: $TRANSACTION_AMOUNT RBT"
    print_status "Quorum Count: $QUORUM_COUNT"
    
    # Initialize CSV header
    echo "request_id,status,quorum_count,http_code,curl_total_time,curl_connect_time,curl_transfer_time,measured_total_time,message" > "$TEMP_DIR/results.csv"
    
    local overall_start=$(date +%s.%N)
    
    print_status "Launching $CONCURRENT_REQUESTS concurrent requests..."
    
    # Launch requests in batches to avoid overwhelming the system
    local batch_size=100
    local batches=$(( (CONCURRENT_REQUESTS + batch_size - 1) / batch_size ))
    
    for batch in $(seq 1 $batches); do
        local batch_start=$(( (batch - 1) * batch_size + 1 ))
        local batch_end=$(( batch * batch_size ))
        if [[ $batch_end -gt $CONCURRENT_REQUESTS ]]; then
            batch_end=$CONCURRENT_REQUESTS
        fi
        
        print_status "Launching batch $batch/$batches (requests $batch_start-$batch_end)"
        
        # Launch batch requests
        for i in $(seq $batch_start $batch_end); do
            make_request $i &
        done
        
        # Wait for batch to complete before starting next batch
        if [[ $batch -lt $batches ]]; then
            wait
            sleep 0.1  # Small delay between batches
        fi
    done
    
    # Wait for all requests to complete
    print_status "Waiting for all requests to complete..."
    wait
    
    local overall_end=$(date +%s.%N)
    local total_duration=$(echo "$overall_end - $overall_start" | bc)
    
    print_status "All requests completed in ${total_duration}s"
    
    # Analyze results
    analyze_results "$total_duration"
}

# Function to analyze test results
analyze_results() {
    local total_duration=$1
    
    print_header "Performance Analysis"
    
    # Basic statistics
    local total_requests=$(tail -n +2 "$TEMP_DIR/results.csv" | wc -l)
    local successful_requests=$(tail -n +2 "$TEMP_DIR/results.csv" | grep -c "^[^,]*,true," || echo "0")
    local failed_requests=$(( total_requests - successful_requests ))
    local success_rate=$(echo "scale=2; $successful_requests * 100 / $total_requests" | bc)
    
    print_status "Total Requests: $total_requests"
    print_status "Successful: $successful_requests ($success_rate%)"
    print_status "Failed: $failed_requests"
    print_status "Requests per Second: $(echo "scale=2; $total_requests / $total_duration" | bc)"
    
    # Response time analysis
    if [[ $successful_requests -gt 0 ]]; then
        local avg_response_time=$(tail -n +2 "$TEMP_DIR/results.csv" | grep "^[^,]*,true," | \
            awk -F',' '{sum+=$8} END {printf "%.3f", sum/NR}')
        local min_response_time=$(tail -n +2 "$TEMP_DIR/results.csv" | grep "^[^,]*,true," | \
            awk -F',' '{print $8}' | sort -n | head -1)
        local max_response_time=$(tail -n +2 "$TEMP_DIR/results.csv" | grep "^[^,]*,true," | \
            awk -F',' '{print $8}' | sort -n | tail -1)
        
        print_status "Average Response Time: ${avg_response_time}s"
        print_status "Min Response Time: ${min_response_time}s"
        print_status "Max Response Time: ${max_response_time}s"
    fi
    
    # HTTP status code analysis
    print_header "HTTP Status Code Distribution"
    tail -n +2 "$TEMP_DIR/results.csv" | awk -F',' '{print $4}' | sort | uniq -c | \
        while read count code; do
            print_status "HTTP $code: $count requests"
        done
    
    # Quorum allocation analysis
    analyze_quorum_allocation
    
    # Error analysis
    analyze_errors
    
    # Save results
    save_results "$total_duration"
}

# Function to analyze quorum allocation fairness
analyze_quorum_allocation() {
    print_header "Quorum Allocation Fairness Analysis"
    
    if [[ -f "$TEMP_DIR/allocations.txt" && -s "$TEMP_DIR/allocations.txt" ]]; then
        local total_allocations=$(wc -l < "$TEMP_DIR/allocations.txt")
        local unique_quorums=$(sort "$TEMP_DIR/allocations.txt" | uniq | wc -l)
        
        print_status "Total Quorum Allocations: $total_allocations"
        print_status "Unique Quorums Used: $unique_quorums"
        
        print_status "Top 10 Most Allocated Quorums:"
        sort "$TEMP_DIR/allocations.txt" | uniq -c | sort -nr | head -10 | \
            while read count quorum; do
                local percentage=$(echo "scale=2; $count * 100 / $total_allocations" | bc)
                print_status "  $quorum: $count times ($percentage%)"
            done
        
        # Calculate allocation fairness (standard deviation)
        local allocation_counts=$(sort "$TEMP_DIR/allocations.txt" | uniq -c | awk '{print $1}')
        local mean=$(echo "$allocation_counts" | awk '{sum+=$1} END {print sum/NR}')
        local std_dev=$(echo "$allocation_counts" | awk -v mean="$mean" '{sum+=($1-mean)^2} END {print sqrt(sum/NR)}')
        
        print_status "Allocation Fairness (lower std dev = more fair): $std_dev"
    else
        print_warning "No successful quorum allocations found"
    fi
}

# Function to analyze errors
analyze_errors() {
    print_header "Error Analysis"
    
    local error_count=$(tail -n +2 "$TEMP_DIR/results.csv" | grep -c "^[^,]*,false," || echo "0")
    
    if [[ $error_count -gt 0 ]]; then
        print_status "Total Errors: $error_count"
        
        print_status "Error Messages:"
        tail -n +2 "$TEMP_DIR/results.csv" | grep "^[^,]*,false," | \
            awk -F',' '{print $9}' | sort | uniq -c | \
            while read count message; do
                print_status "  $message: $count times"
            done
    else
        print_status "No errors detected"
    fi
}

# Function to save results
save_results() {
    local total_duration=$1
    local results_file="$RESULTS_DIR/performance_test_${TIMESTAMP}.json"
    local csv_file="$RESULTS_DIR/raw_results_${TIMESTAMP}.csv"
    
    print_header "Saving Results"
    
    # Copy raw CSV data
    cp "$TEMP_DIR/results.csv" "$csv_file"
    
    # Create JSON summary
    local total_requests=$(tail -n +2 "$TEMP_DIR/results.csv" | wc -l)
    local successful_requests=$(tail -n +2 "$TEMP_DIR/results.csv" | grep -c "^[^,]*,true," || echo "0")
    local success_rate=$(echo "scale=4; $successful_requests * 100 / $total_requests" | bc)
    local rps=$(echo "scale=2; $total_requests / $total_duration" | bc)
    
    cat > "$results_file" << EOF
{
  "test_info": {
    "timestamp": "$TIMESTAMP",
    "base_url": "$BASE_URL",
    "concurrent_requests": $CONCURRENT_REQUESTS,
    "transaction_amount": $TRANSACTION_AMOUNT,
    "quorum_count": $QUORUM_COUNT,
    "total_duration": $total_duration
  },
  "results": {
    "total_requests": $total_requests,
    "successful_requests": $successful_requests,
    "failed_requests": $(( total_requests - successful_requests )),
    "success_rate": $success_rate,
    "requests_per_second": $rps
  },
  "files": {
    "raw_data": "$csv_file",
    "allocations": "$TEMP_DIR/allocations.txt"
  }
}
EOF
    
    print_status "Results saved:"
    print_status "  JSON Summary: $results_file"
    print_status "  Raw CSV Data: $csv_file"
    
    # Generate quick report
    generate_quick_report "$results_file"
}

# Function to generate a quick HTML report
generate_quick_report() {
    local json_file=$1
    local html_file="$RESULTS_DIR/performance_report_${TIMESTAMP}.html"
    
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Advisory Node Performance Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        .metric { display: inline-block; margin: 10px; padding: 15px; background-color: #f8f9fa; border-radius: 5px; border-left: 4px solid #007bff; }
        .success { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .error { border-left-color: #dc3545; }
        .metric-value { font-size: 24px; font-weight: bold; color: #333; }
        .metric-label { font-size: 14px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Advisory Node Performance Test Report</h1>
            <p>Generated: $(date)</p>
            <p>Test Configuration: $CONCURRENT_REQUESTS concurrent requests, $TRANSACTION_AMOUNT RBT transactions</p>
        </div>
        
        <div style="text-align: center; margin: 30px 0;">
EOF

    # Add metrics from JSON file
    local total_requests=$(jq -r '.results.total_requests' "$json_file")
    local success_rate=$(jq -r '.results.success_rate' "$json_file")
    local rps=$(jq -r '.results.requests_per_second' "$json_file")
    local duration=$(jq -r '.test_info.total_duration' "$json_file")
    
    cat >> "$html_file" << EOF
            <div class="metric success">
                <div class="metric-value">$total_requests</div>
                <div class="metric-label">Total Requests</div>
            </div>
            
            <div class="metric success">
                <div class="metric-value">$success_rate%</div>
                <div class="metric-label">Success Rate</div>
            </div>
            
            <div class="metric">
                <div class="metric-value">$rps</div>
                <div class="metric-label">Requests/Second</div>
            </div>
            
            <div class="metric">
                <div class="metric-value">${duration}s</div>
                <div class="metric-label">Total Duration</div>
            </div>
        </div>
        
        <h3>Test Details</h3>
        <p><strong>Base URL:</strong> $BASE_URL</p>
        <p><strong>Transaction Amount:</strong> $TRANSACTION_AMOUNT RBT</p>
        <p><strong>Quorum Count:</strong> $QUORUM_COUNT</p>
        <p><strong>Concurrent Requests:</strong> $CONCURRENT_REQUESTS</p>
        
        <h3>Files Generated</h3>
        <ul>
            <li><strong>Raw Data:</strong> $(basename "$csv_file")</li>
            <li><strong>JSON Summary:</strong> $(basename "$json_file")</li>
        </ul>
    </div>
</body>
</html>
EOF

    print_status "HTML Report: $html_file"
}

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

# Main execution
print_header "Advisory Node Performance Testing"
print_status "Testing with $CONCURRENT_REQUESTS concurrent requests"

# Verify service is accessible
if ! curl -s --connect-timeout 5 "$BASE_URL/api/quorum/health" >/dev/null; then
    print_error "Service not accessible at $BASE_URL"
    exit 1
fi

print_status "Service is accessible, starting performance test..."

# Run the test
run_concurrent_test

print_header "Performance Test Completed!"
print_status "Check results in: $RESULTS_DIR"

