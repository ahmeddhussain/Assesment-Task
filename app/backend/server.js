const http = require('http');
const mysql = require('mysql2/promise');

const PORT = process.env.PORT || 3000;

// Database Connection Pool (Uses ENV vars that Terraform will inject in ECS)
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASS || '',
  database: process.env.DB_NAME || 'test',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

const server = http.createServer(async (req, res) => {
  // CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

// 1. Health Check (Handles internal ALB health checks AND frontend /api/health calls)
  if ((req.url === '/health' || req.url === '/api/health') && req.method === 'GET') {    try {
      await pool.query('SELECT 1');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ status: 'UP', database: 'CONNECTED' }));
    } catch (error) {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ status: 'DOWN', database: 'DISCONNECTED', error: error.message }));
    }
  }

  // 2. Metrics Endpoint (For CloudWatch/Prometheus integration)
  if (req.url === '/metrics' && req.method === 'GET') {
    const memory = process.memoryUsage();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({
      uptime_seconds: process.uptime(),
      memory_rss_bytes: memory.rss,
      memory_heap_used_bytes: memory.heapUsed
    }));
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Route not found' }));
});

// Best Practice: Graceful Shutdown for ECS Container Scaling
const gracefulShutdown = async (signal) => {
  console.log(`Received ${signal}. Closing HTTP server and DB connections...`);
  server.close(async () => {
    console.log('HTTP server closed.');
    await pool.end();
    console.log('Database connections closed.');
    process.exit(0);
  });
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`Backend API listening on port ${PORT}`);
  });
}

module.exports = server;