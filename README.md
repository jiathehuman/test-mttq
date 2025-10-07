# Topology for MTQQ

```
Client → Nginx LB → Primary Broker (192.168.100.10)
              ↓
         Backup Brokers:
         - Broker 2 (192.168.100.11)
         - Broker 3 (192.168.100.12)
         - Broker 4 (192.168.100.13)
         - Broker 5 (192.168.100.14)

All brokers are interconnected via bridges for full message replication.
```

1. **Setup Environment**:
   ```bash
   ./scripts/setup-environment.sh
   ```

2. **Deploy Brokers**:
   ```bash
   ./scripts/deploy-brokers.sh
   ```

3. **Start Services**:
   ```bash
   ./scripts/start-services.sh
   ```

4. **Run Tests**:
   ```bash
   ./scripts/run-tests.sh
   ```

5. **View Dashboard**:
    http://localhost:3000

# Directories
- `multipass/` - VM configurations and cloud-init files
- `nginx/` - Load balancer configuration with health checks
- `mosquitto-configs/` - Broker configurations and bridge settings
- `services/` - Health check service and monitoring
- `client-examples/` - Python MQTT clients with failover logic
- `dashboard/` - Web dashboard for monitoring
- `testing/` - Automated test scripts
- `logs/` - Centralized JSON logs

## Testing Scenarios
- Message replication across all brokers
- Retained message synchronization
- Broker failure simulation (every 60s)
- Client failover verification
- Network recovery testing
- Session state persistence

## Additional code
```bash
for broker in broker1 broker2 broker3 broker4 broker5; do
  ip=$(multipass info $broker --format json | jq -r ".info.$broker.ipv4[0]")
  echo "$broker: $ip"
done
```