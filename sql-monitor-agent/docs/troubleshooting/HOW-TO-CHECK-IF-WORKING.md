# How to Check If Monitoring is Working

After deploying the monitoring system, use these commands to verify everything is working correctly.

---

## 🎯 Quick Health Check (Start Here!)

### Run This First:
```sql
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

**This shows:**
- ✅ Is collection running?
- ✅ When was last snapshot?
- ✅ Is SQL Agent job enabled?
- ✅ Any recent errors?
- ✅ Data collection counts

**Expected Output:**
```
==========================================
SQL Server Monitoring System - Health Check
==========================================

1. Collection Status:
   Total Snapshots: 25
   Status: RUNNING - Latest snapshot 3 minutes ago
   Latest: 2025-10-27 11:45:23

2. SQL Agent Job:
   Enabled: YES
   Last Run: 2025-10-27 11:45:00
   Outcome: Succeeded

3. Recent Errors (Last 24 hours):
   Error Count: 0

4. Data Collection Summary:
   (Shows row counts for all tables)
```

---

## 📊 Quick Test Collection

### Test Manual Collection:
```sql
EXEC DBATools.dbo.DBA_TestCollection
```

**This will:**
1. Run a test collection
2. Show before/after counts
3. Display elapsed time
4. Show latest snapshot if successful

**Expected Output:**
```
==========================================
Test Results:
==========================================
  Snapshots Before: 10
  Snapshots After:  11
  New Snapshots:    1
  Elapsed Time:     1250 ms
  Status: SUCCESS - Collection is working!
```

---

## 📈 View Latest Data

### 1. Show Latest Snapshot
```sql
EXEC DBATools.dbo.DBA_ShowLatestSnapshot
```

Shows most recent performance snapshot with key metrics.

### 2. Show Top Expensive Queries
```sql
EXEC DBATools.dbo.DBA_ShowTopQueries @TopN = 10
```

Shows queries with highest CPU/duration/reads.

### 3. Show Backup Status
```sql
EXEC DBATools.dbo.DBA_ShowBackupStatus
```

Shows last backup for each database with status (OK/WARNING/CRITICAL).

### 4. Show Wait Statistics
```sql
EXEC DBATools.dbo.DBA_ShowWaitStats @TopN = 10
```

Shows top wait types from latest snapshot.

### 5. Show I/O Statistics
```sql
EXEC DBATools.dbo.DBA_ShowIOStats
```

Shows I/O latency by database with status.

### 6. Show Memory Usage
```sql
EXEC DBATools.dbo.DBA_ShowMemoryUsage
```

Shows buffer cache, free memory, plan cache.

### 7. Show Collection History
```sql
EXEC DBATools.dbo.DBA_ShowCollectionHistory @Hours = 24
```

Shows all snapshots from last 24 hours.

### 8. Show Missing Indexes
```sql
EXEC DBATools.dbo.DBA_ShowMissingIndexes @TopN = 10
```

Shows recommended missing indexes with impact score.

---

## 🔍 Manual Queries

### Check Snapshot Count
```sql
SELECT COUNT(*) AS TotalSnapshots
FROM DBATools.dbo.PerfSnapshotRun
```

**Good:** > 0 (any number means it's working)

### Check Latest Snapshot Time
```sql
SELECT TOP 1
    PerfSnapshotRunID,
    dbo.fn_ConvertToReportingTime(SnapshotUTC) AS SnapshotTime_ET,
    DATEDIFF(MINUTE, SnapshotUTC, SYSUTCDATETIME()) AS MinutesAgo
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC
```

**Good:** MinutesAgo < 10 (means collection is running)
**Warning:** MinutesAgo 10-30 (may be delayed)
**Bad:** MinutesAgo > 30 (collection stopped)

### Check SQL Agent Job
```sql
SELECT
    j.name,
    j.enabled,
    js.last_run_date,
    js.last_run_time,
    CASE js.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 3 THEN 'Cancelled'
        ELSE 'Unknown'
    END AS LastOutcome
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
WHERE j.name = 'DBA Collect Perf Snapshot'
```

**Good:** enabled = 1, LastOutcome = 'Succeeded'

### Check for Errors
```sql
SELECT TOP 10
    dbo.fn_ConvertToReportingTime(DateTime_Occurred) AS ErrorTime_ET,
    ProcedureName,
    ProcedureSection,
    ErrDescription
