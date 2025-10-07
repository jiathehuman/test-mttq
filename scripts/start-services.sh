#!/bin/bash

# Start all MQTT network services
# Coordinates startup of brokers, health service, nginx, and dashboard

set -e

echo "🚀 Starting MQTT Hierarchical Network Services"

# Configuration
PROJECT_ROOT="/Users/main/Desktop/test-mqtt-brokers"
HEALTH_SERVICE_PID_FILE="${PROJECT_ROOT}/logs/health-service.pid"
DASHBOARD_PID_FILE="${PROJECT_ROOT}/logs/dashboard.pid"

# Change to project directory
cd "${PROJECT_ROOT}"

# Create logs directory
mkdir -p logs

# Function to check if a service is running
check_service() {
    local service_name="$1"
    local pid_file="$2"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "✅ $service_name is running (PID: $pid)"
            return 0
        else
            echo "⚠️  $service_name PID file exists but process is not running"
            rm -f "$pid_file"
            return 1
        fi
    else
        echo "❌ $service_name is not running"
        return 1
    fi
}

# Function to start health service
start_health_service() {
    echo "🏥 Starting Health Service..."

    if check_service "Health Service" "$HEALTH_SERVICE_PID_FILE"; then
        echo "   Health service already running"
        return 0
    fi

    # Install Python dependencies if needed
    echo "📦 Checking Python dependencies..."
    python3 -m pip install --user paho-mqtt flask requests psutil 2>/dev/null || {
        echo "⚠️  Failed to install some Python dependencies"
    }

    # Start health service in background
    nohup python3 services/health-service.py > logs/health-service.log 2>&1 &
    local health_pid=$!
    echo $health_pid > "$HEALTH_SERVICE_PID_FILE"

    # Wait for service to start
    sleep 3

    if check_service "Health Service" "$HEALTH_SERVICE_PID_FILE"; then
        echo "✅ Health service started successfully"

        # Test health service endpoint
        if curl -s http://localhost:5000/health > /dev/null; then
            echo "✅ Health service endpoint is responding"
        else
            echo "⚠️  Health service endpoint not responding yet"
        fi
    else
        echo "❌ Failed to start health service"
        return 1
    fi
}

# Function to start dashboard
start_dashboard() {
    echo "📊 Starting Dashboard..."

    if check_service "Dashboard" "$DASHBOARD_PID_FILE"; then
        echo "   Dashboard already running"
        return 0
    fi

    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        echo "❌ Node.js not found. Please install Node.js first."
        return 1
    fi

    # Install dashboard dependencies
    cd dashboard
    if [ ! -d "node_modules" ]; then
        echo "📦 Installing dashboard dependencies..."
        npm install
    fi

    # Start dashboard in background
    nohup npm start > ../logs/dashboard.log 2>&1 &
    local dashboard_pid=$!
    echo $dashboard_pid > "$DASHBOARD_PID_FILE"

    cd ..

    # Wait for dashboard to start
    sleep 5

    if check_service "Dashboard" "$DASHBOARD_PID_FILE"; then
        echo "✅ Dashboard started successfully"

        # Test dashboard endpoint
        if curl -s http://localhost:3000 > /dev/null; then
            echo "✅ Dashboard is accessible at http://localhost:3000"
        else
            echo "⚠️  Dashboard not responding yet, may need more time to start"
        fi
    else
        echo "❌ Failed to start dashboard"
        return 1
    fi
}

# Function to check broker status
check_brokers() {
    echo "🔍 Checking MQTT Brokers..."

    local brokers=("broker1" "broker2" "broker3" "broker4" "broker5")
    local ips=("192.168.64.2" "192.168.64.3" "192.168.64.4" "192.168.64.5" "192.168.64.6")

    local running_brokers=0

    for i in "${!brokers[@]}"; do
        local broker="${brokers[$i]}"
        local ip="${ips[$i]}"

        # Check VM status
        local vm_status=$(multipass info "$broker" --format json 2>/dev/null | jq -r ".info[\"$broker\"].state" 2>/dev/null || echo "unknown")

        if [ "$vm_status" = "Running" ]; then
            # Check MQTT port
            if nc -z "$ip" 1883 2>/dev/null; then
                echo "✅ $broker ($ip) is running and MQTT port is accessible"
                ((running_brokers++))
            else
                echo "⚠️  $broker ($ip) VM is running but MQTT port not accessible"
            fi
        else
            echo "❌ $broker VM is not running (status: $vm_status)"
        fi
    done

    echo "📊 Broker Summary: $running_brokers/5 brokers are accessible"

    if [ $running_brokers -eq 0 ]; then
        echo "⚠️  No brokers are running. Please run ./scripts/deploy-brokers.sh first"
        return 1
    fi
}

