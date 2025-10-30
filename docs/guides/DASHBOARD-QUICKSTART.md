# Performance Analysis Dashboard - Quick Start

## 🎯 Single Consolidated Dashboard

**Location**: `grafana/dashboards/05-performance-analysis.json`
**Access**: http://localhost:3000/d/performance-analysis
**Login**: admin / Admin123!

---

## 📊 Dashboard Sections

### 1. Query Performance
**Long-Running Queries Table** - Top 100 slowest queries
- ✅ **Sortable**: Click any column header to sort
- ✅ **Filterable**: Click filter icon in each column header
- ✅ **Color-coded**:
  - 🔴 Red: > 1000ms (critical)
  - 🟠 Orange: 500-1000ms (needs review)
  - 🟡 Yellow: 100-500ms (acceptable)
  - 🟢 Green: < 100ms (excellent)

**Columns**:
- `DatabaseName` - Which database (filterable)
- `QueryPreview` - First 300 chars of query text (filterable)
- `ExecutionCount` - How many times run
- `AvgDurationMs` - Average duration in milliseconds
- `MaxDurationMs` - Maximum duration ever seen
- `AvgCPUMs` - Average CPU time
- `AvgLogicalReads` - Average I/O operations

### 2. Stored Procedure Performance
**Stored Procedure Table** - Top 100 by duration
- ✅ **Sortable**: Click column headers
- ✅ **Filterable**: Filter icon in headers
- ✅ **Color-coded execution count**:
  - 🔴 Red: > 1000 executions (very frequent)
  - 🟠 Orange: 500-1000 executions
  - 🟡 Yellow: 100-500 executions
  - 🟢 Green: < 100 executions

**Columns**:
- `DatabaseName` - Which database (filterable)
- `ProcedureName` - Schema.ProcedureName (filterable)
- `ExecutionCount` - # times executed
- `AvgCPUMs` - Average CPU time
- `AvgDurationMs` - Average duration
- `AvgLogicalReads` - Average I/O

### 3. Performance Trends
**Query Duration Trend** - Top 5 slowest queries over time
**Procedure Duration Trend** - Top 5 slowest procedures over time

---

## 🔍 How to Use

### Filter by Database

**Method 1: Use the Database Dropdown (Top of Dashboard)**
1. Click the **Database** dropdown at the top
2. Select "All" or a specific database
3. All panels filter automatically

**Method 2: Use Column Filters (In Tables)**
1. Click the filter icon next to "DatabaseName" column header
2. Type database name or select from list
3. Only that table filters

### Sort Queries/Procedures

1. Click any column header to sort
2. Click again to reverse sort order
3. Default sort: Longest duration first

### Find Specific Query/Procedure

1. Click filter icon next to column you want to search
2. Type keyword (e.g., "Customer" in QueryPreview)
3. Click "Apply"
4. Table shows only matching rows

### Common Use Cases

**Find Slowest Queries in a Specific Database**:
1. Top dropdown: Select database (e.g., "ALPHA_SVDB_POS")
2. Query table automatically filtered
3. Already sorted by duration (longest first)

**Find Frequently Run Procedures**:
1. In Procedure table, click "ExecutionCount" column header
2. Reverses to show highest execution count first
3. Red cells = very frequently run

**Find High I/O Queries**:
1. In Query table, click "AvgLogicalReads" column header
2. Sorts by I/O (highest first)
3. High values indicate missing indexes

**Search for Specific Procedure**:
1. Click filter icon next to "ProcedureName"
2. Type part of procedure name (e.g., "Customer")
3. Shows only matching procedures

---

## 🎨 Color Guide

### Duration Thresholds
- 🟢 **< 100ms**: Excellent performance
- 🟡 **100-500ms**: Acceptable
- 🟠 **500-1000ms**: Needs review
- 🔴 **> 1000ms**: Critical - immediate attention

### Execution Count
- 🟢 **< 100**: Low frequency
- 🟡 **100-500**: Moderate
- 🟠 **500-1000**: High frequency
- 🔴 **> 1000**: Very high frequency

### CPU Time
- 🟢 **< 50ms**: Efficient
- 🟡 **50-200ms**: Moderate
- 🟠 **200-500ms**: High
- 🔴 **> 500ms**: Very high

---

## ⚙️ Dashboard Settings

**Auto-Refresh**: 30 seconds (adjustable in time picker)
**Time Range**: Last 6 hours (adjustable in time picker)
**Data Aggregation**: Averages across selected time range

---

## 🔧 Quick Actions

**Change Time Range**:
- Top-right corner → Time picker
- Options: Last 5m, 15m, 1h, 6h, 24h, 7d

**Change Refresh Rate**:
- Time picker → Refresh dropdown
- Options: Off, 5s, 10s, 30s, 1m, 5m

**Export Data**:
- Panel menu (three dots) → Inspect → Data → Download CSV

**View Query Text**:
- Panel menu → Edit
- See full SQL query used to populate panel

---

## 📝 Example Workflows

### Workflow 1: Optimize Slowest Query in Production Database

1. Database dropdown → Select "ALPHA_SVDB_POS"
2. Query table shows filtered results
3. Top row = slowest query (already sorted)
4. Check `AvgLogicalReads` - high value indicates indexing issue
5. Copy query text from `QueryPreview`
6. Investigate in SQL Server Management Studio

### Workflow 2: Find Why Database is Slow

1. Database dropdown → Select target database
2. Look at Query table:
   - Red cells in `AvgDurationMs` = slow queries
   - Red cells in `AvgLogicalReads` = I/O issues
3. Look at Procedure table:
   - Red cells in `ExecutionCount` = heavy load
   - Red cells in `AvgDurationMs` = slow procedures
4. Check trends to see if performance degrading

### Workflow 3: Monitor Specific Procedure

1. Procedure table → Click filter icon next to "ProcedureName"
2. Type procedure name
3. View metrics: Execution count, CPU, Duration, I/O
4. Check "Procedure Duration Trend" chart for performance over time

---

## 🐛 Troubleshooting

**No Data Showing**:
- Verify time range covers when data was collected
- Check SQL Agent job is running:
  ```sql
  EXEC msdb.dbo.sp_start_job @job_name = N'SQL Monitor - Complete Collection';
  ```
- Wait 5 minutes for next collection
- Refresh browser (Ctrl+F5)

**Database Dropdown Empty**:
- No data collected yet
- Widen time range to "Last 24 hours"
- Manually collect:
  ```sql
  EXEC dbo.usp_CollectAllMetrics @ServerID = 1;
  ```

**Filters Not Working**:
- Clear all filters (X icon in filter boxes)
- Refresh dashboard
- Check column has data to filter

---

## 📊 What This Dashboard Shows

**Queries**: Aggregated performance across time range
- Top 100 slowest queries by average duration
- Grouped by database and query text
- Shows average/max duration, CPU, I/O

**Procedures**: Aggregated performance across time range
- Top 100 procedures by average duration
- Grouped by database and procedure name
- Shows execution frequency, CPU, duration, I/O

**Trends**: Real-time performance over time
- Top 5 slowest queries at each collection point
- Top 5 slowest procedures at each collection point
- Identifies performance degradation

---

**Access**: http://localhost:3000/d/performance-analysis

Login: admin / Admin123!
