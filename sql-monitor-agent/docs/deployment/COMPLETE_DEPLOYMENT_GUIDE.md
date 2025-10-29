# Complete SQL Server Monitoring System Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the complete SQL Server monitoring system from scratch. All components have been tested and validated.

## Prerequisites

- SQL Server 2019+ on Linux (Standard Edition compatible)
- SQL Server Agent installed and running
- User with sysadmin permissions (or db_owner on DBATools)
- Network connectivity to SQL Server

## Connection Details

**Primary (ZeroTier):**
```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools
```

**Alternative (Regular DNS - if available):**
```bash
sqlcmd -S data.schoolvision.net,14333 -U sv -P Gv51076! -C -d DBATools
```

**WSL Note:** Use ZeroTier hostname (svweb) or Windows host IP (172.31.208.1)

## Deployment Sequence

### Step 1: Create Database and Base Tables
**File:** `01_create_DBATools_and_tables.sql`
**Purpose:** Creates DBATools database and foundational tables

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -i 01_create_DBATools_and_tables.sql
```

**Verification:**
```sql
USE DBATools
GO

SELECT name FROM sys.tables ORDER BY name
-- Expected tables: LogEntry, PerfSnapshotRun, PerfSnapshotDB, PerfSnapshotWorkload, PerfSnapshotErrorLog
```

### Step 2: Create Logging Infrastructure
**File:** `02_create_DBA_LogEntry_Insert.sql`
**Purpose:** Creates centralized logging procedure

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i 02_create_DBA_LogEntry_Insert.sql
```

**Verification:**
```sql
-- Test logging procedure
EXEC dbo.DBA_LogEntry_Insert
    @ProcedureName = 'TEST',
    @ProcedureSection = 'VERIFICATION',
    @IsError = 0,
    @ErrDescription = 'Deployment test'

SELECT TOP 1 * FROM dbo.LogEntry ORDER BY LogEntryID DESC
```

### Step 3: Create Configuration System
**File:** `13_create_config_table_and_functions.sql`
**Purpose:** Creates MonitoringConfig table and helper functions

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i 13_create_config_table_and_functions.sql
```

**Verification:**
```sql
-- View configuration
SELECT * FROM dbo.MonitoringConfig ORDER BY ConfigKey

-- Test functions
SELECT dbo.fn_GetConfigInt('QueryStatsTopN') AS QueryStatsTopN
SELECT dbo.fn_GetConfigBit('MonitorSystemDatabases') AS MonitorSystemDatabases
```

### Step 4: Create Database Filter View
**File:** `13b_create_database_filter_view.sql`
**Purpose:** Creates vw_MonitoredDatabases view (excludes offline databases)

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i 13b_create_database_filter_view.sql
```

**Verification:**
```sql
-- View filtered databases
SELECT database_id, database_name, state_desc, recovery_model_desc
FROM dbo.vw_MonitoredDatabases
ORDER BY database_name

-- Count online vs offline
SELECT
    (SELECT COUNT(*) FROM sys.databases WHERE database_id > 4) AS TotalDatabases,
    (SELECT COUNT(*) FROM dbo.vw_MonitoredDatabases) AS MonitoredDatabases,
    (SELECT COUNT(*) FROM sys.databases WHERE database_id > 4 AND state_desc <> 'ONLINE') AS OfflineDatabases
```

### Step 5: Create Enhanced Snapshot Tables
**File:** `05_create_enhanced_tables.sql`
**Purpose:** Creates all P0/P1/P2/P3 snapshot tables

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i 05_create_enhanced_tables.sql
```

**Verification:**
```sql
-- List all snapshot tables
SELECT name FROM sys.tables
WHERE name LIKE 'PerfSnapshot%'
ORDER BY name

-- Expected: 20+ tables (QueryStats, IOStats, Memory, BackupHistory, IndexUsage, etc.)
```

### Step 6: Create P0 (Critical) Collectors
**File:** `06_create_modular_collectors_P0_FIXED.sql`
**Purpose:** Creates P0 collectors (QueryStats, IOStats, Memory, BackupHistory)

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i 06_create_modular_collectors_P0_FIXED.sql
```

