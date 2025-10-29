# SQL Server Monitoring - Reporting Guide

## Overview

The DBATools monitoring system now includes comprehensive reporting views and diagnostic stored procedures that make it easy to analyze collected performance data without writing complex queries.

## Deployment Status

✅ **Successfully Deployed to All 3 Servers:**
- sqltest.schoolvision.net,14333
- svweb,14333
- suncity.schoolvision.net,14333

## Available Reporting Tools

### Quick Health Checks

#### 1. DBA_CheckSystemHealth
**Purpose:** One-command health overview - run this first!

**Usage:**
```sql
EXEC DBA_CheckSystemHealth
```

**Returns 4 Result Sets:**
1. **Current Status** - Latest snapshot with health assessment
2. **Recent Issues** - Problems in last hour (high CPU, blocking, deadlocks)
3. **Top 5 Slowest Queries** - Recent performance killers
4. **Top 5 Missing Indexes** - Quick wins for performance

**Example Output:**
```
CURRENT STATUS:
  HealthStatus: WARNING - High Blocking
  CpuSignalWaitPct: 1.12%
  BlockingSessionCount: 52
  MinutesSinceSnapshot: 2

TOP 5 SLOWEST QUERIES:
  Database: SVDB_Merced
  AvgElapsedMs: 1,198,396 (20 minutes!)
  ImpactScore: 1,198,396 (needs optimization)

TOP 5 MISSING INDEXES:
  Object: dbo.AccountTransaction
  ImpactScore: 61,356,695
  CREATE INDEX Statement: [Ready to run]
```

### Diagnostic Stored Procedures

#### 2. DBA_GetSystemHealthReport
**Purpose:** Detailed health analysis over time

**Parameters:**
- `@HoursBack INT = 24` - How far back to analyze

**Usage:**
```sql
-- Last 24 hours (default)
EXEC DBA_GetSystemHealthReport

-- Last week
EXEC DBA_GetSystemHealthReport @HoursBack = 168
```

**Returns:**
- Summary statistics (avg/max CPU, blocking, deadlocks)
- All issues found (high CPU, blocking, deadlocks)
- Top wait types in time window

#### 3. DBA_FindSlowQueries
**Purpose:** Find performance problem queries

**Parameters:**
- `@DatabaseName SYSNAME = NULL` - Filter by database (NULL = all)
- `@MinAvgElapsedMs INT = 1000` - Minimum avg elapsed time in ms
- `@TopN INT = 20` - How many to return

**Usage:**
```sql
-- Top 20 slowest queries (>1 second average)
EXEC DBA_FindSlowQueries

-- Top 10 slow queries in specific database
EXEC DBA_FindSlowQueries @DatabaseName = 'SVDB_Wiley', @TopN = 10

-- Queries slower than 5 seconds
EXEC DBA_FindSlowQueries @MinAvgElapsedMs = 5000, @TopN = 50
```

**Returns:**
- Database name
- SQL text
- Execution count
- Average elapsed/CPU/reads
- Impact score (ExecutionCount × AvgElapsedMs)
- Query hash for tracking

#### 4. DBA_GetMissingIndexRecommendations
**Purpose:** Get index suggestions with CREATE statements

**Parameters:**
- `@DatabaseName SYSNAME = NULL` - Filter by database
- `@MinImpactScore FLOAT = 1000` - Minimum impact to show
- `@TopN INT = 20` - How many to return

**Usage:**
```sql
-- Top 20 missing indexes
EXEC DBA_GetMissingIndexRecommendations

-- Top 10 for specific database
EXEC DBA_GetMissingIndexRecommendations @DatabaseName = 'SVDB_Wiley', @TopN = 10

-- Only high-impact indexes (score > 10 million)
EXEC DBA_GetMissingIndexRecommendations @MinImpactScore = 10000000
```

**Example Output:**
```sql
ImpactScore: 61,356,695
Object: dbo.AccountTransaction
CreateIndexStatement:
  CREATE NONCLUSTERED INDEX [IX_dbo.AccountTransaction_1044645808]
  ON dbo.AccountTransaction ([AccountID], [AccountTransactionTypeID],
                             [VoidedDateTime], [ArchivedDateTime])
  INCLUDE ([Amount], [AccountAmount])
```

**⚠️ IMPORTANT:** Always review and test index creation in non-production first!

#### 5. DBA_FindBlockingHistory
**Purpose:** Analyze blocking patterns

