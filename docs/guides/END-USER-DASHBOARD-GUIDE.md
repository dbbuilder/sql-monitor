# End-User Dashboard Guide
## SQL Server Monitor - Phase 1.9

**Last Updated:** 2025-10-28
**Target Audience:** Business Users, Managers, Analysts

## Overview

This guide helps you navigate and use the SQL Server Monitor dashboards in Grafana to monitor database performance, track trends, and troubleshoot issues.

## Getting Started

### Accessing Grafana

1. **Open your web browser** and navigate to:
   ```
   http://localhost:3000
   ```
   *(Replace `localhost` with your server hostname if accessing remotely)*

2. **Login Credentials:**
   - **Username:** `admin`
   - **Password:** `Admin123!` *(default - should be changed after first login)*

3. **First Login:**
   - On first login, you'll be prompted to change the default password
   - Choose a strong password and save it securely
   - Click "Submit" to continue

### Dashboard Navigation

After logging in, you'll see the Grafana home screen.

**To access SQL Server Monitor dashboards:**

1. Click the **hamburger menu** (☰) in the top-left corner
2. Select **"Dashboards"**
3. Navigate to the **"SQL Monitor"** folder
4. Click on any dashboard to open it

**Available Dashboards:**
- SQL Server Performance Overview
- Detailed Metrics View
- Performance Analysis
- Table Browser
- Table Details
- Code Browser
- Audit Logging

## Dashboard Overview

### 1. SQL Server Performance Overview

**Purpose:** Real-time and historical performance monitoring of CPU and Memory usage across all SQL Server instances.

**Use Cases:**
- Daily health checks
- Identifying performance spikes
- Comparing server resource usage
- Capacity planning

**Panels:**

#### CPU Usage (%) - Time Series Chart
- **What it shows:** CPU utilization percentage over time for each server
- **Time range:** Last 24 hours (default, adjustable)
- **How to read:**
  - Green line: Normal CPU usage (< 70%)
  - Yellow: Elevated CPU (70-90%)
  - Red: Critical CPU (> 90%)
  - Hover over any point to see exact values

#### Memory Usage (%) - Time Series Chart
- **What it shows:** Memory utilization percentage over time
- **Interpretation:**
  - SQL Server typically uses all available memory (by design)
  - Sudden drops may indicate server restarts
  - Consistent 100% is normal for production servers

#### Current CPU - Gauge
- **What it shows:** Most recent CPU reading
- **Thresholds:**
  - Green: 0-70% (healthy)
  - Yellow: 70-90% (warning)
  - Red: 90-100% (critical)

#### Current Memory - Gauge
- **What it shows:** Most recent memory reading
- **Thresholds:** Same as CPU gauge

**Common Questions:**

**Q: Why is my memory always at 100%?**
A: This is normal! SQL Server is designed to use all available memory for caching data to improve performance. It will release memory if other applications need it.

**Q: When should I be concerned about CPU usage?**
A: Sustained CPU usage above 80% for more than 30 minutes indicates you should investigate what queries or processes are consuming resources.

**Q: What if I see no data?**
A: Check the time range picker (top-right). If the selected time range has no data, expand it to "Last 24 hours" or "Last 7 days."

---

### 2. Detailed Metrics View

**Purpose:** Granular view of all performance metrics with raw data table and time series visualization.

**Use Cases:**
- Detailed performance investigation
- Exporting raw metric data
- Troubleshooting specific time periods
- Auditing metric collection

**Panels:**

#### Recent Metrics (Last 24 Hours) - Table
- **Columns:**
  - **CollectionTime:** When the metric was collected (UTC)
  - **ServerName:** SQL Server instance name
  - **MetricCategory:** Type of metric (CPU, Memory, Disk, etc.)
  - **MetricName:** Specific metric name (Percent, UsedMB, etc.)
  - **MetricValue:** Numeric value of the metric

- **Features:**
  - **Sorting:** Click any column header to sort
  - **Color-coding:** MetricValue column uses color backgrounds:
    - Green: Normal (< 70)
    - Yellow: Warning (70-85)
    - Red: Critical (> 85)
  - **Pagination:** Table shows top 100 rows, scrollable

