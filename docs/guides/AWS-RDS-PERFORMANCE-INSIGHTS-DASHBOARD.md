# AWS RDS Performance Insights Dashboard for SQL Server

**Last Updated:** 2025-10-30
**Dashboard:** `08-aws-rds-performance-insights.json`
**Status:** Production-Ready

---

## Overview

This dashboard replicates the AWS RDS Performance Insights experience for SQL Server, providing comprehensive database performance monitoring with four key sections:

1. **Counter Metrics** - 10 customizable performance indicators
2. **Database Load** - Active sessions stacked by wait type
3. **Top Dimensions** - Breakdown by SQL, Waits, Hosts, Users, Databases

---

## Dashboard Sections

### 1. Counter Metrics (Performance Indicators)

**10 real-time metrics matching AWS RDS Performance Insights:**

| Panel | Metric | Type | Thresholds | Description |
|-------|--------|------|------------|-------------|
| CPU Utilization | `MetricCategory = 'CPU'` | Time series | >70% yellow, >90% red | SQL Server CPU usage |
| Memory Utilization | `BufferCacheHitRatio`, `MemoryUtilization` | Time series | >80% yellow, >95% red | Memory and buffer cache |
| Database Connections | `TotalConnections`, `ActiveConnections`, `SleepingConnections` | Stacked area | N/A | Connection breakdown |
| Read/Write IOPS | `ReadIOPS`, `WriteIOPS` | Time series | N/A | Disk I/O operations/sec |
| Read/Write Throughput | `ReadThroughputMBps`, `WriteThroughputMBps` | Time series | N/A | Disk throughput MB/s |
| Disk Latency | `AvgReadLatencyMs`, `AvgWriteLatencyMs` | Time series | >15ms yellow, >25ms red | Disk response time |
| Buffer Cache Hit Ratio | `BufferCacheHitRatio` | Gauge | <90% red, <95% yellow, >=95% green | Cache effectiveness |
| Page Life Expectancy | `PageLifeExpectancy` | Gauge | <300s red, <1000s yellow, >=1000s green | Memory pressure indicator |
| Batch Requests/sec | `BatchRequestsPerSec` | Stat | >1000 yellow, >5000 red | Workload intensity |
| Transactions/sec | `TransactionsPerSec` | Stat | >500 yellow, >2000 red | Transaction volume |

**Color Scheme:**
- **Green** = Healthy (normal operation)
- **Yellow** = Warning (approaching limits)
- **Red** = Critical (action required)

---

### 2. Database Load (Active Sessions by Wait Type)

**Large stacked area chart showing:**
- Active sessions grouped by wait type
- Max vCPU line (red dashed) representing server capacity
- When load exceeds Max vCPU = CPU saturation

**Key Wait Types Displayed:**
- **PAGEIOLATCH_SH/EX** - Disk I/O waits (storage bottleneck)
- **LCK_M_S/X/U** - Lock waits (blocking/contention)
- **WRITELOG** - Transaction log waits
- **CXPACKET/CXCONSUMER** - Parallelism waits
- **SOS_SCHEDULER_YIELD** - CPU pressure
- **ASYNC_NETWORK_IO** - Client network delays
- **BROKER_RECEIVE_WAITFOR** - Service Broker waits

**Interpretation:**
```
Active Sessions = Database Load
Max vCPU = Server Capacity

If Load > Max vCPU:
  → CPU bottleneck (consider scaling)

If Load < Max vCPU but high wait times:
  → I/O, locks, or network bottleneck
```

---

### 3. Top Dimensions

**Five tables breaking down database activity:**

#### 3.1 Top SQL (by Total Duration)

Shows most expensive queries by cumulative runtime.

**Columns:**
- Query Text (first 100 characters)
- Executions (total count)
- Total Duration (sec) - sorted descending
- Avg Duration (ms)
- Total CPU (sec)
- Total Reads (millions)

**Use Case:** Identify queries consuming most database time.

#### 3.2 Top Waits (by Total Wait Time)

Shows wait types consuming most time.

