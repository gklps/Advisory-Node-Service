#!/bin/bash

# Master Test Runner for Advisory Node
# Runs comprehensive testing suite including load, performance, and allocation tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_RESULTS_DIR="$SCRIPT_DIR/master-test-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Configuration
DEFAULT_TESTNET_URL="https://testnet-pool.universe.rubix.net"
DEFAULT_MAINNET_URL="https://mainnet-pool.universe.rubix.net"
DEFAULT_CONCURRENT_REQUESTS=1000

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}=== $1 ===${NC}"; }
print_test() { echo -e "${CYAN}[TEST]${NC} $1"; }

# Create master results directory
mkdir -p "$MASTER_RESULTS_DIR"

show_usage() {
    echo "Advisory Node Testing Suite"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t, --testnet URL     Testnet URL (default: $DEFAULT_TESTNET_URL)"
    echo "  -m, --mainnet URL     Mainnet URL (default: $DEFAULT_MAINNET_URL)"
    echo "  -c, --concurrent N    Concurrent requests (default: $DEFAULT_CONCURRENT_REQUESTS)"
    echo "  -e, --environment ENV Test environment: testnet, mainnet, or both (default: both)"
    echo "  -s, --suite SUITE     Test suite: load, performance, allocation, or all (default: all)"
    echo "  -q, --quick           Quick test mode (reduced test parameters)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Run all tests on both environments"
    echo "  $0 -e testnet -s performance         # Run performance tests on testnet only"
    echo "  $0 -c 500 -q                        # Quick test with 500 concurrent requests"
    echo "  $0 -t http://192.168.1.100:8080     # Test specific testnet URL"
}

# Parse command line arguments
TESTNET_URL="$DEFAULT_TESTNET_URL"
MAINNET_URL="$DEFAULT_MAINNET_URL"
CONCURRENT_REQUESTS="$DEFAULT_CONCURRENT_REQUESTS"
TEST_ENVIRONMENT="both"
TEST_SUITE="all"
QUICK_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--testnet)
            TESTNET_URL="$2"
            shift 2
            ;;
        -m|--mainnet)
            MAINNET_URL="$2"
            shift 2
            ;;
        -c|--concurrent)
            CONCURRENT_REQUESTS="$2"
            shift 2
            ;;
        -e|--environment)
            TEST_ENVIRONMENT="$2"
            shift 2
            ;;
        -s|--suite)
            TEST_SUITE="$2"
            shift 2
            ;;
        -q|--quick)
            QUICK_MODE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Adjust parameters for quick mode
if [[ "$QUICK_MODE" == "true" ]]; then
    CONCURRENT_REQUESTS=100
    print_status "Quick mode enabled - using $CONCURRENT_REQUESTS concurrent requests"
fi

# Validate test environment
case $TEST_ENVIRONMENT in
    testnet|mainnet|both) ;;
    *)
        print_error "Invalid environment: $TEST_ENVIRONMENT"
        print_error "Valid options: testnet, mainnet, both"
        exit 1
        ;;
esac

# Validate test suite
case $TEST_SUITE in
    load|performance|allocation|all) ;;
    *)
        print_error "Invalid test suite: $TEST_SUITE"
        print_error "Valid options: load, performance, allocation, all"
        exit 1
        ;;
esac

# Function to check service health
check_service_health() {
    local url=$1
    local name=$2
    
    print_test "Checking $name service health at $url"
    
    if curl -s --connect-timeout 10 "$url/api/quorum/health" >/dev/null; then
        print_status "✅ $name service is accessible"
        return 0
    else
        print_error "❌ $name service is not accessible at $url"
        return 1
    fi
}

# Function to run load tests
run_load_tests() {
    local url=$1
    local env_name=$2
    
    print_header "Running Load Tests - $env_name"
    
    if [[ -f "$SCRIPT_DIR/load-test.sh" ]]; then
        print_test "Starting comprehensive load test for $env_name..."
        
        # Create environment-specific results directory
        local load_results_dir="$MASTER_RESULTS_DIR/load-test-$env_name-$TIMESTAMP"
        mkdir -p "$load_results_dir"
        
        # Run load test (this will create its own results)
        if "$SCRIPT_DIR/load-test.sh" "$url" "$env_name" "$load_results_dir"; then
            print_status "✅ Load test completed for $env_name"
        else
            print_error "❌ Load test failed for $env_name"
        fi
    else
        print_error "Load test script not found: $SCRIPT_DIR/load-test.sh"
    fi
}

