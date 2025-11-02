# Deploy Query Analysis Features to Remote Servers

**Date**: 2025-10-31
**Purpose**: Deploy Phase 2 Query Analysis features to svweb and suncity servers

## Deployment Status

| Server | ServerID | Environment | Status | Last Modified |
|--------|----------|-------------|--------|---------------|
| sqltest.schoolvision.net,14333 | 1 | Test | ✅ Deployed | 2025-10-31 04:38 UTC |
| svweb,14333 | 5 | Production | ⏳ Pending | - |
| suncity.schoolvision.net,14333 | 4 | Production | ⏳ Pending | - |

## What Gets Deployed

### 1. Query Analysis Tables (database/31-create-query-analysis-tables.sql)

Creates 10 new tables for 4 priority features:

**Query Store Integration**:
- `QueryStoreQueries` - Query text and metadata
- `QueryStoreRuntimeStats` - Execution statistics (partitioned monthly)

**Blocking/Deadlock Detection**:
- `BlockingEvents` - Real-time blocking chains (partitioned monthly)
- `DeadlockEvents` - Deadlock graphs from Extended Events (partitioned monthly)

**Wait Statistics Analysis**:
- `WaitStatsSnapshot` - Point-in-time wait stats (partitioned monthly)
- `WaitStatsDelta` - Calculated deltas between snapshots (partitioned monthly)
- `WaitStatsBaseline` - Hourly/daily/weekly baselines for anomaly detection

**Index Optimization**:
- `IndexFragmentation` - Fragmentation scans (partitioned monthly)
- `MissingIndexRecommendations` - DMV-based missing index suggestions (partitioned monthly)
- `UnusedIndexes` - Index usage statistics (partitioned monthly)

### 2. Query Analysis Procedures (database/32-create-query-analysis-procedures.sql)

Creates 8 stored procedures:

**Collection Procedures**:
- `usp_CollectQueryStoreStats` - Query Store data collection
- `usp_CollectBlockingEvents` - Real-time blocking detection (>5 sec blocks)
- `usp_CollectDeadlockEvents` - Parse system_health Extended Events ring buffer
- `usp_CollectWaitStatsSnapshot` - Capture current wait stats
- `usp_CollectIndexFragmentation` - Scan index fragmentation (manual/scheduled)
- `usp_CollectMissingIndexes` - Capture missing index DMV data
- `usp_CollectUnusedIndexes` - Identify unused indexes

**Master Collection**:
- `usp_CollectAllQueryAnalysisMetrics` - Calls all collection procedures with error handling

### 3. Deadlock Trace Flags (database/33-configure-deadlock-trace-flags.sql)

Configures SQL Server for enhanced deadlock monitoring:

**Trace Flag 1222**:
- Writes detailed deadlock graphs to SQL Server error log
- Zero performance overhead (only activates on deadlock)
- Industry best practice

**Extended Events Session**:
- Creates `deadlock_monitor` session
- Captures deadlock events to files (200 MB total)
- 4 MB in-memory ring buffer for quick access
- Auto-starts on SQL Server restart

## Deployment Instructions

### Architecture Note

**MonitoringDB Location**: The MonitoringDB database is hosted on **sqltest.schoolvision.net,14333**.

**Collection Pattern**:
- Local servers (svweb, suncity) run SQL Agent jobs every 5 minutes
- Jobs use **OPENQUERY** or **linked servers** to call procedures on sqltest's MonitoringDB
- Example:
  ```sql
  -- Run from svweb or suncity SQL Agent job
  EXEC [sqltest.schoolvision.net,14333].[MonitoringDB].[dbo].[usp_CollectAllQueryAnalysisMetrics] @ServerID = 5;
  ```

**What This Means**:
- ✅ Tables and procedures only need to exist on **sqltest** (already deployed)
- ✅ Trace flags need to be enabled on **each monitored server** (svweb, suncity)
- ✅ SQL Agent jobs on svweb/suncity need to be updated to call the new procedure

### Step 1: Deploy to sqltest (COMPLETED ✅)

Already deployed on 2025-10-31 04:38 UTC. Verified with:

