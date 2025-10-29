import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// ============================================================================
// SQL Server Monitor API - Soak Test (Endurance Test)
// Run at moderate load for extended period to detect:
// - Memory leaks
// - Connection pool exhaustion
// - Resource leaks
// - Performance degradation over time
// Duration: 4 hours
// ============================================================================

const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');
const requestCounter = new Counter('total_requests');

export const options = {
  // Sustained load for 4 hours
  stages: [
    { duration: '5m', target: 50 },    // Ramp up to 50 users
    { duration: '4h', target: 50 },    // Hold at 50 users for 4 hours
    { duration: '2m', target: 0 },     // Ramp down
  ],

  thresholds: {
    // Response times should remain stable
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.01'],
    'errors': ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:5000';
const SERVER_ID = __ENV.SERVER_ID || '1';

export default function () {
  // Realistic user behavior: mix of read operations
  const scenario = Math.random();

  if (scenario < 0.3) {
    // Scenario 1: Check server health (30%)
    const res = http.get(`${BASE_URL}/api/servers/health`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time stable': (r) => r.timings.duration < 500,
    });

    errorRate.add(!passed);
    responseTime.add(res.timings.duration);
    sleep(3);

  } else if (scenario < 0.6) {
    // Scenario 2: View server list (30%)
    const res = http.get(`${BASE_URL}/api/servers`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time stable': (r) => r.timings.duration < 200,
    });

    errorRate.add(!passed);
    responseTime.add(res.timings.duration);
    sleep(5);

  } else if (scenario < 0.8) {
    // Scenario 3: View server details (20%)
    let res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}`);
    requestCounter.add(1);
    check(res, { 'server details OK': (r) => r.status === 200 });

    res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}/trends`);
    requestCounter.add(1);
    check(res, { 'trends OK': (r) => r.status === 200 });

    res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}/databases`);
    requestCounter.add(1);
    check(res, { 'databases OK': (r) => r.status === 200 });

    sleep(10);

  } else {
    // Scenario 4: Analyze query performance (20%)
    const res = http.get(`${BASE_URL}/api/queries/top?topN=50`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time stable': (r) => r.timings.duration < 1000,
    });

    errorRate.add(!passed);
    responseTime.add(res.timings.duration);
    sleep(15);
  }
}

export function setup() {
  console.log('⏱️  Starting SOAK TEST (Endurance Test)');
  console.log('   Duration: 4 hours');
  console.log('   Concurrent users: 50');
  console.log('   Purpose: Detect memory leaks, connection leaks, degradation');
  console.log('');
  console.log('   Monitor these metrics throughout the test:');
  console.log('   - API memory usage (should remain stable)');
  console.log('   - Database connection pool (should not grow)');
  console.log('   - Response times (should not degrade)');
  console.log('   - Error rate (should remain low)');

  return { startTime: new Date() };
}

export function teardown(data) {
  const endTime = new Date();
  const durationMs = endTime - data.startTime;
  const durationHours = (durationMs / (1000 * 60 * 60)).toFixed(2);

  console.log('✅ Soak test completed');
  console.log(`   Duration: ${durationHours} hours`);

  // Calculate key metrics
  const httpReqDuration = data.metrics.http_req_duration;
  const httpReqFailed = data.metrics.http_req_failed;

  console.log('\n📊 Final Results:');
  console.log(`   Total requests: ${data.metrics.total_requests.values.count}`);
  console.log(`   p95 response time: ${httpReqDuration.values['p(95)'].toFixed(2)}ms`);
  console.log(`   p99 response time: ${httpReqDuration.values['p(99)'].toFixed(2)}ms`);
  console.log(`   Error rate: ${(httpReqFailed.values.rate * 100).toFixed(2)}%`);

  console.log('\n🔍 Check for:');
  console.log('   - Memory leaks: Compare start vs end API memory usage');
  console.log('   - Connection leaks: Check database connection pool');
  console.log('   - Degradation: Compare early vs late response times');
}

export function handleSummary(data) {
  return {
    'soak-test-results.json': JSON.stringify(data, null, 2),
  };
}
