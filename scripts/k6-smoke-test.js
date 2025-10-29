import http from 'k6/http';
import { check, sleep } from 'k6';

// ============================================================================
// SQL Server Monitor API - Smoke Test
// Quick sanity check that all endpoints are working
// Duration: ~1 minute
// ============================================================================

export const options = {
  vus: 1,  // Single user
  duration: '1m',
  thresholds: {
    'http_req_failed': ['rate<0.01'],  // Less than 1% errors
    'http_req_duration': ['p(95)<1000'],  // 95% < 1s
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:5000';
const SERVER_ID = __ENV.SERVER_ID || '1';

export default function () {
  // Health check
  let res = http.get(`${BASE_URL}/health`);
  check(res, { 'health check OK': (r) => r.status === 200 });

  // Get all servers
  res = http.get(`${BASE_URL}/api/servers`);
  check(res, { 'get servers OK': (r) => r.status === 200 });

  // Get server by ID
  res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}`);
  check(res, { 'get server by ID OK': (r) => r.status === 200 || r.status === 404 });

  // Get server health
  res = http.get(`${BASE_URL}/api/servers/health`);
  check(res, { 'get server health OK': (r) => r.status === 200 });

  // Get server trends
  res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}/trends`);
  check(res, { 'get trends OK': (r) => r.status === 200 });

  // Get server databases
  res = http.get(`${BASE_URL}/api/servers/${SERVER_ID}/databases`);
  check(res, { 'get databases OK': (r) => r.status === 200 });

  // Get top queries
  res = http.get(`${BASE_URL}/api/queries/top?topN=10`);
  check(res, { 'get top queries OK': (r) => r.status === 200 });

  sleep(1);
}

export function handleSummary(data) {
  return {
    'stdout': JSON.stringify(data, null, 2),
    'smoke-test-results.json': JSON.stringify(data, null, 2),
  };
}
