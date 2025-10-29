# Phase 1.9: Performance Testing Guide

**Date**: 2025-10-28
**Status**: Documentation Complete
**Phase**: Days 6-7 - API Integration & Testing

## Overview

This document provides comprehensive performance testing guidelines for the sql-monitor API (Phase 1.9). Performance testing ensures the API meets production requirements for response time, throughput, and scalability.

## Performance Requirements

### Response Time Targets

| Endpoint | p50 | p95 | p99 | Max |
|----------|-----|-----|-----|-----|
| GET /api/servers | 50ms | 100ms | 200ms | 500ms |
| GET /api/servers/{id} | 20ms | 50ms | 100ms | 200ms |
| GET /api/servers/health | 100ms | 200ms | 500ms | 1000ms |
| GET /api/servers/{id}/health | 50ms | 100ms | 200ms | 500ms |
| GET /api/servers/{id}/trends | 100ms | 250ms | 500ms | 1000ms |
| GET /api/servers/{id}/databases | 100ms | 250ms | 500ms | 1000ms |
| GET /api/queries/top | 200ms | 500ms | 1000ms | 2000ms |
| POST /api/servers | 100ms | 200ms | 500ms | 1000ms |
| PUT /api/servers/{id} | 50ms | 100ms | 200ms | 500ms |

### Throughput Targets

- **Light Load**: 10-50 requests/second across all endpoints
- **Normal Load**: 50-200 requests/second
- **Peak Load**: 200-500 requests/second
- **Stress Test**: 1000+ requests/second

### Resource Limits

- **API Container**: ≤ 512MB RAM, ≤ 0.5 CPU cores
- **Database**: ≤ 100 concurrent connections
- **Network**: ≤ 1MB/s average throughput

## Testing Tools

### 1. BenchmarkDotNet (Microbenchmarks)

**Purpose**: Measure individual method performance in isolation

**Installation**:
```bash
cd api.tests
dotnet add package BenchmarkDotNet
```

**Example Benchmark**:
```csharp
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Running;

[MemoryDiagnoser]
[SimpleJob(warmupCount: 3, iterationCount: 10)]
public class ServerServiceBenchmarks
{
    private ServerService _service = null!;

    [GlobalSetup]
    public void Setup()
    {
        // Initialize service with test configuration
        var config = new ConfigurationBuilder()
            .AddJsonFile("appsettings.Test.json")
            .Build();
        var logger = LoggerFactory.Create(b => b.AddConsole()).CreateLogger<ServerService>();
        _service = new ServerService(config, logger);
    }

    [Benchmark]
    public async Task GetServers_10Servers()
    {
        await _service.GetServersAsync();
    }

    [Benchmark]
    public async Task GetServerById_SingleServer()
    {
        await _service.GetServerByIdAsync(1);
    }

    [Benchmark]
    public async Task GetServerHealthStatus_AllServers()
    {
        await _service.GetServerHealthStatusAsync();
    }
}

// Run with: dotnet run -c Release --project api.tests
```

### 2. K6 (Load Testing)

**Purpose**: Simulate realistic load patterns and measure API performance

