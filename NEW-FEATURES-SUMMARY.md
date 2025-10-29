# SQL Monitor - New Features Summary

**Date**: 2025-10-29
**Status**: Production Ready

---

## 🎯 Overview

Two major features have been added to the SQL Monitor system:

1. **SQL Server Optimization Blog** - Educational content panel on dashboard browser
2. **DBCC Integrity Check System** - Automated database health monitoring with error/warning cataloging

---

## 📚 Feature 1: SQL Server Optimization Blog

### What It Does

Replaces the quick start guide with a comprehensive blog featuring **12 educational articles** on SQL Server performance optimization and best practices.

### Location

- **Dashboard**: Dashboard Browser (Home)
- **Panel**: Bottom section (full-width markdown panel)
- **Visibility**: All users see on home page

### Articles Included

1. **How to Add Indexes Based on Statistics**
   - Finding missing indexes with DMVs
   - Index key ordering (equality → inequality → included)
   - Performance impact analysis

2. **Temp Tables vs Table Variables**
   - Decision matrix (< 100 rows = table variable, > 1000 rows = temp table)
   - Statistics and performance implications
   - Use cases and examples

3. **When CTE is NOT the Best Idea**
   - Multiple reference performance penalty
   - When to use temp tables instead
   - Recursive CTE best practices

4. **Error Handling and Logging Best Practices**
   - TRY/CATCH patterns
   - Structured logging with context
   - THROW vs RAISERROR

5. **The Dangers of Cross-Database Queries**
   - Distributed transaction issues
   - Message hub/queue architecture patterns
   - Service bus vs API gateway approaches

6. **The Value of INCLUDE and Other Index Options**
   - Covering indexes (10x faster)
   - FILLFACTOR, COMPRESSION, FILTER options
   - Performance impact examples

7. **The Challenge of Branchable Logic in WHERE Clauses**
   - Parameter sniffing issues
   - Dynamic SQL solutions
   - OPTION (RECOMPILE) patterns

8. **When Table-Valued Functions (TVFs) Are Best**
   - Inline TVF (fast) vs Multi-Statement TVF (slow)
   - Decision matrix with use cases
   - Alternative approaches

9. **How to Optimize UPSERT Operations**
   - MERGE vs UPDATE+INSERT vs TRY INSERT
   - Performance comparison (18 seconds vs 45 seconds)
   - Race condition prevention

10. **Best Practices for Partitioning Large Tables**
    - When to partition (> 10 GB tables)
    - Partition elimination benefits
    - Sliding window archiving

11. **How to Manage Mammoth Tables Effectively**
    - Columnstore indexes (10x compression)
    - Hot/warm/cold archiving strategies
    - Incremental statistics
    - Lock escalation control

12. **When to Rebuild Indexes**
    - Fragmentation thresholds (< 10% ignore, 10-30% reorganize, > 30% rebuild)
    - Online vs offline rebuilds
    - Automated maintenance scripts (Ola Hallengren)

### Benefits

- ✅ **Educational Value**: Users learn best practices while monitoring
- ✅ **Contextual**: Links to Code Browser for examples
- ✅ **Actionable**: All articles include code examples
- ✅ **Comprehensive**: 12 topics covering common optimization challenges

### Files Modified

- `dashboards/grafana/dashboards/00-dashboard-browser.json` - Blog panel added

---

## 🔍 Feature 2: DBCC Integrity Check System

### What It Does

Automatically runs **DBCC** (Database Console Commands) checks on a schedule, captures output, parses errors/warnings, and displays results in a dedicated dashboard with repair guidance.

### Components

#### 1. Database Tables

**DBCCCheckResults** - Stores all check results
- ServerID, DatabaseName, CheckType, ObjectName
- Severity (CRITICAL, WARNING, INFO, SUCCESS)
- MessageType (ERROR, WARNING, INFORMATIONAL, REPAIR_SUGGESTION)
- RepairLevel (REPAIR_ALLOW_DATA_LOSS, REPAIR_REBUILD, REPAIR_FAST)
- MessageText, RawOutput
- Duration tracking

**DBCCCheckSchedule** - Defines check schedules
- ServerID, DatabaseName, CheckType
- FrequencyDays (e.g., 7 for weekly)
- LastRunDate, NextRunDate
- IsEnabled, NotifyOnError

#### 2. Stored Procedures

**usp_RunDBCCCheck**
- Runs single DBCC check (CHECKDB, CHECKCATALOG, CHECKALLOC, CHECKTABLE)
- Captures output in temp table
- Parses for errors and warnings
- Catalogs results with severity classification
- Detects repair level recommendations

