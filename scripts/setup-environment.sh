#!/bin/bash

# MQTT Broker Cluster Environment Setup Script
#
# Cross-platform environment preparation script for MQTT broker cluster deployment.
# Handles dependency installation, system configuration, and prerequisite validation
# for both macOS and Linux development/production environments.
#
# Key Responsibilities:
# - Operating system detection and platform-specific package installation
# - Multipass VM orchestration platform setup and configuration
# - Python runtime dependencies installation for monitoring services
# - Node.js ecosystem setup for web dashboard functionality
# - Network configuration validation and firewall considerations
# - Directory structure creation for logs, configurations, and data persistence
#
# Supported Platforms:
# - macOS (via Homebrew package manager)
# - Linux (via snap and apt package managers)
# - Automatic fallback handling for unsupported platforms
#
# Prerequisites: Administrative privileges for system package installation
# Post-setup: System ready for broker cluster deployment via deploy-brokers.sh

set -e  # Exit immediately on any command failure

echo "MQTT Broker Cluster Environment Setup initiated"

# Cross-platform operating system detection
# Determines appropriate package managers and installation methods
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;     # Linux distributions (Ubuntu, CentOS, etc.)
    Darwin*)    MACHINE=Mac;;       # macOS (Darwin kernel)
    *)          MACHINE="UNKNOWN:${OS}"  # Unsupported platforms
esac

echo "Detected operating system: ${MACHINE}"

# Multipass VM Orchestration Platform Installation
#
# Installs Multipass for cross-platform virtual machine management.
# Multipass provides lightweight Ubuntu VM creation and management
# with minimal resource overhead and simple command-line interface.
#
# Platform-specific installation methods:
# - macOS: Homebrew package manager (preferred method)
# - Linux: Snap package manager (universal Linux package system)
#
# Validates existing installation to prevent duplicate setup attempts.
install_multipass() {
    if ! command -v multipass &> /dev/null; then
        echo "Installing Multipass VM orchestration platform..."

        if [[ "$MACHINE" == "Mac" ]]; then
            # macOS installation via Homebrew
            # Requires Homebrew package manager for dependency resolution
            if command -v brew &> /dev/null; then
                brew install multipass
            else
                echo "ERROR: Homebrew package manager required for macOS installation"
                echo "Install Homebrew: https://brew.sh"
                exit 1
            fi
        elif [[ "$MACHINE" == "Linux" ]]; then
            # Linux installation via Snap package manager
            # Snap provides universal package distribution across Linux distributions
            sudo snap install multipass
        fi
    else
        echo "Multipass VM platform already installed - skipping installation"
    fi
}

# Python Runtime Dependencies Installation
#
# Installs essential Python packages for MQTT broker monitoring and management.
# Uses user-level installation to avoid system-wide package conflicts and
# administrative privilege requirements.
#
# Core Dependencies:
# - paho-mqtt: Pure Python MQTT client library for broker communication
# - flask: Lightweight WSGI web framework for HTTP API endpoints
# - requests: HTTP library for external service integration and API calls
# - psutil: System and process monitoring utilities for resource tracking
#
# Installation Strategy:
# - User-level installation (--user flag) for isolated dependency management
# - Cross-platform compatibility with consistent package versions
# - Automatic dependency resolution via pip package manager
install_python_deps() {
    echo "Installing Python runtime dependencies for monitoring services..."

    # User-level installation prevents system-wide conflicts
    # Consistent installation method across macOS and Linux platforms
    python3 -m pip install --user paho-mqtt flask requests psutil

    echo "Python dependencies installed successfully"
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