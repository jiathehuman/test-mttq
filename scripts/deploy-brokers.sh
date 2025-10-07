#!/bin/bash

# Deploy MQTT brokers using Multipass
# Creates 5 VMs with static IPs and full mesh bridging

set -e

echo "Deploying MQTT Broker Network"

# Configuration
BROKERS=("broker1" "broker2" "broker3" "broker4" "broker5")
IPS=("192.168.100.10" "192.168.100.11" "192.168.100.12" "192.168.100.13" "192.168.100.14")
MEMORY="1G"
DISK="5G"
CPUS="1"

# Check if Multipass is installed
if ! command -v multipass &> /dev/null; then
    echo "ERROR: Multipass not found. Please run ./scripts/setup-environment.sh first"
    exit 1
fi

# Function to create cloud-init files for remaining brokers
create_remaining_cloud_init() {
    for i in {2..4}; do
        local broker_num=$((i + 1))
        local broker_ip="192.168.100.1$i"

        cat > multipass/cloud-init-broker${broker_num}.yaml << EOF
#cloud-config
# Cloud-init configuration for MQTT Broker ${broker_num}

package_update: true
package_upgrade: true

packages:
  - mosquitto
  - mosquitto-clients
  - htop
  - curl
  - jq

write_files:
  - path: /etc/mosquitto/mosquitto.conf
    content: |
      # MQTT Broker ${broker_num} Configuration

      # Basic settings
      port 1883
      listener 1883 0.0.0.0

      # Allow anonymous connections for testing
      allow_anonymous true

      # Persistence
      persistence true
      persistence_location /var/lib/mosquitto/

      # Logging
      log_dest file /var/log/mosquitto/mosquitto.log
      log_type all
      log_timestamp true
      log_timestamp_format %Y-%m-%dT%H:%M:%S

      # Connection settings
      max_connections 1000
      max_keepalive 65535

      # Bridge configurations to other brokers
      connection broker1
      address 192.168.100.10:1883
      topic # both 0 local/ remote/
      try_private false
      cleansession true
      restart_timeout 30

      connection broker2
      address 192.168.100.11:1883
      topic # both 0 local/ remote/
      try_private false
      cleansession true
      restart_timeout 30

      connection broker3
      address 192.168.100.12:1883
      topic # both 0 local/ remote/
      try_private false
      cleansession true
      restart_timeout 30

      connection broker4
      address 192.168.100.13:1883
      topic # both 0 local/ remote/
      try_private false
      cleansession true
      restart_timeout 30

      connection broker5
      address 192.168.100.14:1883
      topic # both 0 local/ remote/
      try_private false
      cleansession true
      restart_timeout 30
    owner: mosquitto:mosquitto
    permissions: '0644'

  - path: /usr/local/bin/mqtt-health-reporter.py
    content: |
      #!/usr/bin/env python3
      import paho.mqtt.client as mqtt
      import json
      import time
      import socket
      import subprocess
      import os

      BROKER_ID = "broker${broker_num}"
      BROKER_IP = "${broker_ip}"
      HEALTH_TOPIC = "system/health/brokers"
      CLIENT_STATUS_TOPIC = "clients/status"

      def get_broker_stats():
          try:
              # Get mosquitto process info
              result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
              mosquitto_running = 'mosquitto' in result.stdout

              # Get connection count (approximation)
              try:
                  netstat_result = subprocess.run(['netstat', '-an'], capture_output=True, text=True)
                  connections = netstat_result.stdout.count(':1883')
              except:
                  connections = 0

              return {
                  "broker_id": BROKER_ID,
                  "ip": BROKER_IP,
                  "status": "online" if mosquitto_running else "offline",
                  "timestamp": int(time.time()),
                  "connections": connections,
                  "uptime": time.time() - start_time
              }
          except Exception as e:
              return {
                  "broker_id": BROKER_ID,
                  "ip": BROKER_IP,
                  "status": "error",
                  "error": str(e),
                  "timestamp": int(time.time())
              }

      def on_connect(client, userdata, flags, rc):
          print(f"Health reporter connected with result code {rc}")

      def on_message(client, userdata, msg):
          # Handle client status updates
          if msg.topic.startswith(CLIENT_STATUS_TOPIC):
              print(f"Client status: {msg.topic} - {msg.payload.decode()}")

      if __name__ == "__main__":
          start_time = time.time()

          client = mqtt.Client(f"health-reporter-{BROKER_ID}")
          client.on_connect = on_connect
          client.on_message = on_message

          try:
              client.connect("localhost", 1883, 60)
              client.subscribe(f"{CLIENT_STATUS_TOPIC}/+")

              client.loop_start()

              while True:
                  stats = get_broker_stats()
                  client.publish(HEALTH_TOPIC, json.dumps(stats), retain=True)
                  time.sleep(10)

          except KeyboardInterrupt:
              print("Health reporter stopping...")
              client.loop_stop()
              client.disconnect()
    owner: mosquitto:mosquitto
    permissions: '0755'

  - path: /etc/systemd/system/mqtt-health.service
    content: |
      [Unit]
      Description=MQTT Health Reporter
      After=mosquitto.service

      [Service]
      Type=simple
      User=mosquitto
      ExecStart=/usr/local/bin/mqtt-health-reporter.py
      Restart=always
      RestartSec=10

      [Install]
      WantedBy=multi-user.target
    permissions: '0644'

runcmd:
  - systemctl enable mosquitto
  - systemctl start mosquitto
  - systemctl enable mqtt-health
  - systemctl start mqtt-health
  - echo "MQTT Broker ${broker_num} setup complete" >> /var/log/setup.log

final_message: "MQTT Broker ${broker_num} is ready!"
EOF
    done
}