**Parameters:**
- `@HoursBack INT = 24` - How far back to look
- `@MinBlockingCount INT = 10` - Minimum blocking sessions to report

**Usage:**
```sql
-- Last 24 hours, show when blocking > 10 sessions
EXEC DBA_FindBlockingHistory

-- Last 3 days, show significant blocking (>20 sessions)
EXEC DBA_FindBlockingHistory @HoursBack = 72, @MinBlockingCount = 20
```

**Returns:**
- When blocking occurred
- How many sessions were blocked
- Blocking percentage (blocked/total requests)
- Top wait type during blocking

#### 6. DBA_GetWaitStatsBreakdown
**Purpose:** Analyze wait statistics patterns

**Parameters:**
- `@HoursBack INT = 24` - Time window
- `@TopN INT = 20` - How many wait types to show

**Usage:**
```sql
-- Last 24 hours, top 20 wait types
EXEC DBA_GetWaitStatsBreakdown

-- Last week, top 10
EXEC DBA_GetWaitStatsBreakdown @HoursBack = 168, @TopN = 10
```

**Returns:**
- Wait type name
- Total wait time (ms)
- Observation count
- Percentage of total waits
- First/last seen timestamps

### Reporting Views

#### 7. vw_SystemHealthCurrent
**Purpose:** Latest snapshot with health status

**Usage:**
```sql
SELECT * FROM vw_SystemHealthCurrent
```

**Key Columns:**
- `HealthStatus` - HEALTHY, ATTENTION, WARNING, or CRITICAL
- `CpuSignalWaitPct` - CPU pressure indicator
- `BlockingSessionCount` - Current blocking
- `MinutesSinceSnapshot` - Data freshness

#### 8. vw_SystemHealthLast24Hours
**Purpose:** 24-hour trend data

**Usage:**
```sql
-- View all snapshots from last 24 hours
SELECT * FROM vw_SystemHealthLast24Hours
ORDER BY SnapshotUTC DESC

-- Find problem periods
SELECT * FROM vw_SystemHealthLast24Hours
WHERE Status = 'ISSUE'
ORDER BY SnapshotUTC DESC
```

#### 9. vw_TopSlowestQueries
**Purpose:** All-time worst performing queries

**Usage:**
```sql
-- Top 10 slowest
SELECT TOP 10 * FROM vw_TopSlowestQueries

-- Slowest in specific database
SELECT TOP 10 *
FROM vw_TopSlowestQueries
WHERE DatabaseName = 'SVDB_Wiley'
ORDER BY AvgElapsedMs DESC
```

#### 10. vw_TopCpuQueries
**Purpose:** CPU-intensive queries

**Usage:**
```sql
-- Top 10 CPU consumers
SELECT TOP 10 *
FROM vw_TopCpuQueries
ORDER BY CpuImpactScore DESC
```

#### 11. vw_TopMissingIndexes
**Purpose:** Index recommendations with CREATE statements

**Usage:**
```sql
-- Top 10 missing indexes
SELECT TOP 10
    DatabaseName,
    ObjectName,
    ImpactScore,
    CreateIndexStatement
FROM vw_TopMissingIndexes
ORDER BY ImpactScore DESC

-- For specific database
SELECT TOP 10 *
FROM vw_TopMissingIndexes
WHERE DatabaseName = 'SVDB_Wiley'
ORDER BY ImpactScore DESC
```

#### 12. vw_TopWaitStats
**Purpose:** Wait type summary with descriptions

**Usage:**
```sql
-- Top 10 wait types
SELECT TOP 10 *
FROM vw_TopWaitStats
ORDER BY TotalWaitTimeMs DESC
```

**Includes common wait descriptions:**
- PAGEIOLATCH% → "Disk I/O - Check for slow storage"
- LCK_M% → "Lock contention - Review blocking queries"
- CXPACKET% → "Parallelism - Consider MAXDOP tuning"
- etc.

## Common Use Cases

### Daily Morning Health Check
```sql
-- Run this every morning
EXEC DBA_CheckSystemHealth

-- If issues found, drill down:
EXEC DBA_FindSlowQueries @TopN = 10
EXEC DBA_GetMissingIndexRecommendations @TopN = 10
```

### Investigating "Database is Slow" Reports
```sql
-- 1. Check current status
SELECT * FROM vw_SystemHealthCurrent

-- 2. Look for recent problems
EXEC DBA_GetSystemHealthReport @HoursBack = 4

-- 3. Find slow queries
EXEC DBA_FindSlowQueries @MinAvgElapsedMs = 2000, @TopN = 20

-- 4. Check for blocking
EXEC DBA_FindBlockingHistory @HoursBack = 4, @MinBlockingCount = 5

-- 5. Review wait stats
EXEC DBA_GetWaitStatsBreakdown @HoursBack = 4, @TopN = 10
```

