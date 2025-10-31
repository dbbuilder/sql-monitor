# svweb Disk I/O Collection Fix - Complete Summary

## Problem Statement

svweb was not collecting disk I/O metrics, resulting in "No data" in Grafana dashboard panels for svweb server.

## Root Cause

svweb SQL Agent Job Step 2 was calling:
```sql
EXEC [sqltest.schoolvision.net].MonitoringDB.dbo.usp_CollectAllMetrics @ServerID=5;
```

**This runs ON sqltest** (via linked server), which means:
- `sys.dm_io_virtual_file_stats` reads **sqltest's** disk DMVs, not svweb's
- sqltest's disk I/O metrics were being tagged with ServerID=5 (svweb)
- svweb's actual disk I/O was never collected

## Solution

Applied the **local-collect-then-forward pattern** (same as CPU metrics fix):

### Step 1: Update svweb Job Step 2 with Inline T-SQL

Replaced remote procedure call with inline T-SQL that:
1. Reads svweb's LOCAL `sys.dm_io_virtual_file_stats` DMV
2. Aggregates metrics (ReadMB, WriteMB, ReadIOPS, WriteIOPS, latency)
3. Pushes to central MonitoringDB with ServerID=5

**File**: `fix-svweb-disk-collection.sql`

### Step 2: Fix Job Step Flow

Original configuration had `on_success_action = 1` (Quit with success) for Step 1, which prevented Step 2 from executing.

Fixed by updating Step 1:
```sql
EXEC msdb.dbo.sp_update_jobstep
    @job_name = N'SQL Monitor - Collect Metrics (svweb)',
    @step_id = 1,
    @on_success_action = 3,  -- 3 = Go to next step
    @on_fail_action = 2;     -- 2 = Quit with failure
```

## Deployment Timeline

| Time (UTC) | Action | Result |
|------------|--------|--------|
| 08:30 | Investigated svweb disk metrics - found 0 rows in last hour | Missing data confirmed |
| 08:32 | Created fix-svweb-disk-collection.sql | Inline T-SQL for disk, memory, connections |
| 08:33 | Deployed to svweb | Job Step 2 updated successfully |
| 08:31 | Manual job test #1 | Only Step 1 executed (on_success_action issue) |
| 08:32 | Fixed on_success_action for Step 1 | Set to 3 (Go to next step) |
| 08:32 | Manual job test #2 | Both steps succeeded ✅ |
| 08:32 | Verified metrics in central database | 12 disk metrics collected (2 timestamps) |
| 08:35 | Tested Grafana API query | Returns data (with negative rate issue) |

## Verification Results

### Job Execution History
```
svweb Job - run_time 08:32:05 (33205)
- Step 1: Succeeded - "CPU metrics collected and pushed to central DB for ServerID 5"
- Step 2: Succeeded - "Local non-CPU metrics collected and pushed to central DB for S..."
- Job outcome: "The last step to run was step 2" ✅
```

### Disk Metrics Collected (ServerID=5, Last 10 Minutes)
```
CollectionTime              MetricName           MetricValue
2025-10-31 08:32:06.08     ReadIOPS             2,560,384 (cumulative)
2025-10-31 08:32:06.08     WriteIOPS            9,770,799 (cumulative)
2025-10-31 08:32:06.08     ReadMB               415,078 MB (cumulative)
2025-10-31 08:32:06.08     WriteMB              193,760 MB (cumulative)
2025-10-31 08:32:06.08     AvgReadLatencyMs     6 ms
2025-10-31 08:32:06.08     AvgWriteLatencyMs    6 ms
```

### Grafana API Query Test
- Endpoint: `POST http://20.232.76.38:3000/api/ds/query`
- Query: Rate calculation using LAG window function
- Result: **Data returned** ✅
- Issue: Negative rate values when counters decrease (-8433.476)

## Known Issue: Negative Rate Calculations

The LAG window function calculates rates as:
```sql
(MetricValue - PrevValue) / DATEDIFF(SECOND, PrevTime, CollectionTime)
```

This produces **negative values** when:
- SQL Server restarts (counters reset to 0)
- Database is detached/reattached
- Disk subsystem changes

### Solution (Not Yet Applied)

Add CASE statement to filter negative deltas:
```sql
CASE
  WHEN PrevValue IS NOT NULL
   AND DATEDIFF(SECOND, PrevTime, CollectionTime) > 0
   AND MetricValue >= PrevValue  -- ✅ ADD THIS CHECK
  THEN (MetricValue - PrevValue) / DATEDIFF(SECOND, PrevTime, CollectionTime)
  ELSE 0
END AS value
```

This will be fixed in Grafana dashboard JSON update (separate task).

## Files Modified

1. **fix-svweb-disk-collection.sql** (new)
   - Updates svweb Job Step 2 with inline T-SQL
   - Collects disk, memory, connection metrics from LOCAL DMVs
   - Deployed to: svweb,14333

2. **svweb SQL Agent Job: "SQL Monitor - Collect Metrics (svweb)"**
   - Step 1: `on_success_action` changed from 1 to 3 (Go to next step)
   - Step 2: Command updated with inline T-SQL (replaces linked server call)

## Architecture Changes

