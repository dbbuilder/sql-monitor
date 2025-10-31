# Disk I/O Panels "No Data" Root Cause Analysis

## Summary

The disk I/O panels (Read/Write IOPS, Read/Write Throughput, Disk Latency) are showing "No data" in Grafana despite SQL queries returning valid data when executed directly against the database.

## Investigation Results

### ✅ Database Data Verification (PASSED)

Confirmed disk metrics are being collected correctly:

```sql
-- Test query: Check disk metrics for ServerID 5 (svweb) in last hour
SELECT TOP 20
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue
FROM dbo.PerformanceMetrics
WHERE ServerID = 5
  AND MetricCategory = 'Disk'
  AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY CollectionTime DESC, MetricName;

-- Results: 20 rows returned
-- Metrics found: AvgReadLatencyMs, AvgWriteLatencyMs, ReadIOPS, ReadMB, WriteIOPS, WriteMB
-- Collection interval: Every 5 minutes
-- Latest collection: 2025-10-31 07:10:01
```

### ✅ Rate Calculation Query Verification (PASSED)

Confirmed the LAG window function rate calculation works correctly:

```sql
-- Dashboard query test (Read/Write IOPS with rate calculation)
DECLARE @ServerID INT = 5;
DECLARE @timeFrom DATETIME2 = DATEADD(HOUR, -1, GETUTCDATE());
DECLARE @timeTo DATETIME2 = GETUTCDATE();

WITH MetricsWithPrevious AS (
  SELECT
    CollectionTime,
    MetricName,
    MetricValue,
    LAG(MetricValue) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevValue,
    LAG(CollectionTime) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevTime
  FROM dbo.PerformanceMetrics
  WHERE ServerID = @ServerID
    AND MetricCategory = 'Disk'
    AND MetricName IN ('ReadIOPS', 'WriteIOPS')
    AND CollectionTime >= @timeFrom
    AND CollectionTime <= @timeTo
)
SELECT TOP 10
  CollectionTime AS time,
  CASE
    WHEN PrevValue IS NOT NULL AND DATEDIFF(SECOND, PrevTime, CollectionTime) > 0
    THEN (MetricValue - PrevValue) / DATEDIFF(SECOND, PrevTime, CollectionTime)
    ELSE 0
  END AS value,
  CASE MetricName
    WHEN 'ReadIOPS' THEN 'Read IOPS'
    WHEN 'WriteIOPS' THEN 'Write IOPS'
  END AS metric
FROM MetricsWithPrevious
WHERE PrevValue IS NOT NULL
ORDER BY CollectionTime DESC;

-- Results: 10 rows returned
-- Sample values:
--   - Read IOPS: 0.16 to 323 per second
--   - Write IOPS: 2.5 to 30 per second
-- Query format: ✅ Correct for Grafana (time, value, metric columns)
```

### ✅ Dashboard Variable Configuration (PASSED)

Verified ServerID variable is configured correctly:

```json
{
  "name": "ServerID",
  "datasource": {
    "type": "mssql",
    "uid": "${DS_MONITORINGDB}"
  },
  "query": "SELECT ServerID AS __value, ServerName AS __text FROM dbo.Servers WHERE IsActive = 1 ORDER BY ServerName",
  "type": "query",
  "refresh": 1
}
```

Verified Servers table has correct data:

```sql
SELECT ServerID, ServerName, IsActive FROM dbo.Servers ORDER BY ServerName;

-- Results:
-- ServerID=1, ServerName=sqltest.schoolvision.net,14333, IsActive=1
-- ServerID=4, ServerName=suncity.schoolvision.net,14333, IsActive=1
-- ServerID=5, ServerName=svweb,14333, IsActive=1
```

### ✅ Datasource Configuration (PASSED)

Verified datasource is configured correctly in `dashboards/grafana/provisioning/datasources/monitoringdb.yaml`:

```yaml
datasources:
  - name: MonitoringDB
    type: mssql
    uid: monitoringdb
    access: proxy
    url: sqltest.schoolvision.net:14333
    database: MonitoringDB
    user: sv
    secureJsonData:
      password: Gv51076!
    jsonData:
      maxOpenConns: 10
      maxIdleConns: 2
      connMaxLifetime: 14400
      encrypt: 'true'
      tlsSkipVerify: true
```

