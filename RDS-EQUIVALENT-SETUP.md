# RDS-Equivalent Monitoring Setup for data.schoolvision.net

## ✅ Completed Configuration

### 1. Server Configuration Updated
- **Target Server**: `data.schoolvision.net,14333` (SVWeb\CLUBTRACK)
- **SQL Server Version**: Microsoft SQL Server 2019 (RTM-CU32-GDR)
- **Credentials**: sv / Gv51076!
- **Database**: MonitoringDB (successfully deployed)

### 2. Files Updated
- `.env.test` → Changed server from sqltest to data.schoolvision.net
- `.env` → Copied from .env.test
- `grafana/provisioning/datasources/monitoringdb.yml` → Updated datasource URL

### 3. Database Deployed
```
✅ MonitoringDB created successfully
✅ 2 Tables (Servers, PerformanceMetrics)
✅ 3 Core Stored Procedures (usp_GetServers, usp_InsertMetrics, usp_GetMetrics)
✅ 1 Partition Function (PF_MonitoringByMonth)
✅ 7 RDS-Equivalent Procedures (CPU, Memory, Disk, Connections, Wait Stats, Query Performance)
✅ Server registered (ServerID=1, data.schoolvision.net,14333)
```

### 4. RDS-Equivalent Stored Procedures Created

**File**: `database/05-create-rds-equivalent-procedures.sql`

| Procedure | Purpose | RDS Equivalent |
|-----------|---------|----------------|
| `usp_CollectCPUMetrics` | CPU utilization (SQL Server, System, Other) | CPU Utilization |
| `usp_CollectMemoryMetrics` | Memory usage, buffer cache, page life expectancy | Memory Utilization |
| `usp_CollectDiskIOMetrics` | Read/Write IOPS, throughput, latency | Read/Write IOPS & Throughput |
| `usp_CollectConnectionMetrics` | Total, active, sleeping connections | DatabaseConnections |
| `usp_CollectWaitStats` | Top wait types and wait times | Wait Events |
| `usp_CollectQueryPerformance` | Top queries by CPU, duration, reads | Top SQL |
| `usp_CollectAllRDSMetrics` | Master procedure to collect all metrics | Performance Insights |

---

## 📊 RDS Performance Insights Metrics Coverage

### What AWS RDS Performance Insights Provides

| RDS Metric Category | SQL Server Monitor Equivalent | Status |
|---------------------|------------------------------|--------|
| **CPU Utilization** | sys.dm_os_performance_counters, ring buffers | ✅ Implemented |
| **Memory Utilization** | Buffer cache hit ratio, page life expectancy | ✅ Implemented |
| **Read/Write IOPS** | sys.dm_io_virtual_file_stats | ✅ Implemented |
| **Read/Write Throughput** | Disk I/O stats (MB/s) | ✅ Implemented |
| **DatabaseConnections** | sys.dm_exec_sessions | ✅ Implemented |
| **Wait Events** | sys.dm_os_wait_stats | ✅ Implemented |
| **Top SQL** | sys.dm_exec_query_stats | ✅ Implemented |
| **Network Throughput** | sys.dm_os_performance_counters (network) | ⏳ Pending |
| **Swap Usage** | sys.dm_os_sys_memory (page faults) | ⏳ Pending |
| **Free Storage Space** | sys.dm_os_volume_stats | ⏳ Pending |

---

## 🎯 Usage Instructions

### Manual Metric Collection

```sql
USE MonitoringDB;
GO

-- Collect all RDS-equivalent metrics at once
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;

-- Or collect individual metric categories:
EXEC dbo.usp_CollectCPUMetrics @ServerID = 1;
EXEC dbo.usp_CollectMemoryMetrics @ServerID = 1;
EXEC dbo.usp_CollectDiskIOMetrics @ServerID = 1;
EXEC dbo.usp_CollectConnectionMetrics @ServerID = 1;
EXEC dbo.usp_CollectWaitStats @ServerID = 1;
EXEC dbo.usp_CollectQueryPerformance @ServerID = 1;

-- View collected metrics
SELECT TOP 50
    pm.CollectionTime,
    s.ServerName,
    pm.MetricCategory,
    pm.MetricName,
    pm.MetricValue
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.ServerID = 1
ORDER BY pm.CollectionTime DESC;
```

