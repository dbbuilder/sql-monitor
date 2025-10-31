# CRITICAL: Remote Collection Architecture Fix

**Date**: 2025-10-31
**Priority**: CRITICAL
**Status**: ⚠️ BLOCKING ISSUE IDENTIFIED

## Problem Statement

The current query analysis collection procedures have a fundamental flaw: **they collect LOCAL server data instead of REMOTE server data** when called via linked server.

### Current (BROKEN) Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                svweb (ServerID=5)                           │
├─────────────────────────────────────────────────────────────┤
│  SQL Agent Job runs:                                        │
│  EXEC [sqltest].[MonitoringDB].[dbo].[usp_CollectWaitStats]│
│      @ServerID = 5;                                         │
│                                                              │
│  Problem: Procedure executes on sqltest, queries sqltest   │
│  DMVs, inserts sqltest data with ServerID=5                │
└─────────────────────────────────────────────────────────────┘
         │ Linked server call
         ▼
┌─────────────────────────────────────────────────────────────┐
│                sqltest (ServerID=1)                         │
├─────────────────────────────────────────────────────────────┤
│  usp_CollectWaitStats executes:                             │
│    SELECT * FROM sys.dm_os_wait_stats  ← sqltest's DMVs!   │
│    INSERT INTO WaitStatsSnapshot (..., @ServerID=5, ...)   │
│                                                              │
│  Result: sqltest's wait stats stored with ServerID=5 ❌    │
└─────────────────────────────────────────────────────────────┘
```

**Consequence**: All remote servers (svweb, suncity) collect **sqltest's data** instead of their own!

### Correct Pattern (Two Options)

#### Option 1: OPENQUERY Pattern (Recommended for Current Architecture)

```
┌─────────────────────────────────────────────────────────────┐
│                svweb (ServerID=5)                           │
├─────────────────────────────────────────────────────────────┤
│  SQL Agent Job runs:                                        │
│  EXEC [sqltest].[MonitoringDB].[dbo].[usp_CollectWaitStats_Remote]│
│      @ServerID = 5,                                         │
│      @LinkedServerName = 'SVWEB';  ← NEW parameter         │
└─────────────────────────────────────────────────────────────┘
         │ Linked server call
         ▼
┌─────────────────────────────────────────────────────────────┐
│                sqltest (ServerID=1)                         │
├─────────────────────────────────────────────────────────────┤
│  usp_CollectWaitStats_Remote executes:                      │
│    INSERT INTO WaitStatsSnapshot (...)                      │
│    SELECT * FROM OPENQUERY([SVWEB],                         │
│        'SELECT * FROM sys.dm_os_wait_stats')  ← svweb DMVs!│
│                                                              │
│  Result: svweb's wait stats stored with ServerID=5 ✅      │
└─────────────────────────────────────────────────────────────┘
```

#### Option 2: Local Collection + Remote Insert (Alternative)

```
┌─────────────────────────────────────────────────────────────┐
│                svweb (ServerID=5)                           │
├─────────────────────────────────────────────────────────────┤
│  SQL Agent Job runs LOCAL procedure:                        │
│  EXEC dbo.usp_CollectWaitStats_ToRemoteDB                   │
│      @ServerID = 5,                                         │
│      @MonitoringDBServer = 'sqltest.schoolvision.net,14333';│
│                                                              │
│  Procedure queries LOCAL DMVs:                              │
│    SELECT * FROM sys.dm_os_wait_stats  ← svweb's DMVs ✅   │
│                                                              │
│  Then inserts to REMOTE MonitoringDB:                       │
│    INSERT INTO [sqltest].[MonitoringDB].[dbo].[WaitStatsSnapshot]│
│        (..., @ServerID=5, ...)                              │
└─────────────────────────────────────────────────────────────┘
```

**Tradeoffs**:
| Pattern | Pros | Cons |
|---------|------|------|
| **OPENQUERY** (Option 1) | - Single procedure codebase<br>- Central execution on sqltest<br>- No procedure deployment to remote servers | - Requires linked servers FROM sqltest TO remotes<br>- Dynamic SQL (security concern)<br>- OPENQUERY overhead |
| **Local + Remote Insert** (Option 2) | - No OPENQUERY overhead<br>- Native DMV queries<br>- Simpler security model | - Must deploy procedures to ALL remote servers<br>- Duplicate codebases<br>- Harder to maintain |

## Root Cause Analysis

### Why This Wasn't Caught Earlier

1. **Single Server Testing**: All testing performed on sqltest (ServerID=1) where LOCAL=REMOTE
2. **No ServerID Validation**: Procedures don't verify @@SERVERNAME matches expected server
3. **Linked Server Assumption**: Assumed linked server execution would "magically" run on remote

### Affected Procedures

**All 8 query analysis procedures are affected**:
1. `usp_CollectQueryStoreStats` - Collects local Query Store, not remote
2. `usp_CollectBlockingEvents` - Collects local blocking, not remote
3. `usp_CollectDeadlockEvents` - Collects local deadlocks, not remote
4. `usp_CollectWaitStats` - Collects local wait stats, not remote
5. `usp_CollectIndexFragmentation` - Scans local indexes, not remote
6. `usp_CollectMissingIndexes` - Collects local missing indexes, not remote
7. `usp_CollectUnusedIndexes` - Collects local index usage, not remote
8. `usp_CollectAllQueryAnalysisMetrics` - Master procedure (calls all above)

## Solution: OPENQUERY Pattern (Recommended)

### Step 1: Add LinkedServerName to Servers Table

```sql
ALTER TABLE dbo.Servers
ADD LinkedServerName NVARCHAR(128) NULL;
GO