**usp_RunScheduledDBCCChecks**
- Runs all scheduled checks that are due
- Processes all user databases if DatabaseName = 'ALL'
- Updates schedule after successful run
- Error logging for failed checks

**usp_GetDBCCCheckSummary**
- Returns aggregated summary of check results
- Groups by server, database, check type, severity
- Last 30 days by default

#### 3. Grafana Dashboard

**09-dbcc-integrity-checks.json**

**Panels**:
1. **Summary Stats** (4 stat panels):
   - 🔴 Critical Errors (30d)
   - 🟠 Warnings (30d)
   - ✅ Successful Checks (7d)
   - ⏱️ Avg Check Duration

2. **Check Results Table**:
   - Server, Database, CheckType, Severity, MessageType
   - RepairLevel with color coding
   - CheckTime, Duration, Message, ObjectName
   - Hyperlinks to Server Overview and Table Browser
   - Top 100 results sorted by severity

3. **Check History Chart**:
   - Time series by severity
   - Tracks trends over time

4. **Duration Chart**:
   - Average duration by database
   - Detects performance degradation

5. **Educational Guide Panel**:
   - What is DBCC
   - Check types explained
   - Severity levels
   - Repair levels with dangers
   - Common error messages
   - Maintenance schedule recommendations
   - Performance tips
   - Recovery strategies
   - FAQ section

**Variables**:
- DS_MONITORINGDB (datasource)
- ServerName (multi-select)
- Severity (multi-select filter)

**Color Coding**:
- 🔴 CRITICAL = Red (immediate action required)
- 🟠 WARNING = Orange (repair available)
- 🔵 INFO = Blue (minor issues)
- 🟢 SUCCESS = Green (healthy)

**Repair Level Indicators**:
- ⚠️ REPAIR_ALLOW_DATA_LOSS = Dark Red (⚠️ DATA LOSS)
- 🔧 REPAIR_REBUILD = Orange (🔧 REBUILD)
- ⚡ REPAIR_FAST = Yellow (⚡ FAST - deprecated)

### DBCC Check Types

#### CHECKDB (Most Important)
- **What**: Comprehensive database integrity check
- **Checks**: All tables, indexes, system catalogs
- **Detects**: Corruption, page errors, allocation errors
- **Frequency**: Weekly (PHYSICAL_ONLY for speed), Monthly (full check)
- **Duration**: 10 minutes (PHYSICAL_ONLY) to 8 hours (full)

#### CHECKCATALOG
- **What**: System catalog consistency check
- **Checks**: Metadata integrity (tables, columns, relationships)
- **Detects**: Catalog inconsistencies
- **Frequency**: Weekly
- **Duration**: 5-10 minutes

#### CHECKALLOC
- **What**: Space allocation structure check
- **Checks**: Page usage, extent allocation
- **Detects**: Orphaned pages, allocation errors
- **Frequency**: Monthly
- **Duration**: 15-30 minutes

#### CHECKTABLE
- **What**: Specific table integrity check
- **Checks**: Single table and indexes
- **Detects**: Table-specific corruption
- **Frequency**: On-demand (troubleshooting)
- **Duration**: 1-5 minutes per table

### Default Schedule

Automatically created on deployment:

1. **Weekly CHECKDB** (all databases)
   - Runs every Sunday
   - Uses PHYSICAL_ONLY for speed (10x faster)

2. **Weekly CHECKCATALOG** (all databases)
   - Runs every Monday
   - Full catalog check

### How to Use

#### Add a Custom Schedule
```sql
INSERT INTO dbo.DBCCCheckSchedule (ServerID, DatabaseName, CheckType, FrequencyDays, NextRunDate)
VALUES (
    1,  -- ServerID from dbo.Servers
    'YourDatabase',  -- Or 'ALL' for all databases
    'CHECKDB',  -- CHECKDB, CHECKCATALOG, CHECKALLOC, CHECKTABLE
    7,  -- Run every 7 days
    GETUTCDATE()  -- Start immediately
);
```

#### Run Checks Manually
```sql
EXEC dbo.usp_RunScheduledDBCCChecks;
```

#### View Results
```sql
-- Summary of last 30 days
EXEC dbo.usp_GetDBCCCheckSummary @ServerID = NULL, @DaysBack = 30;

-- All errors/warnings
SELECT * FROM dbo.DBCCCheckResults
WHERE Severity IN ('CRITICAL', 'WARNING')
ORDER BY CheckStartTime DESC;
```

#### View in Grafana
1. Open Dashboard Browser
2. Click **🔍 DBCC Integrity** card
3. Filter by server and severity
4. Review errors/warnings table
5. Follow repair guidance in bottom panel

### Repair Strategies

