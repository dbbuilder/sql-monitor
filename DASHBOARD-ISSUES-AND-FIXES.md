# AWS RDS Performance Insights Dashboard - Issues & Fixes

## Issue 1: CPU Metrics Showing Same Values for All Servers ✅ IDENTIFIED

### Problem
All three servers (sqltest, svweb, suncity) show IDENTICAL CPU values:
- SQLServerCPUPercent: 0-7%
- SystemIdlePercent: 91-99%
- OtherProcessCPUPercent: 1-2%

### Root Cause
Remote servers are collecting CPU metrics via linked server, which executes the procedure on the CENTRAL server (sqltest). The `sys.dm_os_ring_buffers` DMV is LOCAL to the SQL instance, so remote execution always reads sqltest's ring buffer.

**Current (WRONG) Architecture**:
```
svweb SQL Agent Job:
  → EXEC [sqltest].MonitoringDB.dbo.usp_CollectPerformanceCounters @ServerID=5
     → Runs ON sqltest
     → Reads sqltest's sys.dm_os_ring_buffers
     → Inserts sqltest's CPU values with ServerID=5
```

### Solution
Split CPU collection into LOCAL execution + REMOTE insert:

**New (CORRECT) Architecture**:
```
svweb SQL Agent Job (2 steps):
  Step 1 - LOCAL CPU Collection:
    → EXEC MonitoringDB.dbo.usp_CollectAndInsertCPUMetrics @ServerID=5
       → Runs ON svweb (local)
       → Reads svweb's ring buffer
       → Inserts to [sqltest].MonitoringDB via linked server

  Step 2 - REMOTE Counter Collection:
    → EXEC [sqltest].MonitoringDB.dbo.usp_CollectPerformanceCountersNoCPU @ServerID=5
       → Runs ON sqltest (remote)
       → Collects performance counters, disk I/O, connections
       → NO CPU metrics
```

### Deployment Steps

1. **Deploy new procedures to ALL servers** (sqltest, svweb, suncity):
   ```sql
   -- On each server, run:
   sqlcmd -S localhost -d MonitoringDB -i fix-cpu-collection-architecture.sql
   ```

2. **Update SQL Agent jobs on remote servers** (svweb, suncity):
   ```sql
   -- svweb: Update job to have 2 steps
   EXEC msdb.dbo.sp_update_jobstep
       @job_name = N'SQL Monitor - Collect Metrics (svweb)',
       @step_id = 1,
       @step_name = N'Collect LOCAL CPU Metrics',
       @database_name = N'MonitoringDB',
       @command = N'EXEC dbo.usp_CollectAndInsertCPUMetrics @ServerID = 5;';

   EXEC msdb.dbo.sp_add_jobstep
       @job_name = N'SQL Monitor - Collect Metrics (svweb)',
       @step_id = 2,
       @step_name = N'Collect REMOTE Performance Counters',
       @database_name = N'master',
       @command = N'EXEC [sqltest.schoolvision.net].MonitoringDB.dbo.usp_CollectPerformanceCountersNoCPU @ServerID = 5;';
   ```

3. **Update sqltest job** (local collection, both procedures):
   ```sql
   EXEC msdb.dbo.sp_update_jobstep
       @job_name = N'SQL Monitor - Collect Metrics (sqltest)',
       @step_id = 1,
       @command = N'EXEC dbo.usp_CollectAndInsertCPUMetrics @ServerID = 1;
                     EXEC dbo.usp_CollectPerformanceCountersNoCPU @ServerID = 1;';
   ```

---

## Issue 2: Disk I/O Panels Showing "No Data" ⚠️ INVESTIGATING

### Problem
Dashboard panels showing "No data":
- Read/Write IOPS
- Read/Write Throughput (MB/s)
- Disk Latency

### Test Results
✅ **SQL Query Works**: Rate calculation query returns data when executed directly:
```sql
-- Returns: 0.16 to 323 IOPS/sec
WITH MetricsWithPrevious AS (
  SELECT CollectionTime, MetricValue,
         LAG(MetricValue) OVER (...) AS PrevValue,
         LAG(CollectionTime) OVER (...) AS PrevTime
  FROM dbo.PerformanceMetrics
  WHERE ServerID = 5 AND MetricCategory = 'Disk'...
)
SELECT (MetricValue - PrevValue) / DATEDIFF(SECOND, PrevTime, CollectionTime) AS value
```

✅ **Dashboard Query Format**: Correct format for Grafana SQL datasource:
- `time` column (datetime)
- `value` column (numeric)
- `metric` column (string)

### Potential Causes

1. **Grafana Variable Not Populated**:
   - `$ServerID` variable might be empty or null
   - Check: View Grafana dashboard variables dropdown

2. **Time Range Macros Not Working**:
   - `$__timeFrom()` / `$__timeTo()` might not be converting to datetime
   - Grafana SQL datasource expects specific macro format

3. **Dashboard Not Refreshed After Container Restart**:
   - Grafana may be caching old dashboard JSON
   - Dashboard files downloaded from GitHub at container startup

4. **Datasource Connection Issue**:
   - MonitoringDB datasource might not be configured correctly
   - Check Grafana datasource settings

### Debugging Steps

1. **Check Grafana Datasource**:
   - Log into Grafana: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
   - Navigate to: Configuration → Data Sources → MonitoringDB
   - Test connection
   - Verify server/database/credentials

2. **Check Dashboard Variables**:
   - Open AWS RDS Performance Insights dashboard
   - Top of dashboard should show "ServerID" dropdown
   - Select a server (e.g., svweb,14333)
   - Check browser console for JavaScript errors

3. **Test Query in Grafana Explore**:
   - Navigate to: Explore (compass icon in sidebar)
   - Select MonitoringDB datasource
   - Paste the IOPS query
   - Manually replace `$ServerID` with `5`
   - Manually replace `$__timeFrom()` with `DATEADD(HOUR, -1, GETUTCDATE())`
   - Manually replace `$__timeTo()` with `GETUTCDATE()`
   - Run query
   - If this works, problem is with variables/macros

4. **Check Grafana Logs**:
   ```bash
   az container logs --resource-group rg-sqlmonitor-schoolvision --name grafana-schoolvision
   ```
   - Look for SQL query errors
   - Look for datasource connection errors

### Workaround (If Variables Are Issue)
Create a simplified query without rate calculation to verify basic connectivity:
```sql
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  MetricName AS metric
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Disk'
  AND MetricName IN ('ReadIOPS', 'WriteIOPS')
  AND ServerID = $ServerID
  AND CollectionTime >= $__timeFrom()
  AND CollectionTime <= $__timeTo()
ORDER BY CollectionTime
```

---

## Summary

| Issue | Status | Fix Complexity | Impact |
|-------|--------|---------------|--------|
| CPU metrics identical | ✅ IDENTIFIED | Medium (update 3 SQL Agent jobs) | HIGH - All servers show wrong CPU |
| Disk I/O "No data" | ⚠️ INVESTIGATING | Low (likely config) | MEDIUM - Dashboard incomplete |

**Next Steps**:
1. Deploy CPU collection fix to all 3 servers
2. Debug Grafana datasource and variables for disk I/O panels
3. Test all panels after fixes
4. Document final configuration

## Files Created
- `fix-cpu-collection-architecture.sql` - New CPU collection procedures
- `DASHBOARD-ISSUES-AND-FIXES.md` - This document
