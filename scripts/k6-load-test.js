import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// ============================================================================
// SQL Server Monitor API - Load Test
// Phase 1.9: Multi-Server Support
// ============================================================================

// Custom metrics
const errorRate = new Rate('errors');
const serverResponseTime = new Trend('server_response_time');
const healthResponseTime = new Trend('health_response_time');
const queriesResponseTime = new Trend('queries_response_time');
const trendsResponseTime = new Trend('trends_response_time');
const databasesResponseTime = new Trend('databases_response_time');
const serverByIdResponseTime = new Trend('server_by_id_response_time');
const requestCounter = new Counter('total_requests');

// Test configuration
export const options = {
  // Load profile: Ramp up to simulate realistic traffic
  stages: [
    { duration: '30s', target: 10 },   // Warm-up: 10 users
    { duration: '1m', target: 25 },    // Ramp to 25 users (light load)
    { duration: '2m', target: 25 },    // Sustain 25 users
    { duration: '1m', target: 50 },    // Ramp to 50 users (normal load)
    { duration: '3m', target: 50 },    // Sustain 50 users
    { duration: '1m', target: 100 },   // Spike to 100 users (peak load)
    { duration: '2m', target: 100 },   // Sustain 100 users
    { duration: '30s', target: 0 },    // Ramp down
  ],

  // Performance thresholds (test will fail if these are not met)
  thresholds: {
    // HTTP metrics
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],  // 95% < 500ms, 99% < 1s
    'http_req_failed': ['rate<0.01'],                  // Error rate < 1%

    // Custom metrics
    'errors': ['rate<0.01'],                           // Error rate < 1%
    'server_response_time': ['p(95)<200'],             // GET /api/servers p95 < 200ms
    'health_response_time': ['p(95)<500'],             // GET /api/servers/health p95 < 500ms
    'queries_response_time': ['p(95)<1000'],           // GET /api/queries/top p95 < 1s
    'trends_response_time': ['p(95)<500'],             // GET /api/servers/{id}/trends p95 < 500ms
    'databases_response_time': ['p(95)<500'],          // GET /api/servers/{id}/databases p95 < 500ms
    'server_by_id_response_time': ['p(95)<100'],       // GET /api/servers/{id} p95 < 100ms
  },

  // Test metadata
  tags: {
    test_name: 'sql-monitor-api-load-test',
    environment: __ENV.ENV || 'development',
  },
};

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:5000';
const SERVER_ID = __ENV.SERVER_ID || '1';

// ============================================================================
// Main test function (executed by each virtual user)
// ============================================================================