# Function to launch VMs
launch_brokers() {
    echo "Creating cloud-init files for remaining brokers..."
    create_remaining_cloud_init

    echo "Launching broker VMs..."
    for i in "${!BROKERS[@]}"; do
        local broker=${BROKERS[$i]}
        local ip=${IPS[$i]}

        echo "Creating ${broker} with IP ${ip}..."        multipass launch --name "${broker}" \
                          --memory "${MEMORY}" \
                          --disk "${DISK}" \
                          --cpus "${CPUS}" \
                          --cloud-init "multipass/cloud-init-${broker}.yaml" \
                          20.04

        echo "Configuring static IP for ${broker}..."
        # Note: Static IP configuration might need adjustment based on Multipass version
        # This is a simplified approach
        sleep 5
    done
}

# Function to verify deployment
verify_deployment() {
    echo "Verifying broker deployment..."

    for broker in "${BROKERS[@]}"; do
        echo "Checking ${broker}..."
        multipass info "${broker}"

        # Wait for services to start
        echo "Waiting for ${broker} services to start..."
        sleep 10

        # Test MQTT connection
        local ip=$(multipass info "${broker}" --format json | jq -r '.info["'${broker}'"].ipv4[0]')
        echo "Testing MQTT connection to ${broker} (${ip})..."

        # Simple connection test (will be more comprehensive in testing phase)
        timeout 5 bash -c "echo > /dev/tcp/${ip}/1883" && echo "SUCCESS: ${broker} MQTT port accessible" || echo "ERROR: ${broker} MQTT port not accessible"
    done
}# Function to setup networking (if needed)
setup_networking() {
    echo "Setting up network configuration..."

    # Get the network bridge information
    echo "Current Multipass network info:"
    multipass networks

    # List running instances
    echo "Running instances:"
    multipass list
}

# Main execution
main() {
    # Clean up any existing instances
    echo "Cleaning up existing instances..."
    for broker in "${BROKERS[@]}"; do
        multipass delete "${broker}" 2>/dev/null || true
        multipass purge 2>/dev/null || true
    done

    launch_brokers
    setup_networking
    verify_deployment

    echo "MQTT broker network deployment complete!"
    echo "Next steps:"
    echo "   1. Run ./scripts/setup-nginx.sh to configure load balancer"
    echo "   2. Run ./scripts/start-services.sh to start monitoring services"
    echo "   3. Check broker status with: multipass list"
}

main "$@"