### Automated Metric Collection (SQL Agent Job)

Create a SQL Agent job to run every 5 minutes:

```sql
USE [msdb];
GO

-- Step 1: Create SQL Agent Job
EXEC dbo.sp_add_job
    @job_name = N'SQL Monitor - Collect RDS Metrics',
    @enabled = 1,
    @description = N'Collects comprehensive performance metrics matching AWS RDS Performance Insights';
GO

-- Step 2: Add Job Step
EXEC dbo.sp_add_jobstep
    @job_name = N'SQL Monitor - Collect RDS Metrics',
    @step_name = N'Collect All Metrics',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;',
    @retry_attempts = 3,
    @retry_interval = 1;
GO

-- Step 3: Schedule (every 5 minutes)
EXEC dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes',
    @freq_type = 4, -- Daily
    @freq_interval = 1,
    @freq_subday_type = 4, -- Minutes
    @freq_subday_interval = 5,
    @active_start_time = 000000;
GO

-- Step 4: Attach schedule to job
EXEC dbo.sp_attach_schedule
    @job_name = N'SQL Monitor - Collect RDS Metrics',
    @schedule_name = N'Every 5 Minutes';
GO

-- Step 5: Add job to local server
EXEC dbo.sp_add_jobserver
    @job_name = N'SQL Monitor - Collect RDS Metrics',
    @server_name = N'(local)';
GO

PRINT 'SQL Agent job created successfully!';
PRINT 'Metrics will be collected automatically every 5 minutes.';
```

---

## 📈 Grafana Dashboards (Next Steps)

### Dashboard 1: RDS Performance Insights Equivalent
**Panels Needed**:
1. CPU Utilization (%) - Time series
2. Memory Utilization (%) - Time series
3. Database Connections - Time series
4. Read/Write IOPS - Time series
5. Read/Write Latency (ms) - Time series
6. Top Wait Events - Bar chart
7. Active Sessions - Gauge
8. Buffer Cache Hit Ratio - Gauge

### Dashboard 2: Database Performance
**Panels Needed**:
1. Top Queries by CPU - Table
2. Top Queries by Duration - Table
3. Top Queries by Logical Reads - Table
4. Query Execution Counts - Time series
5. Wait Statistics Breakdown - Pie chart
6. Long-Running Queries - Table

### Dashboard 3: Resource Utilization
**Panels Needed**:
1. CPU Breakdown (SQL Server vs System vs Other) - Stacked area chart
2. Memory Components (Buffer Pool, Plan Cache, etc.) - Stacked bar chart
3. Disk I/O by Database - Table
4. Network Throughput - Time series
5. Page Life Expectancy - Time series
6. Memory Grants Pending - Time series

### Dashboard 4: Connection Monitoring
**Panels Needed**:
1. Total Connections - Time series
2. Active vs Sleeping - Stacked area
3. Connections by Database - Pie chart
4. Connections by Application - Table
5. Long-Running Sessions - Table
6. Blocked Sessions - Table

---

## 🚀 Quick Start Commands

### 1. Test API Connection
```bash
curl http://localhost:5000/api/server
# Should return: data.schoolvision.net,14333
```

### 2. Insert Sample Metrics via API
```bash
curl -X POST http://localhost:5000/api/metrics \
  -H "Content-Type: application/json" \
  -d '{
    "serverID": 1,
    "collectionTime": "'$(date -u '+%Y-%m-%dT%H:%M:%SZ')'",
    "metricCategory": "CPU",
    "metricName": "Percent",
    "metricValue": 45.5
  }'
```

### 3. Access Grafana
```
URL: http://localhost:3000
Username: admin
Password: Admin123!
```

### 4. View Existing Dashboards
- SQL Server Performance Overview: http://localhost:3000/d/sql-server-overview
- Detailed Metrics View: http://localhost:3000/d/detailed-metrics

---

## 🔧 Troubleshooting

### Issue: Cannot Connect to data.schoolvision.net

