# Daily Health Overview - Complete Morning Report

## Overview

The `DBA_DailyHealthOverview` procedure provides a comprehensive one-command health report combining all key diagnostic checks into a single execution.

## Quick Start

```sql
-- Run with defaults (most common use case)
EXEC DBA_DailyHealthOverview
```

That's it! One command gives you 12 comprehensive result sets covering everything you need to know.

## What You Get - 12 Result Sets

### 1. Report Header
**Purpose:** Report metadata and data quality status

**Shows:**
- Server name
- Report generation time (UTC)
- Total snapshots collected
- Oldest and newest snapshot dates
- Days of data available
- Data status (CURRENT / STALE / NO DATA)

**Example:**
```
ReportTitle: DAILY HEALTH OVERVIEW REPORT
ServerName: SVWeb\CLUBTRACK
ReportGeneratedUTC: 2025-10-27 22:45:00.123
TotalSnapshotsCollected: 57
DaysOfData: 0 (first day)
DataStatus: DATA CURRENT
```

### 2. Current System Health
**Purpose:** Latest snapshot with health assessment

**Shows:**
- CPU signal wait percentage
- Blocking session count
- Deadlock count
- Top wait type
- Session/request counts
- Overall health status (HEALTHY / ATTENTION / WARNING / CRITICAL)
- Minutes since last snapshot

**Thresholds:**
- CRITICAL: CPU > 40% or Deadlocks > 5
- WARNING: Blocking > 20 or Deadlocks 1-5
- ATTENTION: CPU 20-40%
- HEALTHY: All metrics normal

### 3. Issues Found (Last 24 Hours)
**Purpose:** All problem periods detected

**Shows:**
- When each issue occurred
- CPU percentage
- Blocking count
- Deadlock count
- Issue type (HIGH CPU / HIGH BLOCKING / DEADLOCKS)
- How long ago it occurred

**Use Case:**
"Why was the database slow at 3 PM yesterday?" - This result set tells you.

### 4. 24-Hour Summary Statistics
**Purpose:** Statistical overview of the last day

**Shows:**
- Total snapshots collected
- Average and maximum CPU
- Average and maximum blocking
- Total deadlocks
- Peak sessions and requests
- Count of high-CPU / high-blocking / deadlock snapshots

**Example:**
```
TotalSnapshots: 288 (every 5 minutes × 24 hours)
AvgCpuSignalWaitPct: 1.12%
MaxCpuSignalWaitPct: 2.34%
AvgBlockingSessions: 52
TotalDeadlocks: 0
HighBlockingSnapshots: 12
```

### 5. Top Slowest Queries (Recent)
**Purpose:** Performance bottlenecks from last 24 hours

**Shows:**
- Database name
- SQL text preview (150 characters)
- Execution count
- Average elapsed time (ms)
- Average CPU time (ms)
- Average logical reads
- Impact score (ExecutionCount × AvgElapsedMs)
- Query hash for tracking

**Default:** Top 10 queries
**Customize:** `@TopSlowQueries = 20`

### 6. Top CPU Queries (Recent)
**Purpose:** CPU-intensive queries from last 24 hours

**Shows:**
- Database name
- SQL text preview
- Execution count
- Average CPU time
- Total CPU time
- CPU impact score
- When captured

**Use Case:**
"What's burning my CPU?" - This result set answers it.

### 7. Top Missing Indexes
**Purpose:** Index recommendations with ready-to-run CREATE statements

**Shows:**
- Database and table name
- Equality/inequality/included columns
- User seeks and scans
- Average cost and impact
- Impact score (higher = more important)
- **CREATE INDEX statement (ready to execute)**

**Default:** Top 10 indexes
**Customize:** `@TopMissingIndexes = 20`

**Example Output:**
```sql
ImpactScore: 61,356,695
ObjectName: dbo.AccountTransaction
CreateIndexStatement:
  CREATE NONCLUSTERED INDEX [IX_dbo.AccountTransaction_1044645808]
  ON dbo.AccountTransaction
  ([AccountID], [AccountTransactionTypeID],
   [VoidedDateTime], [ArchivedDateTime])
  INCLUDE ([Amount], [AccountAmount])
```