**Installation**:
```bash
# Install k6 (Linux/WSL)
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

**Load Test Script** (`scripts/k6-load-test.js`):
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const serverResponseTime = new Trend('server_response_time');
const healthResponseTime = new Trend('health_response_time');

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up to 10 users
    { duration: '1m', target: 50 },    // Ramp up to 50 users
    { duration: '2m', target: 50 },    // Stay at 50 users
    { duration: '1m', target: 100 },   // Spike to 100 users
    { duration: '2m', target: 100 },   // Stay at 100 users
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'], // 95% < 500ms, 99% < 1s
    errors: ['rate<0.01'],                          // Error rate < 1%
  },
};

const BASE_URL = 'http://localhost:5000';

export default function () {
  // Test 1: Get all servers
  let res = http.get(`${BASE_URL}/api/servers`);
  check(res, {
    'servers status 200': (r) => r.status === 200,
    'servers response time < 200ms': (r) => r.timings.duration < 200,
  });
  errorRate.add(res.status !== 200);
  serverResponseTime.add(res.timings.duration);
  sleep(1);

  // Test 2: Get server health
  res = http.get(`${BASE_URL}/api/servers/health`);
  check(res, {
    'health status 200': (r) => r.status === 200,
    'health response time < 500ms': (r) => r.timings.duration < 500,
  });
  errorRate.add(res.status !== 200);
  healthResponseTime.add(res.timings.duration);
  sleep(1);

  // Test 3: Get top queries
  res = http.get(`${BASE_URL}/api/queries/top?topN=50`);
  check(res, {
    'queries status 200': (r) => r.status === 200,
    'queries response time < 1000ms': (r) => r.timings.duration < 1000,
  });
  errorRate.add(res.status !== 200);
  sleep(2);

  // Test 4: Get server by ID
  res = http.get(`${BASE_URL}/api/servers/1`);
  check(res, {
    'server by id status 200': (r) => r.status === 200,
    'server by id response time < 100ms': (r) => r.timings.duration < 100,
  });
  errorRate.add(res.status !== 200);
  sleep(1);
}

export function handleSummary(data) {
  return {
    'load-test-results.json': JSON.stringify(data),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}
```

**Run Load Test**:
```bash
k6 run scripts/k6-load-test.js
```

### 3. Apache Bench (Quick Tests)

**Purpose**: Quick API endpoint benchmarking

**Installation**:
```bash
sudo apt-get install apache2-utils
```

**Example Tests**:
```bash
# Test GET /api/servers (100 requests, 10 concurrent)
ab -n 100 -c 10 http://localhost:5000/api/servers

# Test GET /api/servers/health (1000 requests, 50 concurrent)
ab -n 1000 -c 50 http://localhost:5000/api/servers/health

# Test GET /api/queries/top (500 requests, 25 concurrent)
ab -n 500 -c 25 http://localhost:5000/api/queries/top?topN=50
```

### 4. SQL Server Profiler / Extended Events

**Purpose**: Measure database-side performance

**Monitor Queries**:
```sql
-- Create Extended Event session to capture slow queries
CREATE EVENT SESSION [API_Performance_Monitoring]
ON SERVER
ADD EVENT sqlserver.rpc_completed(
    ACTION(
        sqlserver.client_app_name,
        sqlserver.database_name,
        sqlserver.session_id,
        sqlserver.sql_text
    )
    WHERE (
        [duration] > 100000  -- > 100ms
        AND [sqlserver].[client_app_name] = N'SqlServerMonitor.Api'
    )
),
ADD EVENT sqlserver.sql_batch_completed(
    ACTION(
        sqlserver.client_app_name,
        sqlserver.database_name,
        sqlserver.session_id,
        sqlserver.sql_text
    )
    WHERE (
        [duration] > 100000  -- > 100ms
        AND [sqlserver].[client_app_name] = N'SqlServerMonitor.Api'
    )
)
ADD TARGET package0.event_file(SET filename=N'API_Performance_Monitoring')
WITH (MAX_MEMORY=4096 KB, EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS);

-- Start session
ALTER EVENT SESSION [API_Performance_Monitoring] ON SERVER STATE = START;

-- Query results
SELECT
    event_data.value('(event/@timestamp)[1]', 'DATETIME2') AS event_time,
    event_data.value('(event/data[@name="duration"]/value)[1]', 'BIGINT') / 1000 AS duration_ms,
    event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') AS sql_text,
    event_data.value('(event/data[@name="cpu_time"]/value)[1]', 'BIGINT') AS cpu_time_us
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file('API_Performance_Monitoring*.xel', NULL, NULL, NULL)
) AS event_xml
ORDER BY duration_ms DESC;
```

## Test Scenarios

### Scenario 1: Light Load (Baseline)

**Goal**: Establish performance baseline with minimal load

**Configuration**:
- 10 concurrent users
- 5-minute duration
- Mix of read operations (90% reads, 10% writes)