# Function to run performance tests
run_performance_tests() {
    local url=$1
    local env_name=$2
    
    print_header "Running Performance Tests - $env_name"
    
    if [[ -f "$SCRIPT_DIR/performance-test.sh" ]]; then
        print_test "Starting $CONCURRENT_REQUESTS concurrent requests performance test..."
        
        # Run performance test with different transaction amounts
        local transaction_amounts=(50 100 200 500)
        
        for amount in "${transaction_amounts[@]}"; do
            print_test "Performance test: $amount RBT transactions"
            
            if "$SCRIPT_DIR/performance-test.sh" "$url" "$CONCURRENT_REQUESTS" "$amount" 5; then
                print_status "✅ Performance test completed for $amount RBT"
            else
                print_warning "⚠️ Performance test had issues for $amount RBT"
            fi
            
            # Cool down between tests
            sleep 10
        done
    else
        print_error "Performance test script not found: $SCRIPT_DIR/performance-test.sh"
    fi
}

# Function to run allocation tests
run_allocation_tests() {
    local url=$1
    local env_name=$2
    
    print_header "Running Allocation Tests - $env_name"
    
    if [[ -f "$SCRIPT_DIR/allocation-test.sh" ]]; then
        print_test "Starting quorum allocation and fairness tests..."
        
        if "$SCRIPT_DIR/allocation-test.sh" "$url"; then
            print_status "✅ Allocation test completed for $env_name"
        else
            print_warning "⚠️ Allocation test had issues for $env_name"
        fi
    else
        print_error "Allocation test script not found: $SCRIPT_DIR/allocation-test.sh"
    fi
}

# Function to run tests for a specific environment
run_tests_for_environment() {
    local url=$1
    local env_name=$2
    
    print_header "Testing Environment: $env_name ($url)"
    
    # Check service health first
    if ! check_service_health "$url" "$env_name"; then
        print_error "Skipping tests for $env_name due to service unavailability"
        return 1
    fi
    
    # Run selected test suites
    case $TEST_SUITE in
        load)
            run_load_tests "$url" "$env_name"
            ;;
        performance)
            run_performance_tests "$url" "$env_name"
            ;;
        allocation)
            run_allocation_tests "$url" "$env_name"
            ;;
        all)
            run_load_tests "$url" "$env_name"
            sleep 30  # Cool down between test suites
            run_performance_tests "$url" "$env_name"
            sleep 30
            run_allocation_tests "$url" "$env_name"
            ;;
    esac
}