**Verification:**
```sql
-- List P0 procedures
SELECT name FROM sys.procedures
WHERE name LIKE 'DBA_Collect_P0%'
ORDER BY name

-- Expected: DBA_Collect_P0_QueryStats, DBA_Collect_P0_IOStats, DBA_Collect_P0_Memory, DBA_Collect_P0_BackupHistory
```

**Test P0 Collectors:**
```bash
bash test-collectors-parallel.sh
# Expected: All collectors complete in 500-560ms
```

### Step 7: Create P1 (Performance) Collectors
**File:** `07_create_modular_collectors_P1_FIXED.sql`
**Purpose:** Creates P1 collectors (IndexUsage, MissingIndexes, WaitStats, TempDBContention, QueryPlans)

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i 07_create_modular_collectors_P1_FIXED.sql
```

**Verification:**
```sql
-- List P1 procedures
SELECT name FROM sys.procedures
WHERE name LIKE 'DBA_Collect_P1%'
ORDER BY name

-- Expected: 5 P1 collectors
```

### Step 8: Create P2/P3 (Medium/Low) Collectors
**File:** `08_create_modular_collectors_P2_P3_FIXED.sql`
**Purpose:** Creates P2 and P3 collectors (ServerConfig, VLFCounts, Deadlocks, Schedulers, PerfCounters, etc.)

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i 08_create_modular_collectors_P2_P3_FIXED.sql
```

**Verification:**
```sql
-- List P2 procedures
SELECT name FROM sys.procedures
WHERE name LIKE 'DBA_Collect_P2%'
ORDER BY name

-- Expected: 6 P2 collectors
```

**Test P2 Collectors:**
```bash
bash test-p2-collectors.sh
# Expected: All collectors complete in 466-520ms
```

### Step 9: Create Master Orchestrator
**File:** `10_create_master_orchestrator_FIXED.sql`
**Purpose:** Creates DBA_CollectPerformanceSnapshot master procedure

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i 10_create_master_orchestrator_FIXED.sql
```

**Verification:**
```sql
-- Verify orchestrator exists
SELECT name FROM sys.procedures
WHERE name = 'DBA_CollectPerformanceSnapshot'

-- Test full collection (P0 + P1 + P2)
EXEC dbo.DBA_CollectPerformanceSnapshot @MaxPriority = 2, @Debug = 1

-- Check results
SELECT TOP 1 * FROM dbo.PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC

-- Expected execution time: <20 seconds for full P0+P1+P2
```

### Step 10: Create Reporting Procedures
**File:** `14_create_reporting_procedures.sql`
**Purpose:** Creates reporting procedures for data visualization

```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i 14_create_reporting_procedures.sql
```

**Verification:**
```sql
-- List reporting procedures
SELECT name FROM sys.procedures
WHERE name LIKE 'DBA_%' AND name NOT LIKE 'DBA_Collect%' AND name NOT LIKE 'DBA_LogEntry%'
ORDER BY name

-- Test reports
EXEC dbo.DBA_CheckSystemHealth
EXEC dbo.DBA_ShowBackupStatus
EXEC dbo.DBA_ShowTopQueries @TopN = 10
```

## Post-Deployment: SQL Agent Job

### Create Automated Collection Job

**File:** `create_agent_job.sql`

```sql
USE msdb
GO

-- Drop existing job if present
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot')
BEGIN
    EXEC dbo.sp_delete_job @job_name = 'DBA Collect Perf Snapshot'
END
GO

-- Create job
EXEC dbo.sp_add_job
    @job_name = N'DBA Collect Perf Snapshot',
    @enabled = 1,
    @description = N'Collects performance snapshot every 5 minutes (P0+P1+P2)',
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sa'
GO

-- Add job step
EXEC dbo.sp_add_jobstep
    @job_name = N'DBA Collect Perf Snapshot',
    @step_name = N'Execute Collection',
    @subsystem = N'TSQL',
    @command = N'EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @MaxPriority = 2, @Debug = 0',
    @database_name = N'DBATools',
    @retry_attempts = 3,
    @retry_interval = 1
GO

-- Schedule: Every 5 minutes
EXEC dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 4,       -- Minutes
    @freq_subday_interval = 5,   -- Every 5 minutes
    @active_start_time = 0       -- Start at midnight