**Expected Results**:
- p95 response time < 200ms
- 0% error rate
- API memory usage < 256MB

**K6 Script**:
```javascript
export const options = {
  vus: 10,
  duration: '5m',
};
```

### Scenario 2: Normal Load

**Goal**: Simulate typical production usage

**Configuration**:
- 50 concurrent users
- 10-minute duration
- Realistic traffic mix

**Expected Results**:
- p95 response time < 500ms
- Error rate < 0.1%
- API memory usage < 400MB

### Scenario 3: Peak Load

**Goal**: Test system under peak traffic conditions

**Configuration**:
- 200 concurrent users
- 5-minute duration
- High query volume

**Expected Results**:
- p95 response time < 1000ms
- Error rate < 1%
- API memory usage < 512MB
- Database connections < 100

### Scenario 4: Stress Test

**Goal**: Find breaking point

**Configuration**:
- Ramp up from 100 to 1000 users over 10 minutes
- Continue until system fails or degrades significantly

**Success Criteria**:
- System handles > 500 requests/second
- Graceful degradation (no crashes)
- Clear bottleneck identification

### Scenario 5: Soak Test (Endurance)

**Goal**: Verify system stability over extended period

**Configuration**:
- 50 concurrent users
- 4-hour duration
- Continuous load

**Expected Results**:
- No memory leaks (stable memory usage)
- No connection leaks (stable connection pool)
- Consistent response times throughout test

## Database Performance Tuning

### Index Analysis

**Check Missing Indexes**:
```sql
-- Query missing index recommendations
SELECT
    migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    'CREATE INDEX IX_' + OBJECT_NAME(mid.object_id, mid.database_id) + '_'
        + REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns, ''), ', ', '_'), '[', ''), ']', '')
        + CASE WHEN mid.inequality_columns IS NOT NULL THEN '_' + REPLACE(REPLACE(REPLACE(mid.inequality_columns, ', ', '_'), '[', ''), ']', '') ELSE '' END
        + ' ON ' + mid.statement + ' (' + ISNULL(mid.equality_columns, '')
        + CASE WHEN mid.inequality_columns IS NOT NULL THEN ',' + mid.inequality_columns ELSE '' END + ')'
        + CASE WHEN mid.included_columns IS NOT NULL THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END AS create_index_statement,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_user_impact
FROM sys.dm_db_missing_index_groups mig
INNER JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE mid.database_id = DB_ID('MonitoringDB')
ORDER BY improvement_measure DESC;
```

### Query Plan Analysis

**Expensive Queries**:
```sql
-- Find most expensive queries by CPU
SELECT TOP 20
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS statement_text,
    qs.execution_count,
    qs.total_worker_time / qs.execution_count AS avg_cpu_time_us,
    qs.total_elapsed_time / qs.execution_count AS avg_elapsed_time_us,
    qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
    qs.creation_time,
    qs.last_execution_time,
    qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE st.text LIKE '%usp_Get%'  -- Filter for our stored procedures
ORDER BY avg_cpu_time_us DESC;
```

### Statistics Maintenance

**Update Statistics**:
```sql
-- Update statistics for critical tables
UPDATE STATISTICS dbo.Servers WITH FULLSCAN;
UPDATE STATISTICS dbo.PerformanceMetrics WITH FULLSCAN, NORECOMPUTE;
UPDATE STATISTICS dbo.QueryStoreSnapshots WITH FULLSCAN;
```

### Partitioning Performance

**Verify Partition Elimination**:
```sql
-- Check if queries use partition elimination
SET STATISTICS XML ON;

DECLARE @StartTime DATETIME2 = DATEADD(DAY, -7, SYSUTCDATETIME());
DECLARE @EndTime DATETIME2 = SYSUTCDATETIME();

SELECT ServerID, CollectionTime, MetricValue
FROM dbo.PerformanceMetrics
WHERE CollectionTime BETWEEN @StartTime AND @EndTime;

SET STATISTICS XML OFF;

-- Look for "Partition Id" in query plan
-- Should only scan relevant partitions, not all
```