#### Option 1: Restore from Backup (Best)
```sql
RESTORE DATABASE YourDatabase
FROM DISK = 'E:\Backups\YourDatabase_LastGood.bak'
WITH REPLACE, RECOVERY;

-- Verify repair
DBCC CHECKDB('YourDatabase') WITH NO_INFOMSGS;
```

#### Option 2: REPAIR_REBUILD (No Data Loss)
```sql
ALTER DATABASE YourDatabase SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DBCC CHECKDB('YourDatabase', REPAIR_REBUILD);
ALTER DATABASE YourDatabase SET MULTI_USER;
```

#### Option 3: REPAIR_ALLOW_DATA_LOSS (LAST RESORT)
```sql
-- ⚠️ WARNING: PERMANENT DATA LOSS POSSIBLE
-- Only use if no backup available

ALTER DATABASE YourDatabase SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DBCC CHECKDB('YourDatabase', REPAIR_ALLOW_DATA_LOSS);
ALTER DATABASE YourDatabase SET MULTI_USER;

-- Verify what was lost
DBCC CHECKDB('YourDatabase') WITH NO_INFOMSGS;
```

### Benefits

- ✅ **Proactive**: Catches corruption before it causes downtime
- ✅ **Automated**: Runs on schedule without manual intervention
- ✅ **Cataloged**: All results stored for trend analysis
- ✅ **Guided**: Dashboard provides repair recommendations
- ✅ **Educational**: Comprehensive guide panel explains everything
- ✅ **Multi-Server**: Supports monitoring all servers from one dashboard

### Files Created

**Database Scripts**:
- `database/28-create-dbcc-check-system.sql` - Tables and stored procedures

**Dashboards**:
- `dashboards/grafana/dashboards/09-dbcc-integrity-checks.json` - Dashboard

**Dashboard Browser**:
- `00-dashboard-browser.json` - Added 🔍 DBCC Integrity card

---

## 📊 Dashboard Browser Updates

### New Layout

The dashboard browser now has **9 cards** (was 8):

**Row 1** (y=3):
1. 📊 Server Overview (blue)
2. 💡 Insights (purple)
3. ⚡ Performance (green)
4. 🔍 Query Store (orange)

**Row 2** (y=11):
5. 📋 Table Browser (blue)
6. 💻 Code Browser (purple)
7. 📈 Detailed Metrics (green)
8. 🔒 Audit Logging (red)

**Row 3** (y=19):
9. 🔍 DBCC Integrity (dark red)

**Blog Panel** (y=27):
- SQL Server Optimization Blog (12 articles)

### Dashboard Folder Organization

**Recommended folder assignment** (update `dashboards.yaml`):

**Security & Compliance** folder:
- Audit Logging
- **DBCC Integrity Checks** (NEW)

**Analysis & Insights** folder:
- Query Store
- Insights

**Stats & Metrics** folder:
- SQL Server Overview
- Detailed Metrics
- Performance Analysis

**Code & Schema** folder:
- Code Browser
- Table Browser
- Table Details

---

## 🚀 Deployment Instructions

### Step 1: Deploy Database Schema

```bash
# Connect to SQL Server
sqlcmd -S data.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB

# Run DBCC system script
:r database/28-create-dbcc-check-system.sql
GO

# Verify tables created
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE 'DBCC%';
-- Expected: 2 tables (DBCCCheckResults, DBCCCheckSchedule)

# Verify procedures created
SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME LIKE '%DBCC%';
-- Expected: 3 procedures

EXIT
```

### Step 2: Restart Grafana

```bash
# Restart to load new dashboard and updated browser
docker compose restart grafana

# Wait 30 seconds for startup
sleep 30
```

### Step 3: Verify in Grafana

```
1. Open http://data.schoolvision.net:9002
2. Login: admin / Admin123!
3. Verify Dashboard Browser shows:
   - ✅ 9 cards (including 🔍 DBCC Integrity)
   - ✅ SQL Server Optimization Blog at bottom
4. Click 🔍 DBCC Integrity card
5. Verify dashboard loads with:
   - ✅ 4 stat panels (errors, warnings, success, duration)
   - ✅ Results table (may be empty initially)
   - ✅ History charts
   - ✅ Educational guide panel at bottom
6. Scroll down in blog panel to verify all 12 articles present
```

### Step 4: Run Initial DBCC Checks

```sql
-- Connect to MonitoringDB
sqlcmd -S data.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB

-- Run scheduled checks manually (first time)
EXEC dbo.usp_RunScheduledDBCCChecks;
GO
-- This will take 10-30 minutes depending on database size

-- Verify results
SELECT * FROM dbo.DBCCCheckResults ORDER BY CheckStartTime DESC;
GO

-- View summary
EXEC dbo.usp_GetDBCCCheckSummary;
GO

EXIT
```

