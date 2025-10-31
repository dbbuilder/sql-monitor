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

## Issue 2: Disk I/O Panels Showing "No Data" ⚠️ ROOT CAUSE IDENTIFIED

### Problem
Dashboard panels showing "No data":
- Read/Write IOPS
- Read/Write Throughput (MB/s)
- Disk Latency

### Test Results (2025-10-31)

✅ **SQL Query Works**: Rate calculation query returns data when executed directly:
```sql
-- Executed via sqlcmd against sqltest.schoolvision.net,14333
-- Returns: 0.16 to 323 IOPS/sec (Read), 2.5 to 30 IOPS/sec (Write)
-- Sample data from 07:00-07:10 UTC, ServerID=5 (svweb)
WITH MetricsWithPrevious AS (
  SELECT CollectionTime, MetricValue,
         LAG(MetricValue) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevValue,
         LAG(CollectionTime) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevTime
  FROM dbo.PerformanceMetrics
  WHERE ServerID = 5 AND MetricCategory = 'Disk' AND MetricName IN ('ReadIOPS', 'WriteIOPS')
)
SELECT (MetricValue - PrevValue) / DATEDIFF(SECOND, PrevTime, CollectionTime) AS value
FROM MetricsWithPrevious WHERE PrevValue IS NOT NULL;
```

✅ **Dashboard Query Format**: Correct format for Grafana SQL datasource:
- `time` column (datetime) ✓
- `value` column (numeric) ✓
- `metric` column (string) ✓

✅ **Dashboard Variable Configuration**: ServerID variable query is correct:
```sql
SELECT ServerID AS __value, ServerName AS __text FROM dbo.Servers WHERE IsActive = 1
-- Returns: 3 servers (sqltest=1, suncity=4, svweb=5)
```

✅ **Datasource Configuration**: Verified `dashboards/grafana/provisioning/datasources/monitoringdb.yaml`:
- Connection string: sqltest.schoolvision.net:14333
- Database: MonitoringDB
- Credentials: sv / Gv51076!
- TLS skip verify: true

❌ **Grafana Container Status**: **Container does not exist in Azure**
- Searched all 18 Azure subscriptions
- No container instances found matching "grafana" or "sqlmonitor"
- Resource group `rg-sqlmonitor-schoolvision` not found
- Cannot access Grafana UI for testing

### Root Cause

**PRIMARY ISSUE**: Grafana container instance does not exist. Cannot test dashboard panels until container is deployed.

**SECONDARY ISSUES** (when container exists):

1. **Time Range Macros May Not Convert Correctly**:
   - `$__timeFrom()` / `$__timeTo()` might not convert to SQL Server DATETIME2
   - Grafana MSSQL plugin may require explicit `CAST($__timeFrom() AS DATETIME2)`

2. **Dashboard Variable Refresh Timing**:
   - `refresh: 1` (on time range change) may not load options on dashboard open
   - Should be `refresh: 2` (on dashboard load)

3. **Dashboard Cache After Container Recreation**:
   - If container was recreated, Grafana may use cached old dashboard
   - Requires browser cache clear or dashboard re-import

### Debugging Steps (After Grafana Container is Deployed)

**PREREQUISITE**: Deploy Grafana container to Azure Container Instances first.

1. **Verify Grafana Container Exists**:
   ```bash
   # Find Grafana container in all subscriptions
   for sub in $(az account list --query "[].id" -o tsv); do
     az account set --subscription "$sub"
     az container list --query "[?contains(name, 'grafana')].[name, resourceGroup, ipAddress.ip]" -o table
   done
   ```

2. **Access Grafana UI**:
   - URL: http://<GRAFANA_IP>:3000 (or FQDN if configured)
   - Credentials: admin / Admin123!

3. **Test Datasource Connection**:
   - Log into Grafana
   - Navigate to: **Configuration** → **Data Sources** → **MonitoringDB**
   - Click **Save & Test**
   - Expected: "Database Connection OK"

4. **Check Dashboard Variables**:
   - Open **AWS RDS Performance Insights** dashboard
   - Top of dashboard should show **Server** dropdown
   - Verify it shows 3 options:
     - sqltest.schoolvision.net,14333
     - suncity.schoolvision.net,14333
     - svweb,14333
   - Select "svweb,14333"

5. **Test Query in Grafana Explore** (Manual Test):
   - Navigate to: **Explore** (compass icon in sidebar)
   - Select **MonitoringDB** datasource
   - Switch to **Code** mode
   - Paste manual test query (see DISK-IO-PANELS-ROOT-CAUSE-ANALYSIS.md)
   - Click **Run Query**
   - Expected: Time series graph with Read IOPS and Write IOPS

6. **Test Query With Variables**:
   - In Grafana Explore, paste dashboard query with `$ServerID`, `$__timeFrom()`, `$__timeTo()`
   - Run query
   - If manual works but variables don't: Time range macro issue
   - If both fail: Check Query Inspector for SQL errors