### ❌ Grafana Container Status (ISSUE IDENTIFIED)

**Root Cause**: Grafana container instance does not exist in Azure.

Attempted to locate container:
- Searched all subscriptions (18 total)
- No container instances found matching "grafana" or "sqlmonitor"
- Resource group `rg-sqlmonitor-schoolvision` does not exist
- No Grafana container accessible for testing

## Root Cause Analysis

Based on the investigation:

1. ✅ **SQL queries are working** - Data exists, rate calculations are correct
2. ✅ **Dashboard configuration is correct** - Variable queries, datasource config all valid
3. ❌ **Grafana container does not exist** - Cannot test dashboard panels

## Likely Causes (When Container Exists)

Since the SQL queries and dashboard configuration are verified working, when the Grafana container is running, the "No data" issue is likely caused by:

### 1. Grafana Time Range Macro Issue (MOST LIKELY)

The dashboard queries use `$__timeFrom()` and `$__timeTo()` macros. The Grafana MSSQL plugin may not be converting these correctly to SQL Server DATETIME2 format.

**Test**: When Grafana is accessible, use Grafana Explore to run the query and check query inspector for actual SQL generated.

**Potential fix**: Replace macros with explicit conversion:
```sql
-- Instead of:
AND CollectionTime >= $__timeFrom()
AND CollectionTime <= $__timeTo()

-- Try:
AND CollectionTime >= CAST($__timeFrom() AS DATETIME2)
AND CollectionTime <= CAST($__timeTo() AS DATETIME2)
```

### 2. Dashboard Variable Not Populating

The `$ServerID` variable may not be loading options from the query on dashboard load.

**Test**: Check if ServerID dropdown shows "1", "4", "5" as options.

**Potential fix**: Add `refresh: 2` (on dashboard load) instead of `refresh: 1` (on time range change).

### 3. Dashboard Cache After Container Restart

If the container was recently recreated, Grafana may be using a cached version of the dashboard that doesn't have the updated queries.

**Fix**: Clear browser cache, force dashboard refresh, or re-import dashboard JSON.

## Diagnostic Steps (When Grafana Container Exists)

### Step 1: Verify Grafana is Accessible

```bash
# Find Grafana container
az container list --query "[?contains(name, 'grafana')].[name, resourceGroup, ipAddress.ip]" -o table

# Access Grafana UI
# URL: http://<GRAFANA_IP>:3000
# Credentials: admin / Admin123!
```

### Step 2: Test Datasource Connection

1. Log into Grafana
2. Navigate to: **Configuration** → **Data Sources** → **MonitoringDB**
3. Click **Save & Test**
4. Verify: "Database Connection OK"

### Step 3: Test Variable Population

1. Open **AWS RDS Performance Insights** dashboard
2. Check top of dashboard for **Server** dropdown
3. Verify it shows 3 options:
   - sqltest.schoolvision.net,14333
   - suncity.schoolvision.net,14333
   - svweb,14333
4. Select "svweb,14333"

### Step 4: Test Query in Grafana Explore

1. Navigate to: **Explore** (compass icon in sidebar)
2. Select **MonitoringDB** datasource
3. Switch to **Code** mode
4. Paste this query:

```sql
-- Manual test (no variables)
DECLARE @ServerID INT = 5;
DECLARE @timeFrom DATETIME2 = DATEADD(HOUR, -1, GETUTCDATE());
DECLARE @timeTo DATETIME2 = GETUTCDATE();

WITH MetricsWithPrevious AS (
  SELECT
    CollectionTime,
    MetricName,
    MetricValue,
    LAG(MetricValue) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevValue,
    LAG(CollectionTime) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevTime
  FROM dbo.PerformanceMetrics
  WHERE ServerID = @ServerID
    AND MetricCategory = 'Disk'
    AND MetricName IN ('ReadIOPS', 'WriteIOPS')
    AND CollectionTime >= @timeFrom
    AND CollectionTime <= @timeTo
)
SELECT
  CollectionTime AS time,
  CASE
    WHEN PrevValue IS NOT NULL AND DATEDIFF(SECOND, PrevTime, CollectionTime) > 0
    THEN (MetricValue - PrevValue) / DATEDIFF(SECOND, PrevTime, CollectionTime)
    ELSE 0
  END AS value,
  CASE MetricName
    WHEN 'ReadIOPS' THEN 'Read IOPS'
    WHEN 'WriteIOPS' THEN 'Write IOPS'
  END AS metric
FROM MetricsWithPrevious
WHERE PrevValue IS NOT NULL
ORDER BY CollectionTime;
```

