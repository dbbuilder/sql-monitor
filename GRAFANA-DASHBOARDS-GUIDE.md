# Grafana Dashboards - Complete Guide

## 📊 Available Dashboards

### Dashboard 1: Query Performance Drill-Down ✅ NEW
**File**: `grafana/dashboards/03-query-performance-drilldown.json`
**UID**: `query-performance-drilldown`

**Purpose**: Analyze long-running queries with database filtering

**Features**:
- ✅ **Long-Running Queries Table**: Top 100 queries sorted by average duration
- ✅ **Query Duration Trend**: Time-series chart of top 5 slowest queries
- ✅ **Average Duration by Database**: Bar chart showing database-level query performance
- ✅ **Average Logical Reads by Database**: Identify queries with high I/O
- ✅ **Database Filter Variable**: Filter all panels by specific database or view all

**Panels**:

1. **Long-Running Queries (Sorted by Avg Duration)** - Table
   - Columns: DatabaseName, QueryPreview (500 chars), ExecutionCount, AvgDurationMs, MaxDurationMs, AvgCPUMs, AvgLogicalReads, LastExecutionTime
   - Sorted: Longest to shortest average duration
   - Color-coded thresholds:
     - Green: < 100ms
     - Yellow: 100-500ms
     - Orange: 500-1000ms
     - Red: > 1000ms

2. **Query Duration Trend (Top 5 Slowest)** - Time Series
   - Shows duration over time for the 5 slowest queries
   - Legend displays mean and max duration
   - Smooth line interpolation

3. **Average Query Duration by Database** - Bar Gauge
   - Horizontal bars showing average duration per database
   - Top 10 databases
   - Color thresholds for quick identification

4. **Average Logical Reads by Database** - Bar Gauge
   - Identifies databases with high I/O queries
   - Helps spot indexing opportunities

**Variables**:
- `$database` - Dropdown with "All" + all databases from QueryMetrics table
- Auto-refreshes from data
- Filters all panels when changed

**Refresh**: Auto-refresh every 30 seconds

**Time Range**: Default last 6 hours (adjustable)

---

### Dashboard 2: Stored Procedure Performance ✅ NEW
**File**: `grafana/dashboards/04-stored-procedure-performance.json`
**UID**: `stored-procedure-performance`

**Purpose**: Monitor stored procedure execution frequency and performance

**Features**:
- ✅ **Execution Count Ranking**: Top 100 procedures by # of executions
- ✅ **Slowest Procedures**: Top 50 procedures by average duration
- ✅ **Execution Trend**: Time-series of most frequently run procedures
- ✅ **Duration Trend**: Time-series of slowest procedures
- ✅ **Database-level CPU Analysis**: Average CPU usage by database
- ✅ **Database-level I/O Analysis**: Average logical reads by database
- ✅ **Database Filter Variable**: Filter by specific database or view all

**Panels**:

1. **Stored Procedures by Execution Count** - Table
   - Shows most frequently executed procedures
   - Columns: DatabaseName, ProcedureName (Schema.Name), ExecutionCount, AvgCPUMs, AvgDurationMs, AvgLogicalReads, LastExecutionTime
   - Sorted: Highest execution count first
   - Color-coded execution count:
     - Green: < 100
     - Yellow: 100-500
     - Orange: 500-1000
     - Red: > 1000

2. **Slowest Stored Procedures (by Avg Duration)** - Table
   - Top 50 procedures with longest average duration
   - Same columns as panel 1
   - Sorted: Longest duration first
   - Color-coded duration thresholds

3. **Execution Count Trend (Top 5 Most Run)** - Time Series
   - Tracks execution frequency over time
   - Top 5 most frequently executed procedures
   - Shows if usage is increasing/decreasing

4. **Average Duration Trend (Top 5 Slowest)** - Time Series
   - Monitors performance degradation
   - Top 5 slowest procedures
   - Helps identify performance regressions

5. **Average CPU by Database (Procedures)** - Bar Gauge
   - Database-level CPU aggregation
   - Top 10 databases
   - Color thresholds: Green < 50ms, Yellow 50-200ms, Orange 200-500ms, Red > 500ms

6. **Average Logical Reads by Database (Procedures)** - Bar Gauge
   - Database-level I/O analysis
   - Identifies databases with inefficient procedures
   - Color thresholds for high I/O

