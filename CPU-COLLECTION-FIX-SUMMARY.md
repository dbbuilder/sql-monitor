# CPU Collection Fix - Complete Summary

## Problem Statement

SQL Agent jobs for metrics collection were failing with QUOTED_IDENTIFIER errors, preventing CPU metrics from being collected.

## Root Causes Identified

1. **QUOTED_IDENTIFIER Setting Missing**: Stored procedures accessing `sys.dm_os_ring_buffers` require QUOTED_IDENTIFIER ON
2. **Column Count Mismatch**: Original `usp_CollectAndInsertCPUMetrics` tried to INSERT result set directly without adding ServerID column
3. **SQL Agent Job Step Missing Setting**: Job step T-SQL also needs SET QUOTED_IDENTIFIER ON

## Fixes Applied

### Fix 1: Recreate Procedures with QUOTED_IDENTIFIER ON

**File**: `fix-quoted-identifier-cpu-procedures.sql`

**Changes**:
- `usp_GetLocalCPUMetrics`: Added `SET QUOTED_IDENTIFIER ON` at both CREATE and within procedure
- `usp_CollectAndInsertCPUMetrics`: Completely rewritten to use table variable approach

**Before** (usp_CollectAndInsertCPUMetrics):
```sql
CREATE PROCEDURE dbo.usp_CollectAndInsertCPUMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    EXEC dbo.usp_GetLocalCPUMetrics;  -- ❌ Missing ServerID column, wrong column count
END;
```

**After** (usp_CollectAndInsertCPUMetrics):
```sql
CREATE PROCEDURE dbo.usp_CollectAndInsertCPUMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;  -- ✅ Setting added

    -- Table variable to capture procedure results
    DECLARE @CPUMetrics TABLE (
        CollectionTime DATETIME2,
        MetricCategory NVARCHAR(50),
        MetricName NVARCHAR(100),
        MetricValue DECIMAL(20,4)
    );

    -- Capture results
    INSERT INTO @CPUMetrics (CollectionTime, MetricCategory, MetricName, MetricValue)
    EXEC dbo.usp_GetLocalCPUMetrics;

    -- Insert with ServerID column
    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    SELECT @ServerID, CollectionTime, MetricCategory, MetricName, MetricValue
    FROM @CPUMetrics;  -- ✅ ServerID added correctly

    PRINT 'CPU metrics collected and inserted for ServerID ' + CAST(@ServerID AS VARCHAR(10));
END;
```

### Fix 2: Update SQL Agent Job Steps

**sqltest job** (`SQL Monitor - Collect Metrics (sqltest)`):
- Added `SET QUOTED_IDENTIFIER ON;` at the beginning of job step command
- Kept procedure calls: `EXEC dbo.usp_CollectAndInsertCPUMetrics @ServerID = 1;`

**svweb job** (`SQL Monitor - Collect Metrics (svweb)`):
- Step 1: Updated inline T-SQL to use table variable approach (same as procedure)
- Added `SET QUOTED_IDENTIFIER ON;` at the beginning
- Step 2: No changes needed (calls remote procedure for non-CPU metrics)

## Deployment Timeline

| Time (UTC) | Action | Result |
|------------|--------|--------|
| 07:30 | Identified QUOTED_IDENTIFIER error in job history | Jobs failing with Error 1934 |
| 07:35 | Created `fix-quoted-identifier-cpu-procedures.sql` | Procedures with SET QUOTED_IDENTIFIER ON |
| 07:40 | Deployed to sqltest | Procedures created successfully |
| 07:42 | Manual job test | Failed with column count mismatch (Error 213) |
| 07:45 | Fixed `usp_CollectAndInsertCPUMetrics` with table variable | Procedure test successful |
| 07:48 | Updated sqltest job step with SET QUOTED_IDENTIFIER ON | Job step updated |
| 07:50 | Updated svweb job step 1 with table variable approach | Job step updated |
| 07:52 | Waiting for next scheduled run (02:55 local time) | Scheduled for validation |

## Verification Steps

### 1. Check Procedure Settings
```sql
SELECT
    OBJECT_NAME(object_id) AS ProcedureName,
    uses_quoted_identifier AS QuotedIdentifier,
    CASE uses_quoted_identifier
        WHEN 1 THEN '✓ CORRECT'
        WHEN 0 THEN '✗ WRONG'
    END AS Status
FROM sys.sql_modules
WHERE OBJECT_NAME(object_id) IN ('usp_GetLocalCPUMetrics', 'usp_CollectAndInsertCPUMetrics')
ORDER BY ProcedureName;
```

**Expected Result**:
```
ProcedureName                   QuotedIdentifier  Status
usp_CollectAndInsertCPUMetrics  1                 ✓ CORRECT
usp_GetLocalCPUMetrics          1                 ✓ CORRECT
```