## API Performance Optimization

### 1. Response Compression

**Enable Gzip Compression** (Program.cs):
```csharp
builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
    options.Providers.Add<GzipCompressionProvider>();
});

builder.Services.Configure<GzipCompressionProviderOptions>(options =>
{
    options.Level = System.IO.Compression.CompressionLevel.Fastest;
});

var app = builder.Build();
app.UseResponseCompression();
```

### 2. Output Caching

**Add Output Caching Middleware**:
```csharp
builder.Services.AddOutputCache(options =>
{
    options.AddBasePolicy(builder => builder.Cache());
    options.AddPolicy("ServerList", builder =>
        builder.Cache().Expire(TimeSpan.FromMinutes(5)));
});

// In controller
[OutputCache(PolicyName = "ServerList")]
public async Task<ActionResult<IEnumerable<ServerModel>>> GetServers()
```

### 3. Connection Pooling

**Optimize Connection String**:
```json
{
  "ConnectionStrings": {
    "MonitoringDB": "Server=...;Min Pool Size=10;Max Pool Size=100;Pooling=true;Connection Timeout=30"
  }
}
```

### 4. Async All The Way

**Ensure Async Path**:
```csharp
// ❌ BAD: Sync over async (blocks threads)
var servers = _service.GetServersAsync().Result;

// ✅ GOOD: Async all the way
var servers = await _service.GetServersAsync();
```

## Monitoring & Alerting

### Application Insights (Optional)

**Add Telemetry**:
```csharp
builder.Services.AddApplicationInsightsTelemetry();

// Custom metrics
var telemetryClient = new TelemetryClient();
telemetryClient.TrackMetric("API.GetServers.Duration", stopwatch.ElapsedMilliseconds);
```

### Prometheus Metrics

**Add Prometheus Exporter**:
```csharp
builder.Services.AddPrometheusAspNetCore();

// Expose /metrics endpoint
app.UseEndpoints(endpoints =>
{
    endpoints.MapMetrics();
});
```

## Performance Test Checklist

- [ ] BenchmarkDotNet microbenchmarks run for all services
- [ ] K6 load tests pass for all scenarios (light, normal, peak)
- [ ] Apache Bench confirms individual endpoint performance
- [ ] SQL Server Extended Events capture no slow queries (> 500ms)
- [ ] Database indexes optimized (no missing indexes)
- [ ] Query plans verified for partition elimination
- [ ] API response compression enabled
- [ ] Connection pooling configured
- [ ] Memory usage stable during soak test
- [ ] Error rate < 0.1% under normal load
- [ ] p95 response times meet targets

## Baseline Results (Target)

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| GET /api/servers p95 | < 100ms | TBD | ⏳ |
| GET /api/queries/top p95 | < 500ms | TBD | ⏳ |
| Throughput (normal load) | 50 req/s | TBD | ⏳ |
| Throughput (peak load) | 200 req/s | TBD | ⏳ |
| Memory usage (steady state) | < 400MB | TBD | ⏳ |
| Database connections (max) | < 100 | TBD | ⏳ |
| Error rate (normal load) | < 0.1% | TBD | ⏳ |

## Next Steps

1. **Run Baseline Tests**: Execute all test scenarios and record actual results
2. **Identify Bottlenecks**: Analyze results to find performance bottlenecks
3. **Optimize**: Apply database/API optimizations
4. **Re-test**: Verify improvements meet targets
5. **Continuous Monitoring**: Implement production monitoring with alerts

## References

- BenchmarkDotNet: https://benchmarkdotnet.org/
- K6 Documentation: https://k6.io/docs/
- ASP.NET Core Performance Best Practices: https://learn.microsoft.com/en-us/aspnet/core/performance/performance-best-practices
- SQL Server Performance Tuning: https://learn.microsoft.com/en-us/sql/relational-databases/performance/performance-monitoring-and-tuning-tools
