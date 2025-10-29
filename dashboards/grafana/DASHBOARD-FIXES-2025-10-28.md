# Phase 1.9 Dashboard Fixes - 2025-10-28

## Problem

Three Phase 1.9 dashboards were not showing data:
1. **SQL Server Performance Overview** (`sql-server-overview.json`)
2. **Detailed Metrics View** (`detailed-metrics.json`)
3. **Performance Analysis** (`05-performance-analysis.json`)

## Root Causes

### 1. Missing Stored Procedures

The Phase 1.9 stored procedures from `26-create-aggregation-procedures.sql` were never deployed to the database.

**Solution**: Deployed stored procedures:
- ✅ `usp_GetServerHealthStatus`
- ✅ `usp_GetMetricHistory`
- ✅ `usp_GetTopQueries`
- ✅ `usp_GetDatabaseSummary`
- ⚠️ `usp_GetResourceTrends` - Failed due to missing `PerfSnapshotRun` table

### 2. Incorrect SQL Queries in Dashboards

Dashboard queries referenced `ServerName` column directly from `PerformanceMetrics` table, but that table only has `ServerID`.

**Example Problem Query:**
```sql
-- ❌ BROKEN: ServerName doesn't exist in PerformanceMetrics
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  ServerName AS metric
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'CPU'
```

**Fixed Query:**
```sql
-- ✅ FIXED: Added JOIN to Servers table
SELECT
  pm.CollectionTime AS time,
  pm.MetricValue AS value,
  s.ServerName AS metric
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.MetricCategory = 'CPU'
```

## Fixes Applied

### 1. Deployed Stored Procedures

```bash
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB \
  -i /mnt/d/dev2/sql-monitor/database/26-create-aggregation-procedures.sql
```

**Result**: 4 out of 5 procedures deployed successfully.

### 2. Fixed Dashboard SQL Queries

Created Python script (`/tmp/fix-dashboards.py`) to automatically fix all queries:

```bash
python3 /tmp/fix-dashboards.py \
  dashboards/grafana/dashboards/sql-server-overview.json \
  dashboards/grafana/dashboards/05-performance-analysis.json
```

**Results (Initial Pass):**
- **sql-server-overview.json**: Fixed 3 queries (CPU, Memory panels)
- **05-performance-analysis.json**: No changes needed
- **detailed-metrics.json**: Partial - Panel 1 had correct JOIN, Panel 2 missed

### 3. Additional Fix for detailed-metrics.json (2025-10-28 Evening)

After user testing, discovered Panel 2 ("All Metrics Time Series") was still broken.

**Problem Query (Panel 2):**
```sql
-- ❌ BROKEN: ServerName concatenation without JOIN
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  ServerName + ' - ' + MetricCategory + ' - ' + MetricName AS metric
FROM dbo.PerformanceMetrics
WHERE CollectionTime >= DATEADD(hour, -24, GETUTCDATE())
```

**Fixed Query:**
```sql
-- ✅ FIXED: Added JOIN with proper table aliases
SELECT
  pm.CollectionTime AS time,
  pm.MetricValue AS value,
  s.ServerName + ' - ' + pm.MetricCategory + ' - ' + pm.MetricName AS metric
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.CollectionTime >= DATEADD(hour, -24, GETUTCDATE())
```

**Action**: Manually edited `detailed-metrics.json` and restarted Grafana

## Current Dashboard Status

### ✅ Working Dashboards

1. **SQL Server Performance Overview** (`sql-server-overview.json`)
   - CPU Usage (%) - Time series chart
   - Memory Usage (%) - Time series chart
   - Current CPU - Gauge
   - Current Memory - Gauge
   - Data source: `PerformanceMetrics` JOIN `Servers`

2. **Detailed Metrics View** (`detailed-metrics.json`)
   - Recent Metrics (Last 24 Hours) - Table
   - All Metrics Time Series - Time series chart
   - Data source: `PerformanceMetrics` JOIN `Servers`

3. **Performance Analysis** (`05-performance-analysis.json`)
   - Already correctly configured
   - Data source: Multiple tables

### ⚠️ Partial/Schema Mismatch

4. **Table Browser** (`01-table-browser.json`) - Phase 1.25
5. **Table Details** (`02-table-details.json`) - Phase 1.25
6. **Code Browser** (`03-code-browser.json`) - Phase 1.25
7. **Audit Logging** (`07-audit-logging.json`) - Phase 2.0

## Database Schema (Actual)

### Available Tables with Data

| Table | Row Count | Purpose |
|-------|-----------|---------|
| `Servers` | 1 | Server registration |
| `PerformanceMetrics` | 151 | CPU, Memory metrics |
| `ProcedureMetrics` | 168 | Stored procedure performance |
| `QueryMetrics` | 700 | Query performance |
| `DatabaseMetrics` | 1,660 | Database size, backups |

### PerformanceMetrics Schema

```sql
MetricID INT
ServerID INT          -- ⚠️ No ServerName column!
CollectionTime DATETIME2
MetricCategory VARCHAR(50)  -- 'CPU', 'Memory', etc.
MetricName VARCHAR(100)     -- 'Percent', etc.
MetricValue DECIMAL(18,4)
```