**Variables**:
- `$database` - Dropdown with "All" + all databases from ProcedureMetrics table
- Auto-refreshes from data
- Filters all panels when changed

**Refresh**: Auto-refresh every 30 seconds

**Time Range**: Default last 6 hours (adjustable)

---

## 🚀 How to Access Dashboards

### 1. Access Grafana

```bash
# Ensure Grafana is running
cd /mnt/d/Dev2/sql-monitor
docker-compose up -d grafana

# Access URL
http://localhost:3000

# Login
Username: admin
Password: Admin123!
```

### 2. Navigate to Dashboards

**Method 1: Dashboard List**
1. Click the **Dashboards** icon (4 squares) in the left sidebar
2. Look for:
   - **Query Performance Drill-Down**
   - **Stored Procedure Performance**

**Method 2: Direct URL**
- Query Performance: http://localhost:3000/d/query-performance-drilldown
- Stored Procedure: http://localhost:3000/d/stored-procedure-performance

**Method 3: Search**
1. Click search icon (magnifying glass)
2. Type "Query" or "Stored Procedure"
3. Click the dashboard

---

## 🔍 Using the Dashboards

### Query Performance Drill-Down Dashboard

**Use Case 1: Find Long-Running Queries**

1. Open the dashboard
2. Look at the **Long-Running Queries** table (top panel)
3. Sort by `AvgDurationMs` (descending) - red cells are slowest
4. Click on a query to see full text in the `QueryPreview` column
5. Check `ExecutionCount` to see frequency
6. Note `AvgLogicalReads` - high values indicate missing indexes

**Use Case 2: Analyze Query Performance for Specific Database**

1. Click the **Database** dropdown at the top
2. Select a specific database (e.g., "ALPHA_SVDB_POS")
3. All panels filter to show only that database
4. Review **Average Query Duration by Database** to compare
5. Check **Query Duration Trend** to see performance over time

**Use Case 3: Identify Queries with High I/O**

1. Scroll to **Average Logical Reads by Database** panel
2. Red/orange bars indicate databases with high I/O queries
3. Select that database from the dropdown
4. Review the query table - sort by `AvgLogicalReads`
5. These queries are candidates for index optimization

**Use Case 4: Monitor Query Performance Over Time**

1. Adjust time range (top-right corner) - try "Last 24 hours"
2. Review **Query Duration Trend** chart
3. Look for spikes or gradual increases (performance degradation)
4. Hover over lines to see specific query text
5. Compare mean vs max duration in the legend

### Stored Procedure Performance Dashboard

**Use Case 1: Find Most Frequently Run Procedures**

1. Open the dashboard
2. Top panel shows procedures sorted by execution count
3. Red/orange cells indicate very frequent execution
4. Check if high-execution procedures have high duration/CPU
5. Consider caching or optimization for frequently run procedures

**Use Case 2: Identify Slowest Procedures**

1. Scroll to **Slowest Stored Procedures** table
2. Sorted by average duration (descending)
3. Red cells (> 1000ms) need immediate attention
4. Orange cells (500-1000ms) should be reviewed
5. Note the database and schema for investigation

**Use Case 3: Monitor Procedure Performance by Database**

1. Click **Database** dropdown at top
2. Select a specific database
3. View **Execution Count Trend** to see usage patterns
4. View **Average Duration Trend** to spot regressions
5. Check **Average CPU by Database** for resource usage

**Use Case 4: Track Performance Degradation**

1. Set time range to "Last 7 days"
2. Review **Average Duration Trend** chart
3. Look for upward trends (performance getting worse)
4. Compare with **Execution Count Trend** to see if load increased
5. Investigate procedures showing degradation

**Use Case 5: Find I/O-Heavy Procedures**

1. Scroll to **Average Logical Reads by Database** panel
2. High values (orange/red) indicate potential indexing issues
3. Select that database from dropdown
4. In the main table, sort by `AvgLogicalReads`
5. Review procedure code for missing WHERE clauses or indexes

---

## 📈 Dashboard Variables

### Database Variable (`$database`)

**Purpose**: Filter all panels by a specific database

**Values**:
- "All" - Shows data from all databases (default)
- Database names - Dynamically populated from data

