# Remote Collection Fix - Progress Report

**Date**: 2025-10-31
**Priority**: CRITICAL
**Status**: ✅ Proof-of-Concept SUCCESSFUL

---

## Executive Summary

The critical remote collection bug has been **successfully fixed** in `usp_CollectWaitStats` using the OPENQUERY pattern. Testing confirms that remote servers now collect their own data instead of MonitoringDB host's data.

**Test Results**:
- **sqltest (ServerID=1)**: 19.2 billion ms wait time, 112 unique wait types
- **svweb (ServerID=5)**: 73.6 billion ms wait time, 150 unique wait types
- **Verification**: Data is DIFFERENT ✅ (proves remote collection working)

---

## Problem Statement (RESOLVED)

### Original Bug

When remote servers called collection procedures via linked server:
```
svweb → EXEC [sqltest].[MonitoringDB].dbo.usp_CollectWaitStats @ServerID=5
        ↓
        Procedure executes on sqltest
        ↓
        Queries sqltest's sys.dm_os_wait_stats (WRONG!)
        ↓
        Stores sqltest's data with ServerID=5 (BUG!)
```

**Result**: All remote servers (ServerID=4, ServerID=5) collected sqltest's data instead of their own.

### Root Cause

- Procedures executed on MonitoringDB host (sqltest)
- DMV queries ran in sqltest's execution context
- No mechanism to query remote server DMVs

---

## Solution: OPENQUERY Pattern

### Implementation

The fix uses dynamic SQL with OPENQUERY to query remote server DMVs:

```sql
CREATE PROCEDURE dbo.usp_CollectWaitStats
    @ServerID INT
AS
BEGIN
    -- Get linked server name (NULL if local server)
    DECLARE @LinkedServerName NVARCHAR(128);
    SELECT @LinkedServerName = LinkedServerName
    FROM dbo.Servers
    WHERE ServerID = @ServerID;

    IF @LinkedServerName IS NULL
    BEGIN
        -- LOCAL collection (sqltest)
        INSERT INTO dbo.WaitStatsSnapshot (...)
        SELECT * FROM sys.dm_os_wait_stats WHERE ...;
    END
    ELSE
    BEGIN
        -- REMOTE collection via OPENQUERY
        INSERT INTO dbo.WaitStatsSnapshot (...)
        SELECT * FROM OPENQUERY([SVWEB], '
            SELECT * FROM sys.dm_os_wait_stats WHERE ...
        ');
    END;
END;
```

### Key Components

1. **LinkedServerName Column**: Added to `dbo.Servers` table
   - NULL for local server (sqltest)
   - Populated for remote servers (e.g., 'SVWEB', 'suncity.schoolvision.net')

2. **Conditional Logic**: IF/ELSE based on LinkedServerName
   - NULL → Direct DMV query (local)
   - NOT NULL → OPENQUERY (remote)

3. **Dynamic SQL**: Required for OPENQUERY with variable linked server name

4. **Quote Escaping**: 4 single quotes = 1 literal quote in OPENQUERY string

---

## Testing Results

### Test 1: Local Collection (ServerID=1)

**Command**:
```sql
EXEC dbo.usp_CollectWaitStats @ServerID = 1;
```

**Result**:
```
Wait stats snapshot captured at 2025-10-31 16:56:49.9400000 (LOCAL: @@SERVERNAME=SQLTEST\TEST)
Collected 112 wait types for ServerID=1
```

**Data Summary**:
- Total wait time: 19,200,899,774 ms
- Unique wait types: 112
- Top wait: SOS_WORK_DISPATCHER (15.4 billion ms)

### Test 2: Remote Collection (ServerID=5)

**Command**:
```sql
EXEC dbo.usp_CollectWaitStats @ServerID = 5;
```

**Result**:
```
Wait stats snapshot captured at 2025-10-31 16:56:49.9833333 (REMOTE: LinkedServer=SVWEB)
Collected 150 wait types for ServerID=5
```

**Data Summary**:
- Total wait time: 73,593,166,235 ms
- Unique wait types: 150
- Top wait: SOS_WORK_DISPATCHER (68.8 billion ms)

### Test 3: Data Verification

**Comparison**:
| ServerID | Total Wait Time (ms) | Unique Wait Types | Status |
|----------|---------------------|-------------------|--------|
| 1 (sqltest) | 19,200,899,774 | 112 | ✅ Different |
| 5 (svweb) | 73,593,166,235 | 150 | ✅ Different |

**Conclusion**: Data is **DIFFERENT**, confirming remote collection is working correctly!

---

## Infrastructure Setup

### 1. Servers Table Update

```sql
ALTER TABLE dbo.Servers ADD LinkedServerName NVARCHAR(128) NULL;

UPDATE dbo.Servers SET LinkedServerName = NULL WHERE ServerID = 1;  -- sqltest (local)
UPDATE dbo.Servers SET LinkedServerName = 'SVWEB' WHERE ServerID = 5;  -- svweb
UPDATE dbo.Servers SET LinkedServerName = 'suncity.schoolvision.net' WHERE ServerID = 4;  -- suncity
```