FROM DBATools.dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC
```

**Good:** No rows (no errors)
**Check:** If errors exist, review descriptions

### Check Data Counts
```sql
SELECT 'Snapshots' AS Category, COUNT(*) AS RowCount FROM DBATools.dbo.PerfSnapshotRun
UNION ALL SELECT 'QueryStats', COUNT(*) FROM DBATools.dbo.PerfSnapshotQueryStats
UNION ALL SELECT 'IOStats', COUNT(*) FROM DBATools.dbo.PerfSnapshotIOStats
UNION ALL SELECT 'Memory', COUNT(*) FROM DBATools.dbo.PerfSnapshotMemory
UNION ALL SELECT 'BackupHistory', COUNT(*) FROM DBATools.dbo.PerfSnapshotBackupHistory
UNION ALL SELECT 'IndexUsage', COUNT(*) FROM DBATools.dbo.PerfSnapshotIndexUsage
UNION ALL SELECT 'WaitStats', COUNT(*) FROM DBATools.dbo.PerfSnapshotWaitStats
ORDER BY Category
```

**Good:** All counts > 0 (data is being collected)

---

## 📋 Configuration Check

### View Current Settings
```sql
EXEC DBATools.dbo.DBA_ViewConfig
```

Shows all 28 configuration settings.

### Key Settings to Check:
```sql
SELECT ConfigKey, ConfigValue
FROM DBATools.dbo.MonitoringConfig
WHERE ConfigKey IN (
    'EnableP0Collection',
    'EnableP1Collection',
    'EnableP2Collection',
    'EnableP3Collection',
    'RetentionDays',
    'CollectionIntervalMinutes'
)
```

**Expected:**
- EnableP0Collection = 1 (enabled)
- EnableP1Collection = 1 (enabled)
- EnableP2Collection = 1 (enabled)
- EnableP3Collection = 0 (disabled by default)
- RetentionDays = 30
- CollectionIntervalMinutes = 5

---

## 🚨 Troubleshooting

### Problem: No Snapshots Collected

**Check 1:** Is SQL Agent running?
```bash
# On Linux server
sudo systemctl status mssql-server-agent
```

**Check 2:** Is job enabled?
```sql
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

**Check 3:** Run manual collection
```sql
EXEC DBATools.dbo.DBA_TestCollection
```

### Problem: Collection Stopped

**Check:** Recent errors
```sql
SELECT TOP 10 *
FROM DBATools.dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC
```

**Action:** Review error messages and fix issues

### Problem: Job Runs But No Data

**Check:** Configuration settings
```sql
EXEC DBATools.dbo.DBA_ViewConfig
```

**Action:** Ensure P0, P1, P2 are enabled

---

## 📊 Reporting Views

Three built-in views with Eastern Time:

### Latest Snapshot Summary
```sql
SELECT * FROM DBATools.dbo.vw_LatestSnapshotSummary_ET
```

### Backup Risk Assessment
```sql
SELECT * FROM DBATools.dbo.vw_BackupRiskAssessment_ET
```

### I/O Latency Hotspots
```sql
SELECT * FROM DBATools.dbo.vw_IOLatencyHotspots_ET
```

---

## 🎓 Daily Monitoring Routine

### Morning Check (5 minutes):
```sql
-- 1. Overall health
EXEC DBATools.dbo.DBA_CheckSystemHealth

-- 2. Backup status
EXEC DBATools.dbo.DBA_ShowBackupStatus

-- 3. Top queries
EXEC DBATools.dbo.DBA_ShowTopQueries @TopN = 5

-- 4. I/O latency
EXEC DBATools.dbo.DBA_ShowIOStats
```

### Weekly Review (15 minutes):
```sql
-- 1. Collection history trend
EXEC DBATools.dbo.DBA_ShowCollectionHistory @Hours = 168

-- 2. Missing indexes
EXEC DBATools.dbo.DBA_ShowMissingIndexes @TopN = 20

-- 3. Wait statistics patterns
EXEC DBATools.dbo.DBA_ShowWaitStats @TopN = 20

-- 4. Memory trends
EXEC DBATools.dbo.DBA_ShowMemoryUsage
```

---

## 📦 Installation of Reporting Procedures

If you haven't deployed them yet:

### In SSMS:
1. Open `14_create_reporting_procedures.sql`
2. Execute (F5)
3. All 10 procedures will be created

### In PowerShell:
```powershell
$env:SQLCMDPASSWORD = "YourPassword"
sqlcmd -S your-server -U sa -d DBATools -N -C -i "14_create_reporting_procedures.sql"
```

---

## ✅ Success Indicators

Your monitoring is working correctly if:

- ✅ `DBA_CheckSystemHealth` shows "RUNNING"
- ✅ Latest snapshot < 10 minutes ago
- ✅ SQL Agent job enabled and succeeding
- ✅ No errors in last 24 hours
- ✅ Data counts increasing over time
- ✅ `DBA_TestCollection` creates new snapshot successfully

---

## 📞 Need Help?

**Documentation:**
- `FINAL-DEPLOYMENT-SUMMARY.md` - Complete system overview
- `CONFIGURATION-GUIDE.md` - Config settings
- `SSMS-DEPLOYMENT-GUIDE.md` - Deployment help

**Quick Test:**
```sql
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

This one command tells you everything!