UPDATE dbo.Servers SET LinkedServerName = NULL WHERE ServerID = 1;  -- sqltest (local)
UPDATE dbo.Servers SET LinkedServerName = 'SVWEB' WHERE ServerID = 5;  -- svweb
UPDATE dbo.Servers SET LinkedServerName = 'suncity.schoolvision.net' WHERE ServerID = 4;  -- suncity
```

### Step 2: Modify Collection Procedures to Use OPENQUERY

**Example: usp_CollectWaitStats_v2**

```sql
CREATE OR ALTER PROCEDURE dbo.usp_CollectWaitStats
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Get linked server name (NULL if local server)
    DECLARE @LinkedServerName NVARCHAR(128);
    SELECT @LinkedServerName = LinkedServerName
    FROM dbo.Servers
    WHERE ServerID = @ServerID;

    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SnapshotTime DATETIME2 = GETUTCDATE();

    IF @LinkedServerName IS NULL
    BEGIN
        -- LOCAL collection (sqltest)
        INSERT INTO dbo.WaitStatsSnapshot
            (ServerID, SnapshotTime, WaitType, WaitTimeMs, WaitingTasksCount, SignalWaitTimeMs)
        SELECT
            @ServerID,
            @SnapshotTime,
            wait_type,
            wait_time_ms,
            waiting_tasks_count,
            signal_wait_time_ms
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (
            'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE',
            'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH',
            'WAITFOR', 'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE',
            'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT', 'BROKER_TO_FLUSH'
        );
    END
    ELSE
    BEGIN
        -- REMOTE collection via OPENQUERY
        SET @SQL = N'
        INSERT INTO dbo.WaitStatsSnapshot
            (ServerID, SnapshotTime, WaitType, WaitTimeMs, WaitingTasksCount, SignalWaitTimeMs)
        SELECT
            @ServerID,
            @SnapshotTime,
            wait_type,
            wait_time_ms,
            waiting_tasks_count,
            signal_wait_time_ms
        FROM OPENQUERY([' + @LinkedServerName + N'], ''
            SELECT
                wait_type,
                wait_time_ms,
                waiting_tasks_count,
                signal_wait_time_ms
            FROM sys.dm_os_wait_stats
            WHERE wait_type NOT IN (
                ''''CLR_SEMAPHORE'''', ''''LAZYWRITER_SLEEP'''', ''''RESOURCE_QUEUE'''',
                ''''SLEEP_TASK'''', ''''SLEEP_SYSTEMTASK'''', ''''SQLTRACE_BUFFER_FLUSH'''',
                ''''WAITFOR'''', ''''LOGMGR_QUEUE'''', ''''CHECKPOINT_QUEUE'''',
                ''''REQUEST_FOR_DEADLOCK_SEARCH'''', ''''XE_TIMER_EVENT'''', ''''BROKER_TO_FLUSH''''
            )
        '')';

        EXEC sp_executesql @SQL,
            N'@ServerID INT, @SnapshotTime DATETIME2',
            @ServerID = @ServerID,
            @SnapshotTime = @SnapshotTime;
    END;

    DECLARE @RowCount INT = @@ROWCOUNT;
    PRINT 'Collected ' + CAST(@RowCount AS VARCHAR(10)) + ' wait types for server ' + CAST(@ServerID AS VARCHAR(10));
END;
GO
```

### Step 3: Test Remote Collection

```sql
-- Test svweb collection (should collect svweb's data, not sqltest's)
EXEC dbo.usp_CollectWaitStats @ServerID = 5;

-- Verify: Check that data is different from sqltest
SELECT TOP 10
    ServerID,
    WaitType,
    WaitTimeMs,
    SnapshotTime
FROM dbo.WaitStatsSnapshot
WHERE ServerID IN (1, 5)
ORDER BY SnapshotTime DESC, ServerID;