- **How to use:**
  - **Filter by server:** Use the search box to find specific server
  - **Export data:** Click the panel title → "Inspect" → "Data" → "Download CSV"
  - **Find patterns:** Sort by MetricValue descending to find highest values

#### All Metrics Time Series - Chart
- **What it shows:** Every metric plotted over time as separate lines
- **Legend:** Shows server name, category, and metric name
  - Example: `SQL-PROD-01 - CPU - Percent`
- **Statistics:** Legend displays mean, last value, max, min for each series

**Common Questions:**

**Q: The table is overwhelming with too many metrics. How do I filter?**
A: Use the search box above the table (magnifying glass icon) to search for specific servers, categories, or metric names.

**Q: Can I export this data to Excel?**
A: Yes! Click the panel title → "Inspect" → "Data" → "Download CSV". Open the CSV in Excel for further analysis.

**Q: Why do some lines disappear on the chart?**
A: Lines with very different scales can make others appear flat. Click legend items to hide/show specific metrics for better visibility.

---

### 3. Performance Analysis

**Purpose:** Advanced analysis of query performance, stored procedure execution, and database-level metrics.

**Use Cases:**
- Finding slow queries
- Identifying frequently-executed procedures
- Analyzing database growth trends
- Troubleshooting performance degradation

**Panels:**