```sql
SELECT
    'sqltest' AS ServerName,
    OBJECT_NAME(object_id) AS ProcedureName,
    modify_date AS LastModified
FROM sys.objects
WHERE type = 'P'
  AND name IN (
    'usp_CollectAllQueryAnalysisMetrics',
    'usp_CollectBlockingEvents',
    'usp_CollectDeadlockEvents',
    'usp_CollectWaitStatsSnapshot',
    'usp_CollectQueryStoreStats',
    'usp_CollectIndexFragmentation',
    'usp_CollectMissingIndexes',
    'usp_CollectUnusedIndexes'
  )
ORDER BY ProcedureName;
```

### Step 2: Enable Trace Flags on svweb and suncity (REQUIRED)

**On svweb server** (connect to `svweb,14333`):

```sql
-- Connect to svweb
sqlcmd -S svweb,14333 -U sv -P YourPassword -C -d master -i database/33-configure-deadlock-trace-flags.sql
```

**On suncity server** (connect to `suncity.schoolvision.net,14333`):

```sql
-- Connect to suncity
sqlcmd -S suncity.schoolvision.net,14333 -U sv -P YourPassword -C -d master -i database/33-configure-deadlock-trace-flags.sql
```

**What this does**:
- Enables Trace Flag 1222 globally (persists across restarts)
- Creates `deadlock_monitor` Extended Events session
- Verifies configuration

**Verification**:

```sql
-- Verify trace flag enabled
DBCC TRACESTATUS(1222);
-- Expected: TraceFlag=1222, Status=1, Global=1

-- Verify Extended Events session running
SELECT name, create_time
FROM sys.dm_xe_sessions
WHERE name = 'deadlock_monitor';
-- Expected: 1 row
```

### Step 3: Update SQL Agent Jobs on svweb and suncity (REQUIRED)

**Current Job Structure** (example from sqltest):
- Job Name: `SQL Monitor - Collect Metrics (sqltest)`
- Step 1: `Collect All Metrics (Local)` (calls existing collection procedure)

**Required Change**: Add Step 2 to call query analysis collection

**On svweb server**:

```sql
USE msdb;
GO

-- Find the job
DECLARE @job_id UNIQUEIDENTIFIER;
SELECT @job_id = job_id FROM sysjobs WHERE name LIKE 'SQL Monitor - Collect Metrics%';

-- Add Step 2: Query Analysis Collection
EXEC sp_add_jobstep
    @job_id = @job_id,
    @step_id = 2,
    @step_name = N'Collect Query Analysis Metrics',
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @ServerID INT = 5;  -- svweb ServerID

        EXEC [sqltest.schoolvision.net,14333].[MonitoringDB].[dbo].[usp_CollectAllQueryAnalysisMetrics]
            @ServerID = @ServerID;
    ',
    @database_name = N'master',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2,      -- Quit with failure
    @retry_attempts = 0,
    @retry_interval = 0;
GO

-- Update Step 1 to continue on success (not quit)
EXEC sp_update_jobstep
    @job_name = N'SQL Monitor - Collect Metrics (svweb)',  -- Adjust name as needed
    @step_id = 1,
    @on_success_action = 3;  -- Go to next step
GO
```

**On suncity server**:

```sql
USE msdb;
GO

-- Find the job
DECLARE @job_id UNIQUEIDENTIFIER;
SELECT @job_id = job_id FROM sysjobs WHERE name LIKE 'SQL Monitor - Collect Metrics%';

-- Add Step 2: Query Analysis Collection
EXEC sp_add_jobstep
    @job_id = @job_id,
    @step_id = 2,
    @step_name = N'Collect Query Analysis Metrics',
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @ServerID INT = 4;  -- suncity ServerID

        EXEC [sqltest.schoolvision.net,14333].[MonitoringDB].[dbo].[usp_CollectAllQueryAnalysisMetrics]
            @ServerID = @ServerID;
    ',
    @database_name = N'master',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2,      -- Quit with failure
    @retry_attempts = 0,
    @retry_interval = 0;
GO

-- Update Step 1 to continue on success (not quit)
EXEC sp_update_jobstep
    @job_name = N'SQL Monitor - Collect Metrics (suncity)',  -- Adjust name as needed
    @step_id = 1,
    @on_success_action = 3;  -- Go to next step
GO
```

**Verification**:

