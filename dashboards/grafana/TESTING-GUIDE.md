# Grafana Dashboard Testing & Validation Guide

## 🎯 Purpose

This guide walks through testing all 9 Grafana dashboards to ensure:
- Functional correctness (dashboards load, queries work)
- User experience quality (documentation helpful, navigation intuitive)
- Performance (dashboards load <3 seconds)
- Data accuracy (metrics match expected values)

## 📋 Testing Checklist

### ✅ Pre-Testing Setup

**1. Verify Environment**
```bash
# Check Grafana is running
docker ps | grep grafana
# Expected: sql-monitor-grafana ... Up ... 0.0.0.0:9002->3000/tcp

# Check database connectivity
sqlcmd -S 172.31.208.1,14333 -U sv -P Gv51076! -C -Q "SELECT @@VERSION"
```

**2. Access Grafana**
- URL: http://localhost:9002
- Username: `admin`
- Password: `Admin123!`

**3. Verify Data Exists**
```sql
-- Check metric collection is running
SELECT TOP 10 * FROM dbo.PerformanceMetrics ORDER BY CollectionTime DESC;
-- Should show data from last 5 minutes

-- Check table metadata
SELECT COUNT(*) FROM dbo.TableMetadata;
-- Should show >0 tables

-- Check code objects
SELECT COUNT(*) FROM dbo.CodeObjectMetadata;
-- Should show >0 procedures/functions

-- Check audit log (Phase 2.0)
SELECT COUNT(*) FROM dbo.AuditLog;
-- May be 0 if Phase 2.0 not deployed

-- Check Query Store (Phase 1.9 or manual)
SELECT COUNT(*) FROM dbo.QueryStoreSnapshots;
-- May be 0 if Query Store not configured
```

---

## 🧪 Functional Testing

### Test 1: Landing Page (00-landing-page.json)

**Dashboard UID**: `sql-monitor-home`
**URL**: http://localhost:9002/d/sql-monitor-home

**Checklist**:
- [ ] Dashboard loads without errors
- [ ] arcTrade branding displays (logo colors, tagline)
- [ ] 6 navigation tiles render with gradient backgrounds
- [ ] Tiles display correct icons and descriptions
- [ ] Quick Start section renders (Dev, DBA, Ops)
- [ ] Key Features boxes display (6 boxes)
- [ ] Documentation links are visible
- [ ] System Status shows green checkmark
- [ ] Footer displays arcTrade branding

**Interactive Tests**:
- [ ] Click "System Overview" tile → Opens 00-sql-server-monitoring
- [ ] Click "Performance Analysis" tile → Opens 05-performance-analysis
- [ ] Click "Code Browser" tile → Opens 03-code-browser
- [ ] Click "Table Browser" tile → Opens 01-table-browser
- [ ] Click "Audit Logging" tile → Opens 07-audit-logging
- [ ] Click "Detailed Metrics" tile → Opens detailed-metrics

**Expected Results**: All links navigate to correct dashboards

**Pass Criteria**: All checkboxes ✅, no errors, navigation works

---

### Test 2: SQL Server Monitoring (00-sql-server-monitoring.json)

**Dashboard UID**: `sql-server-monitoring`

**Checklist**:
- [ ] Dashboard loads with all panels visible
- [ ] Server dropdown populates (shows active servers)
- [ ] Metric Category dropdown populates (CPU, Memory, etc.)
- [ ] Active Servers stat shows >0
- [ ] Active Alerts stat displays (may be 0)
- [ ] CPU Usage gauges render (green/yellow/red)
- [ ] Memory Usage gauges render
- [ ] Performance Trends charts display time series data
- [ ] Database Performance table shows data
- [ ] Wait Statistics table shows top 15 waits
- [ ] Developer Guide markdown panel displays at bottom