export default function () {
  // Test 1: Get all servers
  group('GET /api/servers', () => {
    const res = http.get(`${BASE_URL}/api/servers`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 200ms': (r) => r.timings.duration < 200,
      'has servers array': (r) => {
        try {
          const body = JSON.parse(r.body);
          return Array.isArray(body) && body.length >= 0;
        } catch (e) {
          return false;
        }
      },
    });

    errorRate.add(!passed);
    serverResponseTime.add(res.timings.duration);
  });
  sleep(1);

  // Test 2: Get server by ID
  group('GET /api/servers/{id}', () => {
    const res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 100ms': (r) => r.timings.duration < 100,
      'has server object': (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.serverID && body.serverName;
        } catch (e) {
          return false;
        }
      },
    });

    errorRate.add(!passed);
    serverByIdResponseTime.add(res.timings.duration);
  });
  sleep(0.5);

  // Test 3: Get server health status (all servers)
  group('GET /api/servers/health', () => {
    const res = http.get(`${BASE_URL}/api/servers/health`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 500ms': (r) => r.timings.duration < 500,
      'has health data': (r) => {
        try {
          const body = JSON.parse(r.body);
          return Array.isArray(body) && (body.length === 0 || body[0].healthStatus);
        } catch (e) {
          return false;
        }
      },
    });

    errorRate.add(!passed);
    healthResponseTime.add(res.timings.duration);
  });
  sleep(1);

  // Test 4: Get server health by ID
  group('GET /api/servers/{id}/health', () => {
    const res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}/health`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200 or 404': (r) => r.status === 200 || r.status === 404,
      'response time < 200ms': (r) => r.timings.duration < 200,
    });

    errorRate.add(!passed);
    healthResponseTime.add(res.timings.duration);
  });
  sleep(1);

  // Test 5: Get resource trends
  group('GET /api/servers/{id}/trends', () => {
    const res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}/trends?days=7`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 500ms': (r) => r.timings.duration < 500,
      'has trends array': (r) => {
        try {
          const body = JSON.parse(r.body);
          return Array.isArray(body);
        } catch (e) {
          return false;
        }
      },
    });

    errorRate.add(!passed);
    trendsResponseTime.add(res.timings.duration);
  });
  sleep(1);

  // Test 6: Get database summaries
  group('GET /api/servers/{id}/databases', () => {
    const res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}/databases`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 500ms': (r) => r.timings.duration < 500,
      'has databases array': (r) => {
        try {
          const body = JSON.parse(r.body);
          return Array.isArray(body);
        } catch (e) {
          return false;
        }
      },
    });

    errorRate.add(!passed);
    databasesResponseTime.add(res.timings.duration);
  });
  sleep(1);

  // Test 7: Get top queries (most expensive operation)
  group('GET /api/queries/top', () => {
    const res = http.get(`${BASE_URL}/api/queries/top?topN=50&orderBy=TotalCpu`);
    requestCounter.add(1);

    const passed = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 1000ms': (r) => r.timings.duration < 1000,
      'has queries array': (r) => {
        try {
          const body = JSON.parse(r.body);
          return Array.isArray(body);
        } catch (e) {
          return false;
        }
      },
      'respects topN limit': (r) => {
        try {
          const body = JSON.parse(r.body);
          return Array.isArray(body) && body.length <= 50;
        } catch (e) {
          return false;
        }
      },
    });

    errorRate.add(!passed);
    queriesResponseTime.add(res.timings.duration);
  });
  sleep(2);

  // Test 8: Get servers filtered by environment (randomly)
  if (Math.random() < 0.3) {  // 30% of users
    group('GET /api/servers?environment=Production', () => {
      const res = http.get(`${BASE_URL}/api/servers?environment=Production`);
      requestCounter.add(1);

      const passed = check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 200ms': (r) => r.timings.duration < 200,
      });

      errorRate.add(!passed);
      serverResponseTime.add(res.timings.duration);
    });
    sleep(1);
  }
}

// ============================================================================
// Setup function (runs once before test starts)
// ============================================================================

export function setup() {
  console.log('🚀 Starting SQL Server Monitor API Load Test');
  console.log(`   Base URL: ${BASE_URL}`);
  console.log(`   Server ID: ${SERVER_ID}`);
  console.log('   Test duration: ~12 minutes');
  console.log('   Max concurrent users: 100');

  // Verify API is accessible
  const healthCheck = http.get(`${BASE_URL}/health`);
  if (healthCheck.status !== 200) {
    console.error('❌ API health check failed. Is the API running?');
    throw new Error('API is not accessible');
  }
  console.log('✅ API health check passed');

  return { startTime: new Date().toISOString() };
}

// ============================================================================
// Teardown function (runs once after test completes)
// ============================================================================

export function teardown(data) {
  console.log('✅ Load test completed');
  console.log(`   Started: ${data.startTime}`);
  console.log(`   Ended: ${new Date().toISOString()}`);
}

// ============================================================================
// Summary report handler
// ============================================================================

export function handleSummary(data) {
  // Generate text summary for console
  const summary = textSummary(data, { indent: '  ', enableColors: true });

  // Generate HTML report
  const htmlOutput = htmlReport(data);

  // Save reports to files
  return {
    'stdout': summary,
    'load-test-results.json': JSON.stringify(data, null, 2),
    'load-test-report.html': htmlOutput,
  };
}