⚠️ **IMPORTANT:** Always review and test index creation in non-production first!

### 8. Top Wait Types (Last 24 Hours)
**Purpose:** Wait statistics breakdown with explanations

**Shows:**
- Wait type name
- Total wait time (ms)
- Total waiting tasks
- Observation count
- Percentage of total waits
- **Plain English description of what each wait means**

**Example:**
```
WaitType: PAGEIOLATCH_SH
TotalWaitTimeMs: 1,234,567
PctOfTotalWaits: 45.2%
Description: Disk I/O - Check storage performance
```

### 9. Database Size Summary
**Purpose:** Current size of all databases

**Shows:**
- Database name
- Total size (MB)
- Data file size (MB)
- Log file size (MB)
- File count
- State (ONLINE / OFFLINE)
- Recovery model
- Log reuse wait description
- As-of date

**Use Case:**
"Which database is growing the fastest?" - Review this over multiple days.

### 10. Recent Errors (If Any)
**Purpose:** Collection errors from last 24 hours

**Shows:**
- When error occurred
- Procedure name
- Error number
- Error description
- How long ago

**If no errors:**
```
Status: No errors found in the last 24 hours
```

### 11. Collection Job Status
**Purpose:** Verify automated collection is working

**Shows:**
- Job name
- Enabled status
- Last run status (Succeeded / Failed)
- Last run date/time
- Next run date/time

**Use Case:**
"Is the monitoring still running?" - This tells you immediately.

### 12. Action Items & Recommendations
**Purpose:** Prioritized list of what to do next

**Shows:**
- Priority (CRITICAL / HIGH / MEDIUM / LOW / INFO)
- Action item
- Details

**Common Recommendations:**
- **CRITICAL:** Collection job stopped (data stale)
- **HIGH:** Investigate high CPU usage
- **HIGH:** Investigate blocking sessions
- **MEDIUM:** Review deadlock graphs
- **MEDIUM:** Consider creating missing indexes
- **MEDIUM:** Optimize slow queries
- **INFO:** System healthy (no action needed)

**Example:**
```
Priority: HIGH
ActionItem: Investigate High CPU Usage
Details: CPU signal wait percentage exceeded 40% in the last 24 hours.
         Review top CPU queries and consider optimization.
```

## Usage Examples

### Daily Morning Check (Default)
```sql
-- Run every morning - takes 5-10 seconds
EXEC DBA_DailyHealthOverview
```

### Extended Analysis
```sql
-- Look back 48 hours, show more results
EXEC DBA_DailyHealthOverview
    @TopSlowQueries = 20,
    @TopMissingIndexes = 20,
    @HoursBackForIssues = 48
```

### Weekly Review
```sql
-- Show top 50 queries and indexes for comprehensive review
EXEC DBA_DailyHealthOverview
    @TopSlowQueries = 50,
    @TopMissingIndexes = 50,
    @HoursBackForIssues = 168  -- 1 week
```

### Quick Status Check
```sql
-- Just want to know if everything is okay?
-- Look at result set #2 (Current Health) and #12 (Recommendations)
EXEC DBA_DailyHealthOverview
```

## How to Read the Report