**Interactive Tests**:
- [ ] Select specific server from dropdown → All panels update
- [ ] Select "All" servers → Shows all servers
- [ ] Select "CPU" from Metric Category → Filters to CPU only
- [ ] Change time range to "Last 24 hours" → Queries re-execute
- [ ] Change time range to "Last 7 days" → Historical data loads

**Performance**:
- [ ] Initial load <3 seconds
- [ ] Filter change <1 second
- [ ] Time range change <2 seconds

**Pass Criteria**: All panels populate, filtering works, performance acceptable

---

### Test 3: Table Browser (01-table-browser.json)

**Dashboard UID**: `table-browser`

**Checklist**:
- [ ] Database dropdown populates (user databases only, NO system DBs)
- [ ] Schema dropdown shows schemas (defaults to "All")
- [ ] Table Name filter textbox visible
- [ ] Table list displays with columns: TableName, RowCount, DataSizeMB, IndexSizeMB
- [ ] Tables sorted by TotalSizeMB descending
- [ ] Developer Guide markdown panel displays

**System Database Verification** (CRITICAL):
- [ ] Database dropdown does NOT show "master"
- [ ] Database dropdown does NOT show "model"
- [ ] Database dropdown does NOT show "msdb"
- [ ] Database dropdown does NOT show "tempdb"
- [ ] Database dropdown does NOT show "ReportServer"
- [ ] Database dropdown does NOT show "ReportServerTempDB"

**Interactive Tests**:
- [ ] Select database → Tables filtered to that database
- [ ] Type "Customer" in Table Name filter → Shows only matching tables
- [ ] Click column header to sort → Table re-sorts
- [ ] Click table name → Navigates to Table Details dashboard

**Pass Criteria**: Only user databases visible, filtering works, no system databases

---

### Test 4: Table Details (02-table-details.json)

**Dashboard UID**: `table-details`

**Checklist**:
- [ ] Table Summary panel shows row count, size, dates
- [ ] Column Details table displays with data types, nullable, defaults
- [ ] Indexes table shows index names, types, columns
- [ ] Constraints table shows PKs, FKs, checks
- [ ] Foreign Key Relationships table shows dependencies
- [ ] Developer Guide markdown panel displays

**Interactive Tests**:
- [ ] Select different table → All panels update
- [ ] Click column to sort → Table re-sorts
- [ ] Review column data types → Match expected types

**Pass Criteria**: All panels populate, data accurate

---

### Test 5: Code Browser (03-code-browser.json)

**Dashboard UID**: `sql-monitor-code-browser`

**Checklist**:
- [ ] Database dropdown shows only user databases
- [ ] Object Type dropdown (All, Procedure, Function, View, Trigger)
- [ ] Object Name search textbox visible
- [ ] SelectedObject and SelectedSchema textboxes visible
- [ ] Code Objects table displays with LineCount, DependencyCount
- [ ] Dependencies panel (initially empty)
- [ ] Source Code panel (initially empty)
- [ ] Developer Guide markdown panel displays

**Interactive Tests** (CRITICAL - Test New Features):
- [ ] Click object name in Code Objects table
  - [ ] SelectedObject and SelectedSchema variables populate
  - [ ] Dependencies panel updates to show selected object's dependencies
  - [ ] Source Code panel updates to show full source code
- [ ] Click "View Code" link
  - [ ] Opens popup in new tab
  - [ ] Shows full source code
- [ ] Click "To" object in Dependencies panel
  - [ ] Jumps to that object
  - [ ] Updates all panels for new object

**Trace Call Chain Test**:
1. Find a stored procedure that calls other procedures
2. Click procedure name → See dependencies
3. Click dependency "To" object → Navigate to it
4. Continue clicking to trace full call chain

**Pass Criteria**: All interactive features work, tracing call chains successful

---

### Test 6: Performance Analysis (05-performance-analysis.json)

**Dashboard UID**: `performance-analysis`