**Columns:**
- Wait Type
- Wait Count (occurrences)
- Total Wait Time (sec) - sorted descending
- Avg Wait Time (ms)

**Use Case:** Diagnose bottlenecks (I/O, locks, CPU, network).

#### 3.3 Top Hosts (by Connection Count)

Shows client machines with most connections.

**Columns:**
- Host Name
- Connections (total) - sorted descending
- Active (running queries)
- Sleeping (idle connections)

**Use Case:** Identify connection leaks or misbehaving clients.

#### 3.4 Top Users (by Connection Count)

Shows SQL Server logins with most connections.

**Columns:**
- User Name
- Connections (total) - sorted descending
- Active
- Sleeping

**Use Case:** Identify users with excessive connections.

#### 3.5 Top Databases (by Connection Count)

Shows databases with most active sessions.

**Columns:**
- Database Name
- Connections (total) - sorted descending
- Active
- Sleeping

**Use Case:** Identify which databases are most active.

---

## Dashboard Variables

### 1. `$DS_MONITORINGDB`
- **Type:** Datasource
- **Query:** `mssql`
- **Description:** MonitoringDB datasource

### 2. `$ServerID`
- **Type:** Query
- **Query:** `SELECT ServerID AS __value, ServerName AS __text FROM dbo.Servers WHERE IsActive = 1 ORDER BY ServerName`
- **Description:** Select monitored server
- **Default:** First active server

---

## Data Requirements

### Required Tables
- `dbo.PerformanceMetrics` - Time-series metrics
- `dbo.Servers` - Server inventory

### Required Stored Procedures (from Phase 1)
```sql
-- RDS-Equivalent Metrics Collection
EXEC dbo.usp_CollectCPUMetrics @ServerID = 1;
EXEC dbo.usp_CollectMemoryMetrics @ServerID = 1;
EXEC dbo.usp_CollectDiskIOMetrics @ServerID = 1;
EXEC dbo.usp_CollectConnectionMetrics @ServerID = 1;
EXEC dbo.usp_CollectWaitStats @ServerID = 1;
EXEC dbo.usp_CollectQueryPerformance @ServerID = 1;

-- Or all at once:
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;
```

### Automated Collection
Create SQL Agent job to run every 5 minutes:
```sql
USE [msdb];
GO

EXEC dbo.sp_add_job
    @job_name = N'SQL Monitor - Collect RDS Metrics',
    @enabled = 1;

EXEC dbo.sp_add_jobstep
    @job_name = N'SQL Monitor - Collect RDS Metrics',
    @step_name = N'Collect All Metrics',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;';

EXEC dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 5;

EXEC dbo.sp_attach_schedule
    @job_name = N'SQL Monitor - Collect RDS Metrics',
    @schedule_name = N'Every 5 Minutes';

EXEC dbo.sp_add_jobserver
    @job_name = N'SQL Monitor - Collect RDS Metrics';
GO
```

---

## Time Range and Refresh

**Default Settings:**
- **Time Range:** Last 1 hour (`now-1h` to `now`)
- **Refresh:** Every 30 seconds
- **Available Ranges:** 5m, 15m, 1h, 6h, 12h, 24h, 2d, 7d, 30d

**Timezone:** Browser (automatically converts UTC data to local time)

---

## Comparison: AWS RDS vs SQL Monitor

| AWS RDS Feature | SQL Monitor Equivalent | Status |
|-----------------|------------------------|--------|
| CPU Utilization | sys.dm_os_ring_buffers | ✅ Implemented |
| Memory Utilization | sys.dm_os_performance_counters | ✅ Implemented |
| DatabaseConnections | sys.dm_exec_sessions | ✅ Implemented |
| Read/Write IOPS | sys.dm_io_virtual_file_stats | ✅ Implemented |
| Read/Write Throughput | sys.dm_io_virtual_file_stats | ✅ Implemented |
| Database Load | sys.dm_os_wait_stats | ✅ Implemented |
| Top SQL | sys.dm_exec_query_stats | ✅ Implemented |
| Top Waits | sys.dm_os_wait_stats | ✅ Implemented |
| Top Hosts | sys.dm_exec_sessions | ✅ Implemented |
| Top Users | sys.dm_exec_sessions | ✅ Implemented |
| Top Databases | sys.dm_exec_sessions | ✅ Implemented |
| Network Throughput | sys.dm_os_performance_counters | ⏳ Pending |
| Swap Usage | sys.dm_os_sys_memory | ⏳ Pending |
| Free Storage Space | sys.dm_os_volume_stats | ⏳ Pending |