GO

-- Attach schedule to job
EXEC dbo.sp_attach_schedule
    @job_name = N'DBA Collect Perf Snapshot',
    @schedule_name = N'Every 5 Minutes'
GO

-- Add job to local server
EXEC dbo.sp_add_jobserver
    @job_name = N'DBA Collect Perf Snapshot',
    @server_name = N'(LOCAL)'
GO

PRINT 'SQL Agent job created successfully'
PRINT 'Job: DBA Collect Perf Snapshot'
PRINT 'Schedule: Every 5 minutes'
PRINT 'Priority: P0 + P1 + P2'
GO

-- Verify job
SELECT
    j.name AS JobName,
    j.enabled AS JobEnabled,
    s.name AS ScheduleName,
    CASE s.freq_type
        WHEN 4 THEN 'Daily'
        WHEN 8 THEN 'Weekly'
    END AS Frequency,
    'Every ' + CAST(s.freq_subday_interval AS VARCHAR(10)) + ' minutes' AS Interval
FROM dbo.sysjobs j
INNER JOIN dbo.sysjobschedules js ON j.job_id = js.job_id
INNER JOIN dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name = 'DBA Collect Perf Snapshot'
GO
```

**Deploy Agent Job:**
```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -i create_agent_job.sql
```

**Monitor Job Execution:**
```sql
-- View job history (last 20 runs)
SELECT TOP 20
    j.name AS JobName,
    h.run_date,
    h.run_time,
    h.run_duration,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS Status,
    h.message
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name = 'DBA Collect Perf Snapshot'
ORDER BY h.run_date DESC, h.run_time DESC
```

## Post-Deployment: Data Retention

### Create Retention Policy Procedure

**File:** `create_retention_policy.sql`

```sql
USE DBATools
GO

-- =============================================
-- Data Retention Procedure
-- Deletes snapshot data older than specified days
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_PurgeOldSnapshots
    @RetentionDays INT = 14,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_PurgeOldSnapshots'
    DECLARE @CutoffDate DATETIME2(3) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME())
    DECLARE @DeletedRuns INT = 0
    DECLARE @AdditionalInfo VARCHAR(4000)

    BEGIN TRY
        -- Get list of runs to delete
        DECLARE @RunsToDelete TABLE (PerfSnapshotRunID BIGINT)

        INSERT INTO @RunsToDelete
        SELECT PerfSnapshotRunID
        FROM dbo.PerfSnapshotRun
        WHERE SnapshotUTC < @CutoffDate

        SET @DeletedRuns = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            PRINT 'Cutoff Date: ' + CAST(@CutoffDate AS VARCHAR(30))
            PRINT 'Runs to delete: ' + CAST(@DeletedRuns AS VARCHAR(10))
        END

        -- Delete child records first (in priority order for performance)
        DELETE FROM dbo.PerfSnapshotWorkload WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotErrorLog WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotQueryPlans WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotMemoryClerks WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotBackupHistory WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotIndexUsage WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotTempDBContention WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotDB WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotServerConfig WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotVLFCounts WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotDeadlockDetails WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotSchedulerHealth WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotPerfCounters WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotAutogrowthEvents WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotLatchStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotJobHistory WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        DELETE FROM dbo.PerfSnapshotSpinlockStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)

        -- Finally, delete parent records
        DELETE FROM dbo.PerfSnapshotRun WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)

        SET @AdditionalInfo = 'Retention=' + CAST(@RetentionDays AS VARCHAR(10)) + ' days, Deleted=' + CAST(@DeletedRuns AS VARCHAR(10)) + ' runs'

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Purge completed',
                @AdditionalInfo = @AdditionalInfo
        END

        PRINT @AdditionalInfo

        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()

        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'ERROR',
            @IsError = 1,
            @ErrDescription = @ErrMessage,
            @ErrNumber = @ErrNumber,
            @ErrSeverity = @ErrSeverity,
            @ErrState = @ErrState,
            @ErrLine = @ErrLine

        RETURN -1
    END CATCH
END
GO