# Function to generate master summary report
generate_master_report() {
    print_header "Generating Master Test Report"
    
    local master_report="$MASTER_RESULTS_DIR/master_test_report_$TIMESTAMP.html"
    
    cat > "$master_report" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Advisory Node Master Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; margin-bottom: 30px; }
        .section { margin: 20px 0; padding: 15px; background-color: #f8f9fa; border-radius: 5px; border-left: 4px solid #007bff; }
        .success { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .error { border-left-color: #dc3545; }
        .config-table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        .config-table th, .config-table td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        .config-table th { background-color: #007bff; color: white; }
        .file-list { list-style-type: none; padding: 0; }
        .file-list li { padding: 5px 0; border-bottom: 1px solid #eee; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Advisory Node Master Test Report</h1>
            <p>Generated: $(date)</p>
            <p>Test Suite: $TEST_SUITE | Environment: $TEST_ENVIRONMENT</p>
        </div>
        
        <div class="section">
            <h2>Test Configuration</h2>
            <table class="config-table">
                <tr><th>Parameter</th><th>Value</th></tr>
                <tr><td>Test Environment</td><td>$TEST_ENVIRONMENT</td></tr>
                <tr><td>Test Suite</td><td>$TEST_SUITE</td></tr>
                <tr><td>Concurrent Requests</td><td>$CONCURRENT_REQUESTS</td></tr>
                <tr><td>Testnet URL</td><td>$TESTNET_URL</td></tr>
                <tr><td>Mainnet URL</td><td>$MAINNET_URL</td></tr>
                <tr><td>Quick Mode</td><td>$QUICK_MODE</td></tr>
            </table>
        </div>
        
        <div class="section">
            <h2>Test Results Overview</h2>
            <p>This master test report combines results from multiple test suites:</p>
            <ul>
                <li><strong>Load Tests:</strong> Comprehensive testing with multiple transaction amounts and scenarios</li>
                <li><strong>Performance Tests:</strong> High-concurrency testing with $CONCURRENT_REQUESTS parallel requests</li>
                <li><strong>Allocation Tests:</strong> Quorum allocation fairness and balance validation testing</li>
            </ul>
        </div>
        
        <div class="section">
            <h2>Generated Files</h2>
            <p>Individual test results can be found in the following directories:</p>
            <ul class="file-list">
EOF

    # List all generated result directories
    find "$MASTER_RESULTS_DIR" -type d -name "*$TIMESTAMP*" | while read dir; do
        echo "                <li>$(basename "$dir")</li>" >> "$master_report"
    done
    
    cat >> "$master_report" << EOF
            </ul>
        </div>
        
        <div class="section">
            <h2>Key Metrics Tested</h2>
            <ul>
                <li><strong>Concurrent Request Handling:</strong> $CONCURRENT_REQUESTS simultaneous requests</li>
                <li><strong>Balance Validation:</strong> Proper validation of quorum balances vs transaction amounts</li>
                <li><strong>Load Balancing Fairness:</strong> Even distribution of quorum assignments</li>
                <li><strong>Response Times:</strong> API endpoint performance under load</li>
                <li><strong>Error Handling:</strong> Proper handling of insufficient balance scenarios</li>
                <li><strong>System Stability:</strong> Service health during high load</li>
            </ul>
        </div>
        
        <div class="section">
            <h2>Next Steps</h2>
            <p>Review individual test reports for detailed analysis:</p>
            <ol>
                <li>Check performance test results for response time analysis</li>
                <li>Review allocation test results for fairness metrics</li>
                <li>Examine load test results for system behavior under stress</li>
                <li>Identify any bottlenecks or areas for optimization</li>
            </ol>
        </div>
    </div>
</body>
</html>
EOF
    
    print_status "Master report generated: $master_report"
}

# Main execution
main() {
    print_header "Advisory Node Master Testing Suite"
    print_status "Timestamp: $TIMESTAMP"
    print_status "Test Environment: $TEST_ENVIRONMENT"
    print_status "Test Suite: $TEST_SUITE"
    print_status "Concurrent Requests: $CONCURRENT_REQUESTS"
    
    if [[ "$QUICK_MODE" == "true" ]]; then
        print_status "Quick Mode: Enabled"
    fi
    
    echo ""
    
    # Run tests based on environment selection
    case $TEST_ENVIRONMENT in
        testnet)
            run_tests_for_environment "$TESTNET_URL" "testnet"
            ;;
        mainnet)
            run_tests_for_environment "$MAINNET_URL" "mainnet"
            ;;
        both)
            run_tests_for_environment "$TESTNET_URL" "testnet"
            echo ""
            print_status "Cooling down between environments..."
            sleep 60
            echo ""
            run_tests_for_environment "$MAINNET_URL" "mainnet"
            ;;
    esac
    
    # Generate master report
    generate_master_report
    
    print_header "Master Testing Suite Completed!"
    print_status "All results saved in: $MASTER_RESULTS_DIR"
    print_status "Master report: $MASTER_RESULTS_DIR/master_test_report_$TIMESTAMP.html"
    
    # Show quick summary
    echo ""
    print_status "Quick Summary:"
    print_status "  Environment(s) Tested: $TEST_ENVIRONMENT"
    print_status "  Test Suite(s): $TEST_SUITE"
    print_status "  Concurrent Requests: $CONCURRENT_REQUESTS"
    print_status "  Results Directory: $MASTER_RESULTS_DIR"
}

# Cleanup function
cleanup() {
    print_status "Test suite completed. Check results in $MASTER_RESULTS_DIR"
}

trap cleanup EXIT

# Run main function
main "$@"

