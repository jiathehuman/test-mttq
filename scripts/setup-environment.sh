#!/bin/bash

# Setup script for MQTT hierarchical network
# Works on both macOS and Linux

set -e

echo "Setting up MQTT Hierarchical Network Environment"

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    *)          MACHINE="UNKNOWN:${OS}"
esac

echo "Detected OS: ${MACHINE}"

# Install Multipass
install_multipass() {
    if ! command -v multipass &> /dev/null; then
        echo "Installing Multipass..."
        if [[ "$MACHINE" == "Mac" ]]; then
            if command -v brew &> /dev/null; then
                brew install multipass
            else
                echo "ERROR: Please install Homebrew first: https://brew.sh"
                exit 1
            fi
        elif [[ "$MACHINE" == "Linux" ]]; then
            sudo snap install multipass
        fi
    else
        echo "Multipass already installed"
    fi
}

# Install Python dependencies
install_python_deps() {
    echo "Installing Python dependencies..."
    if [[ "$MACHINE" == "Mac" ]]; then
        python3 -m pip install --user paho-mqtt flask requests psutil
    else
        python3 -m pip install --user paho-mqtt flask requests psutil
    fi
}

# Install Node.js dependencies for dashboard
install_node_deps() {
    echo "Installing Node.js dependencies..."
    if ! command -v node &> /dev/null; then
        if [[ "$MACHINE" == "Mac" ]]; then
            if command -v brew &> /dev/null; then
                brew install node
            else
                echo "ERROR: Please install Node.js: https://nodejs.org"
                exit 1
            fi
        elif [[ "$MACHINE" == "Linux" ]]; then
            curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
            sudo apt-get install -y nodejs
        fi
    else
        echo "Node.js already installed"
    fi
}

# Install Nginx
install_nginx() {
    if ! command -v nginx &> /dev/null; then
        echo "Installing Nginx..."
        if [[ "$MACHINE" == "Mac" ]]; then
            if command -v brew &> /dev/null; then
                brew install nginx
            else
                echo "ERROR: Please install Homebrew first: https://brew.sh"
                exit 1
            fi
        elif [[ "$MACHINE" == "Linux" ]]; then
            sudo apt-get update
            sudo apt-get install -y nginx nginx-module-stream
        fi
    else
        echo "Nginx already installed"
    fi
}

# Create directory structure
create_directories() {
    echo "Creating directory structure..."
    mkdir -p multipass
    mkdir -p nginx
    mkdir -p mosquitto-configs/bridges
    mkdir -p services
    mkdir -p client-examples/python
    mkdir -p dashboard/{public,src}
    mkdir -p testing
    mkdir -p logs
    mkdir -p scripts
}

# Set permissions
set_permissions() {
    echo "Setting permissions..."
    chmod +x scripts/*.sh 2>/dev/null || true
    chmod +x testing/*.sh 2>/dev/null || true
}

# Main execution
main() {
    install_multipass
    install_python_deps
    install_node_deps
    install_nginx
    create_directories
    set_permissions

    echo "Environment setup complete!"
    echo "Next steps:"
    echo "   1. Run ./scripts/deploy-brokers.sh to create VM infrastructure"
    echo "   2. Run ./scripts/start-services.sh to start all services"
    echo "   3. Run ./scripts/run-tests.sh to execute test scenarios"
}

main "$@"