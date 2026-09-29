const assert = require('assert');
const http = require('http');
const server = require('./server');

server.listen(0, () => {
  const port = server.address().port;
  
  // Test 1: Metrics Endpoint (Doesn't rely on DB)
  http.get(`http://localhost:${port}/metrics`, (res) => {
    assert.strictEqual(res.statusCode, 200, 'Metrics should return 200 OK');
    
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
      const metrics = JSON.parse(data);
      assert.ok(metrics.uptime_seconds > 0, 'Uptime should be exposed');
      assert.ok(metrics.memory_rss_bytes > 0, 'Memory should be exposed');
      
      console.log('✅ Unit Tests Passed (App & Metrics are healthy)');
      
      // Close server and exit successfully
      server.close();
      process.exit(0);
    });
  }).on('error', (err) => {
    console.error('❌ Test failed:', err.message);
    process.exit(1);
  });
});