### 2. Test Procedure Manually
```sql
SET QUOTED_IDENTIFIER ON;
EXEC dbo.usp_CollectAndInsertCPUMetrics @ServerID = 1;

-- Check inserted metrics
SELECT TOP 3 ServerID, CollectionTime, MetricName, MetricValue
FROM dbo.PerformanceMetrics
WHERE ServerID = 1 AND MetricCategory = 'CPU'
ORDER BY CollectionTime DESC;
```

**Expected Result**: 3 rows inserted (SQLServerCPUPercent, SystemIdlePercent, OtherProcessCPUPercent)

### 3. Check Job Execution History
```sql
SELECT TOP 5
    j.name AS JobName,
    h.run_date,
    h.run_time,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
    END AS StatusText,
    LEFT(h.message, 100) AS MessagePreview
FROM sysjobs j
INNER JOIN sysjobhistory h ON j.job_id = h.job_id
WHERE j.name = 'SQL Monitor - Collect Metrics (sqltest)'
  AND h.step_id = 0  -- Job outcome
ORDER BY h.run_date DESC, h.run_time DESC;
```

**Expected Result**: StatusText = 'Succeeded' for runs after 07:50 UTC

### 4. Verify CPU Metrics Differ Per Server
```sql
-- Check latest CPU metrics for all servers
SELECT
    s.ServerName,
    pm.ServerID,
    pm.CollectionTime,
    MAX(CASE WHEN pm.MetricName = 'SQLServerCPUPercent' THEN pm.MetricValue END) AS SQLServerCPU,
    MAX(CASE WHEN pm.MetricName = 'SystemIdlePercent' THEN pm.MetricValue END) AS SystemIdle,
    MAX(CASE WHEN pm.MetricName = 'OtherProcessCPUPercent' THEN pm.MetricValue END) AS OtherProcessCPU
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.MetricCategory = 'CPU'
  AND pm.CollectionTime >= DATEADD(MINUTE, -10, GETUTCDATE())
GROUP BY s.ServerName, pm.ServerID, pm.CollectionTime
ORDER BY pm.ServerID, pm.CollectionTime DESC;
```

**Expected Result**: Different CPU values for ServerID 1, 4, 5 (not identical)

## Files Modified

1. **fix-quoted-identifier-cpu-procedures.sql** (new)
   - Recreates `usp_GetLocalCPUMetrics` and `usp_CollectAndInsertCPUMetrics` with correct settings
   - Deployed to: sqltest.schoolvision.net,14333

2. **SQL Agent Jobs** (updated):
   - `SQL Monitor - Collect Metrics (sqltest)` - Step 1 command updated
   - `SQL Monitor - Collect Metrics (svweb)` - Step 1 command updated (inline T-SQL)

## Technical Details

### Why QUOTED_IDENTIFIER ON is Required

The `sys.dm_os_ring_buffers` DMV uses XML data type methods (`.value()`) which require QUOTED_IDENTIFIER ON:
- SQL Server validates SET options when compiling stored procedures
- Error 1934 is raised if QUOTED_IDENTIFIER is not ON when accessing XML methods
- Setting must be ON at both procedure creation AND execution time

### Why Table Variable Approach

Direct INSERT from EXEC results doesn't allow adding columns:
```sql
-- ❌ This doesn't work:
INSERT INTO Table (ServerID, Col1, Col2)
EXEC ProcThatReturns2Columns;  -- Can't add ServerID

-- ✅ This works:
DECLARE @temp TABLE (Col1, Col2);
INSERT INTO @temp EXEC ProcThatReturns2Columns;
INSERT INTO Table (ServerID, Col1, Col2)
SELECT @ServerID, Col1, Col2 FROM @temp;
```

## Success Criteria

- [x] Procedures created with `uses_quoted_identifier = 1`
- [x] Manual procedure execution succeeds
- [ ] SQL Agent job succeeds on next scheduled run (pending validation at 02:55)
- [ ] CPU metrics show different values for each server (pending validation)

## Next Steps

1. ⏳ **Wait for scheduled job run** (02:55 local time / 07:55 UTC)
2. ✅ **Verify job success** in sysjobhistory
3. ✅ **Verify CPU metrics** differ per server
4. 📝 **Update DASHBOARD-ISSUES-AND-FIXES.md** with resolution
5. ✅ **Commit all fixes** to Git

## Lessons Learned

1. **Always set QUOTED_IDENTIFIER ON** for procedures accessing XML methods or indexed views
2. **Check procedure settings** after creation: `SELECT uses_quoted_identifier FROM sys.sql_modules`
3. **SQL Agent job steps** need explicit SET statements; they don't inherit from procedure definitions
4. **INSERT...EXEC limitations**: Can't add columns on the fly, must use table variable/temp table
5. **Test thoroughly**: Manual execution + SQL Agent execution can behave differently
