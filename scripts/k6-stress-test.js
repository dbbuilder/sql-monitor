import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// ============================================================================
// SQL Server Monitor API - Stress Test
// Find the breaking point of the API
// Ramps up to very high load to identify bottlenecks
// ============================================================================

const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');

export const options = {
  // Aggressive ramp-up to find breaking point
  stages: [
    { duration: '2m', target: 100 },   // Ramp to 100 users
    { duration: '2m', target: 200 },   // Ramp to 200 users
    { duration: '2m', target: 400 },   // Ramp to 400 users
    { duration: '2m', target: 600 },   // Ramp to 600 users (stress)
    { duration: '2m', target: 800 },   // Ramp to 800 users (extreme stress)
    { duration: '2m', target: 1000 },  // Ramp to 1000 users (breaking point)
    { duration: '1m', target: 0 },     // Ramp down
  ],

  thresholds: {
    // More lenient thresholds (we expect degradation)
    'http_req_duration': ['p(95)<2000', 'p(99)<5000'],  // 95% < 2s, 99% < 5s
    'http_req_failed': ['rate<0.05'],                    // Error rate < 5%
    'errors': ['rate<0.05'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:5000';
const SERVER_ID = __ENV.SERVER_ID || '1';

export default function () {
  // Focus on most common endpoints
  const endpoints = [
    { url: `${BASE_URL}/api/servers`, name: 'servers' },
    { url: `${BASE_URL}/api/servers/health`, name: 'health' },
    { url: `${BASE_URL}/api/servers/${SERVER_ID}`, name: 'server_by_id' },
  ];

  // Randomly select endpoint (weighted)
  const random = Math.random();
  let endpoint;
  if (random < 0.5) {
    endpoint = endpoints[0];  // 50% servers list
  } else if (random < 0.8) {
    endpoint = endpoints[1];  // 30% health
  } else {
    endpoint = endpoints[2];  // 20% server by ID
  }

  const res = http.get(endpoint.url);
  const passed = check(res, {
    'status is 200': (r) => r.status === 200,
  });

  errorRate.add(!passed);
  responseTime.add(res.timings.duration);

  // Minimal sleep to maximize load
  sleep(0.1);
}

export function setup() {
  console.log('🔥 Starting STRESS TEST');
  console.log('   WARNING: This will push the API to its limits');
  console.log('   Max target: 1000 concurrent users');
  console.log('   Monitor CPU, memory, and database connections');
}

export function teardown(data) {
  console.log('✅ Stress test completed');

  // Calculate key metrics
  const httpReqDuration = data.metrics.http_req_duration;
  const httpReqFailed = data.metrics.http_req_failed;

  console.log('\n📊 Key Results:');
  console.log(`   p95 response time: ${httpReqDuration.values['p(95)'].toFixed(2)}ms`);
  console.log(`   p99 response time: ${httpReqDuration.values['p(99)'].toFixed(2)}ms`);
  console.log(`   Error rate: ${(httpReqFailed.values.rate * 100).toFixed(2)}%`);
  console.log(`   Total requests: ${httpReqFailed.values.passes + httpReqFailed.values.fails}`);
}

export function handleSummary(data) {
  return {
    'stress-test-results.json': JSON.stringify(data, null, 2),
  };
}
