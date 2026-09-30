const http = require('http');
const mysql = require('mysql2/promise');

const PORT = process.env.PORT || 3000;

// Database Connection Pool (env vars are injected by ECS from Secrets Manager)
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASS || '',
  database: process.env.DB_NAME || 'test',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  connectTimeout: 5000 // fail fast so health checks never hang
});

const sendJson = (res, status, body) => {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
};

const server = http.createServer(async (req, res) => {
  // CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  // 1. Health Check (ALB health checks AND frontend /api/health calls)
  if ((req.url === '/health' || req.url === '/api/health') && req.method === 'GET') {
    try {
      await pool.query('SELECT 1');
      return sendJson(res, 200, { status: 'UP', database: 'CONNECTED' });
    } catch (error) {
      // Full error goes to CloudWatch Logs only - never to the public response
      console.error('Health check failed:', error.code || error.message);
      return sendJson(res, 503, { status: 'DOWN', database: 'DISCONNECTED' });
    }
  }

  // 2. Metrics Endpoint (not routed by the ALB - internal use only)
  if (req.url === '/metrics' && req.method === 'GET') {
    const memory = process.memoryUsage();
    return sendJson(res, 200, {
      uptime_seconds: process.uptime(),
      memory_rss_bytes: memory.rss,
      memory_heap_used_bytes: memory.heapUsed
    });
  }

  return sendJson(res, 404, { error: 'Route not found' });
});

// Graceful shutdown so ECS can drain tasks cleanly on deploy / scale-in
const gracefulShutdown = (signal) => {
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
