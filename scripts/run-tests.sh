#!/bin/bash

# Run comprehensive MQTT network tests
# Executes the full test suite including failover scenarios

set -e

echo "🧪 MQTT Network Test Suite"

# Configuration
PROJECT_ROOT="/Users/main/Desktop/test-mqtt-brokers"
TEST_RESULTS_DIR="${PROJECT_ROOT}/logs/test-results"

# Change to project directory
cd "${PROJECT_ROOT}"

# Create test results directory
mkdir -p "$TEST_RESULTS_DIR"

# Function to check prerequisites
check_prerequisites() {
    echo "🔍 Checking prerequisites..."

    local all_good=true

    # Check if brokers are running
    echo "   Checking MQTT brokers..."
    local running_brokers=0
    local brokers=("broker1" "broker2" "broker3" "broker4" "broker5")
    local ips=("192.168.64.2" "192.168.64.3" "192.168.64.4" "192.168.64.5" "192.168.64.6")

    for i in "${!brokers[@]}"; do
        local broker="${brokers[$i]}"
        local ip="${ips[$i]}"

        if nc -z "$ip" 1883 2>/dev/null; then
            ((running_brokers++))
        fi
    done

    if [ $running_brokers -lt 3 ]; then
        echo "❌ Insufficient brokers running ($running_brokers/5). Need at least 3 for testing."
        all_good=false
    else
        echo "✅ $running_brokers/5 brokers are accessible"
    fi

    # Check nginx load balancer
    echo "   Checking nginx load balancer..."
    if nc -z localhost 1883; then
        echo "✅ MQTT load balancer is accessible"
    else
        echo "❌ MQTT load balancer not accessible"
        all_good=false
    fi

    # Check health service
    echo "   Checking health service..."
    if curl -s http://localhost:5000/health > /dev/null; then
        echo "✅ Health service is responding"
    else
        echo "❌ Health service not responding"
        all_good=false
    fi

    # Check dashboard
    echo "   Checking dashboard..."
    if curl -s http://localhost:3000 > /dev/null; then
        echo "✅ Dashboard is accessible"
    else
        echo "⚠️  Dashboard not accessible (non-critical for testing)"
    fi

    # Check Python dependencies
    echo "   Checking Python dependencies..."
    python3 -c "import paho.mqtt.client, json, time, threading, requests" 2>/dev/null && {
        echo "✅ Python dependencies available"
    } || {
        echo "❌ Missing Python dependencies"
        all_good=false
    }

    if [ "$all_good" = false ]; then
        echo ""
        echo "❌ Prerequisites not met. Please ensure:"
        echo "   1. Brokers are deployed and running: ./scripts/deploy-brokers.sh"
        echo "   2. Nginx is configured and running: ./scripts/setup-nginx.sh"
        echo "   3. Services are started: ./scripts/start-services.sh"
        return 1
    fi

    echo "✅ All prerequisites met"
    return 0
}

# Function to run individual test
run_test() {
    local test_name="$1"
    local test_description="$2"

    echo ""
    echo "🧪 Running Test: $test_description"
    echo "=================================="

    local start_time=$(date +%s)
    local test_output_file="${TEST_RESULTS_DIR}/test-${test_name}-$(date +%s).log"

    if python3 testing/network-tests.py "$test_name" 2>&1 | tee "$test_output_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "✅ Test '$test_description' completed successfully in ${duration}s"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "❌ Test '$test_description' failed after ${duration}s"
        echo "   Log file: $test_output_file"
        return 1
    fi
}

# Function to run full test suite
run_full_suite() {
    echo "🚀 Running Full MQTT Network Test Suite"
    echo "========================================"

    local start_time=$(date +%s)
    local test_output_file="${TEST_RESULTS_DIR}/full-test-suite-$(date +%s).log"

    echo "📝 Test log: $test_output_file"
    echo ""

    if python3 testing/network-tests.py 2>&1 | tee "$test_output_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo ""
        echo "🎉 Full test suite completed successfully!"
        echo "   Duration: ${duration}s ($(echo "scale=1; $duration/60" | bc)m)"
        echo "   Log file: $test_output_file"

        # Try to extract summary from test results
        if grep -q "Test Summary:" "$test_output_file"; then
            echo ""
            echo "📊 Test Results Summary:"
            grep -A 10 "Test Summary:" "$test_output_file"
        fi

        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo ""
        echo "❌ Full test suite failed after ${duration}s"
        echo "   Log file: $test_output_file"
        return 1
    fi
}