```sql
-- Check job steps
SELECT
    j.name AS JobName,
    js.step_id,
    js.step_name,
    js.subsystem,
    js.database_name,
    CASE js.on_success_action
        WHEN 1 THEN 'Quit with success'
        WHEN 2 THEN 'Quit with failure'
        WHEN 3 THEN 'Go to next step'
        WHEN 4 THEN 'Go to step...'
    END AS OnSuccessAction
FROM sysjobs j
INNER JOIN sysjobsteps js ON j.job_id = js.job_id
WHERE j.name LIKE 'SQL Monitor - Collect Metrics%'
ORDER BY js.step_id;
```

Expected result:
```
JobName                              step_id step_name                         OnSuccessAction
------------------------------------ ------- --------------------------------- -------------------
SQL Monitor - Collect Metrics (...)  1       Collect All Metrics (Local)       Go to next step
SQL Monitor - Collect Metrics (...)  2       Collect Query Analysis Metrics    Quit with success
```

### Step 4: Manual Test (RECOMMENDED)

Before relying on scheduled jobs, test manual execution:

**On svweb**:

```sql
-- Test collection manually
DECLARE @ServerID INT = 5;  -- svweb

EXEC [sqltest.schoolvision.net,14333].[MonitoringDB].[dbo].[usp_CollectAllQueryAnalysisMetrics]
    @ServerID = @ServerID;

-- Check for errors
SELECT @@ERROR AS ErrorCode;
```

**On suncity**:

```sql
-- Test collection manually
DECLARE @ServerID INT = 4;  -- suncity

EXEC [sqltest.schoolvision.net,14333].[MonitoringDB].[dbo].[usp_CollectAllQueryAnalysisMetrics]
    @ServerID = @ServerID;

-- Check for errors
SELECT @@ERROR AS ErrorCode;
```

**Verify Data Collected** (run on sqltest):

```sql
-- Check data collection for all servers
SELECT
    s.ServerName,
    ws.SnapshotCount AS WaitStatsSnapshots,
    be.BlockingCount AS BlockingEvents,
    de.DeadlockCount AS DeadlockEvents,
    qsq.QueryCount AS QueryStoreQueries
FROM dbo.Servers s
LEFT JOIN (
    SELECT ServerID, COUNT(*) AS SnapshotCount
    FROM dbo.WaitStatsSnapshot
    GROUP BY ServerID
) ws ON s.ServerID = ws.ServerID
LEFT JOIN (
    SELECT ServerID, COUNT(*) AS BlockingCount
    FROM dbo.BlockingEvents
    GROUP BY ServerID
) be ON s.ServerID = be.ServerID
LEFT JOIN (
    SELECT ServerID, COUNT(*) AS DeadlockCount
    FROM dbo.DeadlockEvents
    GROUP BY ServerID
) de ON s.ServerID = de.ServerID
LEFT JOIN (
    SELECT ServerID, COUNT(*) AS QueryCount
    FROM dbo.QueryStoreQueries
    GROUP BY ServerID
) qsq ON s.ServerID = qsq.ServerID
WHERE s.IsActive = 1
ORDER BY s.ServerID;
```

## Troubleshooting

### Issue: "Could not find stored procedure"

**Cause**: MonitoringDB procedures not deployed on sqltest, or incorrect linked server name.

**Fix**: Verify procedures exist on sqltest:

```sql
-- Run on sqltest
SELECT name, modify_date
FROM MonitoringDB.sys.objects
WHERE type = 'P'
  AND name LIKE 'usp_Collect%QueryAnalysis%'
ORDER BY modify_date DESC;
```

### Issue: "Login timeout expired" or "Server not found"

**Cause**: Linked server not configured, or firewall blocking connection.

**Fix**: Create linked server from svweb/suncity to sqltest:

```sql
-- Run on svweb or suncity
EXEC sp_addlinkedserver
    @server = N'sqltest.schoolvision.net,14333',
    @srvproduct = N'',
    @provider = N'SQLNCLI',
    @datasrc = N'sqltest.schoolvision.net,14333';

-- Add credentials
EXEC sp_addlinkedsrvlogin
    @rmtsrvname = N'sqltest.schoolvision.net,14333',
    @useself = N'False',
    @rmtuser = N'sv',
    @rmtpassword = N'YourPassword';

-- Test connection
SELECT @@SERVERNAME FROM [sqltest.schoolvision.net,14333].master.sys.servers;
```

### Issue: "QUOTED_IDENTIFIER error" when collecting deadlocks

**Cause**: XML methods require QUOTED_IDENTIFIER ON.