### Servers Schema

```sql
ServerID INT
ServerName VARCHAR(128)     -- ✓ Has ServerName!
Environment VARCHAR(50)
IsActive BIT
CreatedUTC DATETIME2
LastModifiedUTC DATETIME2
```

## Testing

### Verify Dashboard Data

1. **Access Grafana**: http://localhost:3000
   - Username: `admin`
   - Password: `Admin123!`

2. **Navigate to Dashboards** → "SQL Monitor" folder

3. **Test Each Dashboard:**
   - SQL Server Performance Overview - Should show CPU/Memory charts
   - Detailed Metrics View - Should show table of recent metrics
   - Performance Analysis - Should show performance data

### Manual Query Test

```sql
-- Test the fixed query directly in SSMS
SELECT TOP 10
  pm.CollectionTime AS time,
  pm.MetricValue AS value,
  s.ServerName AS metric
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE
  pm.MetricCategory = 'CPU'
  AND pm.MetricName = 'Percent'
  AND pm.CollectionTime >= DATEADD(hour, -24, GETUTCDATE())
ORDER BY pm.CollectionTime ASC;
```

**Expected**: Should return rows with ServerName, CollectionTime, MetricValue

## Remaining Issues

### 1. Missing `usp_GetResourceTrends` Stored Procedure

The procedure references `PerfSnapshotRun` table which doesn't exist in our schema.

**Options:**
- A. Create the missing table structure
- B. Rewrite the procedure to use `PerformanceMetrics` table
- C. Remove the procedure (not used by current dashboards)

**Recommendation**: Option B - Rewrite to use existing tables

```sql
-- Proposed rewrite
CREATE PROCEDURE dbo.usp_GetResourceTrends
    @ServerID INT = NULL,
    @Days INT = 7
AS
BEGIN
    SELECT
        s.ServerID,
        s.ServerName,
        s.Environment,
        CAST(pm.CollectionTime AS DATE) AS CollectionDate,

        -- CPU metrics
        AVG(CASE WHEN pm.MetricCategory = 'CPU' THEN pm.MetricValue END) AS AvgCpuPct,
        MAX(CASE WHEN pm.MetricCategory = 'CPU' THEN pm.MetricValue END) AS MaxCpuPct,

        -- Memory metrics
        AVG(CASE WHEN pm.MetricCategory = 'Memory' THEN pm.MetricValue END) AS AvgMemoryPct,
        MAX(CASE WHEN pm.MetricCategory = 'Memory' THEN pm.MetricValue END) AS MaxMemoryPct,

        COUNT(*) AS DataPoints
    FROM dbo.Servers s
    INNER JOIN dbo.PerformanceMetrics pm ON s.ServerID = pm.ServerID
    WHERE pm.CollectionTime >= DATEADD(DAY, -@Days, GETUTCDATE())
      AND (@ServerID IS NULL OR s.ServerID = @ServerID)
    GROUP BY
        s.ServerID,
        s.ServerName,
        s.Environment,
        CAST(pm.CollectionTime AS DATE)
    ORDER BY
        s.ServerName,
        CollectionDate DESC;
END
```

### 2. Dashboard Query Performance

Some dashboards query raw `PerformanceMetrics` which could be slow with large datasets.

**Optimization Options:**
- Add indexes on `(MetricCategory, MetricName, CollectionTime)`
- Pre-aggregate data into hourly/daily summaries
- Implement data retention policies (delete old metrics)

### 3. Time Zone Handling

Queries use `GETUTCDATE()` but Grafana might display in local time.

**Solution**: Ensure Grafana timezone settings match database timezone

## Summary

✅ **Fixed**: 4 dashboard SQL queries with missing JOINs (3 in sql-server-overview, 1 in detailed-metrics)
✅ **Deployed**: 4 Phase 1.9 stored procedures
✅ **Working**: Core performance monitoring dashboards now functional (verified after second fix)

⏳ **Remaining**:
- Rewrite `usp_GetResourceTrends` for actual schema
- Add database indexes for performance
- Create missing Phase 1.9 dashboards (Instance Health, Wait Stats, etc.)

## Files Modified

```
dashboards/grafana/dashboards/
├── sql-server-overview.json        ✏️ MODIFIED (3 queries fixed - initial pass)
├── detailed-metrics.json           ✏️ MODIFIED (1 query fixed - Panel 2, second pass)
├── 05-performance-analysis.json    ✓ VERIFIED (already correct)

database/
└── (deployed 26-create-aggregation-procedures.sql)
```

## Next Steps

1. ✅ **Test dashboards in Grafana** - Verify data shows up
2. ⏳ **Create missing dashboards** - Instance Health, Wait Stats, Blocking, etc.
3. ⏳ **Rewrite usp_GetResourceTrends** - Use actual schema
4. ⏳ **Add database indexes** - Optimize query performance
5. ⏳ **Document dashboard usage** - User guide for each dashboard

---

**Dashboard fixes complete!** The three Phase 1.9 performance dashboards should now display data correctly. 🎉
