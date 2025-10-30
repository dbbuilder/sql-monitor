# Data Collection Rollout - All Servers

**Target Servers:**
1. sqltest.schoolvision.net,14333
2. svweb,14333
3. suncity.schoolvision.net,14333

**MonitoringDB Host:** sqltest.schoolvision.net,14333

---

## Quick Start (5 Steps)

### Step 1: Register Servers

**Connect to:** sqltest.schoolvision.net,14333 (MonitoringDB host)

```sql
-- Run this script
:r SETUP-DATA-COLLECTION-ALL-SERVERS.sql
```

**This will:**
- ✅ Register all 3 servers in `Servers` table
- ✅ Verify RDS collection procedures exist
- ✅ Test manual collection from all servers
- ✅ Show metrics summary

### Step 2: Create SQL Agent Job on sqltest

**Connect to:** sqltest.schoolvision.net,14333

**Open:** `CREATE-SQL-AGENT-JOBS-ALL-SERVERS.sql`

**Uncomment:** OPTION 1 (sqltest section)

**Run the script**

### Step 3: Create SQL Agent Job on svweb

**Connect to:** svweb,14333

**Open:** `CREATE-SQL-AGENT-JOBS-ALL-SERVERS.sql`

**Uncomment:** OPTION 2 (svweb section)

**Run the script**

### Step 4: Create SQL Agent Job on suncity

**Connect to:** suncity.schoolvision.net,14333

**Open:** `CREATE-SQL-AGENT-JOBS-ALL-SERVERS.sql`

**Uncomment:** OPTION 3 (suncity section)

**Run the script**

### Step 5: Verify Data Collection

**Wait 10 minutes**, then check Grafana:

http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/d/aws-rds-performance-insights

**Should show data for all 3 servers!**

---

## Detailed Instructions

### Prerequisites

1. **MonitoringDB exists** on sqltest.schoolvision.net,14333
2. **RDS collection procedures** deployed (database/05-create-rds-equivalent-procedures.sql)
3. **Permissions** - `sv` user has:
   - VIEW SERVER STATE
   - VIEW ANY DEFINITION
   - EXECUTE on dbo schema in MonitoringDB

### Server Registration

Run on MonitoringDB:

```sql
USE MonitoringDB;

-- Check current servers
SELECT * FROM dbo.Servers;

-- Register new servers (if needed)
INSERT INTO dbo.Servers (ServerName, InstanceName, IsActive, Description)
VALUES
('sqltest.schoolvision.net,14333', 'SQLTEST', 1, 'MonitoringDB Host'),
('svweb,14333', 'SVWEB', 1, 'Production Web Server'),
('suncity.schoolvision.net,14333', 'SUNCITY', 1, 'Suncity Production');

-- Get ServerIDs (needed for SQL Agent jobs)
SELECT ServerID, ServerName FROM dbo.Servers ORDER BY ServerID;
```

**Note the ServerIDs:**
- sqltest = 1
- svweb = 2
- suncity = 3

### Manual Test Collection

Before creating SQL Agent jobs, test manual collection:

```sql
-- On MonitoringDB
USE MonitoringDB;

-- Test Server 1 (sqltest)
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;

-- Test Server 2 (svweb)
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 2;

-- Test Server 3 (suncity)
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 3;

-- Verify data
SELECT
    s.ServerName,
    pm.MetricCategory,
    COUNT(*) AS MetricCount,
    MAX(pm.CollectionTime) AS LastCollection
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.CollectionTime >= DATEADD(MINUTE, -10, GETUTCDATE())
GROUP BY s.ServerName, pm.MetricCategory
ORDER BY s.ServerName, pm.MetricCategory;
```

**Expected categories per server:**
- CPU (3-5 metrics)
- Memory (3-5 metrics)
- DiskIO (6-8 metrics)
- Connections (3 metrics)
- WaitStats (10+ metrics)
- QueryPerformance (varies)

### SQL Agent Job Creation

**For each server, create the SQL Agent job:**

1. **Connect to the server** (sqltest, svweb, or suncity)
2. **Open** `CREATE-SQL-AGENT-JOBS-ALL-SERVERS.sql`
3. **Uncomment** the section for that server
4. **Update @ServerID** if needed (should match Servers table)
5. **Run the script**
6. **Verify** job created:

```sql
-- Check job exists
SELECT name, enabled FROM msdb.dbo.sysjobs
WHERE name LIKE 'SQL Monitor%';

-- Check schedule
SELECT
    j.name AS JobName,
    s.name AS ScheduleName,
    s.freq_subday_interval AS IntervalMinutes
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
INNER JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name LIKE 'SQL Monitor%';
```

### Test SQL Agent Job

Start the job manually to test:

```sql
-- Run job immediately
EXEC msdb.dbo.sp_start_job @job_name = N'SQL Monitor - Collect Metrics (YOUR_SERVER)';

-- Wait 10 seconds, then check history
EXEC msdb.dbo.sp_help_jobhistory
    @job_name = N'SQL Monitor - Collect Metrics (YOUR_SERVER)',
    @mode = 'FULL';
```

**Expected output:**
- run_status = 1 (success)
- run_duration = a few seconds
- message = "The job succeeded..."

---

## Verification

### Check Metrics in MonitoringDB

```sql
USE MonitoringDB;

-- Metrics per server (last hour)
SELECT
    s.ServerName,
    COUNT(*) AS TotalMetrics,
    COUNT(DISTINCT pm.MetricCategory) AS UniqueCategories,
    MIN(pm.CollectionTime) AS FirstMetric,
    MAX(pm.CollectionTime) AS LastMetric,
    DATEDIFF(MINUTE, MAX(pm.CollectionTime), GETUTCDATE()) AS MinutesSinceLastCollection
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY s.ServerName
ORDER BY s.ServerName;

-- Expected:
-- sqltest:  ~200-300 metrics (every 5 min = 12 collections/hour × 20-25 metrics)
-- svweb:    ~200-300 metrics
-- suncity:  ~200-300 metrics
```