**Checklist**:
- [ ] Top procedures table displays with duration, CPU, reads
- [ ] Avg Duration stat shows value
- [ ] Max Duration stat shows value
- [ ] Color coding (green/yellow/red) works on duration cells
- [ ] Missing indexes recommendations (may be empty)
- [ ] Wait statistics breakdown (if available)
- [ ] Developer Guide markdown panel displays

**Interactive Tests**:
- [ ] Sort by Avg Duration → Slowest queries first
- [ ] Sort by Execution Count → Most frequent first
- [ ] Click procedure name → Opens Code Browser (if linked)

**Pass Criteria**: All metrics display, sorting works, color coding correct

---

### Test 7: Query Store (06-query-store.json)

**Dashboard UID**: `query-store-analysis`

**Checklist**:
- [ ] Plan Regressions stat displays (may be 0)
- [ ] Unique Queries stat displays
- [ ] Avg Query Duration stat displays
- [ ] Total Query Executions stat displays
- [ ] Top 20 Slowest Queries table (requires QueryStoreSnapshots data)
- [ ] Query Duration Trends chart
- [ ] Query Execution Frequency chart
- [ ] Plan Regressions table (queries ≥50% slower)
- [ ] Developer Guide markdown panel displays

**Data Dependency** ⚠️:
This dashboard requires `dbo.QueryStoreSnapshots` table to be populated.

**If No Data**:
```sql
-- Check if table exists
SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'QueryStoreSnapshots';

-- If not exists, dashboard will show "No data"
-- Either deploy Phase 1.9 scripts or manually create/populate table
```

**Pass Criteria**: Dashboard loads (even if no data), markdown displays, queries don't error

---

### Test 8: Audit Logging (07-audit-logging.json)

**Dashboard UID**: `audit-logging-soc2`

**Checklist**:
- [ ] Total Audit Events stat displays (requires AuditLog data)
- [ ] Security Events stat displays
- [ ] Unique Users stat displays
- [ ] Failed Requests stat displays
- [ ] Audit Events by Type chart
- [ ] Security Events Over Time chart
- [ ] Recent Security Events table
- [ ] User Activity Summary table (calls usp_GetSOC2_UserAccessReport)
- [ ] Configuration Changes table (calls usp_GetSOC2_ConfigChangesReport)
- [ ] Anomaly Detection table (calls usp_GetSOC2_AnomalyDetectionSummary)
- [ ] Events by Type pie chart
- [ ] Events by Severity pie chart
- [ ] Top 10 Active Users bar chart
- [ ] Developer Guide markdown panel displays

**Data Dependency** ⚠️:
This dashboard requires:
- `dbo.AuditLog` table (Phase 2.0 authentication/audit logging)
- SOC 2 stored procedures (Phase 2.0)

**If No Data**:
Dashboard will show "No data" but should load without errors

**Pass Criteria**: Dashboard loads, no errors, markdown displays

---

### Test 9: Detailed Metrics (detailed-metrics.json)

**Dashboard UID**: `detailed-metrics`

**Checklist**:
- [ ] Server dropdown populates
- [ ] Metric Category dropdown populates
- [ ] Time range picker works
- [ ] Recent Metrics table displays with server, category, value
- [ ] Metrics Time Series chart displays trends
- [ ] Color coding works (green/yellow/red thresholds)
- [ ] Developer Guide markdown panel displays

**Interactive Tests** (CRITICAL - Test New Filters):
- [ ] Select specific server → Table and chart filter to that server
- [ ] Select "CPU" metric → Shows only CPU metrics
- [ ] Select multiple servers → Shows comparison
- [ ] Change time range to "Last 7 days" → Historical data loads
- [ ] Select "All" servers and "All" metrics → Shows everything

**Pass Criteria**: All filters work, data updates correctly

---

### Test 10: SQL Server Overview (sql-server-overview.json)

**Dashboard UID**: `sql-server-overview`

**Checklist**:
- [ ] CPU usage chart displays
- [ ] Memory usage chart displays
- [ ] Additional metrics (if any)
- [ ] Developer Guide markdown panel displays