-- If ServerID=1 and ServerID=5 have IDENTICAL wait times → BROKEN (collecting same data)
-- If ServerID=1 and ServerID=5 have DIFFERENT wait times → WORKING (collecting different servers)
```

### Step 4: Update All 8 Procedures

Apply the same OPENQUERY pattern to all procedures:
1. Add `@LinkedServerName` lookup from Servers table
2. Conditional logic: `IF @LinkedServerName IS NULL` → local, `ELSE` → OPENQUERY
3. Dynamic SQL for remote execution
4. Proper quote escaping for OPENQUERY (4 single quotes = 1 literal quote)

## Alternative Solution: Local Collection Pattern

**Advantages**:
- No OPENQUERY overhead
- Native DMV queries
- Simpler execution model

**Disadvantages**:
- Must deploy procedures to ALL remote servers (maintenance burden)
- Requires reverse linked servers (remote → sqltest)
- Code duplication

**Implementation**:

```sql
-- Deploy on EACH remote server (svweb, suncity, etc.)
CREATE OR ALTER PROCEDURE dbo.usp_CollectWaitStats_Local
    @ServerID INT,
    @MonitoringDBServer NVARCHAR(128) = 'sqltest.schoolvision.net,14333'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SnapshotTime DATETIME2 = GETUTCDATE();
    DECLARE @SQL NVARCHAR(MAX);

    -- Query LOCAL DMVs
    CREATE TABLE #WaitStats (
        WaitType NVARCHAR(60),
        WaitTimeMs BIGINT,
        WaitingTasksCount BIGINT,
        SignalWaitTimeMs BIGINT
    );

    INSERT INTO #WaitStats
    SELECT
        wait_type,
        wait_time_ms,
        waiting_tasks_count,
        signal_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (...);  -- Filter list

    -- Insert to REMOTE MonitoringDB
    SET @SQL = N'
    INSERT INTO [' + @MonitoringDBServer + N'].[MonitoringDB].[dbo].[WaitStatsSnapshot]
        (ServerID, SnapshotTime, WaitType, WaitTimeMs, WaitingTasksCount, SignalWaitTimeMs)
    SELECT
        @ServerID,
        @SnapshotTime,
        WaitType,
        WaitTimeMs,
        WaitingTasksCount,
        SignalWaitTimeMs
    FROM #WaitStats';

    EXEC sp_executesql @SQL,
        N'@ServerID INT, @SnapshotTime DATETIME2',
        @ServerID = @ServerID,
        @SnapshotTime = @SnapshotTime;

    DROP TABLE #WaitStats;
END;
GO
```

## Impact Assessment

### Current State (BROKEN)

- ✅ sqltest (ServerID=1): Collecting sqltest's data correctly
- ❌ svweb (ServerID=5): Collecting sqltest's data (WRONG - should be svweb's)
- ❌ suncity (ServerID=4): Collecting sqltest's data (WRONG - should be suncity's)

**Data Integrity**: All historical data for ServerID=5 and ServerID=4 is actually sqltest's data.

### After Fix (OPENQUERY Pattern)

- ✅ sqltest (ServerID=1): Collects sqltest's data
- ✅ svweb (ServerID=5): Collects svweb's data via OPENQUERY
- ✅ suncity (ServerID=4): Collects suncity's data via OPENQUERY

**Data Cleanup Required**: Delete all existing data for ServerID=5 and ServerID=4 (it's incorrect).

## Recommended Action Plan

1. ⏳ **STOP** current remote collection jobs (prevent more bad data)
2. ⏳ **ALTER TABLE** Servers to add LinkedServerName column
3. ⏳ **UPDATE** Servers table with linked server names
4. ⏳ **MODIFY** all 8 collection procedures to use OPENQUERY pattern
5. ⏳ **DELETE** incorrect historical data for remote servers
6. ⏳ **TEST** remote collection (verify different data)
7. ⏳ **RE-ENABLE** remote collection jobs

## Testing Checklist

- [ ] Add LinkedServerName column to Servers table
- [ ] Update usp_CollectWaitStats with OPENQUERY logic
- [ ] Test local collection (ServerID=1, LinkedServerName=NULL)
- [ ] Test remote collection (ServerID=5, LinkedServerName='SVWEB')
- [ ] Verify collected data is DIFFERENT for sqltest vs svweb
- [ ] Check sys.dm_exec_requests during collection (verify remote execution)
- [ ] Repeat for all 8 procedures
- [ ] Update master procedure (usp_CollectAllQueryAnalysisMetrics)
- [ ] Test end-to-end via SQL Agent job

## Long-Term Recommendation

**Phase 3 (Azure Function Pattern)** eliminates this entire problem:
- Azure Function connects DIRECTLY to each monitored server
- No linked servers required
- Native DMV queries on each server
- Bulk insert to Azure SQL (MonitoringDB)

See: [AZURE-SQL-INTEGRATION-PLAN.md](docs/AZURE-SQL-INTEGRATION-PLAN.md)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-31 16:45 UTC
**Author**: SQL Monitor Project
**Priority**: CRITICAL - Blocks Phase 2 completion
**Estimated Fix Time**: 2-4 hours (all 8 procedures)