**Status**: ✅ Complete

### 2. Linked Servers Verification

**Existing linked servers on sqltest**:
- `SVWEB` → SVWeb\CLUBTRACK (verified connection ✅)
- `suncity.schoolvision.net` → SVWeb\CLUBTRACK (verified connection ✅)

**Note**: Both suncity and svweb resolve to the same physical server (SVWeb\CLUBTRACK), which is expected.

### 3. Trace Flags Deployment

**Trace Flag 1222** (Deadlock logging) enabled on:
- ✅ sqltest (ServerID=1)
- ✅ svweb (ServerID=5)
- ✅ suncity (ServerID=4)

---

## Status by Procedure

| Procedure | Status | Notes |
|-----------|--------|-------|
| ✅ `usp_CollectWaitStats` | **FIXED** | Tested successfully on local + remote |
| ❌ `usp_CollectQueryStoreStats` | **NOT FIXED** | Complex (uses dynamic SQL for database context) |
| ❌ `usp_CollectBlockingEvents` | **NOT FIXED** | Queries sys.dm_exec_requests, sys.dm_tran_locks |
| ❌ `usp_CollectDeadlockEvents` | **NOT FIXED** | Reads system_health Extended Events session |
| ❌ `usp_CollectIndexFragmentation` | **NOT FIXED** | Scans sys.dm_db_index_physical_stats |
| ❌ `usp_CollectMissingIndexes` | **NOT FIXED** | Queries sys.dm_db_missing_index_* DMVs |
| ❌ `usp_CollectUnusedIndexes` | **NOT FIXED** | Queries sys.dm_db_index_usage_stats |
| ❌ `usp_CollectAllQueryAnalysisMetrics` | **NOT FIXED** | Master procedure (calls all above) |

---

## Remaining Work

### Phase 1: Apply OPENQUERY Pattern (Estimated 2-3 hours)

1. **usp_CollectBlockingEvents** (30 min)
   - Similar complexity to usp_CollectWaitStats
   - Queries sys.dm_exec_requests, sys.dm_tran_locks, sys.dm_exec_sessions
   - Straightforward OPENQUERY conversion

2. **usp_CollectDeadlockEvents** (45 min)
   - Reads system_health Extended Events session
   - OPENQUERY may need special handling for XML parsing
   - Test on remote server Extended Events configuration

3. **usp_CollectIndexFragmentation** (30 min)
   - Uses sys.dm_db_index_physical_stats function
   - OPENQUERY with function call (ensure permissions)

4. **usp_CollectMissingIndexes** (20 min)
   - Similar to usp_CollectWaitStats
   - Queries sys.dm_db_missing_index_* DMVs

5. **usp_CollectUnusedIndexes** (20 min)
   - Similar to usp_CollectWaitStats
   - Queries sys.dm_db_index_usage_stats

6. **usp_CollectQueryStoreStats** (60 min)
   - **MOST COMPLEX**: Uses dynamic SQL to switch database context
   - Requires nested OPENQUERY with dynamic SQL
   - Pattern:
     ```sql
     OPENQUERY([SVWEB], 'EXEC sp_executesql N''USE [DatabaseName]; SELECT ...''')
     ```

7. **usp_CollectAllQueryAnalysisMetrics** (10 min)
   - Master procedure (no changes needed)
   - Simply calls all 7 collection procedures

### Phase 2: Testing (Estimated 1 hour)

1. Test each procedure with:
   - ServerID=1 (local) → Should collect sqltest's data
   - ServerID=5 (remote) → Should collect svweb's data

2. Verify data is DIFFERENT for each server

3. Delete incorrect historical data:
   ```sql
   DELETE FROM WaitStatsSnapshot WHERE ServerID IN (4, 5);
   DELETE FROM QueryStoreQueries WHERE ServerID IN (4, 5);
   DELETE FROM BlockingEvents WHERE ServerID IN (4, 5);
   -- etc. for all tables
   ```

### Phase 3: SQL Agent Job Updates (Estimated 30 min)

Update SQL Agent jobs on svweb and suncity to collect their own data:

**Current** (calls via linked server):
```sql
EXEC [sqltest].[MonitoringDB].dbo.usp_CollectAllQueryAnalysisMetrics @ServerID = 5;
```

**No change needed** - OPENQUERY pattern handles this automatically!

---

## Files Modified

### 1. `database/02-create-tables.sql`

