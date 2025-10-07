#!/usr/bin/env python3
"""
MQTT Client with Transparent Failover
Connects through nginx load balancer for automatic failover
"""

import paho.mqtt.client as mqtt
import json
import time
import threading
import uuid
import random
from datetime import datetime

class MQTTFailoverClient:
    def __init__(self, client_id=None, load_balancer_host="localhost", load_balancer_port=1883):
        self.client_id = client_id or f"client-{uuid.uuid4().hex[:8]}"
        self.load_balancer_host = load_balancer_host
        self.load_balancer_port = load_balancer_port

        self.client = mqtt.Client(self.client_id)
        self.client.on_connect = self.on_connect
        self.client.on_disconnect = self.on_disconnect
        self.client.on_message = self.on_message
        self.client.on_publish = self.on_publish

        self.connected = False
        self.reconnect_attempts = 0
        self.max_reconnect_attempts = 10
        self.reconnect_delay = 5  # seconds

        self.status_topic = f"clients/status/{self.client_id}"
        self.subscribed_topics = set()

        # Message stats
        self.messages_sent = 0
        self.messages_received = 0
        self.connection_start = None

        print(f"🚀 Initialized MQTT client: {self.client_id}")

    def on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            self.connected = True
            self.reconnect_attempts = 0
            self.connection_start = time.time()

            print(f"✅ Connected to MQTT broker via load balancer")

            # Publish client status
            self.publish_client_status("connected")

            # Resubscribe to topics
            self.resubscribe_topics()

        else:
            print(f"❌ Failed to connect to MQTT broker: {rc}")
            self.connected = False

    def on_disconnect(self, client, userdata, rc):
        self.connected = False
        connection_duration = time.time() - self.connection_start if self.connection_start else 0

        print(f"🔌 Disconnected from MQTT broker (duration: {connection_duration:.1f}s)")

        if rc != 0:  # Unexpected disconnection
            print(f"⚠️  Unexpected disconnection: {rc}")
            self.handle_reconnection()

    def on_message(self, client, userdata, msg):
        self.messages_received += 1
        topic = msg.topic
        payload = msg.payload.decode()

        print(f"📨 Received message on {topic}: {payload}")

        # Handle specific message types
        if topic.startswith("sensors/"):
            self.handle_sensor_message(topic, payload)
        elif topic.startswith("commands/"):
            self.handle_command_message(topic, payload)

    def on_publish(self, client, userdata, mid):
        self.messages_sent += 1
        print(f"📤 Message published (MID: {mid})")

    def handle_reconnection(self):
        """Handle automatic reconnection with exponential backoff"""
        if self.reconnect_attempts < self.max_reconnect_attempts:
            self.reconnect_attempts += 1
            delay = min(self.reconnect_delay * (2 ** (self.reconnect_attempts - 1)), 60)

            print(f"🔄 Reconnection attempt {self.reconnect_attempts}/{self.max_reconnect_attempts} in {delay}s...")
            time.sleep(delay)

            try:
                self.connect()
            except Exception as e:
                print(f"❌ Reconnection failed: {e}")
        else:
            print(f"💀 Max reconnection attempts reached. Giving up.")

    def publish_client_status(self, status):
        """Publish client status to monitoring topic"""
        if self.connected:
            status_data = {
                "client_id": self.client_id,
                "status": status,
                "timestamp": datetime.now().isoformat(),
                "connected_broker": "load_balancer",  # We don't know which actual broker
                "messages_sent": self.messages_sent,
                "messages_received": self.messages_received,
                "connection_duration": time.time() - self.connection_start if self.connection_start else 0
            }

            self.client.publish(self.status_topic, json.dumps(status_data), retain=True)

    def resubscribe_topics(self):
        """Resubscribe to all previously subscribed topics"""
        for topic in self.subscribed_topics:
            self.client.subscribe(topic)
            print(f"🔔 Resubscribed to: {topic}")

    def connect(self):
        """Connect to MQTT broker via load balancer"""
        try:
            print(f"🔌 Connecting to load balancer at {self.load_balancer_host}:{self.load_balancer_port}")
            self.client.connect(self.load_balancer_host, self.load_balancer_port, 60)
            self.client.loop_start()

            # Wait for connection
            timeout = 10
            start_time = time.time()
            while not self.connected and (time.time() - start_time) < timeout:
                time.sleep(0.1)

            if not self.connected:
                raise Exception("Connection timeout")

        except Exception as e:
            print(f"❌ Connection failed: {e}")
            raise

    def disconnect(self):
        """Disconnect from MQTT broker"""
        if self.connected:
            self.publish_client_status("disconnecting")
            time.sleep(0.5)  # Give time for status message to be sent

        self.client.loop_stop()
        self.client.disconnect()
        self.connected = False
        print(f"👋 Disconnected from MQTT broker")

    def subscribe(self, topic, qos=0):
        """Subscribe to a topic"""
        if self.connected:
            self.client.subscribe(topic, qos)
            self.subscribed_topics.add(topic)
            print(f"🔔 Subscribed to: {topic}")
        else:
            print(f"❌ Cannot subscribe - not connected")

    def publish(self, topic, payload, qos=0, retain=False):
        """Publish a message"""
        if self.connected:
            result = self.client.publish(topic, payload, qos, retain)
            return result.mid
        else:
            print(f"❌ Cannot publish - not connected")
            return None

    def handle_sensor_message(self, topic, payload):
        """Handle sensor data messages"""
        try:
            data = json.loads(payload)
            sensor_type = topic.split('/')[-1]
            print(f"🌡️  Sensor {sensor_type}: {data}")
        except json.JSONDecodeError:
            print(f"⚠️  Invalid JSON in sensor message: {payload}")

    def handle_command_message(self, topic, payload):
        """Handle command messages"""
        try:
            command = json.loads(payload)
            print(f"⚡ Command received: {command}")

            # Simulate command execution
            response_topic = f"responses/{self.client_id}"
            response = {
                "command_id": command.get("id"),
                "status": "executed",
                "timestamp": datetime.now().isoformat()
            }
            self.publish(response_topic, json.dumps(response))

        except json.JSONDecodeError:
            print(f"⚠️  Invalid JSON in command message: {payload}")