### 1. Start with the Header (Result Set #1)
- Is DataStatus = "DATA CURRENT"? Good!
- Is it "STALE DATA"? Check collection jobs (Result Set #11)
- Is it "NO DATA"? Collection isn't running - investigate immediately

### 2. Check Current Health (Result Set #2)
- HealthStatus = "HEALTHY"? Move on
- HealthStatus = "WARNING" or "CRITICAL"? Read the metrics carefully

### 3. Review Action Items (Result Set #12)
- Any CRITICAL items? Address immediately
- Any HIGH items? Investigate today
- Any MEDIUM items? Add to weekly review
- Only INFO? You're good!

### 4. Drill Down as Needed
- High CPU? → Check Result Set #6 (Top CPU Queries)
- Slow queries? → Check Result Set #5 (Slowest Queries)
- Performance issues? → Check Result Set #7 (Missing Indexes) and #8 (Wait Types)

### 5. Look for Trends
- Run this daily and compare
- Are slow queries getting worse?
- Are missing index impact scores growing?
- Is database size growing as expected?

## Time Savings

**Without this procedure:**
- Run 5-10 different queries
- Switch between result sets
- Manually correlate data
- **Total time: 15-20 minutes**

**With this procedure:**
- One command
- All data in one place
- Action items prioritized
- **Total time: 2-3 minutes to review**

**Savings: 12-17 minutes per day = ~5 hours per month**

## Integration with Existing Tools

### Works Great With:
```sql
-- For detailed analysis after finding issues
EXEC DBA_FindSlowQueries @DatabaseName = 'ProblemDB', @TopN = 20
EXEC DBA_FindBlockingHistory @HoursBack = 4
EXEC DBA_GetWaitStatsBreakdown @HoursBack = 1
```

### Complements:
- User Guide daily routines (docs/USER-GUIDE.md)
- Specific troubleshooting scenarios
- Deep-dive investigations

## Best Practices

### 1. Run Daily
Set up a reminder to run this every morning. It becomes your daily dashboard.

### 2. Save Historical Results
Consider saving results to a table for trend analysis:
```sql
-- Create archive table
CREATE TABLE DBATools.dbo.DailyOverviewArchive (
    RunDate DATE,
    ServerName SYSNAME,
    ReportData XML
)

-- Archive today's report (advanced users)
-- Export results to XML and insert
```

### 3. Focus on Action Items
Result Set #12 tells you exactly what to do. Trust it.

### 4. Don't Panic on Warnings
A WARNING status doesn't mean disaster - it means "pay attention."
- Review the specific metrics
- Check if it's a pattern or one-time spike
- Use trending data to determine severity

### 5. Create Indexes Carefully
Result Set #7 gives you CREATE statements, but:
- Test in non-production first
- Verify the index helps query performance
- Monitor index usage after creation
- Don't create all suggested indexes at once

## Troubleshooting

### Report Takes Too Long
```sql
-- Reduce result counts
EXEC DBA_DailyHealthOverview
    @TopSlowQueries = 5,
    @TopMissingIndexes = 5,
    @HoursBackForIssues = 12
```

### No Data Returned
```sql
-- Check if collections are running
SELECT TOP 5 * FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC
```

### "STALE DATA" Status
```sql
-- Check collection job
EXEC msdb.dbo.sp_help_job @job_name = 'DBA Collect Perf Snapshot'

-- Check for errors
SELECT TOP 10 * FROM DBATools.dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC
```

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| @TopSlowQueries | INT | 10 | How many slow queries to show in result sets #5 and #6 |
| @TopMissingIndexes | INT | 10 | How many missing indexes to show in result set #7 |
| @HoursBackForIssues | INT | 24 | How far back to look for issues in result set #3 |

## Related Documentation

- [Reporting Guide](REPORTING-GUIDE.md) - Individual reporting procedures
- [User Guide](USER-GUIDE.md) - For non-DBAs
- [Deployment Summary](DEPLOYMENT-SUMMARY-2025-10-27.md) - System overview

## Quick Reference Card

**Daily Routine:**
```sql
-- Monday through Friday, every morning
EXEC DBA_DailyHealthOverview
-- Review result sets #1, #2, #12
-- Address any CRITICAL or HIGH priority items
```

**Weekly Review:**
```sql
-- Monday morning, extended view
EXEC DBA_DailyHealthOverview
    @TopSlowQueries = 20,
    @TopMissingIndexes = 20,
    @HoursBackForIssues = 168  -- Whole week
-- Review all result sets
-- Plan optimization work for the week
```

**Incident Response:**
```sql
-- "Database is slow right now!"
EXEC DBA_DailyHealthOverview @HoursBackForIssues = 1
-- Focus on result sets #2 (current health) and #3 (recent issues)
```

---

**Remember:** This one procedure replaces 5+ separate commands and gives you everything you need for daily monitoring in 2-3 minutes of review time.