### Check Grafana Dashboards

**1. AWS RDS Performance Insights:**
```
http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/d/aws-rds-performance-insights
```

**Select server dropdown:**
- sqltest.schoolvision.net,14333
- svweb,14333
- suncity.schoolvision.net,14333

**Should show:**
- ✅ CPU Utilization chart (data)
- ✅ Memory Utilization chart (data)
- ✅ Database Connections (data)
- ✅ Read/Write IOPS (data)
- ✅ Disk Latency (data)
- ✅ Buffer Cache Hit Ratio (gauge shows %)
- ✅ Page Life Expectancy (gauge shows seconds)
- ✅ Database Load chart (stacked waits)
- ✅ Top SQL table (queries)
- ✅ Top Waits table (wait types)

**2. Other Dashboards:**

All dashboards should now have data when you select a server.

---

## Troubleshooting

### Issue: "No data" in Grafana

**Cause:** Metrics not collected yet or wrong ServerID

**Fix:**

1. **Verify ServerID in Grafana variable:**
   - Click "Server" dropdown at top
   - Should show all 3 servers

2. **Check metrics exist:**
```sql
SELECT COUNT(*) FROM dbo.PerformanceMetrics
WHERE ServerID = 1 -- Change to test each server
  AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE());
```

3. **If count = 0, run manual collection:**
```sql
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;
```

### Issue: SQL Agent job fails

**Cause:** Permission error or procedure missing

**Fix:**

1. **Check job history:**
```sql
EXEC msdb.dbo.sp_help_jobhistory
    @job_name = N'SQL Monitor - Collect Metrics (YOUR_SERVER)',
    @mode = 'FULL';
```

2. **Look for error message in `message` column**

3. **Common errors:**

**"Could not find stored procedure"**
- Run: `database/05-create-rds-equivalent-procedures.sql`

**"VIEW SERVER STATE permission denied"**
```sql
USE master;
GRANT VIEW SERVER STATE TO sv;
GRANT VIEW ANY DEFINITION TO sv;
```

**"Cannot insert duplicate key"**
- Check @ServerID is correct (not already used)
- Verify in `SELECT * FROM dbo.Servers`

### Issue: Metrics collected but not showing in Grafana

**Cause:** Grafana datasource issue or time range

**Fix:**

1. **Check datasource:**
   - Grafana → Configuration → Data Sources
   - Test connection to MonitoringDB
   - Should show "Database Connection OK"

2. **Check time range:**
   - Grafana dashboard top-right
   - Change to "Last 1 hour" or "Last 6 hours"

3. **Hard refresh browser:**
   - Ctrl + Shift + R (Windows)
   - Cmd + Shift + R (Mac)

### Issue: Some metrics missing (e.g., CPU but no Disk I/O)

**Cause:** Collection procedure incomplete

**Fix:**

Check which metrics are being collected:

```sql
SELECT DISTINCT MetricCategory, MetricName
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
  AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY MetricCategory, MetricName;
```

If missing categories, re-run:
```sql
:r database/05-create-rds-equivalent-procedures.sql
```

---

## Maintenance

### Monitor Collection Health

```sql
-- Daily check - are all servers collecting?
SELECT
    s.ServerName,
    MAX(pm.CollectionTime) AS LastCollection,
    DATEDIFF(MINUTE, MAX(pm.CollectionTime), GETUTCDATE()) AS MinutesSinceLast,
    CASE
        WHEN DATEDIFF(MINUTE, MAX(pm.CollectionTime), GETUTCDATE()) > 10 THEN 'STALE'
        ELSE 'OK'
    END AS Status
FROM dbo.Servers s
LEFT JOIN dbo.PerformanceMetrics pm ON s.ServerID = pm.ServerID
WHERE s.IsActive = 1
GROUP BY s.ServerName
ORDER BY MinutesSinceLast DESC;
```

### Check SQL Agent Job History

```sql
-- Jobs that failed in last 24 hours
SELECT
    j.name AS JobName,
    h.step_name AS StepName,
    h.run_status AS Status,
    h.run_date,
    h.run_time,
    h.message
FROM msdb.dbo.sysjobhistory h
INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE j.name LIKE 'SQL Monitor%'
  AND h.run_status <> 1 -- Not success
  AND h.run_date >= CONVERT(INT, CONVERT(VARCHAR(8), DATEADD(DAY, -1, GETDATE()), 112))
ORDER BY h.run_date DESC, h.run_time DESC;
```

### Data Retention

PerformanceMetrics table grows ~300 metrics per server per hour.

**Growth estimate:**
- 3 servers × 300 metrics/hour × 24 hours × 90 days = 19,440,000 rows (90-day retention)
- With columnstore compression: ~2-3 GB

**Cleanup old data:**
```sql
-- Delete metrics older than 90 days
DELETE FROM dbo.PerformanceMetrics
WHERE CollectionTime < DATEADD(DAY, -90, GETUTCDATE());

-- Or use partitioning (see database/03-create-partitions.sql)
```

---

## Success Criteria

✅ All 3 servers registered in `Servers` table
✅ Manual collection works for all 3 servers
✅ SQL Agent jobs created on all 3 servers
✅ Jobs running successfully (check history)
✅ Metrics flowing into `PerformanceMetrics` table
✅ Grafana dashboards showing data for all servers
✅ No errors in job history
✅ Collection happening every 5 minutes

---

**Ready to deploy!** 🚀

Start with Step 1: Run `SETUP-DATA-COLLECTION-ALL-SERVERS.sql`