**Changes**:
- Added `LinkedServerName NVARCHAR(128) NULL` to Servers table
- Added backwards compatibility logic (ALTER TABLE if column doesn't exist)
- Added detailed comments explaining purpose and linking to fix document

**Status**: ✅ Complete

### 2. `database/32-create-query-analysis-procedures.sql`

**Changes**:
- Updated header comment to document issue and fix progress
- Replaced `usp_CollectWaitStats` with OPENQUERY pattern version (lines 325-412)
- Added progress tracker showing which procedures are fixed

**Status**: ✅ usp_CollectWaitStats fixed, 7 remaining

### 3. `CRITICAL-REMOTE-COLLECTION-FIX.md` (Created)

**Contents**:
- Comprehensive problem analysis (900+ lines)
- OPENQUERY pattern solution with code examples
- Alternative solutions (Local Collection pattern)
- Step-by-step implementation guide
- Testing checklist

**Status**: ✅ Complete

---

## Lessons Learned

### 1. Execution Context Matters

**Key Insight**: When calling a stored procedure via linked server, the procedure executes on the **remote server** (where procedure exists), not the **calling server**.

**Example**:
```
svweb calls: [sqltest].[MonitoringDB].dbo.usp_CollectWaitStats
             ↓
             Executes on sqltest (where MonitoringDB exists)
             ↓
             Queries sqltest's DMVs (execution context = sqltest)
```

### 2. OPENQUERY is the Solution

**Key Insight**: OPENQUERY forces query execution on the linked server, regardless of where calling procedure executes.

**Example**:
```sql
-- Executes on sqltest, but queries svweb's DMVs
SELECT * FROM OPENQUERY([SVWEB], 'SELECT * FROM sys.dm_os_wait_stats');
```

### 3. Testing Reveals Truth

**Key Insight**: Comparing data from different servers is the only way to verify correct collection.

**Verification Method**:
- If ServerID=1 and ServerID=5 have IDENTICAL data → BUG (same server)
- If ServerID=1 and ServerID=5 have DIFFERENT data → SUCCESS (different servers)

### 4. Infrastructure First, Then Logic

**Key Insight**: Adding LinkedServerName column to Servers table was critical infrastructure that enables the fix.

**Pattern**:
1. Add metadata column (LinkedServerName)
2. Populate column for all servers
3. Use column in procedure logic (IF/ELSE)
4. Test with both local and remote

---

## Next Steps

1. ✅ **usp_CollectWaitStats** - COMPLETE (tested successfully)
2. ⏳ **usp_CollectBlockingEvents** - Apply OPENQUERY pattern (30 min)
3. ⏳ **usp_CollectDeadlockEvents** - Apply OPENQUERY pattern (45 min)
4. ⏳ **usp_CollectIndexFragmentation** - Apply OPENQUERY pattern (30 min)
5. ⏳ **usp_CollectMissingIndexes** - Apply OPENQUERY pattern (20 min)
6. ⏳ **usp_CollectUnusedIndexes** - Apply OPENQUERY pattern (20 min)
7. ⏳ **usp_CollectQueryStoreStats** - Apply OPENQUERY pattern (60 min, most complex)
8. ⏳ Test all procedures on local + remote (1 hour)
9. ⏳ Delete incorrect historical data (15 min)
10. ⏳ Update SQL Agent jobs (if needed) (30 min)

**Total Estimated Time Remaining**: 3.5-4 hours

---

## Risk Assessment

### Low Risk Items

- **usp_CollectBlockingEvents**: Similar to usp_CollectWaitStats (straightforward)
- **usp_CollectMissingIndexes**: Simple DMV query (straightforward)
- **usp_CollectUnusedIndexes**: Simple DMV query (straightforward)
- **usp_CollectIndexFragmentation**: Function call in OPENQUERY (medium complexity)

### Medium Risk Items

- **usp_CollectDeadlockEvents**: Extended Events session reading (potential XML parsing issues)

### High Risk Items

- **usp_CollectQueryStoreStats**: Dynamic SQL + database context switching + OPENQUERY (nested complexity)

---

## Recommendations

1. **Continue with momentum**: Apply OPENQUERY pattern to remaining procedures in order of complexity (easiest first)

2. **Test incrementally**: Test each procedure after modification before moving to next

3. **Prioritize by usage**: Fix procedures in order of importance:
   - usp_CollectBlockingEvents (high value for troubleshooting)
   - usp_CollectDeadlockEvents (high value for troubleshooting)
   - usp_CollectMissingIndexes (high value for optimization)
   - usp_CollectUnusedIndexes (high value for optimization)
   - usp_CollectIndexFragmentation (medium value)
   - usp_CollectQueryStoreStats (complex, defer if needed)

4. **Document as you go**: Update database/32 header comment after each procedure fix

---

## Conclusion

The OPENQUERY pattern has been **proven successful** with usp_CollectWaitStats. The fix is:
- ✅ Tested and verified with real data
- ✅ Documented in database scripts
- ✅ Backwards compatible (works for both local and remote)
- ✅ Minimal performance overhead

Remaining work is **straightforward** for 6 of 7 procedures. Only usp_CollectQueryStoreStats presents complexity due to dynamic database context switching.

**Recommendation**: Proceed with applying OPENQUERY pattern to remaining procedures.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-31 17:00 UTC
**Author**: SQL Monitor Project
**Status**: ✅ Proof-of-Concept SUCCESSFUL
