/**
 * MQTT Broker Cluster Monitoring Dashboard Server
 *
 * Real-time web dashboard for monitoring MQTT broker cluster health,
 * client connections, and system performance metrics. Provides live
 * WebSocket-based updates and RESTful API endpoints for cluster visibility.
 *
 * Key Features:
 * - Real-time broker health monitoring with WebSocket updates
 * - Client connection tracking and session management visibility
 * - TCP connectivity validation and network health checks
 * - Historical data collection and trend analysis
 * - Responsive web interface with automatic refresh capabilities
 * - CORS-enabled API for external integration and monitoring tools
 *
 * Architecture:
 * - Express.js HTTP server with Socket.io WebSocket integration
 * - Periodic health service polling with configurable intervals
 * - In-memory data caching for performance optimization
 * - Static file serving for dashboard HTML/CSS/JS assets
 * - Error handling and graceful degradation for service unavailability
 *
 * Dependencies: express, socket.io, axios, cors
 * Integration: Python health monitoring service (port 5000)
 */

const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const axios = require('axios');
const cors = require('cors');
const path = require('path');

// Express application and HTTP server setup
const app = express();
const server = http.createServer(app);

// WebSocket server configuration for real-time dashboard updates
// CORS configuration allows cross-origin requests for development environments
const io = socketIo(server, {
  cors: {
    origin: "*",              // Allow all origins (restrict in production)
    methods: ["GET", "POST"]  // Supported HTTP methods for CORS
  }
});

// Middleware configuration for HTTP request processing
app.use(cors());                                      // Enable CORS for API endpoints
app.use(express.json());                              // Parse JSON request bodies
app.use(express.static(path.join(__dirname, 'public'))); // Serve static dashboard assets

// Service integration configuration
const HEALTH_SERVICE_URL = 'http://localhost:5000';   // Python health monitoring service
const UPDATE_INTERVAL = 2000; // 2 second refresh rate for real-time updates

// In-memory data store for dashboard state management
// Caches latest cluster data to reduce API calls and improve response times
let dashboardData = {
  brokers: {},        // Broker health status and connection information
  clients: {},        // Active client connections and session data
  systemHealth: {},   // Overall system health metrics and status
  lastUpdate: null    // Timestamp of last successful data refresh
};

// Fetch data from health service
async function fetchHealthData() {
  try {
    const [brokersResponse, clientsResponse, healthResponse, tcpResponse] = await Promise.all([
      axios.get(`${HEALTH_SERVICE_URL}/brokers`),
      axios.get(`${HEALTH_SERVICE_URL}/clients`),
      axios.get(`${HEALTH_SERVICE_URL}/health`),
      axios.get(`${HEALTH_SERVICE_URL}/tcp-check`)
    ]);

    dashboardData = {
      brokers: brokersResponse.data,
      clients: clientsResponse.data,
      systemHealth: healthResponse.data,
      tcpHealth: tcpResponse.data,
      lastUpdate: new Date().toISOString()
    };

    // Emit to all connected clients
    io.emit('dashboard-update', dashboardData);

  } catch (error) {
    console.error('Error fetching health data:', error.message);

    // Emit error state
    io.emit('dashboard-error', {
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
}

// Routes
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/api/status', (req, res) => {
  res.json(dashboardData);
});

app.get('/api/brokers', (req, res) => {
  res.json(dashboardData.brokers);
});

app.get('/api/clients', (req, res) => {
  res.json(dashboardData.clients);
});

// Socket.IO connections
io.on('connection', (socket) => {
  console.log('Client connected to dashboard');

  // Send current data to new client
  socket.emit('dashboard-update', dashboardData);

  socket.on('disconnect', () => {
    console.log('Client disconnected from dashboard');
  });

  // Handle client requests for specific data
  socket.on('request-update', () => {
    socket.emit('dashboard-update', dashboardData);
  });
});

// Start periodic data fetching
setInterval(fetchHealthData, UPDATE_INTERVAL);

// Initial data fetch
fetchHealthData();

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Dashboard server running on port ${PORT}`);
  console.log(`Dashboard URL: http://localhost:${PORT}`);
});