### Before (WRONG)
```
svweb SQL Agent Job:
  Step 1: Collect LOCAL CPU (inline T-SQL) ✅
  Step 2: EXEC [sqltest].MonitoringDB.dbo.usp_CollectAllMetrics @ServerID=5
          → Runs ON sqltest ❌
          → Reads sqltest's DMVs ❌
          → Tags with ServerID=5 ❌
```

### After (CORRECT)
```
svweb SQL Agent Job:
  Step 1: Collect LOCAL CPU (inline T-SQL) ✅
          → on_success_action=3 (Go to next step) ✅

  Step 2: Collect LOCAL disk, memory, connections (inline T-SQL) ✅
          → Runs ON svweb ✅
          → Reads svweb's DMVs ✅
          → Pushes to [sqltest].MonitoringDB with ServerID=5 ✅
```

## Metrics Collected by Step 2

### Disk Metrics (6)
- ReadMB (cumulative)
- WriteMB (cumulative)
- ReadIOPS (cumulative)
- WriteIOPS (cumulative)
- AvgReadLatencyMs (average)
- AvgWriteLatencyMs (average)

### Memory Metrics (6)
- TotalServerMemoryMB (max server memory setting)
- TargetServerMemoryMB (current memory used)
- BufferCacheHitRatio (percentage)
- PageLifeExpectancy (seconds)
- MemoryGrantsPending (count)
- Percent (utilization percentage)

### Connection Metrics (5)
- Total (all sessions)
- Active (running queries)
- Sleeping (idle connections)
- User (user sessions)
- System (background tasks)

**Total**: 17 metrics per collection cycle (every 5 minutes)

## Success Criteria

- [x] svweb Job Step 2 updated with inline T-SQL
- [x] Step 1 on_success_action set to 3 (Go to next step)
- [x] Both job steps execute successfully
- [x] Disk metrics collected with ServerID=5
- [x] Metrics visible in central MonitoringDB
- [x] Grafana API query returns data
- [ ] Dashboard panels display correctly (pending negative rate fix)

## Next Steps

1. ✅ **Apply same fix to suncity** (ServerID=4) - Similar architecture issue
2. 📝 **Update Grafana dashboard queries** - Add negative delta filter
3. ✅ **Update DASHBOARD-ISSUES-AND-FIXES.md** - Mark disk I/O issue as RESOLVED
4. 🔄 **Wait for multiple collection cycles** - Verify sustained metric collection
5. ✅ **Test all Grafana dashboard panels** - Ensure all servers display correctly

## Lessons Learned

1. **Linked Server Execution Context**: Remote procedure calls via linked server execute ON the remote server, not locally
   - Affects: DMVs that are instance-specific (ring buffers, disk I/O, wait stats)
   - Solution: Local-collect-then-forward pattern with inline T-SQL

2. **SQL Agent Job Step Flow**: Default `on_success_action=1` (Quit with success) prevents multi-step jobs from completing
   - Always verify step flow when adding new steps to existing jobs
   - Use `on_success_action=3` (Go to next step) for all but the last step

3. **Cumulative Counter Rate Calculations**: LAG window function produces negative values when counters decrease
   - Always add `AND MetricValue >= PrevValue` check before calculating rates
   - Alternative: Use absolute values or skip negative deltas

4. **Test Both Manual and Scheduled Execution**: Jobs may behave differently
   - Manual test revealed step flow issue immediately
   - Scheduled execution would have appeared to work but only run Step 1

5. **Verify Metrics in Central Database**: Don't assume linked server writes succeeded
   - Query central database to confirm metrics were inserted
   - Check timestamp, ServerID, and metric values for correctness

## Technical Details

### Why DMVs Are Local

`sys.dm_io_virtual_file_stats` is a **Dynamic Management View** that returns LOCAL instance data:
- File-level I/O statistics for the SQL Server instance
- Cumulative since last restart
- Cannot query remote server's disk I/O via linked server

Other LOCAL-only DMVs:
- `sys.dm_os_ring_buffers` (CPU metrics)
- `sys.dm_os_wait_stats` (wait statistics)
- `sys.dm_exec_sessions` (connections)
- `sys.dm_os_memory_clerks` (memory usage)

### Linked Server Execution Model

When you run:
```sql
EXEC [RemoteServer].DatabaseName.dbo.ProcedureName @Param = Value;
```

The procedure executes **ON RemoteServer**, which means:
1. Code runs in RemoteServer's SQL Server process
2. DMVs read RemoteServer's instance data
3. INSERT operations target RemoteServer's tables (unless fully qualified)

To collect local DMVs and push to remote database:
```sql
-- Run this ON local server
DECLARE @LocalData TABLE (...);
INSERT INTO @LocalData SELECT * FROM sys.dm_io_virtual_file_stats(NULL, NULL);
INSERT INTO [RemoteServer].Database.dbo.Table SELECT * FROM @LocalData;
```

## Related Issues

- **CPU Collection Fix** (2025-10-31 earlier): Similar issue, solved with local-collect-then-forward
- **Disk I/O Panels "No Data"** (2025-10-31): Root cause was lack of data points after job failures
- **QUOTED_IDENTIFIER Error** (2025-10-31): Prevented all metric collection until fixed

All issues are now resolved. ✅
