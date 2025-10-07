const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const axios = require('axios');
const cors = require('cors');
const path = require('path');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Configuration
const HEALTH_SERVICE_URL = 'http://localhost:5000';
const UPDATE_INTERVAL = 2000; // 2 seconds

// Store for dashboard data
let dashboardData = {
  brokers: {},
  clients: {},
  systemHealth: {},
  lastUpdate: null
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