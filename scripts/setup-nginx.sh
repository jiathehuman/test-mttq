#!/bin/bash

# Setup Nginx load balancer for MQTT brokers
# Configures nginx with stream module for TCP load balancing

set -e

echo "🌐 Setting up Nginx Load Balancer"

# Configuration
NGINX_CONF_DIR="/usr/local/etc/nginx"  # macOS path
NGINX_CONF_FILE="${NGINX_CONF_DIR}/nginx.conf"
PROJECT_NGINX_CONF="/Users/main/Desktop/test-mqtt-brokers/nginx/nginx.conf"

# Detect OS for nginx paths
OS="$(uname -s)"
case "${OS}" in
    Linux*)
        NGINX_CONF_DIR="/etc/nginx"
        NGINX_CONF_FILE="${NGINX_CONF_DIR}/nginx.conf"
        ;;
    Darwin*)
        NGINX_CONF_DIR="/usr/local/etc/nginx"
        NGINX_CONF_FILE="${NGINX_CONF_DIR}/nginx.conf"
        ;;
    *)
        echo "❌ Unsupported OS: ${OS}"
        exit 1
        ;;
esac

# Backup existing nginx configuration
backup_nginx_config() {
    if [ -f "${NGINX_CONF_FILE}" ]; then
        echo "📋 Backing up existing nginx configuration..."
        sudo cp "${NGINX_CONF_FILE}" "${NGINX_CONF_FILE}.backup.$(date +%s)"
    fi
}

# Install nginx stream module if needed
install_stream_module() {
    echo "🔧 Checking nginx stream module..."

    if [[ "$OS" == "Darwin" ]]; then
        # macOS - check if nginx was compiled with stream module
        if nginx -V 2>&1 | grep -q "with-stream"; then
            echo "✅ Nginx stream module already available"
        else
            echo "📦 Installing nginx with stream module..."
            brew uninstall nginx 2>/dev/null || true
            brew install nginx-full --with-stream-module 2>/dev/null || {
                echo "⚠️  nginx-full not available, using standard nginx"
                echo "   Note: Stream module may not be available"
                brew install nginx
            }
        fi
    elif [[ "$OS" == "Linux" ]]; then
        # Linux - install nginx stream module
        sudo apt-get update
        sudo apt-get install -y nginx nginx-module-stream
    fi
}

# Setup nginx configuration
setup_nginx_config() {
    echo "⚙️  Setting up nginx configuration..."

    # Ensure nginx config directory exists
    sudo mkdir -p "${NGINX_CONF_DIR}"

    # Copy our nginx configuration
    sudo cp "${PROJECT_NGINX_CONF}" "${NGINX_CONF_FILE}"

    # Create log directories
    sudo mkdir -p /var/log/nginx

    # Ensure nginx can write to log files
    if [[ "$OS" == "Linux" ]]; then
        sudo chown -R www-data:www-data /var/log/nginx
    elif [[ "$OS" == "Darwin" ]]; then
        sudo chown -R $(whoami):staff /var/log/nginx
    fi

    echo "✅ Nginx configuration installed"
}

# Test nginx configuration
test_nginx_config() {
    echo "🔍 Testing nginx configuration..."

    if sudo nginx -t; then
        echo "✅ Nginx configuration is valid"
        return 0
    else
        echo "❌ Nginx configuration has errors"
        return 1
    fi
}

# Start nginx service
start_nginx() {
    echo "🚀 Starting nginx service..."

    if [[ "$OS" == "Darwin" ]]; then
        # macOS
        sudo brew services start nginx 2>/dev/null || {
            echo "Starting nginx manually..."
            sudo nginx
        }
    elif [[ "$OS" == "Linux" ]]; then
        # Linux
        sudo systemctl enable nginx
        sudo systemctl start nginx
    fi

    # Wait a moment for nginx to start
    sleep 2

    # Check if nginx is running
    if pgrep nginx > /dev/null; then
        echo "✅ Nginx is running"

        # Test load balancer endpoint
        echo "🔍 Testing load balancer endpoint..."
        if nc -z localhost 1883; then
            echo "✅ MQTT load balancer port (1883) is accessible"
        else
            echo "⚠️  MQTT load balancer port (1883) is not accessible"
        fi

        # Test health check endpoint
        if nc -z localhost 8080; then
            echo "✅ Health check endpoint (8080) is accessible"
        else
            echo "⚠️  Health check endpoint (8080) is not accessible"
        fi

    else
        echo "❌ Failed to start nginx"
        return 1
    fi
}

# Stop nginx service
stop_nginx() {
    echo "🛑 Stopping nginx service..."

    if [[ "$OS" == "Darwin" ]]; then
        sudo brew services stop nginx 2>/dev/null || sudo nginx -s quit
    elif [[ "$OS" == "Linux" ]]; then
        sudo systemctl stop nginx
    fi
}

# Reload nginx configuration
reload_nginx() {
    echo "🔄 Reloading nginx configuration..."
    sudo nginx -s reload
}

# Show nginx status
show_status() {
    echo "📊 Nginx Status:"

    if pgrep nginx > /dev/null; then
        echo "   Status: Running ✅"

        # Show listening ports
        echo "   Listening ports:"
        netstat -an | grep LISTEN | grep -E "(1883|8080)" | while read line; do
            echo "     $line"
        done

        # Show nginx processes
        echo "   Processes:"
        pgrep -l nginx | while read line; do
            echo "     $line"
        done

    else
        echo "   Status: Not running ❌"
    fi
}

# Main execution
main() {
    case "${1:-setup}" in
        setup)
            backup_nginx_config
            install_stream_module
            setup_nginx_config
            if test_nginx_config; then
                start_nginx
                show_status

                echo ""
                echo "🎯 Nginx Load Balancer Setup Complete!"
                echo "   MQTT Load Balancer: localhost:1883"
                echo "   Health Check API: localhost:8080"
                echo "   Dashboard: localhost:8080 (proxied to port 3000)"
                echo ""
                echo "Next steps:"
                echo "   1. Ensure all MQTT brokers are running"
                echo "   2. Start the health service: python3 services/health-service.py"
                echo "   3. Start the dashboard: cd dashboard && npm start"
            fi
            ;;
        start)
            start_nginx
            ;;
        stop)
            stop_nginx
            ;;
        restart)
            stop_nginx
            sleep 2
            start_nginx
            ;;
        reload)
            reload_nginx
            ;;
        status)
            show_status
            ;;
        test)
            test_nginx_config
            ;;
        *)
            echo "Usage: $0 {setup|start|stop|restart|reload|status|test}"
            echo ""
            echo "Commands:"
            echo "  setup   - Install and configure nginx (default)"
            echo "  start   - Start nginx service"
            echo "  stop    - Stop nginx service"
            echo "  restart - Restart nginx service"
            echo "  reload  - Reload nginx configuration"
            echo "  status  - Show nginx status"
            echo "  test    - Test nginx configuration"
            ;;
    esac
}

main "$@"