PRINT 'Retention policy procedure created: dbo.DBA_PurgeOldSnapshots'
PRINT 'Default retention: 14 days'
PRINT 'Usage: EXEC dbo.DBA_PurgeOldSnapshots @RetentionDays = 14, @Debug = 1'
GO
```

**Deploy Retention Procedure:**
```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -d DBATools -i create_retention_policy.sql
```

### Create Retention Agent Job

**File:** `create_retention_job.sql`

```sql
USE msdb
GO

-- Drop existing job if present
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = 'DBA Purge Old Snapshots')
BEGIN
    EXEC dbo.sp_delete_job @job_name = 'DBA Purge Old Snapshots'
END
GO

-- Create job
EXEC dbo.sp_add_job
    @job_name = N'DBA Purge Old Snapshots',
    @enabled = 1,
    @description = N'Purges snapshot data older than 14 days (runs daily at 2 AM)',
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sa'
GO

-- Add job step
EXEC dbo.sp_add_jobstep
    @job_name = N'DBA Purge Old Snapshots',
    @step_name = N'Execute Purge',
    @subsystem = N'TSQL',
    @command = N'EXEC DBATools.dbo.DBA_PurgeOldSnapshots @RetentionDays = 14, @Debug = 1',
    @database_name = N'DBATools',
    @retry_attempts = 2,
    @retry_interval = 5
GO

-- Schedule: Daily at 2 AM
EXEC dbo.sp_add_schedule
    @schedule_name = N'Daily 2 AM',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 1,       -- Once
    @active_start_time = 20000   -- 2:00 AM
GO

-- Attach schedule to job
EXEC dbo.sp_attach_schedule
    @job_name = N'DBA Purge Old Snapshots',
    @schedule_name = N'Daily 2 AM'
GO

-- Add job to local server
EXEC dbo.sp_add_jobserver
    @job_name = N'DBA Purge Old Snapshots',
    @server_name = N'(LOCAL)'
GO

PRINT 'Retention job created successfully'
PRINT 'Job: DBA Purge Old Snapshots'
PRINT 'Schedule: Daily at 2:00 AM'
PRINT 'Retention: 14 days'
GO
```

**Deploy Retention Job:**
```bash
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -i create_retention_job.sql
```

## Performance Validation

### Expected Performance Metrics

**Individual Collectors:**
- P0 collectors: 500-560ms each
- P1 collectors: 512-560ms each
- P2 collectors: 466-520ms each

**Full Orchestrated Collection:**
- P0 + P1 + P2: <20 seconds
- P0 only: <5 seconds
- P0 + P1 only: <10 seconds

### Performance Test Scripts

**Test P0 + P1 Collectors (Parallel):**
```bash
bash test-collectors-parallel.sh
```

**Test P2 Collectors:**
```bash
bash test-p2-collectors.sh
```

**Test Full Collection:**
```sql
SET STATISTICS TIME ON
EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @MaxPriority = 2, @Debug = 1
SET STATISTICS TIME OFF
```

### Monitor Collection History

```sql
-- View recent collections with timing
SELECT TOP 20
    PerfSnapshotRunID,
    SnapshotUTC,
    ServerName,
    SqlVersion,
    CpuSignalWaitPct,
    ActiveSessionCount,
    ActiveRequestCount,
    BlockingSessionCount,
    RecentDeadlockCount,
    TopWaitType,
    TopWaitTimeMs,
    DATEDIFF(SECOND, LAG(SnapshotUTC) OVER (ORDER BY SnapshotUTC), SnapshotUTC) AS SecondsSinceLastSnapshot
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC
```

## Troubleshooting

### Connection Issues

**Symptom:** "Login failed for user 'sv'"

**Diagnostics:**
```bash
# Test network connectivity
ping svweb

# Test SQL Server reachable
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -Q "SELECT @@VERSION"

# Check connection count
sqlcmd -S svweb,14333 -U sv -P Gv51076! -C -Q "EXEC sp_who"
```

**Possible Causes:**
1. ZeroTier VPN disconnected/unstable
2. SQL Server max connections reached (check sp_who)
3. SQL Server login disabled or locked
4. Network firewall blocking port 14333

**Solutions:**
1. Restart ZeroTier: `sudo systemctl restart zerotier-one`
2. Wait 2-3 minutes for connection cleanup
3. Try alternative connection method (Windows host IP: 172.31.208.1,14333)
4. Check SQL Server error log for authentication failures

### Collection Hangs or Timeouts

**Symptom:** Collection takes >60 seconds or times out

**Diagnostics:**
```sql
-- Check for blocking
SELECT
    blocking.session_id AS BlockingSessionID,
    blocked.session_id AS BlockedSessionID,
    blocked.wait_type,
    blocked.wait_time,
    blocked.wait_resource,
    blocking_text.text AS BlockingSQL,
    blocked_text.text AS BlockedSQL