**How to Use**:
1. Click the dropdown at the top of the dashboard
2. Select "All" to see everything
3. Select a specific database to filter all panels
4. Variable auto-refreshes as new databases appear in data

**SQL Query** (auto-runs):
```sql
SELECT 'All' AS DatabaseName
UNION
SELECT DISTINCT DatabaseName
FROM dbo.QueryMetrics  -- or ProcedureMetrics
WHERE ServerID = 1
ORDER BY DatabaseName
```

---

## 🎨 Color Coding Reference

### Query Duration (AvgDurationMs)
- 🟢 **Green**: < 100ms (excellent)
- 🟡 **Yellow**: 100-500ms (acceptable)
- 🟠 **Orange**: 500-1000ms (needs review)
- 🔴 **Red**: > 1000ms (critical - needs immediate attention)

### Procedure Duration (AvgDurationMs)
- 🟢 **Green**: < 100ms (excellent)
- 🟡 **Yellow**: 100-500ms (acceptable)
- 🟠 **Orange**: 500-1000ms (needs review)
- 🔴 **Red**: > 1000ms (critical)

### Execution Count
- 🟢 **Green**: < 100 executions
- 🟡 **Yellow**: 100-500 executions
- 🟠 **Orange**: 500-1000 executions
- 🔴 **Red**: > 1000 executions (very frequent)

### CPU Usage (AvgCPUMs)
- 🟢 **Green**: < 50ms (efficient)
- 🟡 **Yellow**: 50-200ms (moderate)
- 🟠 **Orange**: 200-500ms (high)
- 🔴 **Red**: > 500ms (very high)

### Logical Reads
- 🟢 **Green**: < 10,000 (efficient)
- 🟡 **Yellow**: 10,000-50,000 (moderate)
- 🟠 **Orange**: 50,000-100,000 (high)
- 🔴 **Red**: > 100,000 (very high - likely missing indexes)

---

## 🔧 Customizing Dashboards

### Change Refresh Rate

1. Click the time picker (top-right)
2. Find "Refresh" dropdown
3. Options: Off, 5s, 10s, 30s, 1m, 5m, 15m, 30m, 1h
4. Default: 30s

### Change Time Range

1. Click the time picker (top-right)
2. Select from presets:
   - Last 5 minutes
   - Last 15 minutes
   - Last 1 hour
   - Last 6 hours (default)
   - Last 24 hours
   - Last 7 days
3. Or use "Custom range" for specific dates

### Modify Panel Queries

1. Edit dashboard (gear icon → Edit)
2. Click panel title → Edit
3. Modify SQL query
4. Click "Apply" to save
5. Save dashboard

### Add New Panels

1. Edit dashboard
2. Click "Add" → "Visualization"
3. Select datasource: MonitoringDB
4. Write SQL query
5. Choose visualization type (Table, Time series, Bar gauge, etc.)
6. Configure options
7. Click "Apply"
8. Save dashboard

---

## 📊 Sample SQL Queries for Custom Panels

### Top 10 Databases by Total Query Duration

```sql
SELECT
    DatabaseName,
    SUM(TotalDurationMs) / 1000.0 AS TotalDurationSeconds
FROM dbo.QueryMetrics
WHERE ServerID = 1
  AND $__timeFilter(CollectionTime)
GROUP BY DatabaseName
ORDER BY TotalDurationSeconds DESC
LIMIT 10
```

### Query Execution Frequency Heatmap

```sql
SELECT
    DATEPART(HOUR, CollectionTime) AS Hour,
    DATEPART(WEEKDAY, CollectionTime) AS DayOfWeek,
    SUM(ExecutionCount) AS TotalExecutions
FROM dbo.QueryMetrics
WHERE ServerID = 1
  AND $__timeFilter(CollectionTime)
GROUP BY DATEPART(HOUR, CollectionTime), DATEPART(WEEKDAY, CollectionTime)
ORDER BY DayOfWeek, Hour
```

### Procedure CPU vs Duration Scatter

```sql
SELECT
    CollectionTime AS time,
    AvgCPUMs AS x,
    AvgDurationMs AS y,
    SchemaName + '.' + ProcedureName AS metric
FROM dbo.ProcedureMetrics
WHERE ServerID = 1
  AND DatabaseName = '$database'
  AND $__timeFilter(CollectionTime)
```

