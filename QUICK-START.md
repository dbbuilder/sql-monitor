# SQL Server Monitor - Quick Start Guide

## ✅ System Status

**Server**: data.schoolvision.net,14333 (SVWeb\CLUBTRACK)
**Database**: MonitoringDB
**API**: http://localhost:5000
**Grafana**: http://localhost:3000 (admin/Admin123!)

---

## 🚀 Collect Metrics Now (Working Procedures)

```sql
USE MonitoringDB;
GO

-- Collect all working metrics at once
EXEC dbo.usp_CollectMemoryMetrics @ServerID = 1;
EXEC dbo.usp_CollectDiskIOMetrics @ServerID = 1;
EXEC dbo.usp_CollectConnectionMetrics @ServerID = 1;
EXEC dbo.usp_CollectWaitStats @ServerID = 1;
EXEC dbo.usp_CollectQueryPerformance @ServerID = 1;
GO

-- View collected metrics
SELECT TOP 50
    CollectionTime,
    MetricCategory,
    MetricName,
    CAST(MetricValue AS DECIMAL(18,2)) AS Value
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
ORDER BY CollectionTime DESC, MetricCategory;
```

---

## 📊 Available Metrics

| Category | Metrics Collected | Status |
|----------|-------------------|--------|
| **Memory** | TotalServerMemoryMB, TargetServerMemoryMB, BufferCacheHitRatio, PageLifeExpectancy, MemoryGrantsPending, Percent | ✅ Working |
| **Disk** | TotalReadMB, TotalWriteMB, TotalReadIOPS, TotalWriteIOPS, AvgReadLatencyMs, AvgWriteLatencyMs | ✅ Working |
| **Connections** | Total, Active, Sleeping, User, System | ✅ Working |
| **Wait Stats** | Top 10 wait types with wait times | ✅ Working |
| **Query Performance** | AvgCPUMs, AvgDurationMs, TotalLogicalReads, TotalPhysicalReads, TotalExecutions | ✅ Working |
| **CPU** | SQLServerUtilization, SystemIdle, OtherProcessUtilization, Percent | ⚠️ Pending fix |

---

## 📈 View in Grafana

1. **Open Grafana**: http://localhost:3000
2. **Login**: admin / Admin123!
3. **Go to Dashboards**:
   - SQL Server Performance Overview
   - Detailed Metrics View

**Dashboards auto-refresh every 30 seconds** and will show data immediately after you run the metric collection procedures above.

---

## 🔄 Automated Collection (SQL Agent Job)

Create this job to collect metrics automatically every 5 minutes:

```sql
USE [msdb];
GO

-- Create job
EXEC dbo.sp_add_job
    @job_name = N'SQL Monitor - Auto Collect Metrics',
    @enabled = 1;
GO

-- Add step
EXEC dbo.sp_add_jobstep
    @job_name = N'SQL Monitor - Auto Collect Metrics',
    @step_name = N'Collect Metrics',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'
EXEC dbo.usp_CollectMemoryMetrics @ServerID = 1;
EXEC dbo.usp_CollectDiskIOMetrics @ServerID = 1;
EXEC dbo.usp_CollectConnectionMetrics @ServerID = 1;
EXEC dbo.usp_CollectWaitStats @ServerID = 1;
EXEC dbo.usp_CollectQueryPerformance @ServerID = 1;
';
GO

-- Schedule every 5 minutes
EXEC dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 5;
GO

-- Attach schedule
EXEC dbo.sp_attach_schedule
    @job_name = N'SQL Monitor - Auto Collect Metrics',
    @schedule_name = N'Every 5 Minutes';
GO

-- Add to local server
EXEC dbo.sp_add_jobserver
    @job_name = N'SQL Monitor - Auto Collect Metrics';
GO
```

---

## 📊 Sample Grafana Queries

### Memory Utilization (%)
```sql
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  'Memory Utilization' AS metric
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
  AND MetricCategory = 'Memory'
  AND MetricName = 'Percent'
  AND CollectionTime >= DATEADD(hour, -24, GETUTCDATE())
ORDER BY time ASC
```

### Buffer Cache Hit Ratio
```sql
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  'Buffer Cache Hit Ratio' AS metric
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
  AND MetricCategory = 'Memory'
  AND MetricName = 'BufferCacheHitRatio'
  AND CollectionTime >= DATEADD(hour, -24, GETUTCDATE())
ORDER BY time ASC
```

### Active Connections
```sql
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  MetricName AS metric
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
  AND MetricCategory = 'Connections'
  AND MetricName IN ('Total', 'Active', 'Sleeping')
  AND CollectionTime >= DATEADD(hour, -24, GETUTCDATE())
ORDER BY time ASC
```

### Disk I/O Latency
```sql
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  CASE MetricName
    WHEN 'AvgReadLatencyMs' THEN 'Read Latency'
    WHEN 'AvgWriteLatencyMs' THEN 'Write Latency'
  END AS metric
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
  AND MetricCategory = 'Disk'
  AND MetricName IN ('AvgReadLatencyMs', 'AvgWriteLatencyMs')
  AND CollectionTime >= DATEADD(hour, -24, GETUTCDATE())
ORDER BY time ASC
```

---

## 🔍 Troubleshooting

### Check if metrics are being collected
```sql
SELECT
    MetricCategory,
    COUNT(*) AS SampleCount,
    MIN(CollectionTime) AS FirstCollection,
    MAX(CollectionTime) AS LastCollection,
    DATEDIFF(MINUTE, MAX(CollectionTime), GETUTCDATE()) AS MinutesSinceLast
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
GROUP BY MetricCategory
ORDER BY MetricCategory;
```

### Check recent collection errors
```sql
-- If SQL Agent job is created
SELECT TOP 20
    job.name AS JobName,
    run_date,
    run_time,
    run_duration,
    CASE run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
    END AS Status,
    message
FROM msdb.dbo.sysjobhistory history
INNER JOIN msdb.dbo.sysjobs job ON history.job_id = job.job_id
WHERE job.name LIKE '%SQL Monitor%'
ORDER BY run_date DESC, run_time DESC;
```

---

## 📝 Next Steps

1. ✅ **Collect initial metrics** (run procedures above)
2. ✅ **View in Grafana** (should show data immediately)
3. ⏳ **Create SQL Agent job** (automated collection)
4. ⏳ **Let run for 1 hour** (accumulate trending data)
5. ⏳ **Fix CPU metrics procedure** (optional - for completeness)
6. ⏳ **Set up alerts** (CPU > 80%, Memory > 90%)

---

## 🎯 What's Working

- ✅ MonitoringDB deployed on data.schoolvision.net
- ✅ 5 metric collection procedures working perfectly
- ✅ Grafana dashboards auto-provisioned
- ✅ API endpoints functional
- ✅ Data visible in Grafana within 30 seconds of collection

**Start collecting now and watch your dashboards populate!**