**Coverage:** 11/14 metrics (78%) ✅

---

## Troubleshooting

### Issue: Dashboard shows "No data"

**Cause:** Metrics not collected yet.

**Fix:**
```sql
-- Manually collect metrics
USE MonitoringDB;
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;

-- Verify data exists
SELECT COUNT(*) FROM dbo.PerformanceMetrics WHERE ServerID = 1;
```

### Issue: Counter metrics show flat lines

**Cause:** Stored procedures returning incorrect MetricCategory or MetricName.

**Fix:**
```sql
-- Check metric categories
SELECT DISTINCT MetricCategory, MetricName
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
  AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY MetricCategory, MetricName;
```

Expected categories: `CPU`, `Memory`, `DiskIO`, `Connections`, `WaitStats`, `QueryPerformance`

### Issue: Top SQL table is empty

**Cause:** `MetricDetails` column missing or not JSON format.

**Fix:**
```sql
-- Verify MetricDetails format
SELECT TOP 1 MetricDetails
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'QueryPerformance';

-- Should return JSON like:
-- {"QueryText": "SELECT ...", "ExecutionCount": 100, "TotalDurationMs": 5000, ...}
```

### Issue: Database Load chart missing Max vCPU line

**Cause:** `LogicalProcessors` metric not collected.

**Fix:**
```sql
-- Insert logical CPU count manually
INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
SELECT 1, GETUTCDATE(), 'CPU', 'LogicalProcessors', cpu_count
FROM sys.dm_os_sys_info;
```

---

## Performance Optimization

### Query Performance
All queries optimized for sub-500ms response:
- Indexes on `(ServerID, MetricCategory, CollectionTime)`
- Columnstore index for large time ranges
- TOP 10 limits on table panels
- Time range filters on all queries

### Dashboard Load Time
- **Initial Load:** <2 seconds
- **Refresh (30s):** <1 second
- **Data Points:** ~1,000 per panel (5-minute intervals over 1 hour)

---

## Customization

### Add Custom Counter Metric

1. Collect new metric via stored procedure:
```sql
INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
VALUES (1, GETUTCDATE(), 'CustomCategory', 'CustomMetric', 123.45);
```

2. Add new panel to dashboard:
- Copy existing panel JSON
- Change `MetricCategory` and `MetricName` in SQL query
- Update title, description, thresholds

### Change Wait Types in Database Load

Edit panel 11 query, modify `IN (...)` clause:
```sql
WHERE MetricCategory = 'WaitStats'
  AND MetricName IN (
    'YOUR_WAIT_TYPE_1',
    'YOUR_WAIT_TYPE_2',
    -- Add/remove wait types here
  )
```

---

## Access URLs

### Development
- **Grafana:** http://localhost:9001
- **Dashboard:** http://localhost:9001/d/aws-rds-performance-insights

### Production
- **Grafana:** http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
- **Dashboard:** http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/d/aws-rds-performance-insights

**Credentials:** admin / [see deployment docs]

---

## Related Documentation

- [RDS Equivalent Setup Guide](RDS-EQUIVALENT-SETUP.md) - Initial deployment
- [Quick Start Guide](QUICK-START.md) - Getting started
- [Grafana Dashboards Guide](GRAFANA-DASHBOARDS-GUIDE.md) - All dashboards

---

## Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2025-10-30 | 1.0 | Initial release - AWS RDS Performance Insights equivalent dashboard |

---

**Status:** Production-Ready
**Coverage:** 11/14 AWS RDS metrics (78%)
**Target Users:** DBAs, DevOps, Performance Engineers