**Pass Criteria**: All charts render, markdown displays

---

## 📊 User Acceptance Testing

### Developer Role Test

**Scenario**: "My application is slow"

1. [ ] Open Landing Page
2. [ ] Read "For Developers" → "Troubleshoot Slow Queries" section
3. [ ] Click "Performance Analysis" tile
4. [ ] Follow markdown guide: Identify slow queries
5. [ ] Click query to view in Code Browser
6. [ ] Review source code and dependencies
7. [ ] Check Table Details for indexes
8. [ ] Make recommendation (add index, rewrite query, etc.)

**Expected Duration**: 5-10 minutes (down from 30 minutes before)

**Pass Criteria**: Developer can complete workflow without asking DBA for help

---

### DBA Role Test

**Scenario**: "Daily health check"

1. [ ] Open Landing Page
2. [ ] Read "For DBAs" → "Daily Health Check" section
3. [ ] Click "System Overview" tile
4. [ ] Verify all CPU/Memory gauges are green
5. [ ] Check for active alerts (should be 0)
6. [ ] Review overnight batch job performance in Performance Analysis
7. [ ] Check for plan regressions in Query Store
8. [ ] Review security events in Audit Logging

**Expected Duration**: 5 minutes (down from 15 minutes before)

**Pass Criteria**: DBA can quickly assess health, identify issues

---

### Operations Role Test

**Scenario**: "Incident response"

1. [ ] Note exact time of incident (e.g., 15:43 UTC)
2. [ ] Open Landing Page
3. [ ] Read "For Operations" → "Incident Response" section
4. [ ] Click "System Overview" tile
5. [ ] Set time range to incident window (15:40-15:50)
6. [ ] Check for CPU/Memory spikes
7. [ ] Open Performance Analysis dashboard
8. [ ] Identify slow queries during incident
9. [ ] Use diagnostic query script (database/diagnostic-queries/)
10. [ ] Correlate with application logs

**Expected Duration**: 10-15 minutes (down from 1 hour before)

**Pass Criteria**: Operations can identify root cause quickly

---

## ⚡ Performance Testing

### Dashboard Load Times

**Target**: All dashboards <3 seconds initial load

**Measurement**:
1. Open Chrome DevTools (F12)
2. Go to Network tab
3. Hard refresh (Ctrl+Shift+R)
4. Note "Load" time at bottom

**Acceptable Times**:
- Landing Page: <1 second (no data queries)
- System Overview: <3 seconds (complex aggregations)
- Table/Code Browser: <2 seconds (cached metadata)
- Performance Analysis: <3 seconds (historical data)
- Query Store: <3 seconds (7-day baseline comparison)
- Audit Logging: <3 seconds (SOC 2 stored procedures)
- Detailed Metrics: <2 seconds (filtered queries)

**If Slow (>5 seconds)**:
- Check PerformanceMetrics table size (partitioned? indexed?)
- Review query execution plans in SQL Server
- Consider adding indexes on CollectionTime, ServerID
- Check Grafana query cache settings

---

## 📖 Documentation Review

### Markdown Quality Checklist

For each dashboard's developer guide:
- [ ] Markdown renders correctly (no broken formatting)
- [ ] Tables display properly
- [ ] Code blocks have syntax highlighting
- [ ] Links work (internal dashboard links, external docs)
- [ ] Emoji icons display correctly
- [ ] Scenarios are realistic and actionable
- [ ] SQL examples are syntactically correct
- [ ] Thresholds match color coding (e.g., "green <70%")
- [ ] No typos or grammatical errors

### Content Accuracy

- [ ] Metric explanations match actual queries
- [ ] Threshold values match dashboard configuration
- [ ] Scenarios match real-world troubleshooting
- [ ] SQL examples can be copy-pasted and run
- [ ] External links go to correct resources
- [ ] SOC 2 criteria correctly mapped (CC6.1, CC7.2, etc.)