FROM sys.dm_exec_requests blocked
INNER JOIN sys.dm_exec_requests blocking ON blocked.blocking_session_id = blocking.session_id
CROSS APPLY sys.dm_exec_sql_text(blocking.sql_handle) blocking_text
CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle) blocked_text
WHERE blocked.session_id <> blocked.blocking_session_id

-- Check for long-running queries
SELECT
    session_id,
    start_time,
    DATEDIFF(SECOND, start_time, GETDATE()) AS ElapsedSeconds,
    status,
    command,
    wait_type,
    wait_time,
    cpu_time,
    logical_reads,
    t.text AS SqlText
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE session_id > 50
ORDER BY ElapsedSeconds DESC
```

**Known Issue:** XEvent XML parsing can hang if system_health ring buffer is large

**Solution:** Already implemented in 10_create_master_orchestrator_FIXED.sql:
- XML loaded into variable (avoids repeated DMV access)
- Timestamp filtering during shredding
- TRY/CATCH wrapper for graceful failure

### Zero Rows Collected

**Symptom:** Snapshot runs but no data in child tables

**Diagnostics:**
```sql
-- Check if collectors exist
SELECT name FROM sys.procedures
WHERE name LIKE 'DBA_Collect%'
ORDER BY name

-- Check for errors in log
SELECT TOP 20 *
FROM DBATools.dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC

-- Test individual collector
DECLARE @TestRunID BIGINT
INSERT INTO DBATools.dbo.PerfSnapshotRun (SnapshotUTC, ServerName)
VALUES (SYSUTCDATETIME(), @@SERVERNAME)
SET @TestRunID = SCOPE_IDENTITY()

EXEC DBATools.dbo.DBA_Collect_P0_QueryStats @TestRunID, 1

-- Check results
SELECT * FROM DBATools.dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID = @TestRunID
```

### Agent Job Not Running

**Symptom:** No new snapshots after enabling job

**Diagnostics:**
```sql
-- Check if SQL Server Agent is running
EXEC xp_servicecontrol 'QueryState', 'SQLServerAGENT'

-- Check job status
SELECT
    j.name,
    j.enabled AS JobEnabled,
    js.last_run_date,
    js.last_run_time,
    CASE js.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 5 THEN 'Unknown'
    END AS LastOutcome
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
WHERE j.name = 'DBA Collect Perf Snapshot'
```

**Linux Note:** Ensure SQL Server Agent is enabled and started:
```bash
sudo /opt/mssql/bin/mssql-conf set sqlagent.enabled true
sudo systemctl restart mssql-server
sudo systemctl status mssql-server
```

## Summary

**Deployment Steps:**
1. Create database and tables (01)
2. Create logging infrastructure (02)
3. Create config system (13)
4. Create database filter view (13b)
5. Create enhanced tables (05)
6. Create P0 collectors (06)
7. Create P1 collectors (07)
8. Create P2/P3 collectors (08)
9. Create master orchestrator (10)
10. Create reporting procedures (14)

**Post-Deployment:**
11. Create SQL Agent job for 5-minute collection
12. Create retention policy procedure
13. Create retention job for daily purge (2 AM)

**Expected Results:**
- Collection every 5 minutes
- <20 seconds per collection (P0+P1+P2)
- 14-day retention (configurable)
- Minimal performance overhead
- 39 online databases monitored (46 offline excluded)

**Key Performance Optimizations:**
- XEvent XML variable loading (avoids 120+ second hangs)
- sys.dm_io_virtual_file_stats for file sizes (avoids offline DB issues)
- vw_MonitoredDatabases filtering (reduces scope)
- NOLOCK hints on metadata queries
- TRY/CATCH wrappers for graceful failures