**Test connectivity**:
```bash
sqlcmd -S data.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT @@SERVERNAME"
```

**Common fixes**:
- Ensure port 14333 is open
- Verify SQL Server allows remote connections
- Check SQL Server Browser service is running

### Issue: Stored Procedures Fail

**Check permissions**:
```sql
-- Grant necessary permissions to sv user
USE MonitoringDB;
GO

GRANT VIEW SERVER STATE TO sv;
GRANT VIEW DATABASE STATE TO sv;
GO
```

### Issue: Grafana Shows "No Data"

**Collect metrics first**:
```sql
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;
```

**Verify data exists**:
```sql
SELECT COUNT(*) FROM dbo.PerformanceMetrics WHERE ServerID = 1;
```

---

## 📝 Next Implementation Steps

### High Priority
1. **Create RDS Performance Insights Dashboard** - Main monitoring dashboard
2. **Set up SQL Agent job** - Automated 5-minute collection
3. **Test metric collection** - Run for 1 hour, verify data
4. **Add Network metrics** - Complete RDS coverage
5. **Add Storage metrics** - Disk space monitoring

### Medium Priority
6. **Create Database Performance Dashboard** - Query analysis
7. **Create Resource Utilization Dashboard** - Detailed breakdowns
8. **Create Connection Monitoring Dashboard** - Session tracking
9. **Set up alerts** - CPU > 80%, Memory > 90%, Connections > 100

### Low Priority
10. **Add custom metrics** - Application-specific
11. **Create executive dashboard** - High-level summary
12. **Set up email notifications** - Alert delivery
13. **Create reports** - Weekly/monthly summaries

---

## 📚 Reference Queries

### Current Server Status
```sql
SELECT
    @@SERVERNAME AS ServerName,
    @@VERSION AS Version,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductLevel') AS ServicePack,
    SERVERPROPERTY('ProductVersion') AS VersionNumber;
```

### Check Metric Collection Status
```sql
SELECT
    s.ServerName,
    COUNT(*) AS TotalMetrics,
    MIN(pm.CollectionTime) AS FirstCollection,
    MAX(pm.CollectionTime) AS LastCollection,
    DATEDIFF(MINUTE, MAX(pm.CollectionTime), GETUTCDATE()) AS MinutesSinceLastCollection
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
GROUP BY s.ServerName;
```

### Metric Categories Collected
```sql
SELECT
    MetricCategory,
    MetricName,
    COUNT(*) AS SampleCount,
    MIN(MetricValue) AS MinValue,
    MAX(MetricValue) AS MaxValue,
    AVG(MetricValue) AS AvgValue
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
  AND CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
GROUP BY MetricCategory, MetricName
ORDER BY MetricCategory, MetricName;
```

---

## ✅ Deployment Checklist

- [x] Updated configuration files (.env, datasource YAML)
- [x] Deployed MonitoringDB to data.schoolvision.net
- [x] Created base tables and procedures
- [x] Created RDS-equivalent stored procedures
- [x] Registered server for monitoring
- [x] Tested connectivity
- [ ] Created SQL Agent job for automated collection
- [ ] Built RDS Performance Insights dashboard
- [ ] Built Database Performance dashboard
- [ ] Built Resource Utilization dashboard
- [ ] Built Connection Monitoring dashboard
- [ ] Tested end-to-end monitoring
- [ ] Configured alerts
- [ ] Documented usage for team

---

## 🎉 Summary

**What's Working**:
- ✅ Database infrastructure deployed to `data.schoolvision.net,14333`
- ✅ All RDS-equivalent metric collection procedures created
- ✅ API and Grafana containers running
- ✅ Datasource automatically provisioned in Grafana
- ✅ 2 base dashboards available (will be enhanced)

**Next Steps**:
1. Run manual metric collection to populate data
2. Create SQL Agent job for automated collection
3. Build comprehensive RDS-equivalent dashboards
4. Test for 24 hours to ensure stability

**Access URLs**:
- API: http://localhost:5000/swagger
- Grafana: http://localhost:3000 (admin/Admin123!)
- Database: data.schoolvision.net,14333 (MonitoringDB)