---

## 🐛 Known Issues & Workarounds

### Issue 1: QueryStoreSnapshots Table Missing

**Symptom**: Query Store dashboard shows "No data"

**Cause**: Table not created yet (Phase 1.9 or manual creation required)

**Workaround**:
- Dashboard will load but show empty panels
- Deploy Phase 1.9 scripts to create table
- Or manually create table and populate from sys.query_store views

**Impact**: Low (dashboard functional, just no data yet)

---

### Issue 2: AuditLog Empty (Phase 2.0 Not Deployed)

**Symptom**: Audit Logging dashboard shows "No data"

**Cause**: Phase 2.0 authentication/audit logging not deployed

**Workaround**:
- Dashboard will load but show empty panels
- Deploy Phase 2.0 to enable audit logging
- Or manually insert test data for demo purposes

**Impact**: Low (dashboard functional, just no data yet)

---

### Issue 3: System Databases in Dropdowns (Should Be Fixed)

**Symptom**: master, model, msdb, tempdb appear in database dropdowns

**Cause**: Filter not applied or cache not cleared

**Fix**:
```sql
-- Run system database cleanup script
:r database/28-cleanup-system-databases-from-cache.sql

-- Restart Grafana
docker compose restart grafana
```

**Verification**:
- Open Table Browser → Database dropdown
- Should only show user databases

---

## ✅ Sign-Off Checklist

### Functional Testing
- [ ] All 9 dashboards load without errors
- [ ] Navigation links work (landing page → dashboards)
- [ ] Interactive features work (filters, drill-down, code browser)
- [ ] Markdown panels render correctly
- [ ] No system databases in dropdowns

### User Acceptance Testing
- [ ] Developer workflow tested and approved
- [ ] DBA workflow tested and approved
- [ ] Operations workflow tested and approved
- [ ] Documentation reviewed by non-technical user

### Performance Testing
- [ ] All dashboards load <3 seconds
- [ ] Filter changes <1 second
- [ ] Time range changes <2 seconds
- [ ] No browser lag or freezing

### Documentation Review
- [ ] All markdown panels reviewed for accuracy
- [ ] All SQL examples tested
- [ ] All external links verified
- [ ] No typos or formatting issues

### Data Accuracy
- [ ] Metrics match SQL Server actual values
- [ ] Color coding thresholds correct
- [ ] Baseline comparisons accurate
- [ ] Trend charts show expected patterns

---

## 📝 Feedback Template

**Tester Name**: ___________________
**Role**: [ ] Developer [ ] DBA [ ] Operations [ ] Management
**Date**: ___________________

### Overall Experience (1-5 stars)
- Navigation: ⭐⭐⭐⭐⭐
- Documentation Quality: ⭐⭐⭐⭐⭐
- Performance: ⭐⭐⭐⭐⭐
- Visual Design: ⭐⭐⭐⭐⭐

### What Worked Well?
-
-
-

### What Needs Improvement?
-
-
-

### Specific Issues Found
| Dashboard | Issue | Severity (Low/Med/High) |
|-----------|-------|-------------------------|
|           |       |                         |
|           |       |                         |

### Feature Requests
-
-
-

### Would you use this daily?  [ ] Yes [ ] No

**Additional Comments**:


---

## 🚀 Next Steps After Testing

1. **Compile Feedback**: Aggregate all tester feedback
2. **Prioritize Issues**: High → Medium → Low severity
3. **Create GitHub Issues**: Document bugs and feature requests
4. **Iterate**: Make refinements based on feedback
5. **Retest**: Verify fixes work
6. **Announce**: Internal launch announcement
7. **Training**: Optional training session if needed

Then → **Option A: Resume Phase 2.0 Authentication Work**

---

**Testing Guide Version**: 1.0
**Last Updated**: 2025-10-28
**Next Review**: After user feedback cycle

🤖 Generated with Claude Code (https://claude.com/claude-code)