# Example usage and testing functions
def simulate_sensor_client():
    """Simulate a sensor client that publishes data"""
    client = MQTTFailoverClient("sensor-client")

    try:
        client.connect()

        # Subscribe to commands for this sensor
        client.subscribe(f"commands/{client.client_id}")

        # Publish sensor data every 5 seconds
        sensor_data = {
            "temperature": 20.0,
            "humidity": 45.0,
            "pressure": 1013.25
        }

        for i in range(60):  # Run for 5 minutes
            if client.connected:
                # Simulate changing sensor values
                sensor_data["temperature"] += random.uniform(-1, 1)
                sensor_data["humidity"] += random.uniform(-2, 2)
                sensor_data["pressure"] += random.uniform(-5, 5)
                sensor_data["timestamp"] = datetime.now().isoformat()
                sensor_data["reading_id"] = i

                topic = f"sensors/{client.client_id}/data"
                client.publish(topic, json.dumps(sensor_data), retain=True)

                # Update client status periodically
                if i % 10 == 0:
                    client.publish_client_status("active")

            time.sleep(5)

    except KeyboardInterrupt:
        print("\n🛑 Sensor client stopping...")
    finally:
        client.disconnect()

def simulate_control_client():
    """Simulate a control client that sends commands"""
    client = MQTTFailoverClient("control-client")

    try:
        client.connect()

        # Subscribe to sensor data
        client.subscribe("sensors/+/data")
        client.subscribe("responses/+")

        # Send commands every 15 seconds
        for i in range(20):  # Run for 5 minutes
            if client.connected:
                command = {
                    "id": f"cmd-{i}",
                    "type": "set_threshold",
                    "parameters": {
                        "temperature_max": random.uniform(25, 30),
                        "humidity_max": random.uniform(60, 80)
                    },
                    "timestamp": datetime.now().isoformat()
                }

                # Send command to sensor client
                topic = "commands/sensor-client"
                client.publish(topic, json.dumps(command))

            time.sleep(15)

    except KeyboardInterrupt:
        print("\n🛑 Control client stopping...")
    finally:
        client.disconnect()

if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        if sys.argv[1] == "sensor":
            simulate_sensor_client()
        elif sys.argv[1] == "control":
            simulate_control_client()
        else:
            print("Usage: python failover-client.py [sensor|control]")
    else:
        print("🔧 Testing basic client functionality...")

        client = MQTTFailoverClient("test-client")
        try:
            client.connect()
            client.subscribe("test/+")

            # Publish test messages
            for i in range(10):
                message = {
                    "message_id": i,
                    "content": f"Test message {i}",
                    "timestamp": datetime.now().isoformat()
                }
                client.publish("test/messages", json.dumps(message))
                time.sleep(2)

        except KeyboardInterrupt:
            print("\n🛑 Test client stopping...")
        finally:
            client.disconnect()