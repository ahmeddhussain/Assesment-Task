const assert = require('assert');
const http = require('http');
const server = require('./server');

const get = (port, path) =>
  new Promise((resolve, reject) => {
    http
      .get(`http://localhost:${port}${path}`, (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(data) }));
      })
      .on('error', reject);
  });

server.listen(0, async () => {
  const port = server.address().port;
  try {
    // Test 1: Metrics endpoint (no DB needed)
    const metrics = await get(port, '/metrics');
    assert.strictEqual(metrics.status, 200, 'Metrics should return 200 OK');
    assert.ok(metrics.body.uptime_seconds > 0, 'Uptime should be exposed');
    assert.ok(metrics.body.memory_rss_bytes > 0, 'Memory should be exposed');

    // Test 2: Unknown route returns 404
    const missing = await get(port, '/does-not-exist');
    assert.strictEqual(missing.status, 404, 'Unknown route should return 404');

    // Test 3: Health check reports DOWN (503) without a DB and never leaks error details
    const health = await get(port, '/health');
    assert.strictEqual(health.status, 503, 'Health should be 503 when DB is unreachable');
    assert.strictEqual(health.body.status, 'DOWN');
    assert.strictEqual(health.body.error, undefined, 'Health must not leak error details');

    console.log('✅ Unit Tests Passed (metrics, 404 handling, safe health failure)');
    server.close();
    process.exit(0);
  } catch (err) {
    console.error('❌ Test failed:', err.message);
    process.exit(1);
  }
});
