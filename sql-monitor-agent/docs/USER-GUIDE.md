# SQL Server Monitoring System - User Guide for Non-DBAs

## Table of Contents
1. [Quick Start](#quick-start)
2. [Understanding Key Metrics](#understanding-key-metrics)
3. [Common Problems & Solutions](#common-problems--solutions)
4. [Where to Look When Issues Arise](#where-to-look-when-issues-arise)
5. [Daily Health Checks](#daily-health-checks)
6. [Weekly Reviews](#weekly-reviews)
7. [Troubleshooting Scenarios](#troubleshooting-scenarios)

---

## Quick Start

### What is This System?

This monitoring system captures snapshots of your SQL Server's performance every 5 minutes, storing:
- Which queries are running slow
- What databases need indexes
- Which sessions are blocking others
- Memory and disk usage
- Backup status

Think of it as a "black box recorder" for your database server.

### How to Access the Data

All monitoring data is in the `DBATools` database. Connect using:

**SQL Server Management Studio (SSMS):**
```
Server: your-server-name,port
Database: DBATools
Authentication: Windows or SQL Server
```

**Quick Health Check:**
```sql
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

---

## Understanding Key Metrics

### 1. CPU Signal Wait Percentage

**What it means:** Percentage of time SQL Server is waiting for CPU (not getting enough CPU).

**Normal:** 0-20%
**Warning:** 20-40%
**Critical:** >40%

**What it tells you:**
- **Low (<20%):** Server has plenty of CPU capacity
- **High (>40%):** Server is CPU-bound, needs more CPU power or query optimization

**What to do:**
```sql
-- Find CPU-intensive queries
SELECT TOP 10 DatabaseName, SqlText, AvgCpuMs, ExecutionCount
FROM DBATools.dbo.PerfSnapshotQueryStats
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
ORDER BY AvgCpuMs DESC
```

**Action:**
- Optimize the slowest queries
- Add missing indexes
- Consider scaling up (more CPU) or out (distribute load)

---

### 2. Blocking Sessions

**What it means:** Number of database sessions that are preventing other sessions from working.

**Normal:** 0-5
**Warning:** 5-20
**Critical:** >20

**What it tells you:**
- Users are waiting on each other to finish work
- Can cause application slowdowns or timeouts
- Often caused by long-running transactions or missing indexes

**What to do:**
```sql
-- See current blocking chains
SELECT 
    SessionID,
    LoginName,
    DatabaseName,
    Status,
    Command,
    BlockingSessionID,
    WaitType,
    SqlText
FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
  AND BlockingSessionID IS NOT NULL
ORDER BY BlockingSessionID
```

**Understanding the Output:**
- **BlockingSessionID:** The session causing the wait
- **WaitType:** What they're waiting for (e.g., LCK_M_X = lock wait)
- **SqlText:** What query is blocked

**Action:**
1. Find the "blocker" (session that others are waiting on)
2. Check if it's a long-running query that needs optimization
3. If stuck, may need to kill the blocking session (KILL [SessionID])
4. Look for missing indexes on frequently blocked tables

---

### 3. Deadlocks

**What it means:** Two sessions are waiting for each other (circular wait), SQL Server kills one.

**Normal:** 0-1 per day
**Warning:** 2-10 per day
**Critical:** >10 per day

**What it tells you:**
- Application has conflicting transaction logic
- Usually requires code changes, not SQL Server tuning

**What to do:**
```sql
-- Check recent deadlock count
SELECT TOP 5
    SnapshotUTC,
    DeadlockCountRecent,
    BlockingSessionCount
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC
```

**Action:**
- Check SQL Server error log for detailed deadlock graphs (our system auto-enables trace flags when deadlocks detected)
- Look for pattern: which tables, which operations
- Usually requires changing application transaction order
- Add indexes to reduce lock duration

---

### 4. Top Wait Type

**What it means:** What SQL Server is spending most time waiting on.

**Common Wait Types:**

| Wait Type | What It Means | What To Do |
|-----------|---------------|------------|
| **PAGEIOLATCH_SH** | Reading data from disk (slow I/O) | Add indexes, increase memory, faster disks |
| **CXPACKET** | Parallel query coordination | Usually normal; if excessive, tune Max Degree of Parallelism |
| **LCK_M_X** | Lock waits (blocking) | See Blocking Sessions section above |
| **ASYNC_NETWORK_IO** | Waiting for application to consume results | Application issue, not SQL Server |
| **WRITELOG** | Writing to transaction log (slow disk) | Faster log disk, optimize transactions |
| **SOS_SCHEDULER_YIELD** | CPU pressure | Need more CPU or query optimization |

**What to do:**
```sql
-- See current wait stats
SELECT TOP 10 WaitType, WaitingTasksCount, WaitTimeMs, AvgWaitTimeMs
FROM DBATools.dbo.PerfSnapshotWaitStats
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
ORDER BY WaitTimeMs DESC
```

---

### 5. Memory Usage

**What it means:** How much memory SQL Server is using vs available.

**What to do:**
```sql
-- Check memory usage
SELECT 
    ServerName,
    SnapshotUTC,
    -- Convert pages to MB (8KB per page)
    (SELECT CAST(value AS BIGINT) * 8 / 1024 
     FROM DBATools.dbo.PerfSnapshotMemory 
     WHERE PerfSnapshotRunID = r.PerfSnapshotRunID 
       AND CounterName = 'Database Cache Memory (KB)') AS DatabaseCacheMB,
    (SELECT CAST(value AS BIGINT) * 8 / 1024 
     FROM DBATools.dbo.PerfSnapshotMemory 
     WHERE PerfSnapshotRunID = r.PerfSnapshotRunID 
       AND CounterName = 'Free Memory (KB)') AS FreeMB
FROM DBATools.dbo.PerfSnapshotRun r
ORDER BY PerfSnapshotRunID DESC
```

**Understanding:**
- SQL Server uses memory for caching data (good!)
- Low free memory is normal (SQL Server uses what's available)
- Memory pressure = SQL Server can't allocate enough memory

**Action if memory pressure:**
- Add more RAM
- Reduce SQL Server max memory setting (if other apps need memory)
- Optimize queries to use less memory

---

### 6. Missing Indexes

**What it means:** SQL Server recommends adding indexes to speed up queries.

**What to do:**
```sql
-- See top missing index recommendations
SELECT TOP 10
    DatabaseName,
    ObjectName,
    EqualityColumns,
    InequalityColumns,
    IncludedColumns,
    UserSeeks + UserScans AS TotalUses,
    ImpactScore
FROM DBATools.dbo.PerfSnapshotMissingIndexes
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
ORDER BY ImpactScore DESC
```

**Understanding the Output:**
- **EqualityColumns:** Columns in WHERE clause (col = value)
- **InequalityColumns:** Columns with >, <, BETWEEN, etc.
- **IncludedColumns:** Other columns query needs
- **ImpactScore:** Higher = more benefit (prioritize these)

**How to Create Index:**
```sql
-- Example index creation (modify for your table)
CREATE NONCLUSTERED INDEX IX_TableName_ColumnName
ON SchemaName.TableName (EqualityColumn1, EqualityColumn2)
INCLUDE (IncludedColumn1, IncludedColumn2)
```

**⚠️ Warning:** Don't blindly create all suggested indexes!
- Too many indexes slow down INSERT/UPDATE/DELETE
- Consult a DBA for high-traffic tables
- Test impact before deploying to production

---

### 7. Slow Queries

**What it means:** Queries taking long time to complete.

**What to do:**
```sql
-- Find slowest queries (by average elapsed time)
SELECT TOP 20
    DatabaseName,
    ObjectName,
    LEFT(SqlText, 100) AS SqlTextPreview,
    ExecutionCount,
    AvgElapsedMs,
    AvgCpuMs,
    AvgLogicalReads,
    LastExecutionTime
FROM DBATools.dbo.PerfSnapshotQueryStats
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
ORDER BY AvgElapsedMs DESC
```

**Understanding:**
- **AvgElapsedMs:** Total time query took (wall clock)
- **AvgCpuMs:** CPU time used by query
- **AvgLogicalReads:** Amount of data read (higher = more disk I/O)
- **ExecutionCount:** How often query runs

**Priority:**
- Focus on queries with high ExecutionCount AND high AvgElapsedMs
- A query running 10,000 times at 100ms = more impact than 1 query at 10 seconds

**Action:**
1. Check for missing indexes (see Missing Indexes section)
2. Look at execution plan (SSMS → Display Estimated Execution Plan)
3. Consider rewriting query if it's inefficient
4. Check if data volume is issue (large tables without proper indexes)

---

### 8. Database Backup Status

**What it means:** When databases were last backed up.

**What to do:**
```sql
-- Check backup status
SELECT 
    DatabaseName,
    RecoveryModel,
    LastFullBackup,
    LastLogBackup,
    DATEDIFF(HOUR, LastFullBackup, GETUTCDATE()) AS HoursSinceFullBackup,
    DATEDIFF(MINUTE, LastLogBackup, GETUTCDATE()) AS MinutesSinceLogBackup
FROM DBATools.dbo.PerfSnapshotBackupHistory
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
ORDER BY HoursSinceFullBackup DESC
```

**Understanding Recovery Models:**
- **SIMPLE:** No log backups needed, can only restore to last full backup
- **FULL:** Requires log backups, can do point-in-time recovery
- **BULK_LOGGED:** Like FULL but optimized for bulk operations

**⚠️ Red Flags:**
- Full backup older than 24 hours
- Log backup older than 60 minutes (for FULL recovery model)
- Database showing NULL for backups (never been backed up!)

**Action:**
- Verify backup jobs are running
- Check disk space on backup destination
- Review backup job history for failures

---

## Common Problems & Solutions

### Problem: "Application is Slow"

**Step 1: Quick Health Check**
```sql
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

**Step 2: Check for Blocking**
```sql
SELECT BlockingSessionCount 
FROM DBATools.dbo.PerfSnapshotRun 
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
```
- If >10: See "Blocking Sessions" section above

**Step 3: Check CPU**
```sql
SELECT CpuSignalWaitPct 
FROM DBATools.dbo.PerfSnapshotRun 
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
```
- If >40%: CPU pressure, see "CPU Signal Wait" section

**Step 4: Check Wait Type**
```sql
SELECT TopWaitType 
FROM DBATools.dbo.PerfSnapshotRun 
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
```
- Look up wait type in "Top Wait Type" section above

---

### Problem: "Out of Disk Space"

**Check Database Sizes:**
```sql
SELECT 
    DatabaseName,
    DataSizeMB,
    LogSizeMB,
    DataSizeMB + LogSizeMB AS TotalMB
FROM DBATools.dbo.PerfSnapshotDB
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
ORDER BY TotalMB DESC
```

**Check Growth Trend:**
```sql
-- Compare size over time
SELECT 
    r.SnapshotUTC,
    db.DatabaseName,
    db.DataSizeMB,
    db.LogSizeMB
FROM DBATools.dbo.PerfSnapshotDB db
JOIN DBATools.dbo.PerfSnapshotRun r ON db.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE db.DatabaseName = 'YourDatabaseName'
  AND r.SnapshotUTC >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY r.SnapshotUTC DESC
```

**Common Causes:**
- Transaction log not being backed up (FULL recovery model)
- Large table without proper maintenance
- Autogrowth settings too aggressive

**Action:**
1. If log file is large: Backup transaction log, then shrink
2. Review growth settings (right-click DB → Properties → Files)
3. Consider archiving old data
4. Add disk space if legitimate growth

---

### Problem: "Backup Failed"

**Check Backup History:**
```sql
SELECT 
    DatabaseName,
    LastFullBackup,
    LastLogBackup,
    BackupSizeMB
FROM DBATools.dbo.PerfSnapshotBackupHistory
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
  AND LastFullBackup IS NULL
```

**Check SQL Agent Job History:**
```sql
-- Run on server (not in DBATools)
EXEC msdb.dbo.sp_help_jobhistory 
    @job_name = 'YourBackupJobName',
    @mode = 'FULL'
```

**Common Causes:**
- Insufficient disk space on backup destination
- Network path unavailable
- SQL Agent service not running
- Permissions issue on backup folder

---

### Problem: "Users Getting Timeout Errors"

**Check Active Workload:**
```sql
SELECT 
    SessionID,
    LoginName,
    DatabaseName,
    Status,
    Command,
    WaitType,
    CpuTimeMs,
    DATEDIFF(SECOND, StartTime, GETUTCDATE()) AS RunningSeconds,
    SqlText
FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
  AND Status = 'running'
ORDER BY RunningSeconds DESC
```

**Look For:**
- Long-running queries (>60 seconds)
- Blocking (BlockingSessionID IS NOT NULL)
- Many sessions from same application

**Common Causes:**
1. **Blocking:** See "Blocking Sessions" section
2. **Slow Query:** Missing indexes, needs optimization
3. **Parameter Sniffing:** Query plan cached for different data pattern
4. **Application Issue:** Inefficient logic, N+1 query pattern

---

## Where to Look When Issues Arise

### Issue: Performance Degradation

**Timeline: Last Hour**
```sql
-- See performance trend over last hour
SELECT 
    SnapshotUTC,
    CpuSignalWaitPct,
    BlockingSessionCount,
    SessionsCount,
    RequestsCount,
    TopWaitType
FROM DBATools.dbo.PerfSnapshotRun
WHERE SnapshotUTC >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY SnapshotUTC DESC
```

**Timeline: Last Day**
```sql
-- Daily pattern (shows every 12th snapshot = hourly)
SELECT 
    SnapshotUTC,
    CpuSignalWaitPct,
    BlockingSessionCount
FROM (
    SELECT 
        SnapshotUTC,
        CpuSignalWaitPct,
        BlockingSessionCount,
        ROW_NUMBER() OVER(ORDER BY PerfSnapshotRunID DESC) AS RowNum
    FROM DBATools.dbo.PerfSnapshotRun
    WHERE SnapshotUTC >= DATEADD(DAY, -1, GETUTCDATE())
) x
WHERE RowNum % 12 = 0  -- Every hour
ORDER BY SnapshotUTC DESC
```

---

### Issue: Identify Problem Database

```sql
-- Find busiest databases by query activity
SELECT 
    DatabaseName,
    COUNT(*) AS QueryCount,
    AVG(AvgElapsedMs) AS AvgElapsedMs,
    SUM(ExecutionCount) AS TotalExecutions,
    AVG(AvgLogicalReads) AS AvgLogicalReads
FROM DBATools.dbo.PerfSnapshotQueryStats
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
GROUP BY DatabaseName
ORDER BY TotalExecutions DESC
```

---

### Issue: Find Problem Application/User

```sql
-- See which logins are most active
SELECT 
    LoginName,
    COUNT(*) AS SessionCount,
    AVG(CpuTimeMs) AS AvgCpuMs,
    SUM(LogicalReads) AS TotalReads
FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
GROUP BY LoginName
ORDER BY TotalReads DESC
```

---

## Daily Health Checks

**Morning Routine (5 minutes):**

```sql
-- 1. Quick health check
EXEC DBATools.dbo.DBA_CheckSystemHealth

-- 2. Check overnight issues
SELECT TOP 5
    SnapshotUTC,
    BlockingSessionCount,
    DeadlockCountRecent,
    CpuSignalWaitPct
FROM DBATools.dbo.PerfSnapshotRun
WHERE SnapshotUTC >= DATEADD(DAY, -1, GETUTCDATE())
  AND (BlockingSessionCount > 20 
       OR DeadlockCountRecent > 0 
       OR CpuSignalWaitPct > 40)
ORDER BY SnapshotUTC DESC

-- 3. Check backup status
EXEC DBATools.dbo.DBA_ShowBackupStatus

-- 4. Check SQL Agent job failures
EXEC msdb.dbo.sp_help_jobhistory 
    @mode = 'FULL',
    @start_run_date = CONVERT(INT, CONVERT(VARCHAR(8), DATEADD(DAY, -1, GETDATE()), 112)),
    @run_status = 0  -- 0 = failed
```

---

## Weekly Reviews

**Monday Morning Review (15 minutes):**

```sql
-- 1. Top 10 slowest queries last week
SELECT TOP 10
    DatabaseName,
    LEFT(SqlText, 100) AS SqlPreview,
    AVG(AvgElapsedMs) AS AvgElapsedMs,
    SUM(ExecutionCount) AS TotalExecutions,
    MAX(LastExecutionTime) AS LastSeen
FROM DBATools.dbo.PerfSnapshotQueryStats qs
JOIN DBATools.dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE r.SnapshotUTC >= DATEADD(DAY, -7, GETUTCDATE())
GROUP BY DatabaseName, SqlText
ORDER BY AvgElapsedMs DESC

-- 2. Database growth trend
SELECT 
    DatabaseName,
    MIN(DataSizeMB) AS MinSizeMB,
    MAX(DataSizeMB) AS MaxSizeMB,
    MAX(DataSizeMB) - MIN(DataSizeMB) AS GrowthMB
FROM DBATools.dbo.PerfSnapshotDB db
JOIN DBATools.dbo.PerfSnapshotRun r ON db.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE r.SnapshotUTC >= DATEADD(DAY, -7, GETUTCDATE())
GROUP BY DatabaseName
HAVING MAX(DataSizeMB) - MIN(DataSizeMB) > 100  -- More than 100MB growth
ORDER BY GrowthMB DESC

-- 3. Top missing indexes that appeared consistently
SELECT 
    DatabaseName,
    ObjectName,
    EqualityColumns,
    IncludedColumns,
    COUNT(*) AS AppearanceCount,
    AVG(ImpactScore) AS AvgImpact
FROM DBATools.dbo.PerfSnapshotMissingIndexes mi
JOIN DBATools.dbo.PerfSnapshotRun r ON mi.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE r.SnapshotUTC >= DATEADD(DAY, -7, GETUTCDATE())
GROUP BY DatabaseName, ObjectName, EqualityColumns, IncludedColumns
HAVING COUNT(*) > 10  -- Appeared in >10 snapshots
ORDER BY AvgImpact DESC
```

---

## Troubleshooting Scenarios

### Scenario 1: "Database is Slow Right Now"

**Real-Time Investigation:**

```sql
-- Step 1: What's running now?
SELECT 
    SessionID,
    LoginName,
    Status,
    Command,
    WaitType,
    DATEDIFF(SECOND, StartTime, GETUTCDATE()) AS Seconds,
    LEFT(SqlText, 200) AS Query
FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
  AND Status IN ('running', 'runnable', 'suspended')
ORDER BY Seconds DESC

-- Step 2: Any blocking?
SELECT 
    'BLOCKER' AS Type, SessionID, LoginName, Status, LEFT(SqlText, 100) AS Query
FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
  AND SessionID IN (SELECT DISTINCT BlockingSessionID 
                    FROM DBATools.dbo.PerfSnapshotWorkload 
                    WHERE BlockingSessionID IS NOT NULL)

UNION ALL

SELECT 
    'BLOCKED' AS Type, SessionID, LoginName, Status, LEFT(SqlText, 100) AS Query
FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
  AND BlockingSessionID IS NOT NULL
ORDER BY Type, SessionID

-- Step 3: System health
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

**If You Need to Kill a Session:**
```sql
-- Only do this if absolutely necessary!
-- Make sure you're killing the right session
KILL [SessionID]
```

---

### Scenario 2: "Performance Was Bad Yesterday at 3 PM"

**Historical Investigation:**

```sql
-- Find snapshots around that time
DECLARE @TargetTime DATETIME = '2025-10-27 15:00:00'  -- Adjust date/time

-- Step 1: System state at that time
SELECT TOP 5
    SnapshotUTC,
    CpuSignalWaitPct,
    BlockingSessionCount,
    DeadlockCountRecent,
    TopWaitType,
    SessionsCount,
    RequestsCount
FROM DBATools.dbo.PerfSnapshotRun
WHERE SnapshotUTC BETWEEN DATEADD(MINUTE, -10, @TargetTime) 
                     AND DATEADD(MINUTE, 10, @TargetTime)
ORDER BY SnapshotUTC

-- Step 2: What queries were running?
SELECT 
    r.SnapshotUTC,
    w.DatabaseName,
    w.LoginName,
    w.Status,
    w.WaitType,
    LEFT(w.SqlText, 200) AS Query,
    w.CpuTimeMs,
    w.LogicalReads
FROM DBATools.dbo.PerfSnapshotWorkload w
JOIN DBATools.dbo.PerfSnapshotRun r ON w.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE r.SnapshotUTC BETWEEN DATEADD(MINUTE, -10, @TargetTime) 
                        AND DATEADD(MINUTE, 10, @TargetTime)
ORDER BY w.CpuTimeMs DESC
```

---

### Scenario 3: "Need to Find When Problem Started"

**Trend Analysis:**

```sql
-- Blocking trend over last 24 hours
SELECT 
    DATEPART(HOUR, SnapshotUTC) AS Hour,
    AVG(BlockingSessionCount) AS AvgBlocking,
    MAX(BlockingSessionCount) AS MaxBlocking,
    COUNT(*) AS Snapshots
FROM DBATools.dbo.PerfSnapshotRun
WHERE SnapshotUTC >= DATEADD(DAY, -1, GETUTCDATE())
GROUP BY DATEPART(HOUR, SnapshotUTC)
ORDER BY Hour

-- CPU trend
SELECT 
    DATEPART(HOUR, SnapshotUTC) AS Hour,
    AVG(CpuSignalWaitPct) AS AvgCpu,
    MAX(CpuSignalWaitPct) AS MaxCpu
FROM DBATools.dbo.PerfSnapshotRun
WHERE SnapshotUTC >= DATEADD(DAY, -1, GETUTCDATE())
GROUP BY DATEPART(HOUR, SnapshotUTC)
ORDER BY Hour
```

---

## When to Escalate to a DBA

**Escalate immediately if:**
- Blocking sessions >50 and not resolving
- Deadlocks >20 in an hour
- CPU Signal Wait >80%
- Database corruption detected
- Backup failures for >24 hours

**Escalate within 1 hour if:**
- Blocking sessions >20 for >30 minutes
- Consistent slowness not explained by monitoring data
- Unusual wait types you don't recognize
- Memory pressure warnings
- Log file growing uncontrollably

**Can handle yourself:**
- Creating suggested indexes (after testing!)
- Killing runaway query sessions
- Basic backup troubleshooting
- Routine monitoring and reporting

---

## Quick Reference Card

### Most Useful Queries

**System Health:**
```sql
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

**Backup Status:**
```sql
EXEC DBATools.dbo.DBA_ShowBackupStatus
```

**Current Blocking:**
```sql
SELECT SessionID, BlockingSessionID, LoginName, DatabaseName, 
       LEFT(SqlText, 100) AS Query
FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) 
                           FROM DBATools.dbo.PerfSnapshotRun)
  AND BlockingSessionID IS NOT NULL
```

**Slow Queries:**
```sql
SELECT TOP 10 DatabaseName, LEFT(SqlText, 100) AS Query, 
       AvgElapsedMs, ExecutionCount
FROM DBATools.dbo.PerfSnapshotQueryStats
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) 
                           FROM DBATools.dbo.PerfSnapshotRun)
ORDER BY AvgElapsedMs DESC
```

**Missing Indexes:**
```sql
SELECT TOP 10 DatabaseName, ObjectName, EqualityColumns, 
       IncludedColumns, ImpactScore
FROM DBATools.dbo.PerfSnapshotMissingIndexes
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) 
                           FROM DBATools.dbo.PerfSnapshotRun)
ORDER BY ImpactScore DESC
```

---

## Need Help?

- **Documentation:** See `docs/` folder
- **Configuration:** `docs/reference/CONFIGURATION-GUIDE.md`
- **Troubleshooting:** `docs/troubleshooting/`
- **DBA Escalation:** Contact your DBA team with:
  - Timestamp of issue
  - Symptoms observed
  - Query results from this guide
  - Any error messages

---

**Last Updated:** October 27, 2025  
**Version:** 2.0