# Function to check nginx
check_nginx() {
    echo "🌐 Checking Nginx Load Balancer..."

    if pgrep nginx > /dev/null; then
        echo "✅ Nginx is running"

        # Check MQTT load balancer port
        if nc -z localhost 1883; then
            echo "✅ MQTT load balancer (port 1883) is accessible"
        else
            echo "❌ MQTT load balancer port not accessible"
        fi

        # Check health check API port
        if nc -z localhost 8080; then
            echo "✅ Health check API (port 8080) is accessible"
        else
            echo "❌ Health check API port not accessible"
        fi
    else
        echo "❌ Nginx is not running. Please run ./scripts/setup-nginx.sh first"
        return 1
    fi
}

# Function to stop all services
stop_services() {
    echo "🛑 Stopping all services..."

    # Stop health service
    if [ -f "$HEALTH_SERVICE_PID_FILE" ]; then
        local health_pid=$(cat "$HEALTH_SERVICE_PID_FILE")
        if ps -p "$health_pid" > /dev/null 2>&1; then
            echo "🛑 Stopping health service (PID: $health_pid)..."
            kill "$health_pid"
            rm -f "$HEALTH_SERVICE_PID_FILE"
        fi
    fi

    # Stop dashboard
    if [ -f "$DASHBOARD_PID_FILE" ]; then
        local dashboard_pid=$(cat "$DASHBOARD_PID_FILE")
        if ps -p "$dashboard_pid" > /dev/null 2>&1; then
            echo "🛑 Stopping dashboard (PID: $dashboard_pid)..."
            kill "$dashboard_pid"
            rm -f "$DASHBOARD_PID_FILE"
        fi
    fi

    # Stop nginx (optional, as it might be used by other services)
    read -p "Stop nginx load balancer? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🛑 Stopping nginx..."
        sudo nginx -s quit 2>/dev/null || true
    fi

    echo "✅ Services stopped"
}

# Function to show service status
show_status() {
    echo "📊 Service Status Overview"
    echo "=========================="

    check_brokers
    echo ""
    check_nginx
    echo ""
    check_service "Health Service" "$HEALTH_SERVICE_PID_FILE"
    check_service "Dashboard" "$DASHBOARD_PID_FILE"

    echo ""
    echo "🌐 Service URLs:"
    echo "   Dashboard: http://localhost:3000"
    echo "   Health API: http://localhost:5000"
    echo "   Nginx Proxy: http://localhost:8080"
    echo "   MQTT Load Balancer: localhost:1883"
}

# Function to follow logs
follow_logs() {
    echo "📋 Following service logs (Ctrl+C to stop)..."

    # Create log files if they don't exist
    touch logs/health-service.log logs/dashboard.log

    # Follow all logs
    tail -f logs/health-service.log logs/dashboard.log 2>/dev/null | while read line; do
        echo "$(date '+%H:%M:%S') $line"
    done
}

# Main execution
main() {
    case "${1:-start}" in
        start)
            echo "🚀 Starting all services..."
            check_brokers
            check_nginx
            start_health_service
            start_dashboard

            echo ""
            echo "🎉 MQTT Network Services Started!"
            echo ""
            show_status
            echo ""
            echo "🎯 Next steps:"
            echo "   1. Open dashboard: http://localhost:3000"
            echo "   2. Run tests: python3 testing/network-tests.py"
            echo "   3. Monitor logs: $0 logs"
            ;;
        stop)
            stop_services
            ;;
        restart)
            stop_services
            sleep 2
            main start
            ;;
        status)
            show_status
            ;;
        logs)
            follow_logs
            ;;
        health)
            start_health_service
            ;;
        dashboard)
            start_dashboard
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|status|logs|health|dashboard}"
            echo ""
            echo "Commands:"
            echo "  start     - Start all services (default)"
            echo "  stop      - Stop all services"
            echo "  restart   - Restart all services"
            echo "  status    - Show service status"
            echo "  logs      - Follow service logs"
            echo "  health    - Start only health service"
            echo "  dashboard - Start only dashboard"
            ;;
    esac
}

main "$@"