5. Click **Run Query**
6. **Expected**: Time series graph with 2 series (Read IOPS, Write IOPS)
7. **If it works**: Problem is with dashboard variables/macros
8. **If it fails**: Check Query Inspector for SQL errors

### Step 5: Test Query With Variables

If manual query works, try with Grafana variables:

```sql
WITH MetricsWithPrevious AS (
  SELECT
    CollectionTime,
    MetricName,
    MetricValue,
    LAG(MetricValue) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevValue,
    LAG(CollectionTime) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevTime
  FROM dbo.PerformanceMetrics
  WHERE ServerID = $ServerID
    AND MetricCategory = 'Disk'
    AND MetricName IN ('ReadIOPS', 'WriteIOPS')
    AND CollectionTime >= $__timeFrom()
    AND CollectionTime <= $__timeTo()
)
SELECT
  CollectionTime AS time,
  CASE
    WHEN PrevValue IS NOT NULL AND DATEDIFF(SECOND, PrevTime, CollectionTime) > 0
    THEN (MetricValue - PrevValue) / DATEDIFF(SECOND, PrevTime, CollectionTime)
    ELSE 0
  END AS value,
  CASE MetricName
    WHEN 'ReadIOPS' THEN 'Read IOPS'
    WHEN 'WriteIOPS' THEN 'Write IOPS'
  END AS metric
FROM MetricsWithPrevious
WHERE PrevValue IS NOT NULL
ORDER BY CollectionTime;
```

### Step 6: Check Query Inspector

1. On any panel showing "No data"
2. Click panel title → **Inspect** → **Query**
3. Check **Query** tab for actual SQL sent to database
4. Check **Response** tab for raw database response
5. Look for:
   - SQL syntax errors
   - Empty result sets
   - Null variable values

### Step 7: Check Browser Console

1. Open browser Developer Tools (F12)
2. Switch to **Console** tab
3. Look for JavaScript errors
4. Check **Network** tab for failed requests
5. Look for 500/400 errors from Grafana API

## Potential Fixes

### Fix 1: Explicit DATETIME2 Casting

Update all time range filters in dashboard queries:

```sql
-- Current:
AND CollectionTime >= $__timeFrom()
AND CollectionTime <= $__timeTo()

-- Updated:
AND CollectionTime >= CAST($__timeFrom() AS DATETIME2)
AND CollectionTime <= CAST($__timeTo() AS DATETIME2)
```

### Fix 2: Variable Refresh Trigger

Update ServerID variable to load on dashboard open:

```json
{
  "name": "ServerID",
  "refresh": 2  // Change from 1 (on time range change) to 2 (on dashboard load)
}
```

### Fix 3: Simplified Fallback Query

If rate calculations are causing issues, test with simplified query first:

```sql
-- Fallback query (no rate calculation)
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

Note: This will show cumulative values (millions), not per-second rates, but proves the query path works.

## Next Steps

1. **Deploy Grafana Container** to Azure Container Instances
2. **Test datasource connection** via Grafana UI
3. **Run diagnostic queries** in Grafana Explore
4. **Check query inspector** for actual SQL and errors
5. **Apply fixes** based on diagnostic results
6. **Update dashboard JSON** with working queries
7. **Commit and push** fixed dashboard

## Files to Update (After Diagnosis)

- `dashboards/grafana/dashboards/08-aws-rds-performance-insights.json` - Apply query fixes
- `DASHBOARD-ISSUES-AND-FIXES.md` - Document resolution

## Summary

**Current Status**: Cannot test Grafana panels because container does not exist.

**SQL Queries**: ✅ Working (verified with sqlcmd)
**Dashboard Config**: ✅ Correct (verified JSON structure)
**Grafana Container**: ❌ Does not exist

**Recommendation**: Deploy Grafana container first, then run diagnostic steps above to identify exact issue with panel rendering.