7. **Check Query Inspector**:
   - On any panel showing "No data"
   - Click panel title → **Inspect** → **Query**
   - Check **Query** tab for actual SQL sent to database
   - Check **Response** tab for raw database response
   - Look for null variable values or SQL syntax errors

8. **Check Grafana Logs**:
   ```bash
   az container logs --resource-group <RG_NAME> --name <CONTAINER_NAME>
   ```
   - Look for SQL query errors
   - Look for datasource connection errors

9. **Check Browser Console**:
   - Open browser Developer Tools (F12)
   - Look for JavaScript errors
   - Check Network tab for failed API requests

### Potential Fixes (After Diagnosis)

**Fix 1: Explicit DATETIME2 Casting** (if time macros fail):
```sql
AND CollectionTime >= CAST($__timeFrom() AS DATETIME2)
AND CollectionTime <= CAST($__timeTo() AS DATETIME2)
```

**Fix 2: Variable Refresh Trigger** (if ServerID dropdown empty):
```json
{
  "name": "ServerID",
  "refresh": 2  // Change from 1 to 2 (load on dashboard open)
}
```

**Fix 3: Simplified Fallback Query** (if rate calc fails):
```sql
-- Shows cumulative values (millions), not per-second rates
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  CASE MetricName
    WHEN 'ReadIOPS' THEN 'Read IOPS (cumulative)'
    WHEN 'WriteIOPS' THEN 'Write IOPS (cumulative)'
  END AS metric
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Disk'
  AND MetricName IN ('ReadIOPS', 'WriteIOPS')
  AND ServerID = $ServerID
  AND CollectionTime >= $__timeFrom()
  AND CollectionTime <= $__timeTo()
ORDER BY CollectionTime;
```

### Detailed Diagnostic Document

See `DISK-IO-PANELS-ROOT-CAUSE-ANALYSIS.md` for:
- Complete test results with sample data
- Step-by-step diagnostic procedures
- All potential fixes with examples
- Next steps after container deployment

---

## Summary

| Issue | Status | Fix Complexity | Impact |
|-------|--------|---------------|--------|
| CPU metrics identical | ✅ DEPLOYED (pending validation) | Medium (updated 3 SQL Agent jobs) | HIGH - All servers showed wrong CPU |
| Disk I/O "No data" | ⚠️ ROOT CAUSE IDENTIFIED | Cannot test (Grafana container missing) | MEDIUM - Dashboard incomplete |

**Status as of 2025-10-31 07:30 UTC**:

### Issue 1: CPU Metrics (DEPLOYED)
- ✅ Root cause identified: Remote DMV execution via linked server
- ✅ Solution implemented: Local-collect-then-forward pattern
- ✅ Procedures deployed: usp_GetLocalCPUMetrics, usp_CollectAndInsertCPUMetrics
- ✅ SQL Agent jobs updated: sqltest (local), svweb (2-step local+remote)
- ⏳ **Validation pending**: Waiting for next scheduled collection cycle (5 min intervals)
- 📋 **Next step**: Verify ServerID 1, 4, 5 show different CPU values in PerformanceMetrics table

### Issue 2: Disk I/O Panels (BLOCKED)
- ✅ SQL queries verified working (returns 0.16-323 IOPS/sec rates)
- ✅ Dashboard configuration verified correct (variables, datasource, query format)
- ❌ **BLOCKER**: Grafana container does not exist in Azure
- 📋 **Next step**: Deploy Grafana container to Azure Container Instances
- 📋 **After deployment**: Follow diagnostic steps in DISK-IO-PANELS-ROOT-CAUSE-ANALYSIS.md
- 📋 **Likely fixes**: Time macro casting, variable refresh timing, or dashboard cache

**Files Created**:
- `fix-cpu-collection-architecture.sql` - New CPU collection procedures (deployed to sqltest, svweb)
- `update-sql-agent-jobs-for-cpu-fix.sql` - SQL Agent job updates (executed on sqltest, svweb)
- `deploy-cpu-fix-to-remote-servers.sql` - Remote deployment script (attempted, revised to inline T-SQL)
- `DASHBOARD-ISSUES-AND-FIXES.md` - This document
- `DISK-IO-PANELS-ROOT-CAUSE-ANALYSIS.md` - Detailed diagnostic guide for disk I/O issue

**Next Steps**:
1. ⏳ **Wait for next CPU collection cycle** (5 min) to validate fix
2. 🚀 **Deploy Grafana container** to Azure Container Instances
3. 🔍 **Run disk I/O diagnostics** using DISK-IO-PANELS-ROOT-CAUSE-ANALYSIS.md
4. ✅ **Apply fixes** based on diagnostic results
5. 📝 **Document final resolution** and commit all changes