**Fix**: Already included in `usp_CollectDeadlockEvents` (line 2):

```sql
SET QUOTED_IDENTIFIER ON;
```

If still failing, check procedure was created with QUOTED_IDENTIFIER ON:

```sql
-- Recreate procedure
:r database/32-create-query-analysis-procedures.sql
```

### Issue: No deadlocks captured

**Expected**: On quiet servers, deadlocks may be rare.

**To Test**: Run intentional deadlock test (see `tests/test-deadlock-detection.sql`)

**Verify Trace Flag**:

```sql
-- Should return: TraceFlag=1222, Status=1, Global=1
DBCC TRACESTATUS(1222);

-- Check error log for deadlock graphs
EXEC xp_readerrorlog 0, 1, N'deadlock';
```

## Post-Deployment Verification Checklist

- [ ] **svweb**: Trace Flag 1222 enabled (DBCC TRACESTATUS)
- [ ] **svweb**: Extended Events session running (sys.dm_xe_sessions)
- [ ] **svweb**: SQL Agent job has 2 steps (Step 2 = Query Analysis)
- [ ] **svweb**: Manual collection test succeeds (no errors)
- [ ] **suncity**: Trace Flag 1222 enabled (DBCC TRACESTATUS)
- [ ] **suncity**: Extended Events session running (sys.dm_xe_sessions)
- [ ] **suncity**: SQL Agent job has 2 steps (Step 2 = Query Analysis)
- [ ] **suncity**: Manual collection test succeeds (no errors)
- [ ] **sqltest**: Data being collected from all 3 servers (query above)
- [ ] **sqltest**: WaitStatsSnapshot has rows for all ServerIDs
- [ ] **All servers**: SQL Agent jobs running every 5 minutes (check job history)

## Rollback Plan

If issues arise, rollback is simple since this is additive (no schema changes to existing tables):

**On svweb/suncity**:

```sql
-- Disable trace flag (optional - can leave enabled)
DBCC TRACEOFF(1222, -1);

-- Stop Extended Events session (optional)
ALTER EVENT SESSION deadlock_monitor ON SERVER STATE = STOP;
DROP EVENT SESSION deadlock_monitor ON SERVER;

-- Remove Step 2 from SQL Agent job
EXEC sp_delete_jobstep
    @job_name = N'SQL Monitor - Collect Metrics (...)',
    @step_id = 2;

-- Restore Step 1 to quit on success
EXEC sp_update_jobstep
    @job_name = N'SQL Monitor - Collect Metrics (...)',
    @step_id = 1,
    @on_success_action = 1;  -- Quit with success
```

**On sqltest** (only if needed - will lose all collected query analysis data):

```sql
-- Drop procedures
DROP PROCEDURE IF EXISTS dbo.usp_CollectAllQueryAnalysisMetrics;
DROP PROCEDURE IF EXISTS dbo.usp_CollectQueryStoreStats;
DROP PROCEDURE IF EXISTS dbo.usp_CollectBlockingEvents;
DROP PROCEDURE IF EXISTS dbo.usp_CollectDeadlockEvents;
DROP PROCEDURE IF EXISTS dbo.usp_CollectWaitStatsSnapshot;
DROP PROCEDURE IF EXISTS dbo.usp_CollectIndexFragmentation;
DROP PROCEDURE IF EXISTS dbo.usp_CollectMissingIndexes;
DROP PROCEDURE IF EXISTS dbo.usp_CollectUnusedIndexes;

-- Drop tables (WARNING: Deletes all data)
DROP TABLE IF EXISTS dbo.UnusedIndexes;
DROP TABLE IF EXISTS dbo.MissingIndexRecommendations;
DROP TABLE IF EXISTS dbo.IndexFragmentation;
DROP TABLE IF EXISTS dbo.WaitStatsBaseline;
DROP TABLE IF EXISTS dbo.WaitStatsDelta;
DROP TABLE IF EXISTS dbo.WaitStatsSnapshot;
DROP TABLE IF EXISTS dbo.DeadlockEvents;
DROP TABLE IF EXISTS dbo.BlockingEvents;
DROP TABLE IF EXISTS dbo.QueryStoreRuntimeStats;
DROP TABLE IF EXISTS dbo.QueryStoreQueries;
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-31 10:45 UTC
**Author**: SQL Monitor Project