# Function to run client simulation
run_client_simulation() {
    echo "👥 Running Client Simulation"
    echo "============================="

    local duration=${1:-300}  # Default 5 minutes

    echo "🚀 Starting sensor and control clients for ${duration}s..."

    # Start sensor client in background
    python3 client-examples/python/failover-client.py sensor &
    local sensor_pid=$!

    # Start control client in background
    python3 client-examples/python/failover-client.py control &
    local control_pid=$!

    echo "📊 Clients started:"
    echo "   Sensor client PID: $sensor_pid"
    echo "   Control client PID: $control_pid"
    echo ""
    echo "⏱️  Running for ${duration}s..."
    echo "   Press Ctrl+C to stop early"

    # Wait for specified duration or user interrupt
    local count=0
    while [ $count -lt $duration ]; do
        sleep 1
        ((count++))

        # Show progress every 30 seconds
        if [ $((count % 30)) -eq 0 ]; then
            echo "   Progress: ${count}/${duration}s ($(echo "scale=1; $count*100/$duration" | bc)%)"
        fi
    done

    echo ""
    echo "🛑 Stopping clients..."

    # Stop clients
    kill $sensor_pid $control_pid 2>/dev/null || true
    wait $sensor_pid $control_pid 2>/dev/null || true

    echo "✅ Client simulation completed"
}

# Function to generate test report
generate_report() {
    echo "📊 Generating Test Report"
    echo "========================="

    local report_file="${TEST_RESULTS_DIR}/test-report-$(date +%Y%m%d-%H%M%S).html"

    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>MQTT Network Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; }
        .header { text-align: center; margin-bottom: 30px; }
        .summary { background: #e8f4fd; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .test-result { margin: 10px 0; padding: 10px; border-left: 4px solid #ddd; }
        .pass { border-left-color: #28a745; background: #d4edda; }
        .fail { border-left-color: #dc3545; background: #f8d7da; }
        .log { background: #f8f9fa; padding: 10px; border-radius: 3px; font-family: monospace; font-size: 12px; }
        pre { white-space: pre-wrap; word-wrap: break-word; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔗 MQTT Network Test Report</h1>
            <p>Generated on $(date)</p>
        </div>

        <div class="summary">
            <h2>📋 Test Summary</h2>
            <p>Test execution completed. Detailed results below.</p>
        </div>

        <div class="test-results">
            <h2>🧪 Test Results</h2>
EOF

    # Add test result files to report
    for log_file in "${TEST_RESULTS_DIR}"/*.log; do
        if [ -f "$log_file" ]; then
            local test_name=$(basename "$log_file" .log)
            cat >> "$report_file" << EOF
            <div class="test-result">
                <h3>$test_name</h3>
                <div class="log">
                    <pre>$(cat "$log_file" | head -50)</pre>
                </div>
            </div>
EOF
        fi
    done

    cat >> "$report_file" << EOF
        </div>
    </div>
</body>
</html>
EOF

    echo "📄 Test report generated: $report_file"

    # Try to open report in browser
    if command -v open &> /dev/null; then
        open "$report_file"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$report_file"
    else
        echo "   Open the file in a web browser to view the report"
    fi
}

# Main execution
main() {
    case "${1:-full}" in
        full)
            if check_prerequisites; then
                run_full_suite
                generate_report
            fi
            ;;
        connectivity)
            if check_prerequisites; then
                run_test "connectivity" "Initial Connectivity Test"
            fi
            ;;
        replication)
            if check_prerequisites; then
                run_test "replication" "Message Replication Test"
            fi
            ;;
        retained)
            if check_prerequisites; then
                run_test "retained" "Retained Message Test"
            fi
            ;;
        failover)
            if check_prerequisites; then
                run_test "failover" "Broker Failover Test"
            fi
            ;;
        clients)
            local duration=${2:-300}
            if check_prerequisites; then
                run_client_simulation "$duration"
            fi
            ;;
        check)
            check_prerequisites
            ;;
        report)
            generate_report
            ;;
        *)
            echo "Usage: $0 {full|connectivity|replication|retained|failover|clients|check|report}"
            echo ""
            echo "Commands:"
            echo "  full         - Run complete test suite (default)"
            echo "  connectivity - Test initial broker connectivity"
            echo "  replication  - Test message replication across brokers"
            echo "  retained     - Test retained message synchronization"
            echo "  failover     - Test broker failover scenarios"
            echo "  clients [duration] - Run client simulation (default: 300s)"
            echo "  check        - Check prerequisites only"
            echo "  report       - Generate HTML test report"
            echo ""
            echo "Examples:"
            echo "  $0 full              # Run all tests"
            echo "  $0 clients 600       # Run client simulation for 10 minutes"
            echo "  $0 connectivity      # Test connectivity only"
            ;;
    esac
}

main "$@"