### Weekly Performance Review
```sql
-- 1. Overall health trend
EXEC DBA_GetSystemHealthReport @HoursBack = 168  -- Last week

-- 2. Top performance issues
EXEC DBA_FindSlowQueries @TopN = 20

-- 3. Index opportunities
EXEC DBA_GetMissingIndexRecommendations @MinImpactScore = 5000000, @TopN = 20

-- 4. Wait statistics analysis
EXEC DBA_GetWaitStatsBreakdown @HoursBack = 168, @TopN = 20
```

### Before Creating an Index
```sql
-- Get recommendations
EXEC DBA_GetMissingIndexRecommendations @DatabaseName = 'YourDatabase', @TopN = 10

-- Review the CREATE INDEX statement
-- Test in non-production first
-- Monitor query performance before and after
```

## Performance Tips

1. **Use TopN Parameters:** Limit result sets for better performance
   ```sql
   EXEC DBA_FindSlowQueries @TopN = 10  -- Not 1000
   ```

2. **Filter by Database:** When possible, narrow scope
   ```sql
   EXEC DBA_FindSlowQueries @DatabaseName = 'SpecificDB'
   ```

3. **Reasonable Time Windows:** Don't query too far back
   ```sql
   EXEC DBA_GetSystemHealthReport @HoursBack = 24  -- Not 720 (30 days)
   ```

## Understanding Health Status

The `vw_SystemHealthCurrent` view returns a health status based on current metrics:

| Status | Meaning | Criteria |
|--------|---------|----------|
| **HEALTHY** | Normal operation | CPU < 20%, Blocking < 20, No deadlocks |
| **ATTENTION** | Minor issues | CPU 20-40%, Blocking 10-20 |
| **WARNING** | Significant issues | Blocking > 20, Deadlocks 1-5 |
| **CRITICAL** | Severe problems | CPU > 40%, Deadlocks > 5 |

## Common Wait Types Guide

| Wait Type | Meaning | Action |
|-----------|---------|--------|
| PAGEIOLATCH_* | Disk I/O waits | Check storage performance, add memory |
| LCK_M_* | Lock contention | Review blocking queries, optimize transactions |
| CXPACKET | Parallelism waits | Consider MAXDOP settings, check query plans |
| SOS_SCHEDULER_YIELD | CPU pressure | Review CPU-intensive queries |
| ASYNC_NETWORK_IO | Network waits | Check client performance, result set sizes |
| WRITELOG | Log write waits | Check log disk performance |

## Troubleshooting

### No Data Returned
```sql
-- Check if collections are running
SELECT TOP 5 * FROM dbo.PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC

-- Check for errors
SELECT TOP 10 * FROM dbo.LogEntry WHERE IsError = 1 ORDER BY LogEntryID DESC
```

### Data Seems Outdated
```sql
-- Check last collection time
SELECT TOP 1
    SnapshotUTC,
    DATEDIFF(MINUTE, SnapshotUTC, SYSUTCDATETIME()) AS MinutesOld
FROM dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC
```

### Procedure Not Found
```sql
-- List all available procedures
SELECT name FROM sys.procedures
WHERE name LIKE 'DBA_%'
ORDER BY name
```

## Related Documentation

- [User Guide](USER-GUIDE.md) - For non-DBAs
- [Deployment Guide](deployment/COMPLETE_DEPLOYMENT_GUIDE.md) - Installation instructions
- [Configuration Guide](reference/CONFIGURATION-GUIDE.md) - Settings and tuning

## Quick Reference

**Most Useful Commands:**
```sql
-- Daily health check
EXEC DBA_CheckSystemHealth

-- Find slow queries
EXEC DBA_FindSlowQueries @TopN = 10

-- Get index recommendations
EXEC DBA_GetMissingIndexRecommendations @TopN = 10

-- Check current status
SELECT * FROM vw_SystemHealthCurrent

-- View 24-hour history
SELECT * FROM vw_SystemHealthLast24Hours
WHERE Status = 'ISSUE'
```

## Support

For issues or questions:
1. Check LogEntry table for errors
2. Review [Troubleshooting Guide](troubleshooting/)
3. Consult [User Guide](USER-GUIDE.md) for common scenarios
