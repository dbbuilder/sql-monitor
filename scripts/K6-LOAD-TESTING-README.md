# K6 Load Testing - SQL Server Monitor API

Comprehensive load testing suite for sql-monitor Phase 1.9 API using [K6](https://k6.io/).

## Prerequisites

### Install K6

**Linux/WSL:**
```bash
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

**macOS:**
```bash
brew install k6
```

**Windows:**
```powershell
choco install k6
```

**Verify Installation:**
```bash
k6 version
```

## Test Suites

### 1. Smoke Test (Quick Sanity Check)

**File:** `k6-smoke-test.js`
**Duration:** ~1 minute
**Users:** 1 concurrent user
**Purpose:** Quick sanity check that all endpoints are working

**Run:**
```bash
cd /mnt/d/dev2/sql-monitor/scripts
k6 run k6-smoke-test.js
```

**With custom settings:**
```bash
k6 run --env BASE_URL=http://localhost:5000 --env SERVER_ID=1 k6-smoke-test.js
```

**When to use:**
- After deploying to a new environment
- Before running expensive load tests
- In CI/CD pipelines for fast feedback
- After making API changes

---

### 2. Load Test (Realistic Traffic Simulation)

**File:** `k6-load-test.js`
**Duration:** ~12 minutes
**Max Users:** 100 concurrent users
**Purpose:** Simulate realistic traffic patterns and measure performance

**Load Profile:**
```
10 users  (30s)  - Warm-up
25 users  (3m)   - Light load
50 users  (4m)   - Normal load
100 users (3m)   - Peak load
0 users   (30s)  - Ramp down
```

**Run:**
```bash
cd /mnt/d/dev2/sql-monitor/scripts
k6 run k6-load-test.js
```

**Output:**
- `load-test-results.json` - Detailed metrics (JSON)
- `load-test-report.html` - Visual HTML report

**Thresholds (must pass):**
- 95% of requests < 500ms
- 99% of requests < 1000ms
- Error rate < 1%
- Specific endpoint targets:
  - GET /api/servers p95 < 200ms
  - GET /api/servers/health p95 < 500ms
  - GET /api/queries/top p95 < 1000ms

**When to use:**
- Performance regression testing
- Before production releases
- After infrastructure changes
- Baseline performance measurement

---

### 3. Stress Test (Find Breaking Point)

**File:** `k6-stress-test.js`
**Duration:** ~13 minutes
**Max Users:** 1000 concurrent users
**Purpose:** Find the breaking point and identify bottlenecks

**Load Profile:**
```
100 users  (2m)
200 users  (2m)
400 users  (2m)
600 users  (2m)
800 users  (2m)
1000 users (2m)  - Breaking point
0 users    (1m)  - Ramp down
```

**Run:**
```bash
cd /mnt/d/dev2/sql-monitor/scripts
k6 run k6-stress-test.js
```

**⚠️ Warning:**
- This test will push your API to its limits
- Monitor CPU, memory, and database connections
- Run in a test environment, NOT production
- May require increasing database connection pool limits

**Expected Behavior:**
- Response times will degrade at high load
- Some requests may fail (< 5% acceptable)
- Identify bottleneck (CPU, memory, database, network)

**When to use:**
- Capacity planning
- Infrastructure sizing
- Bottleneck identification
- Pre-production validation

---

### 4. Soak Test (Endurance Test)

**File:** `k6-soak-test.js`
**Duration:** 4 hours
**Users:** 50 concurrent users (sustained)
**Purpose:** Detect memory leaks, connection leaks, and degradation over time

**Load Profile:**
```
50 users (5m)   - Ramp up
50 users (4h)   - Hold steady
0 users  (2m)   - Ramp down
```

**Run:**
```bash
cd /mnt/d/dev2/sql-monitor/scripts
k6 run k6-soak-test.js
```

**What to Monitor:**
- **API Memory Usage:** Should remain stable (no gradual increase)
- **Database Connections:** Pool size should not grow
- **Response Times:** Should not degrade over time
- **Error Rate:** Should remain consistently low

**Indicators of Problems:**
- Memory increases steadily (memory leak)
- Connection pool grows (connection leak)
- Response times increase over time (resource exhaustion)
- Errors increase over time (resource cleanup issues)

**When to use:**
- Before major releases
- After changes to connection handling
- Stability validation
- Production readiness assessment

---

## Environment Variables

All tests support these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `http://localhost:5000` | API base URL |
| `SERVER_ID` | `1` | Test server ID for specific server endpoints |
| `ENV` | `development` | Environment name (for reporting) |

**Example:**
```bash
k6 run --env BASE_URL=https://api.prod.com --env SERVER_ID=5 k6-load-test.js
```

## Interpreting Results

### Key Metrics

**Request Duration (http_req_duration):**
- **p50**: Median response time (50th percentile)
- **p95**: 95th percentile (95% of requests faster than this)
- **p99**: 99th percentile (99% of requests faster than this)
- **avg**: Average response time
- **max**: Slowest request

**Request Rate (http_reqs):**
- Requests per second throughput

**Failed Requests (http_req_failed):**
- Percentage of failed requests (non-2xx status codes)

**Custom Metrics:**
- `server_response_time`: GET /api/servers response time
- `health_response_time`: GET /api/servers/health response time
- `queries_response_time`: GET /api/queries/top response time
- `errors`: Total error rate

### Success Criteria

✅ **Passed:**
```
✓ http_req_duration..............: avg=150ms p95=350ms p99=800ms
✓ http_req_failed................: 0.12%
✓ server_response_time...........: avg=80ms p95=150ms
✓ health_response_time...........: avg=200ms p95=450ms
✓ queries_response_time..........: avg=500ms p95=950ms
```

❌ **Failed:**
```
✗ http_req_duration..............: avg=850ms p95=1500ms p99=3000ms
✗ http_req_failed................: 2.5%
✗ server_response_time...........: avg=400ms p95=800ms
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Load Tests

on:
  push:
    branches: [main]
  pull_request:

jobs:
  load-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install K6
        run: |
          sudo gpg -k
          sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install k6

      - name: Run Smoke Test
        run: |
          cd scripts
          k6 run --env BASE_URL=${{ secrets.API_URL }} k6-smoke-test.js

      - name: Run Load Test
        run: |
          cd scripts
          k6 run --env BASE_URL=${{ secrets.API_URL }} k6-load-test.js

      - name: Upload Results
        uses: actions/upload-artifact@v3
        with:
          name: load-test-results
          path: |
            scripts/load-test-results.json
            scripts/load-test-report.html
```

### Azure Pipelines Example

```yaml
trigger:
  - main

pool:
  vmImage: ubuntu-latest

steps:
  - script: |
      sudo apt-get update
      sudo apt-get install -y k6
    displayName: 'Install K6'

  - script: |
      cd scripts
      k6 run --env BASE_URL=$(API_URL) k6-smoke-test.js
    displayName: 'Run Smoke Test'

  - script: |
      cd scripts
      k6 run --env BASE_URL=$(API_URL) k6-load-test.js
    displayName: 'Run Load Test'

  - task: PublishBuildArtifacts@1
    inputs:
      pathToPublish: 'scripts/load-test-results.json'
      artifactName: 'load-test-results'
```

## Troubleshooting

### Connection Refused

**Error:** `ERRO[0000] GoError: Get "http://localhost:5000/health": dial tcp connect: connection refused`

**Solution:** Ensure API is running:
```bash
cd /mnt/d/dev2/sql-monitor/api
dotnet run
```

### High Error Rate

**Error:** `✗ http_req_failed: rate>0.01 (5.2%)`

**Possible Causes:**
1. Database connection pool exhausted
2. API not handling load
3. Network issues
4. Database server overloaded

**Debug:**
1. Check API logs
2. Monitor database connections
3. Check server CPU/memory
4. Run with fewer users to isolate issue

### Slow Response Times

**Error:** `✗ http_req_duration: p(95)>500 (850ms)`

**Possible Causes:**
1. Slow database queries
2. Missing indexes
3. No query plan caching
4. Network latency
5. API overhead

**Debug:**
1. Enable SQL Server Extended Events
2. Check query execution plans
3. Review missing indexes
4. Verify partition elimination
5. Check API response compression

### Memory Issues

**Error:** Out of memory during test

**Solution:**
1. Increase Docker container memory limits
2. Optimize connection pooling
3. Enable response compression
4. Review service lifetimes (Scoped vs Singleton)

## Best Practices

1. **Run Smoke Test First:** Always run smoke test before expensive load tests
2. **Monitor Resources:** Watch CPU, memory, and database connections during tests
3. **Use Test Environment:** Never run stress/soak tests against production
4. **Baseline Before Changes:** Establish baseline performance before making changes
5. **Run Regularly:** Include load tests in CI/CD for regression detection
6. **Analyze Failures:** Investigate threshold failures immediately
7. **Document Results:** Keep historical results for trend analysis

## Results Comparison

Track performance over time:

| Date | Test | p95 | p99 | Error Rate | Notes |
|------|------|-----|-----|------------|-------|
| 2025-10-28 | Load | TBD | TBD | TBD | Initial baseline |
| | Stress | TBD | TBD | TBD | |
| | Soak | TBD | TBD | TBD | |

## Next Steps

1. Run all test suites and record baseline results
2. Document actual performance vs targets
3. Identify bottlenecks (if any)
4. Optimize based on findings
5. Re-test to verify improvements
6. Establish continuous monitoring in production

## References

- K6 Documentation: https://k6.io/docs/
- K6 Test Types: https://k6.io/docs/test-types/
- K6 Metrics: https://k6.io/docs/using-k6/metrics/
- K6 Thresholds: https://k6.io/docs/using-k6/thresholds/