---

## 🎯 Best Practices

### Performance Optimization Workflow

1. **Identify**: Use dashboards to find slow queries/procedures
2. **Analyze**: Review query text and execution patterns
3. **Investigate**: Check for:
   - Missing indexes (high logical reads)
   - Table scans (high duration + high reads)
   - Parameter sniffing (high max vs avg duration)
   - Blocking (check WaitEventsByDatabase)
4. **Fix**: Apply indexes, rewrite queries, update statistics
5. **Monitor**: Use time-series charts to verify improvement

### Regular Monitoring Routine

**Daily**:
- Check **Long-Running Queries** table for new red cells
- Review **Execution Count Trend** for usage spikes
- Monitor **Average Duration Trend** for regressions

**Weekly**:
- Review all databases using the dropdown filter
- Compare week-over-week performance
- Identify procedures/queries for optimization

**Monthly**:
- Analyze **Average Logical Reads** trends
- Plan index maintenance
- Review query patterns for refactoring opportunities

---

## 🐛 Troubleshooting

### Dashboard Shows "No Data"

**Cause**: No metrics collected yet or time range too narrow

**Solution**:
1. Verify SQL Agent job is running:
   ```sql
   SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name LIKE 'SQL Monitor%';
   ```
2. Check recent job history:
   ```sql
   SELECT TOP 5 run_date, run_time, run_status
   FROM msdb.dbo.sysjobhistory h
   INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
   WHERE j.name = 'SQL Monitor - Complete Collection'
   ORDER BY instance_id DESC;
   ```
3. Manually collect metrics:
   ```sql
   EXEC dbo.usp_CollectAllMetrics @ServerID = 1;
   ```
4. Widen time range to "Last 24 hours"
5. Refresh browser (Ctrl+F5)

### Variables Not Showing Databases

**Cause**: No data in tables or variable query error

**Solution**:
1. Check if data exists:
   ```sql
   SELECT DISTINCT DatabaseName FROM dbo.QueryMetrics WHERE ServerID = 1;
   ```
2. Verify datasource connection in Grafana
3. Edit dashboard → Settings → Variables → Check query
4. Ensure variable refresh is set to "On Dashboard Load"

### Panels Not Filtering by Database Variable

**Cause**: Variable not used in panel query

**Solution**:
1. Edit panel
2. Check SQL query contains:
   ```sql
   AND DatabaseName LIKE CASE WHEN '$database' = 'All' THEN '%' ELSE '$database' END
   ```
3. Ensure variable name matches: `$database` (not `${database}`)

### Time Series Shows Disconnected Points

**Cause**: Gaps in data collection

**Solution**:
1. Verify SQL Agent job runs every 5 minutes
2. Check job history for failures
3. Enable "Connect null values" in panel options:
   - Edit panel → Panel options → Graph styles → Connect null values

---

## ✅ Dashboard Deployment Checklist

- [x] Query Performance Drill-Down dashboard created
- [x] Stored Procedure Performance dashboard created
- [x] Database filter variable configured on both dashboards
- [x] Color thresholds set for all metrics
- [x] Auto-refresh enabled (30 seconds)
- [x] Time-series charts configured
- [x] Tables sorted correctly
- [x] Dashboards saved to `grafana/dashboards/` directory
- [x] Grafana restarted to load new dashboards

**Next Steps**:
- [ ] Create additional dashboards (Database Drill-Down, Server Overview)
- [ ] Set up Grafana alerts for critical thresholds
- [ ] Configure email/Slack notifications
- [ ] Export dashboards for backup

---

## 📚 Additional Resources

**Grafana Documentation**:
- [Panel Types](https://grafana.com/docs/grafana/latest/panels-visualizations/)
- [Variables](https://grafana.com/docs/grafana/latest/dashboards/variables/)
- [Time Series](https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/time-series/)

**SQL Server Monitoring**:
- `QUICK-START.md` - Fast setup with working SQL commands
- `DRILL-DOWN-GUIDE.md` - Hierarchical drill-down analysis guide
- `DEPLOYMENT-COMPLETE.md` - Full deployment status

---

**Dashboards Ready to Use!** 🚀

Access them at: http://localhost:3000
