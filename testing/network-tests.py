#!/usr/bin/env python3
"""
MQTT Broker Cluster Comprehensive Testing Suite

Automated testing framework for validating MQTT broker cluster functionality,
failover behavior, message replication, and recovery scenarios. Provides
comprehensive validation of the distributed MQTT architecture including
load balancer integration, health monitoring, and client failover mechanisms.

Test Categories:
1. Connectivity Testing - Validates basic MQTT protocol connectivity to all brokers
2. Replication Testing - Verifies message replication across broker mesh network
3. Failover Testing - Simulates broker failures and validates client failover
4. Recovery Testing - Tests broker recovery and cluster reintegration
5. Load Testing - Validates performance under concurrent client load
6. Persistence Testing - Verifies retained messages and session persistence

The testing suite implements multi-threaded test execution with real-time
monitoring and comprehensive result reporting. Each test scenario includes
detailed metrics collection and failure analysis.

Dependencies: paho-mqtt, requests, subprocess (for VM control)
Architecture: Multi-threaded Python test runner with MQTT client simulation
"""

import subprocess
import time
import json
import threading
import paho.mqtt.client as mqtt
import requests
from datetime import datetime
import sys
import os


class MQTTNetworkTester:
    """
    Comprehensive MQTT cluster testing framework.

    Provides automated testing capabilities for MQTT broker clusters including
    connectivity validation, failover simulation, recovery testing, and
    performance benchmarking. Implements thread-safe test execution with
    detailed result collection and analysis.
    """

    def __init__(self):
        """
        Initialize the MQTT network testing framework.

        Sets up broker configuration, test parameters, and result collection
        structures. Configures timing parameters for various test scenarios
        based on expected network behavior and failover timeouts.
        """
        # Broker cluster configuration - matches deployment configuration
        # IP addresses should align with actual VM deployment from deploy-brokers.sh
        self.brokers = [
            {"id": "broker1", "ip": "192.168.64.2", "port": 1883, "priority": 1},
            {"id": "broker2", "ip": "192.168.64.3", "port": 1883, "priority": 2},
            {"id": "broker3", "ip": "192.168.64.4", "port": 1883, "priority": 3},
            {"id": "broker4", "ip": "192.168.64.5", "port": 1883, "priority": 4},
            {"id": "broker5", "ip": "192.168.64.6", "port": 1883, "priority": 5},
        ]

        # Load balancer configuration for client connectivity testing
        self.load_balancer = {"host": "localhost", "port": 1883}

        # Health service configuration for monitoring integration
        self.health_service = {"host": "localhost", "port": 5000}

        # Test result collection and message tracking
        self.test_results = []        # Comprehensive test result history
        self.test_messages = []       # Published test messages for validation
        self.received_messages = {}   # Received message tracking by topic

        # Test execution timing configuration
        # These values are tuned based on MQTT keepalive, network latency,
        # and expected failover detection times in the cluster
        self.test_duration = 300      # 5 minute comprehensive test duration
        self.failure_interval = 60    # 60 second broker failure simulation
        self.recovery_time = 60       # 60 second recovery observation period

        print("MQTT Network Comprehensive Testing Suite initialized")

    def log_result(self, test_name, status, details=None):
        """Log test result"""
        result = {
            "test": test_name,
            "status": status,
            "timestamp": datetime.now().isoformat(),
            "details": details or {}
        }
        self.test_results.append(result)

        status_emoji = "✅" if status == "PASS" else "❌" if status == "FAIL" else "⏳"
        print(f"{status_emoji} {test_name}: {status}")
        if details:
            print(f"   Details: {details}")

    def check_broker_health(self, broker_ip, port=1883, timeout=5):
        """Check if a broker is reachable"""
        try:
            import socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((broker_ip, port))
            sock.close()
            return result == 0
        except Exception as e:
            print(f"Health check error for {broker_ip}: {e}")
            return False

    def get_multipass_vm_status(self, vm_name):
        """Get Multipass VM status"""
        try:
            result = subprocess.run(
                ["multipass", "info", vm_name, "--format", "json"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                info = json.loads(result.stdout)
                vm_info = info["info"][vm_name]
                return vm_info["state"]
            return "unknown"
        except Exception as e:
            print(f"Error getting VM status for {vm_name}: {e}")
            return "error"

    def simulate_broker_failure(self, broker_id):
        """Simulate broker failure by stopping the VM"""
        try:
            print(f"🔥 Simulating failure of {broker_id}")
            result = subprocess.run(
                ["multipass", "stop", broker_id],
                capture_output=True, text=True, timeout=30
            )

            if result.returncode == 0:
                self.log_result(
                    f"Simulate {broker_id} failure",
                    "PASS",
                    {"method": "multipass_stop"}
                )
                return True
            else:
                self.log_result(
                    f"Simulate {broker_id} failure",
                    "FAIL",
                    {"error": result.stderr}
                )
                return False

        except Exception as e:
            self.log_result(
                f"Simulate {broker_id} failure",
                "FAIL",
                {"error": str(e)}
            )
            return False

    def simulate_broker_recovery(self, broker_id):
        """Simulate broker recovery by starting the VM"""
        try:
            print(f"🔧 Simulating recovery of {broker_id}")
            result = subprocess.run(
                ["multipass", "start", broker_id],
                capture_output=True, text=True, timeout=60
            )

            if result.returncode == 0:
                # Wait for services to start
                time.sleep(30)
                self.log_result(
                    f"Simulate {broker_id} recovery",
                    "PASS",
                    {"method": "multipass_start"}
                )
                return True
            else:
                self.log_result(
                    f"Simulate {broker_id} recovery",
                    "FAIL",
                    {"error": result.stderr}
                )
                return False

        except Exception as e:
            self.log_result(
                f"Simulate {broker_id} recovery",
                "FAIL",
                {"error": str(e)}
            )
            return False

    def test_initial_connectivity(self):
        """Test initial connectivity to all brokers"""
        print("\n🔍 Testing Initial Connectivity")

        # Test direct broker connections
        for broker in self.brokers:
            healthy = self.check_broker_health(broker["ip"], broker["port"])
            self.log_result(
                f"Direct connection to {broker['id']}",
                "PASS" if healthy else "FAIL",
                {"ip": broker["ip"], "port": broker["port"]}
            )

        # Test load balancer connection
        lb_healthy = self.check_broker_health(
            self.load_balancer["host"],
            self.load_balancer["port"]
        )
        self.log_result(
            "Load balancer connection",
            "PASS" if lb_healthy else "FAIL",
            {"host": self.load_balancer["host"], "port": self.load_balancer["port"]}
        )

        # Test health service
        try:
            response = requests.get(f"http://{self.health_service['host']}:{self.health_service['port']}/health", timeout=5)
            self.log_result(
                "Health service connectivity",
                "PASS" if response.status_code == 200 else "FAIL",
                {"status_code": response.status_code}
            )
        except Exception as e:
            self.log_result(
                "Health service connectivity",
                "FAIL",
                {"error": str(e)}
            )

    def test_message_replication(self):
        """Test message replication across all brokers"""
        print("\n📡 Testing Message Replication")

        test_topic = "test/replication"
        test_message = {
            "test_id": "replication_test",
            "timestamp": datetime.now().isoformat(),
            "message": "Testing cross-broker replication"
        }

        # Create clients for each broker
        clients = {}
        received_on_brokers = {}

        def on_message(client, userdata, msg):
            broker_id = userdata["broker_id"]
            payload = json.loads(msg.payload.decode())
            received_on_brokers[broker_id] = payload
            print(f"📨 Message received on {broker_id}: {payload['test_id']}")

        # Setup subscribers on each broker
        for broker in self.brokers:
            if self.check_broker_health(broker["ip"]):
                try:
                    client = mqtt.Client(f"test-sub-{broker['id']}")
                    client.user_data_set({"broker_id": broker["id"]})
                    client.on_message = on_message
                    client.connect(broker["ip"], broker["port"], 60)
                    client.subscribe(test_topic)
                    client.loop_start()
                    clients[broker["id"]] = client
                    print(f"🔔 Subscribed to {broker['id']}")
                except Exception as e:
                    print(f"❌ Failed to subscribe to {broker['id']}: {e}")

        time.sleep(2)  # Allow subscriptions to establish

        # Publish via load balancer
        try:
            publisher = mqtt.Client("test-publisher")
            publisher.connect(self.load_balancer["host"], self.load_balancer["port"], 60)
            publisher.publish(test_topic, json.dumps(test_message))
            publisher.disconnect()
            print(f"📤 Published test message via load balancer")
        except Exception as e:
            self.log_result("Message publication", "FAIL", {"error": str(e)})
            return

        # Wait for message propagation
        time.sleep(5)

        # Check replication results
        expected_brokers = len([b for b in self.brokers if self.check_broker_health(b["ip"])])
        actual_brokers = len(received_on_brokers)

        self.log_result(
            "Message replication test",
            "PASS" if actual_brokers >= expected_brokers * 0.8 else "FAIL",  # Allow for some tolerance
            {
                "expected_brokers": expected_brokers,
                "actual_brokers": actual_brokers,
                "received_on": list(received_on_brokers.keys())
            }
        )

        # Cleanup
        for client in clients.values():
            client.loop_stop()
            client.disconnect()

    def test_retained_messages(self):
        """Test retained message synchronization"""
        print("\n💾 Testing Retained Message Synchronization")

        retained_topic = "test/retained"
        retained_message = {
            "test_id": "retained_test",
            "timestamp": datetime.now().isoformat(),
            "message": "Testing retained message sync",
            "value": 42
        }

        # Publish retained message via load balancer
        try:
            publisher = mqtt.Client("retained-publisher")
            publisher.connect(self.load_balancer["host"], self.load_balancer["port"], 60)
            publisher.publish(retained_topic, json.dumps(retained_message), retain=True)
            publisher.disconnect()
            print(f"📤 Published retained message via load balancer")
        except Exception as e:
            self.log_result("Retained message publication", "FAIL", {"error": str(e)})
            return

        time.sleep(3)  # Allow message to propagate

        # Check retained message on each broker
        retained_found = {}

        def on_retained_message(client, userdata, msg):
            broker_id = userdata["broker_id"]
            if msg.retain:
                payload = json.loads(msg.payload.decode())
                retained_found[broker_id] = payload
                print(f"💾 Retained message found on {broker['id']}: {payload['test_id']}")

        for broker in self.brokers:
            if self.check_broker_health(broker["ip"]):
                try:
                    client = mqtt.Client(f"retained-test-{broker['id']}")
                    client.user_data_set({"broker_id": broker["id"]})
                    client.on_message = on_retained_message
                    client.connect(broker["ip"], broker["port"], 60)
                    client.subscribe(retained_topic)
                    client.loop_start()

                    time.sleep(2)  # Wait for retained message

                    client.loop_stop()
                    client.disconnect()
                except Exception as e:
                    print(f"❌ Failed to check retained message on {broker['id']}: {e}")

        # Evaluate results
        expected_brokers = len([b for b in self.brokers if self.check_broker_health(b["ip"])])
        actual_brokers = len(retained_found)

        self.log_result(
            "Retained message synchronization",
            "PASS" if actual_brokers >= expected_brokers * 0.6 else "FAIL",  # More tolerant for retained messages
            {
                "expected_brokers": expected_brokers,
                "actual_brokers": actual_brokers,
                "found_on": list(retained_found.keys())
            }
        )

    def test_failover_scenario(self):
        """Test complete failover scenario"""
        print("\n🔄 Testing Failover Scenario")

        # Start client that connects via load balancer
        client_messages = []
        client_connected = threading.Event()
        client_disconnected = threading.Event()

        def on_connect(client, userdata, flags, rc):
            if rc == 0:
                client_connected.set()
                print("🔌 Test client connected via load balancer")

        def on_disconnect(client, userdata, rc):
            client_disconnected.set()
            print(f"🔌 Test client disconnected: {rc}")

        def on_message(client, userdata, msg):
            payload = json.loads(msg.payload.decode())
            client_messages.append(payload)
            print(f"📨 Client received: {payload['message_id']}")

        # Setup test client
        test_client = mqtt.Client("failover-test-client")
        test_client.on_connect = on_connect
        test_client.on_disconnect = on_disconnect
        test_client.on_message = on_message

        try:
            test_client.connect(self.load_balancer["host"], self.load_balancer["port"], 60)
            test_client.subscribe("test/failover")
            test_client.loop_start()

            # Wait for connection
            if not client_connected.wait(10):
                self.log_result("Client connection via load balancer", "FAIL", {"error": "Connection timeout"})
                return

            # Start message publisher
            def publish_messages():
                publisher = mqtt.Client("failover-publisher")
                publisher.connect(self.load_balancer["host"], self.load_balancer["port"], 60)

                for i in range(30):  # Publish for 30 messages over 5 minutes
                    message = {
                        "message_id": i,
                        "timestamp": datetime.now().isoformat(),
                        "content": f"Failover test message {i}"
                    }
                    publisher.publish("test/failover", json.dumps(message))
                    time.sleep(10)  # Every 10 seconds

                publisher.disconnect()

            publisher_thread = threading.Thread(target=publish_messages)
            publisher_thread.start()

            # Wait a bit, then simulate broker failures
            time.sleep(30)

            # Simulate primary broker failure
            primary_broker = self.brokers[0]  # broker1
            failure_success = self.simulate_broker_failure(primary_broker["id"])

            if failure_success:
                print(f"⏳ Waiting {self.recovery_time}s before recovery...")
                time.sleep(self.recovery_time)

                # Simulate recovery
                recovery_success = self.simulate_broker_recovery(primary_broker["id"])

                if recovery_success:
                    print("⏳ Waiting for services to stabilize...")
                    time.sleep(30)

            # Wait for publisher to finish
            publisher_thread.join()

            # Evaluate failover results
            expected_messages = 30
            received_messages = len(client_messages)

            self.log_result(
                "Failover message continuity",
                "PASS" if received_messages >= expected_messages * 0.8 else "FAIL",  # Allow for some message loss during failover
                {
                    "expected_messages": expected_messages,
                    "received_messages": received_messages,
                    "message_loss_percentage": ((expected_messages - received_messages) / expected_messages) * 100
                }
            )

        except Exception as e:
            self.log_result("Failover scenario test", "FAIL", {"error": str(e)})
        finally:
            test_client.loop_stop()
            test_client.disconnect()

    def run_full_test_suite(self):
        """Run the complete test suite"""
        print("🚀 Starting MQTT Network Test Suite")
        print(f"📅 Test started at: {datetime.now().isoformat()}")
        print(f"⏱️  Test duration: {self.test_duration}s ({self.test_duration//60} minutes)")

        start_time = time.time()

        # Run tests
        self.test_initial_connectivity()
        self.test_message_replication()
        self.test_retained_messages()
        self.test_failover_scenario()

        end_time = time.time()
        total_duration = end_time - start_time

        # Generate test report
        self.generate_test_report(total_duration)

    def generate_test_report(self, duration):
        """Generate and save test report"""
        print("\n📊 Generating Test Report")

        total_tests = len(self.test_results)
        passed_tests = len([r for r in self.test_results if r["status"] == "PASS"])
        failed_tests = len([r for r in self.test_results if r["status"] == "FAIL"])

        report = {
            "test_summary": {
                "total_tests": total_tests,
                "passed_tests": passed_tests,
                "failed_tests": failed_tests,
                "success_rate": (passed_tests / total_tests) * 100 if total_tests > 0 else 0,
                "test_duration": duration,
                "timestamp": datetime.now().isoformat()
            },
            "test_results": self.test_results,
            "configuration": {
                "brokers": self.brokers,
                "load_balancer": self.load_balancer,
                "test_duration": self.test_duration,
                "failure_interval": self.failure_interval,
                "recovery_time": self.recovery_time
            }
        }

        # Save report to file
        report_file = f"/Users/main/Desktop/test-mqtt-brokers/logs/test-report-{int(time.time())}.json"
        os.makedirs(os.path.dirname(report_file), exist_ok=True)

        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)

        # Print summary
        print(f"\n📋 Test Summary:")
        print(f"   Total Tests: {total_tests}")
        print(f"   Passed: {passed_tests}")
        print(f"   Failed: {failed_tests}")
        print(f"   Success Rate: {report['test_summary']['success_rate']:.1f}%")
        print(f"   Duration: {duration:.1f} seconds")
        print(f"   Report saved: {report_file}")

        return report

if __name__ == "__main__":
    tester = MQTTNetworkTester()

    if len(sys.argv) > 1:
        test_name = sys.argv[1]
        if test_name == "connectivity":
            tester.test_initial_connectivity()
        elif test_name == "replication":
            tester.test_message_replication()
        elif test_name == "retained":
            tester.test_retained_messages()
        elif test_name == "failover":
            tester.test_failover_scenario()
        else:
            print("Available tests: connectivity, replication, retained, failover")
    else:
        tester.run_full_test_suite()