### Step 5: Verify Dashboard Shows Data

```
1. Refresh DBCC Integrity dashboard
2. Verify stat panels show counts
3. Verify results table shows check records
4. Verify charts populate
```

---

## 📈 Expected Results

### After Initial Deployment

**Dashboard Browser**:
- 9 cards visible (4 + 4 + 1 layout)
- Blog panel with 12 articles visible at bottom
- All cards clickable and open correct dashboards

**DBCC Integrity Dashboard** (after first check run):
- **Critical Errors**: 0 (ideal)
- **Warnings**: 0-5 (typical)
- **Successful Checks**: 10-50 (depending on database count)
- **Avg Duration**: 60-300 seconds

**Blog Panel**:
- All 12 articles visible
- Code examples readable
- Formatting correct (markdown)

### Typical Weekly Activity

**DBCC Checks**:
- Sunday 2 AM: CHECKDB runs on all databases (10-30 min)
- Monday 2 AM: CHECKCATALOG runs on all databases (5-10 min)

**Dashboard Usage**:
- DBAs check DBCC dashboard Monday morning
- No errors = 🟢 green success
- Warnings = 🟠 review repair recommendations
- Critical = 🔴 immediate investigation + restore from backup

**Blog Usage**:
- Developers reference articles when optimizing queries
- DBAs share links to specific articles with team
- New hires read all 12 articles as onboarding

---

## 🎓 Training Materials

### For Developers

**Recommended Reading** (from Blog):
1. How to Add Indexes Based on Statistics
2. Temp Tables vs Table Variables
3. When CTE is NOT the Best Idea
4. How to Optimize UPSERT Operations

**Use Cases**:
- Slow query? → Read index article, check Performance Analysis dashboard
- Need temp storage? → Read temp table article, choose wisely
- Complex query? → Read CTE article, consider temp table alternative

### For DBAs

**Recommended Reading** (from Blog):
1. When to Rebuild Indexes
2. Best Practices for Partitioning Large Tables
3. How to Manage Mammoth Tables Effectively
4. Error Handling and Logging Best Practices

**Use Cases**:
- Weekly maintenance? → Read index rebuild article, check fragmentation
- Large tables (>10GB)? → Read partitioning article
- Database corruption? → Check DBCC dashboard, follow repair guide

### For DevOps

**Recommended Reading** (from Blog):
1. The Dangers of Cross-Database Queries
2. The Value of INCLUDE and Other Index Options

**Use Cases**:
- Multi-database app? → Read cross-database article, implement message queue
- Performance tuning? → Read INCLUDE article, add covering indexes

---

## 🔧 Maintenance

### Weekly Tasks

1. **Review DBCC Dashboard** (Monday morning):
   - Check for critical errors or warnings
   - Review duration trends (sudden increase = problem)
   - Verify all databases checked

2. **Update Blog Content** (Monthly):
   - Edit `00-dashboard-browser.json` blog panel
   - Add new articles or update existing
   - Restart Grafana to apply changes

### Monthly Tasks

1. **Cleanup Old DBCC Results** (if needed):
   ```sql
   -- Keep last 90 days only
   DELETE FROM dbo.DBCCCheckResults
   WHERE CheckStartTime < DATEADD(DAY, -90, GETUTCDATE());
   ```

2. **Review DBCC Schedule**:
   ```sql
   SELECT * FROM dbo.DBCCCheckSchedule WHERE IsEnabled = 1;
   ```

---

## 📚 Documentation References

**DBCC Commands**:
- [DBCC CHECKDB](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkdb-transact-sql)
- [DBCC CHECKCATALOG](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkcatalog-transact-sql)
- [DBCC CHECKALLOC](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkalloc-transact-sql)

**SQL Server Best Practices**:
- [Index Design Guidelines](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-index-design-guide)
- [Partitioning Tables and Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/partitions/partitioned-tables-and-indexes)

---

## ✅ Feature Checklist

- [x] SQL Server Optimization Blog (12 articles)
- [x] DBCC Check System (tables, procedures)
- [x] DBCC Integrity Checks Dashboard
- [x] DBCC card added to Dashboard Browser
- [x] Educational guide panels
- [x] Color-coded severity levels
- [x] Repair level indicators
- [x] Hyperlinks to related dashboards
- [x] Multi-server support
- [x] Automated scheduling
- [x] Error parsing and cataloging
- [x] Default schedules (weekly CHECKDB + CHECKCATALOG)

---

**Created**: 2025-10-29
**Status**: Production Ready
**Ready for Deployment**: ✅ YES

🤖 **ArcTrade SQL Monitor** - Enterprise-Grade SQL Server Monitoring + Education