*(This dashboard's specific panels depend on the actual configuration. Update this section after reviewing the 05-performance-analysis.json content.)*

**Common Analysis Scenarios:**

#### Finding Slow Queries
1. Look for queries with high **Average Duration** (> 1000ms)
2. Check **Execution Count** - frequent slow queries have bigger impact
3. Note the **Database Name** and **Query Text** for optimization

#### Identifying Resource-Heavy Procedures
1. Sort by **CPU Time** or **Logical Reads**
2. High values indicate procedures that need optimization
3. Work with developers to add indexes or rewrite queries

---

### 4. Table Browser (Phase 1.25)

**Purpose:** Browse database tables, view row counts, and monitor table growth.

**Use Cases:**
- Database inventory
- Identifying large tables
- Monitoring table growth
- Capacity planning

**Note:** This dashboard requires Phase 1.25 schema extensions. If you see "No data" errors, the required tables may not be configured yet.

---

### 5. Table Details (Phase 1.25)

**Purpose:** Detailed view of a specific table's statistics, indexes, and partition information.

**Use Cases:**
- Analyzing table structure
- Index fragmentation monitoring
- Partition management
- Storage optimization

**Note:** Requires Phase 1.25 schema extensions.

---

### 6. Code Browser (Phase 1.25)

**Purpose:** Browse stored procedures, functions, and views across databases.

**Use Cases:**
- Code inventory
- Finding procedures by name or database
- Tracking code modifications
- Database documentation

**Note:** Requires Phase 1.25 schema extensions.

---

### 7. Audit Logging (Phase 2.0)

**Purpose:** Security audit trail showing user access, permission changes, and sensitive operations.

**Use Cases:**
- Compliance reporting
- Security investigations
- User activity tracking
- Access auditing

**Note:** Requires Phase 2.0 authentication and authorization features.

---

## Dashboard Features

### Time Range Picker

Located in the **top-right corner** of every dashboard.

**Quick Ranges:**
- Last 5 minutes
- Last 15 minutes
- Last 30 minutes
- Last 1 hour
- Last 3 hours
- Last 6 hours
- Last 12 hours
- Last 24 hours (default for most dashboards)
- Last 7 days
- Last 30 days

**Custom Range:**
- Click "Absolute time range"
- Select start and end dates/times
- Click "Apply time range"

**Tip:** If you see "No data," try expanding the time range to "Last 7 days" to ensure there's data in the selected period.

---

### Auto-Refresh

Keep dashboards up-to-date automatically.

**To enable:**
1. Click the **refresh icon** (🔄) in the top-right corner
2. Select refresh interval:
   - Off (manual refresh only)
   - 5s, 10s, 30s (for real-time monitoring)
   - 1m (recommended for most use cases)
   - 5m, 15m, 30m (for long-term monitoring)
   - 1h (for historical analysis)

**Best Practices:**
- Use **1m refresh** for active monitoring
- Use **5m refresh** for background monitoring
- Use **Off** when analyzing historical data (saves resources)

---

### Dashboard Variables

Some dashboards have **dropdown filters** at the top to customize the view.

**Common Variables:**
- **Server:** Filter to show only specific SQL Server instance
- **Database:** Filter to specific database
- **Time Grain:** Choose aggregation level (minute, hour, day)

**How to use:**
1. Click the dropdown at the top of the dashboard
2. Select one or more values (multi-select enabled on some variables)
3. Dashboard will automatically update

---

### Panel Actions

Every panel has additional options accessed via the **panel title**.

**Click the panel title** to reveal:
- **View:** Full-screen view of the panel
- **Edit:** Modify the panel (requires edit permissions)
- **Share:** Get a link to share this panel
- **Explore:** Open in Grafana Explore for ad-hoc queries
- **Inspect:** View raw data, query, and panel JSON
  - **Data:** See the raw query results
  - **Query:** View the SQL query
  - **Panel JSON:** See the panel configuration

**Useful Actions:**

#### Export Data
1. Click panel title → **"Inspect"**
2. Click **"Data"** tab
3. Click **"Download CSV"** or **"Download Excel"**
4. Open in spreadsheet application

#### View SQL Query
1. Click panel title → **"Inspect"**
2. Click **"Query"** tab
3. See the exact SQL query being executed
4. Copy query to run in SSMS for debugging

---

### Zoom and Pan

**Time Series Charts** support interactive zoom and pan.

**To zoom in:**
- Click and drag horizontally on the chart to select a time range
- Chart will zoom to the selected period

**To zoom out:**
- Click the **"Zoom out"** button (appears after zooming)
- Or double-click the chart to reset zoom

**To pan:**
- Hold **Shift** and drag the chart left/right

---

## Common Use Cases

### 1. Daily Health Check

**Goal:** Verify all servers are healthy and collecting metrics.

**Steps:**
1. Open **"SQL Server Performance Overview"** dashboard
2. Check **time range** is set to "Last 24 hours"
3. Verify all expected servers appear in the CPU and Memory charts
4. Look for:
   - ✅ Continuous lines (data is being collected)
   - ⚠️ Gaps in lines (collection failures)
   - 🔴 Sustained red zones (> 90% CPU or critical thresholds)

**What to do if:**
- **Lines are flat/missing:** Check SQL Agent jobs on affected servers (see DBA Operational Guide)
- **CPU in red zone:** Investigate with "Performance Analysis" dashboard to find culprit queries

---

### 2. Troubleshooting High CPU Usage

**Goal:** Identify what's causing high CPU on a specific server.

**Steps:**
1. Open **"SQL Server Performance Overview"**
2. Identify the server with high CPU (red line)
3. Note the **time period** when CPU spiked
4. Open **"Performance Analysis"** dashboard
5. Set **time range** to match the spike period
6. Look at **"Top Queries by CPU"** panel
7. Identify queries with highest CPU time during that period
8. Copy the **Query Text** and **Database Name**
9. Work with developers to optimize or add indexes

**Common Causes:**
- Missing indexes (queries doing table scans)
- Poorly-written queries (nested loops, cursors)
- Parameter sniffing (bad execution plans)
- Blocking/locking (check blocking dashboard)

---

### 3. Finding Long-Running Queries

**Goal:** Identify slow queries that are impacting user experience.

**Steps:**
1. Open **"Performance Analysis"** dashboard
2. Set time range to period when users reported slowness
3. Look at **"Top Queries by Duration"** panel
4. Sort by **Average Duration** (descending)
5. Focus on queries with:
   - **High Avg Duration** (> 5000ms = 5 seconds)
   - **High Execution Count** (frequent execution)
6. Copy the **Query Text** for analysis

**Investigation:**
- Run the query in SSMS with "Include Actual Execution Plan"
- Look for:
  - Table scans (missing indexes)
  - Key lookups (covering index needed)
  - High estimated rows vs. actual rows (statistics issue)

---

### 4. Capacity Planning

**Goal:** Predict when servers will run out of resources.

**Steps:**
1. Open **"SQL Server Performance Overview"**
2. Set time range to **"Last 30 days"**
3. Look at **Memory Usage** trend
4. Open **"Detailed Metrics View"**
5. Look for metrics related to:
   - **Disk Space** (if available)
   - **Database Growth** (in Performance Analysis)
6. Export data to Excel for trend analysis
7. Calculate growth rate (GB per month)
8. Predict when thresholds will be exceeded

**Example Calculation:**
```
Current database size: 500 GB
Growth rate: 10 GB/month
Available disk space: 100 GB
Months until full: 100 GB ÷ 10 GB/month = 10 months
```

---

### 5. Comparing Server Performance

**Goal:** Compare multiple servers to identify outliers or inconsistencies.

**Steps:**
1. Open **"SQL Server Performance Overview"**
2. Set time range to **"Last 7 days"**
3. Compare CPU and Memory lines across servers
4. Look for:
   - Servers consistently higher than others (workload imbalance)
   - Servers with spiky patterns (batch jobs, ETL)
   - Servers with declining performance over time (resource exhaustion)

**Actions:**
- Rebalance workloads if one server is overloaded
- Schedule batch jobs during off-peak hours
- Investigate growing resource usage

---

### 6. Verifying Backup Completion

**Goal:** Ensure all databases were backed up successfully.

**Steps:**
1. Open **"Performance Analysis"** dashboard (or custom backup dashboard if available)
2. Look for **"Last Backup"** or **"Backup Status"** panel
3. Check for databases with:
   - ⚠️ **Last backup > 24 hours ago** (daily backups not running)
   - 🔴 **Last backup > 7 days ago** (critical - backup failure)
4. Note affected databases and investigate backup jobs

**Escalation:**
- If backups are failing, contact DBA immediately (data loss risk)

---

## Interpreting Metrics

### CPU Metrics

| Metric | Healthy Range | Warning | Critical | Action |
|--------|---------------|---------|----------|--------|
| CPU % | 0-70% | 70-90% | > 90% | Investigate queries, consider scaling |

**Notes:**
- Brief spikes (< 5 minutes) are normal for batch jobs
- Sustained high CPU (> 30 minutes) needs investigation
- 100% CPU can cause query timeouts and slowness

---

### Memory Metrics

| Metric | Healthy Range | Warning | Critical | Action |
|--------|---------------|---------|----------|--------|
| Memory % | 80-100% | < 80% | < 50% | Normal for SQL Server; low values indicate issues |

**Notes:**
- SQL Server **should** use all available memory
- Low memory usage indicates:
  - Server restart (memory cache rebuilding)
  - Configuration issue (max server memory too low)
  - Memory pressure from other applications

---

### Query Performance Metrics

| Metric | Healthy | Warning | Critical | Action |
|--------|---------|---------|----------|--------|
| Avg Duration | < 100ms | 100-1000ms | > 1000ms | Optimize query, add indexes |
| Logical Reads | < 1000 | 1000-10000 | > 10000 | Add indexes, rewrite query |
| Execution Count | Varies | N/A | Very high + slow | Caching opportunity |

**Notes:**
- **Duration:** Time query takes to complete
- **Logical Reads:** Number of 8KB pages read (memory or disk)
- **Execution Count:** How many times query ran

---

### Wait Statistics

Wait stats show why queries are waiting (not executing).

**Common Wait Types:**

| Wait Type | Meaning | Action |
|-----------|---------|--------|
| PAGEIOLATCH_* | Waiting for data pages to be read from disk | Add memory, optimize queries, check disk I/O |
| LCK_M_* | Waiting for locks (blocking) | Identify blocking queries, reduce transaction time |
| CXPACKET | Parallel query coordination | Normal for large queries; excessive = poor parallelism |
| SOS_SCHEDULER_YIELD | CPU pressure | High CPU usage - optimize queries |
| WRITELOG | Waiting to write to transaction log | Transaction log I/O bottleneck |

---

## Exporting and Sharing

### Export Dashboard as PDF

1. Click **"Share"** icon (📤) in top-right corner
2. Select **"Export"** tab
3. Click **"Save as PDF"**
4. PDF will download with current time range and data

**Use Cases:**
- Weekly reports for management
- Incident documentation
- Audit compliance

---

### Share Dashboard Link

1. Click **"Share"** icon (📤) in top-right corner
2. Select **"Link"** tab
3. Configure options:
   - **Lock time range:** Share with specific time range
   - **Template variables:** Include current filter selections
4. Click **"Copy"** to copy link
5. Share URL via email or chat

**Note:** Recipients need Grafana login credentials to view.

---

### Create Custom Dashboard

If you need a custom view:

1. Click **"+"** icon in left sidebar
2. Select **"Dashboard"**
3. Click **"Add new panel"**
4. Select **"monitoringdb"** data source
5. Write your SQL query (or ask DBA for help)
6. Configure visualization type (table, graph, gauge, etc.)
7. Click **"Apply"**
8. Click **"Save dashboard"** (disk icon)
9. Name your dashboard and select folder

**Tip:** Clone existing dashboards to use as templates:
1. Open dashboard
2. Click settings gear icon (⚙️)
3. Click **"Save As"**
4. Give it a new name
5. Modify panels as needed

---

## Troubleshooting

### Dashboard Shows "No Data"

**Possible Causes:**

1. **Time range has no data:**
   - **Fix:** Expand time range to "Last 7 days" or "Last 30 days"

2. **Data collection stopped:**
   - **Check:** Open "SQL Server Performance Overview" - do you see data for other servers?
   - **Fix:** Contact DBA to check SQL Agent jobs (see DBA Operational Guide)

3. **Wrong time zone:**
   - **Check:** Grafana timezone setting (bottom-left, click profile icon → Preferences)
   - **Fix:** Set timezone to match database (UTC recommended)

4. **Database connection issue:**
   - **Check:** Other dashboards - do any work?
   - **Fix:** Contact DBA to verify database connectivity

---

### Dashboard Shows "Query Error"

**Possible Causes:**

1. **SQL syntax error:**
   - **Check:** Panel title → Inspect → Query (see error message)
   - **Fix:** Contact administrator - dashboard needs correction

2. **Missing database objects:**
   - **Example:** "Invalid object name 'PerformanceMetrics'"
   - **Fix:** Dashboard requires newer schema version - contact administrator

3. **Permission denied:**
   - **Example:** "SELECT permission denied on object 'PerformanceMetrics'"
   - **Fix:** Contact DBA to grant read permissions on MonitoringDB

---

### Dashboard is Slow to Load

**Possible Causes:**

1. **Large time range:**
   - **Fix:** Reduce time range to "Last 24 hours" or "Last 7 days"

2. **Too many metrics displayed:**
   - **Fix:** Use dashboard variables to filter to specific servers or databases

3. **Database performance issue:**
   - **Check:** Are other dashboards also slow?
   - **Fix:** Contact DBA - database may need index maintenance

---

### Can't Find a Dashboard

**Steps:**

1. Click hamburger menu (☰) → **"Dashboards"**
2. Look in **"SQL Monitor"** folder
3. Use the **Search** box at the top
4. Try searching by keywords like "performance," "overview," or "analysis"

**If still missing:**
- Contact administrator - dashboard may not be deployed yet
- Check if you're in the correct Grafana instance (production vs. test)

---

### Data Looks Wrong or Inconsistent

**Possible Causes:**

1. **Caching:**
   - **Fix:** Hard refresh (Ctrl+F5 or Cmd+Shift+R)

2. **Time zone mismatch:**
   - **Check:** Are timestamps in UTC? Local time?
   - **Fix:** Adjust Grafana preferences to match database timezone

3. **Incomplete collection:**
   - **Check:** Detailed Metrics View - are there gaps in CollectionTime?
   - **Fix:** Contact DBA - collection jobs may have failed

4. **Dashboard query issue:**
   - **Check:** Inspect → Query - review SQL query logic
   - **Fix:** Report issue to administrator

---

## Best Practices

### 1. Regular Monitoring Schedule

- **Daily:** Quick check of Performance Overview (5 minutes)
- **Weekly:** Review Performance Analysis for slow queries (15 minutes)
- **Monthly:** Capacity planning and trend analysis (30 minutes)

---

### 2. Set Up Alerting

*(Coming in future phase)*

Configure Grafana alerts to notify you when:
- CPU > 90% for 15 minutes
- Memory < 50% (unusual for SQL Server)
- Data collection stops (no new metrics for 15 minutes)
- Query duration > 10 seconds

---

### 3. Document Incidents

When issues occur:
1. **Note the time range** when issue occurred
2. **Take screenshots** of relevant dashboard panels
3. **Export data** (Inspect → Data → Download CSV)
4. **Record actions taken** and resolution
5. **Share findings** with team

---

### 4. Collaborate with DBAs

- **Share dashboard links** when reporting issues (includes time range)
- **Use specific metric names** ("Logical Reads" not "reads")
- **Provide query text** when asking about performance
- **Include time ranges** (UTC preferred)

Example good bug report:
```
Server: SQL-PROD-03
Issue: High CPU usage
Time: 2025-10-28 14:30-15:00 UTC
Dashboard: SQL Server Performance Overview
Observation: CPU spiked to 95% for 20 minutes
Additional Info: Performance Analysis shows query ID 12345
  with 45000ms avg duration during this period
```

---

### 5. Keep Learning

- **Explore panels:** Click "Inspect" to see SQL queries and learn
- **Ask questions:** DBAs can help explain metrics and thresholds
- **Review changes:** After optimizations, compare before/after metrics
- **Share knowledge:** Document learnings for team

---

## Frequently Asked Questions

### General

**Q: How often is data refreshed?**
A: Metrics are collected every 5 minutes by default. Dashboard auto-refresh can be configured (1m recommended).

**Q: How far back does historical data go?**
A: 90 days for most metrics (configurable by DBA). Older data is archived or deleted.

**Q: Can I create my own dashboards?**
A: Yes! Clone existing dashboards or create new ones. However, you'll need to know SQL to write queries. Ask your DBA for help.

**Q: What's the difference between UTC and local time?**
A: UTC is universal time (no daylight saving). Local time is your timezone. Database stores in UTC, Grafana can display in local.

**Q: Why do some dashboards show "No data"?**
A: Some dashboards require Phase 1.25 or 2.0 features not yet deployed. Check with administrator for deployment status.

---

### Performance

**Q: What's a "good" query duration?**
A:
- **< 100ms:** Excellent
- **100-1000ms:** Acceptable for complex queries
- **> 1000ms (1 second):** Needs optimization
- **> 5000ms (5 seconds):** Critical - user-facing impact

**Q: When should I worry about CPU usage?**
A: Sustained CPU > 80% for 30+ minutes needs investigation. Brief spikes are normal.

**Q: What are "logical reads" and why do they matter?**
A: Logical reads are 8KB pages of data read from memory or disk. High logical reads = inefficient query (missing indexes, table scans).

**Q: How do I know if a server is overloaded?**
A: Look for:
- CPU consistently > 80%
- High wait times (PAGEIOLATCH, LCK_M)
- Many slow queries (> 1s duration)
- Growing memory pressure

---

### Troubleshooting

**Q: Dashboard suddenly stopped showing data. What happened?**
A: Check:
1. Time range (did you accidentally zoom in?)
2. Network connection (can you load other websites?)
3. Grafana service (contact administrator)
4. Data collection (contact DBA - SQL Agent jobs may be down)

**Q: I see a "Query Error" on a dashboard. What should I do?**
A: Click panel title → Inspect → Query to see the error. Share this error message with your administrator or DBA.

**Q: Data looks delayed. Is this real-time?**
A: Data is **near real-time** with a 5-minute collection interval. So metrics can be up to 5 minutes old, plus any dashboard caching (usually < 1 minute with 1m refresh).

**Q: Can I fix dashboard queries myself?**
A: If you have edit permissions and SQL knowledge, yes. Otherwise, request changes from administrator to avoid breaking dashboards.

---

### Data and Reports

**Q: How do I export data for Excel analysis?**
A: Click panel title → Inspect → Data → Download CSV. Open in Excel or Google Sheets.

**Q: Can I schedule automatic reports?**
A: Not in Grafana OSS (free version). Consider:
- Manual PDF exports weekly
- Upgrading to Grafana Enterprise (paid)
- Using Grafana's "Snapshot" feature to create static copies

**Q: How do I share a dashboard with someone who doesn't have Grafana access?**
A:
- **Short-term:** Export as PDF and email
- **Long-term:** Have administrator create a Grafana account for them

**Q: Can I embed Grafana dashboards in other applications?**
A: Yes, using iframe embedding or Grafana's public dashboards feature (ask administrator to enable).

---

## Getting Help

### Internal Support

1. **Check this guide first** - most common questions answered here
2. **Ask your DBA team** - they manage the monitoring system
3. **Contact your administrator** - for Grafana access and dashboard issues

### Escalation

If you discover critical issues:

- **Data collection stopped:** Notify DBA immediately (data loss)
- **Critical CPU/Memory:** Notify DBA and application teams
- **Suspected security issue:** Notify security team and DBA
- **Grafana unavailable:** Notify administrator and infrastructure team

### Feedback

Help improve this system:

- **Report inaccurate data** - help us fix collection issues
- **Request new dashboards** - tell us what metrics you need
- **Suggest improvements** - we welcome feedback on usability
- **Share success stories** - let us know when dashboards helped solve a problem

---

## Additional Resources

- **DBA Operational Guide** - For database administrators managing the monitoring system
- **Developer Onboarding Guide** - For developers contributing to the project
- **Setup and Deployment Guide** - For administrators installing and configuring the system
- **Grafana Documentation** - https://grafana.com/docs/
- **SQL Server Performance Tuning** - https://learn.microsoft.com/en-us/sql/relational-databases/performance/

---

## Glossary

**CPU (Central Processing Unit):** The "brain" of the server that executes queries. High CPU = server is working hard.

**Memory (RAM):** Fast storage used to cache data. SQL Server uses all available memory by design.

**Metric:** A measured value (e.g., CPU percentage, query duration, row count).

**Time Series:** Data points collected over time, plotted as a line chart.

**Query:** A SQL statement that retrieves or modifies data (SELECT, INSERT, UPDATE, DELETE).

**Stored Procedure:** Pre-compiled SQL code stored in the database for reuse.

**Index:** Database structure that speeds up data retrieval (like a book index).

**Logical Reads:** Number of data pages read from memory or disk (8KB per page).

**Wait Statistics:** Metrics showing why queries are waiting (I/O, locks, CPU, etc.).

**Blocking:** When one query waits for another to release a lock on data.

**Deadlock:** Two queries waiting for each other's locks (database resolves by killing one).

**Transaction Log:** Append-only log file recording all database changes (for recovery).

**Fragmentation:** Disorder in index structure causing slower queries (fixed by rebuilding indexes).

**Execution Plan:** Step-by-step plan showing how SQL Server will execute a query.

**UTC (Coordinated Universal Time):** Global time standard, no daylight saving (e.g., 14:30 UTC).

**Dashboard:** A collection of panels (charts, tables, gauges) showing related metrics.

**Panel:** A single visualization on a dashboard (chart, table, gauge, etc.).

**Time Range:** The period of time displayed on a dashboard (last 24 hours, last 7 days, etc.).

**Auto-Refresh:** Automatic dashboard reload to show latest data (1m, 5m, etc.).

---

**End of End-User Dashboard Guide** - For technical operations, see the DBA Operational Guide.
