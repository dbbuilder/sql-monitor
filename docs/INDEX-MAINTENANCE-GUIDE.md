# Index Maintenance & Health - User Guide

**Feature**: Automated Index Maintenance (Phase 3, Feature #6)
**Version**: 1.0
**Last Updated**: 2025-11-02

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Overview](#overview)
3. [Index Fragmentation Explained](#index-fragmentation-explained)
4. [Maintenance Strategies](#maintenance-strategies)
5. [Statistics Management](#statistics-management)
6. [Scheduling & Windows](#scheduling--windows)
7. [Dashboard Usage](#dashboard-usage)
8. [Customization & Tuning](#customization--tuning)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)

---

## Quick Start

### View Current Fragmentation

```sql
-- See fragmented indexes across all servers
SELECT TOP 20
    s.ServerName,
    f.DatabaseName,
    f.SchemaName + '.' + f.TableName AS [Table],
    f.IndexName,
    f.FragmentationPercent,
    f.PageCount,
    CAST(f.PageCount * 8.0 / 1024 AS DECIMAL(10,2)) AS [Size MB]
FROM dbo.IndexFragmentation f
INNER JOIN dbo.Servers s ON f.ServerID = s.ServerID
WHERE f.FragmentationPercent > 30
  AND f.CollectionTime > DATEADD(HOUR, -12, GETUTCDATE())
ORDER BY f.FragmentationPercent DESC;
```

### Preview Maintenance Actions (Dry Run)

```sql
-- See what maintenance would be performed (without executing)
EXEC dbo.usp_PerformIndexMaintenance @DryRun = 1;
```

### Execute Maintenance Manually

```sql
-- Perform index maintenance (run during low-activity period)
EXEC dbo.usp_PerformIndexMaintenance
    @MinFragmentationPercent = 5.0,
    @RebuildThreshold = 30.0,
    @MaxDurationMinutes = 240; -- 4 hours max
```

### View Maintenance History

```sql
-- Get summary of recent maintenance
EXEC dbo.usp_GetMaintenanceSummary @DaysBack = 7;

-- Detailed history
SELECT TOP 50 *
FROM dbo.IndexMaintenanceHistory
WHERE StartTime >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY StartTime DESC;
```

### Grafana Dashboard

Navigate to: **Dashboards → Index Maintenance & Health**

Key panels:
- **Indexes Requiring Maintenance**: Real-time count of fragmented indexes
- **Fragmentation Trend**: Historical fragmentation levels
- **Top 20 Fragmented Indexes**: Most critical indexes to address
- **Maintenance History**: Recent maintenance operations with status

---

## Overview

### Architecture

The Index Maintenance system consists of three automated workflows:

```
┌─────────────────────────────────────────────────────────┐
│        Every 6 Hours (Fragmentation Collection)         │
│  usp_CollectIndexFragmentation → IndexFragmentation     │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│         Every 6 Hours (Statistics Collection)           │
│  usp_CollectStatisticsInfo → StatisticsInfo             │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│      Weekly Maintenance Window (Saturday 2:00 AM)       │
│  usp_PerformIndexMaintenance → IndexMaintenanceHistory  │
│  usp_UpdateStatistics → Statistics updated on servers   │
└─────────────────────────────────────────────────────────┘
```

### Components

**Tables**:
- `IndexFragmentation`: Fragmentation snapshots (collected every 6 hours)
- `IndexMaintenanceHistory`: Log of all maintenance operations
- `StatisticsInfo`: Statistics freshness tracking
- `MaintenanceSchedule`: Per-server maintenance windows (optional)

**Stored Procedures**:
- `usp_CollectIndexFragmentation`: Collect fragmentation from all servers
- `usp_CollectStatisticsInfo`: Collect statistics metadata
- `usp_PerformIndexMaintenance`: Execute rebuild/reorganize operations
- `usp_UpdateStatistics`: Update outdated statistics
- `usp_GetMaintenanceSummary`: Summary report for dashboards

**SQL Agent Jobs**:
- **Collect Index Fragmentation**: Runs every 6 hours (00:00, 06:00, 12:00, 18:00)
- **Collect Statistics Info**: Runs every 6 hours (00:30, 06:30, 12:30, 18:30)
- **Perform Index Maintenance**: Runs weekly (Saturday 2:00 AM)

---

## Index Fragmentation Explained

### What is Index Fragmentation?

Index fragmentation occurs when the logical order of pages in an index doesn't match the physical order on disk. This causes:
- **Increased I/O**: More disk reads to retrieve data
- **Slower queries**: Especially range scans and table scans
- **Wasted space**: Partially filled pages consume more disk

### Types of Fragmentation

**1. External Fragmentation (Logical Fragmentation)**:
- Measured by `avg_fragmentation_in_percent` from `sys.dm_db_index_physical_stats`
- **< 5%**: Healthy, no action needed
- **5-30%**: Moderate, consider REORGANIZE
- **> 30%**: High, REBUILD recommended

**2. Internal Fragmentation (Page Fullness)**:
- Measured by `avg_page_space_used_in_percent`
- Pages not fully utilized (due to page splits)
- Fixed by REBUILD (applies proper fill factor)

### Causes of Fragmentation

- **INSERT operations**: New rows added in non-sequential order
- **UPDATE operations**: Row size increases, causing page splits
- **DELETE operations**: Leaves gaps in pages
- **Low fill factor**: Intentional space reserved for future growth

### Why Ignore Small Indexes?

Indexes < 1000 pages (~8 MB) are ignored because:
- **Fast to read**: Even if fragmented, entire index fits in memory
- **Overhead**: Maintenance takes longer than reading fragmented pages
- **Best Practice**: Microsoft recommendation (SQL Server Best Practices)

---

## Maintenance Strategies

### Decision Logic

The system uses **industry best practices** to determine maintenance type:

| Fragmentation % | Page Count | Action | Reason |
|-----------------|------------|--------|--------|
| < 5% | Any | **SKIP** | Healthy, no benefit from maintenance |
| 5-30% | ≥ 1000 | **REORGANIZE** | Online operation, minimal impact |
| > 30% | ≥ 1000 | **REBUILD** | Thorough defragmentation |
| Any | < 1000 | **SKIP** | Too small to matter |

### REORGANIZE vs. REBUILD

**REORGANIZE**:
- **Online operation**: Queries can still run (minimal blocking)
- **Incremental**: Compacts leaf-level pages
- **Space efficient**: Doesn't require extra disk space
- **Best for**: Moderate fragmentation (5-30%)
- **SQL Command**: `ALTER INDEX [IndexName] ON [Table] REORGANIZE;`

**REBUILD**:
- **Offline operation**: Table locked during rebuild (Standard Edition)
- **Thorough**: Drops and recreates index from scratch
- **Space required**: Temporary disk space (up to 2x index size)
- **Best for**: High fragmentation (> 30%)
- **SQL Command**: `ALTER INDEX [IndexName] ON [Table] REBUILD;`

**Enterprise Edition Note**: REBUILD can be performed ONLINE, but this feature requires special considerations:
- Longer duration than offline rebuild
- Increased transaction log usage
- Not supported for all index types (e.g., XML, spatial)

### Execution Order

Maintenance is performed in **priority order**:
1. **Highest fragmentation first**: Addresses worst offenders
2. **Largest indexes first**: Maximum impact on query performance
3. **Per-database grouping**: All indexes in one database before moving to next

### Safety Features

**Max Duration Timeout**:
```sql
EXEC dbo.usp_PerformIndexMaintenance @MaxDurationMinutes = 240; -- 4 hours
```
- Stops maintenance after 4 hours (default)
- Prevents runaway maintenance during business hours
- Resumes next week (idempotent)

**Error Handling**:
- Individual index failures don't stop entire maintenance
- Errors logged to `IndexMaintenanceHistory` with `Status = 'Failed'`
- DBA can review failures and retry manually

**Dry Run Mode**:
```sql
EXEC dbo.usp_PerformIndexMaintenance @DryRun = 1;
```
- Preview all maintenance actions without executing
- Shows exactly what would be done
- Useful for estimating duration and impact

---

## Statistics Management

### Why Update Statistics?

SQL Server uses **statistics** to choose optimal query plans. Outdated statistics cause:
- **Suboptimal plans**: Wrong join order, incorrect index selection
- **Parameter sniffing issues**: Cached plans no longer optimal
- **Performance degradation**: Queries run slower over time

### Automatic vs. Manual Updates

**SQL Server Auto-Update** (default):
- Triggers when 20% + 500 rows modified (SQL 2016+)
- **Problem**: Only uses sample, may be inaccurate
- **Problem**: Doesn't trigger until after queries slow down

**Our System**:
- **Proactive**: Updates before performance degrades
- **Configurable thresholds**: 7 days or 20% modification
- **Smart sampling**: FULLSCAN for critical statistics, SAMPLE for others

### Statistics Update Logic

```sql
EXEC dbo.usp_UpdateStatistics
    @MinDaysSinceUpdate = 7,        -- 7+ days old
    @MinModificationPercent = 20.0; -- 20% of rows changed
```

**Criteria**:
- **Age-based**: Statistics not updated in 7+ days
- **Modification-based**: 20%+ of rows inserted/updated/deleted

**Sample Method**:
- **FULLSCAN**: Primary keys, unique indexes (critical for accuracy)
- **SAMPLE 50%**: Non-critical indexes (balance speed vs. accuracy)

### When Statistics Are Updated

**Automatically**:
- After weekly index maintenance (every Saturday 2:00 AM)
- Triggered by `usp_UpdateStatistics` in SQL Agent job

**Manually**:
```sql
-- Update all outdated statistics
EXEC dbo.usp_UpdateStatistics @DryRun = 0;

-- Preview statistics that would be updated
EXEC dbo.usp_UpdateStatistics @DryRun = 1;
```

### Monitoring Statistics Freshness

```sql
-- View outdated statistics
SELECT TOP 20
    s.ServerName,
    si.DatabaseName,
    si.SchemaName + '.' + si.TableName AS [Table],
    si.StatisticsName,
    si.LastUpdated,
    DATEDIFF(DAY, si.LastUpdated, GETUTCDATE()) AS [Days Since Update],
    si.RowCount,
    si.ModificationCounter,
    CAST(si.ModificationCounter * 100.0 / NULLIF(si.RowCount, 0) AS DECIMAL(5,2)) AS [Modification %]
FROM dbo.StatisticsInfo si
INNER JOIN dbo.Servers s ON si.ServerID = s.ServerID
WHERE si.RowCount > 0
  AND (
      DATEDIFF(DAY, si.LastUpdated, GETUTCDATE()) >= 7
      OR (si.ModificationCounter * 100.0 / NULLIF(si.RowCount, 0)) >= 20.0
  )
ORDER BY [Modification %] DESC;
```

---

## Scheduling & Windows

### Default Schedule

**Collection** (Low impact, runs 24x7):
- **Fragmentation**: Every 6 hours (00:00, 06:00, 12:00, 18:00)
- **Statistics Info**: Every 6 hours (00:30, 06:30, 12:30, 18:30)
- **Duration**: 1-5 minutes per collection (read-only queries)

**Maintenance** (High impact, runs weekly):
- **Day**: Saturday
- **Time**: 2:00 AM - 6:00 AM (4-hour window)
- **Operations**: Index rebuild/reorganize + statistics updates
- **Duration**: Variable (depends on fragmentation level)

### Customizing Maintenance Windows

**Per-Server Maintenance Windows** (optional):

```sql
-- Set custom maintenance window for specific server
INSERT INTO dbo.MaintenanceSchedule (ServerID, DayOfWeek, StartTime, EndTime, MaxDurationMinutes)
VALUES (
    1,            -- ServerID (from dbo.Servers)
    7,            -- Saturday (1=Sunday, 7=Saturday)
    '02:00:00',   -- 2:00 AM
    '06:00:00',   -- 6:00 AM
    240           -- 4 hours max
);

-- View current maintenance schedules
SELECT
    s.ServerName,
    CASE ms.DayOfWeek
        WHEN 1 THEN 'Sunday'
        WHEN 2 THEN 'Monday'
        WHEN 3 THEN 'Tuesday'
        WHEN 4 THEN 'Wednesday'
        WHEN 5 THEN 'Thursday'
        WHEN 6 THEN 'Friday'
        WHEN 7 THEN 'Saturday'
    END AS DayName,
    ms.StartTime,
    ms.EndTime,
    ms.MaxDurationMinutes,
    ms.IsEnabled
FROM dbo.MaintenanceSchedule ms
INNER JOIN dbo.Servers s ON ms.ServerID = s.ServerID
ORDER BY s.ServerName, ms.DayOfWeek;
```

**Change Job Schedule** (affects all servers):

```sql
-- Disable weekly maintenance job (temporary)
EXEC msdb.dbo.sp_update_job
    @job_name = N'MonitoringDB - Perform Index Maintenance (Weekly)',
    @enabled = 0;

-- Re-enable weekly maintenance job
EXEC msdb.dbo.sp_update_job
    @job_name = N'MonitoringDB - Perform Index Maintenance (Weekly)',
    @enabled = 1;

-- Change to Sunday 3:00 AM instead of Saturday 2:00 AM
EXEC msdb.dbo.sp_update_schedule
    @name = N'Weekly Saturday 2:00 AM',
    @new_name = N'Weekly Sunday 3:00 AM',
    @freq_interval = 1, -- Sunday (2^0 = 1)
    @active_start_time = 030000; -- 03:00:00 AM
```

### Running Maintenance Manually

```sql
-- Start maintenance job immediately (NOT recommended during business hours)
EXEC msdb.dbo.sp_start_job
    @job_name = N'MonitoringDB - Perform Index Maintenance (Weekly)';

-- Run maintenance for specific server only
EXEC dbo.usp_PerformIndexMaintenance
    @ServerID = 1, -- Specific server
    @MaxDurationMinutes = 60; -- 1 hour only

-- Run maintenance for specific database only
EXEC dbo.usp_PerformIndexMaintenance
    @ServerID = 1,
    @DatabaseName = 'MyDatabase';
```

---

## Dashboard Usage

### Dashboard: Index Maintenance & Health

**Location**: Grafana → Dashboards → Index Maintenance & Health

### Panel 1: Indexes Requiring Maintenance (Stat)

**What it shows**: Count of indexes with ≥ 5% fragmentation and ≥ 1000 pages

**Thresholds**:
- **Green (0)**: No indexes need maintenance
- **Yellow (1-10)**: Few indexes fragmented
- **Orange (11-50)**: Moderate fragmentation
- **Red (51+)**: Many indexes need attention

**Action**: If red/orange, review "Top 20 Fragmented Indexes" table

### Panel 2: Maintenance Operations (Last 30 Days) (Stat)

**What it shows**: Total rebuild + reorganize operations in past 30 days

**Expected value**: ~50-500 per week (depends on number of servers/databases)

**Action**: If 0, check if SQL Agent job is running

### Panel 3: Outdated Statistics (Stat)

**What it shows**: Count of statistics needing updates (7+ days old OR 20%+ modifications)

**Thresholds**:
- **Green (0-9)**: Minimal statistics staleness
- **Yellow (10-49)**: Some statistics outdated
- **Orange (50-99)**: Many statistics outdated
- **Red (100+)**: Critical statistics staleness

**Action**: If red, run `EXEC dbo.usp_UpdateStatistics;`

### Panel 4: Maintenance Success Rate (Stat)

**What it shows**: Percentage of successful maintenance operations (last 30 days)

**Expected value**: ≥ 95%

**Action**: If < 95%, review failures in "Maintenance History" table

### Panel 5: Fragmentation Trend (Time Series)

**What it shows**: Average and maximum fragmentation over last 30 days

**Expected behavior**:
- **Peak** on Saturday morning (before maintenance)
- **Drop** on Saturday night (after maintenance)
- **Gradual increase** during week

**Action**: If trend doesn't drop weekly, check maintenance job success

### Panel 6: Maintenance Duration by Server (Bar Chart)

**What it shows**: Total maintenance time per server (last 30 days)

**Use cases**:
- **Identify slow servers**: Servers with longer maintenance may need more frequent defrag
- **Capacity planning**: Estimate maintenance window requirements
- **Troubleshooting**: Long durations may indicate large indexes or slow disk

### Panel 7: Top 20 Fragmented Indexes (Table)

**Columns**:
- **ServerName, DatabaseName, Table, IndexName**: Location
- **Fragmentation %**: Current fragmentation level (color-coded)
- **PageCount**: Index size (8KB pages)
- **Size MB**: Index size in megabytes
- **IndexType**: CLUSTERED, NONCLUSTERED, COLUMNSTORE
- **Last Checked**: When fragmentation was collected

**Color coding**:
- **Green**: < 5% (healthy)
- **Yellow**: 5-30% (moderate)
- **Orange**: 30-50% (high)
- **Red**: > 50% (critical)

**Actions**:
- **Manual rebuild**: If critical index during business hours
  ```sql
  USE [DatabaseName];
  ALTER INDEX [IndexName] ON [SchemaName].[TableName] REBUILD WITH (ONLINE = OFF);
  ```
- **Exclude from maintenance**: If special handling required
  ```sql
  -- Add to exclusion list (feature not yet implemented)
  ```

### Panel 8: Maintenance History (Table)

**Columns**:
- **ServerName, DatabaseName, Table, IndexName**: Location
- **MaintenanceType**: REBUILD or REORGANIZE
- **Frag Before %**: Fragmentation before maintenance
- **Frag After %**: Fragmentation after maintenance (if rechecked)
- **DurationSeconds**: How long maintenance took
- **StartTime**: When maintenance started
- **Status**: Success or Failed (color-coded)

**Sorting**: Most recent first

**Actions**:
- **Identify slow operations**: Long duration may indicate disk bottleneck
- **Review failures**: Red status = error occurred, see `ErrorMessage` column
- **Validate effectiveness**: Compare "Frag Before" vs. "Frag After"

---

## Customization & Tuning

### Adjusting Fragmentation Thresholds

**Default thresholds**:
- `@MinFragmentationPercent = 5.0` (5% minimum)
- `@RebuildThreshold = 30.0` (30% triggers rebuild)

**Adjust for your workload**:

```sql
-- More aggressive (lower thresholds)
EXEC dbo.usp_PerformIndexMaintenance
    @MinFragmentationPercent = 3.0,   -- Start at 3%
    @RebuildThreshold = 20.0;          -- Rebuild at 20%

-- Less aggressive (higher thresholds)
EXEC dbo.usp_PerformIndexMaintenance
    @MinFragmentationPercent = 10.0,  -- Only > 10%
    @RebuildThreshold = 40.0;          -- Rebuild only at 40%
```

**When to adjust**:
- **More aggressive**: High-performance OLTP systems, SSD storage
- **Less aggressive**: Low-priority databases, limited maintenance windows

### Adjusting Statistics Update Criteria

```sql
-- More frequent statistics updates
EXEC dbo.usp_UpdateStatistics
    @MinDaysSinceUpdate = 3,        -- 3 days instead of 7
    @MinModificationPercent = 10.0; -- 10% instead of 20%

-- Less frequent statistics updates
EXEC dbo.usp_UpdateStatistics
    @MinDaysSinceUpdate = 14,       -- 14 days
    @MinModificationPercent = 30.0; -- 30%
```

### Excluding Specific Indexes

To exclude indexes from automatic maintenance:

```sql
-- Option 1: Filter by database name
EXEC dbo.usp_PerformIndexMaintenance
    @ServerID = 1,
    @DatabaseName = 'ProductionDB'; -- Only this database

-- Option 2: Filter by page count (skip very large indexes)
EXEC dbo.usp_PerformIndexMaintenance
    @MinPageCount = 1000,  -- Default
    @MaxPageCount = 100000; -- Skip indexes > 800 MB
```

**Future enhancement**: Add `IndexMaintenanceExclusions` table for specific index exclusions

### Parallel Maintenance (Future Enhancement)

Currently, maintenance runs serially (one index at a time). Future versions may support:
```sql
-- Not yet implemented
EXEC dbo.usp_PerformIndexMaintenance
    @MaxParallelOperations = 4; -- Run 4 rebuilds concurrently
```

---

## Troubleshooting

### Problem 1: No Fragmentation Data Collected

**Symptoms**:
```sql
SELECT COUNT(*) FROM dbo.IndexFragmentation; -- Returns 0
```

**Causes & Solutions**:

**1. SQL Agent job not running**:
```sql
-- Check job status
SELECT
    j.name,
    j.enabled,
    CASE
        WHEN ja.start_execution_date IS NULL THEN 'Never run'
        ELSE CAST(ja.start_execution_date AS VARCHAR)
    END AS LastRun
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
WHERE j.name LIKE '%Fragmentation%';

-- Enable job if disabled
EXEC msdb.dbo.sp_update_job
    @job_name = N'MonitoringDB - Collect Index Fragmentation (6 Hours)',
    @enabled = 1;

-- Start job manually
EXEC msdb.dbo.sp_start_job
    @job_name = N'MonitoringDB - Collect Index Fragmentation (6 Hours)';
```

**2. Linked server connection failure**:
```sql
-- Test linked server connection
SELECT * FROM OPENQUERY([LinkedServerName], 'SELECT @@VERSION');

-- Check error log
SELECT TOP 50 *
FROM msdb.dbo.sysjobhistory
WHERE job_id = (
    SELECT job_id FROM msdb.dbo.sysjobs
    WHERE name = N'MonitoringDB - Collect Index Fragmentation (6 Hours)'
)
ORDER BY run_date DESC, run_time DESC;
```

**3. Permission issue**:
```sql
-- Ensure monitoring login has VIEW SERVER STATE permission on remote servers
EXEC sp_executesql N'GRANT VIEW SERVER STATE TO [MonitoringLogin];'
    AT [LinkedServerName];
```

### Problem 2: Maintenance Not Reducing Fragmentation

**Symptoms**:
- Maintenance runs successfully
- But fragmentation remains high in next collection

**Causes & Solutions**:

**1. Heavy workload during/after maintenance**:
- Indexes refragment immediately due to high INSERT/UPDATE activity
- **Solution**: Increase maintenance frequency or adjust workload patterns

**2. Low fill factor**:
```sql
-- Check index fill factor
SELECT
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    i.fill_factor
FROM sys.indexes i
WHERE i.fill_factor > 0 AND i.fill_factor < 90;

-- Set appropriate fill factor during rebuild
ALTER INDEX [IndexName] ON [TableName]
REBUILD WITH (FILLFACTOR = 90); -- Leave 10% free space
```

**3. Page splits during data load**:
- Bulk inserts cause page splits even after maintenance
- **Solution**: Use `TABLOCK` and `ORDER` hints during bulk load

### Problem 3: Maintenance Takes Too Long

**Symptoms**:
- Maintenance hits `@MaxDurationMinutes` timeout
- Many indexes remain fragmented

**Causes & Solutions**:

**1. Too many fragmented indexes**:
```sql
-- Check how many indexes need maintenance
SELECT COUNT(*) AS IndexCount
FROM dbo.IndexFragmentation
WHERE FragmentationPercent >= 5.0
  AND PageCount >= 1000
  AND CollectionTime > DATEADD(HOUR, -12, GETUTCDATE());
```

**Solutions**:
- **Increase window**: `@MaxDurationMinutes = 480` (8 hours)
- **Run more frequently**: Change job to run twice per week (Saturday + Wednesday)
- **Raise thresholds**: `@MinFragmentationPercent = 10.0` (skip minor fragmentation)

**2. Slow disk I/O**:
- Rebuilds are I/O intensive
- **Solution**: Use `SORT_IN_TEMPDB = ON` to offload sorting to tempdb
  ```sql
  ALTER INDEX [IndexName] ON [TableName]
  REBUILD WITH (SORT_IN_TEMPDB = ON);
  ```
- **Solution**: Move tempdb to faster disks (SSD)

**3. Lock contention**:
- Offline rebuilds block queries
- **Solution**: Use REORGANIZE instead of REBUILD for busy tables
  ```sql
  -- Lower rebuild threshold to prefer REORGANIZE
  EXEC dbo.usp_PerformIndexMaintenance
      @RebuildThreshold = 50.0; -- Only rebuild at 50%+
  ```

### Problem 4: Statistics Not Updating

**Symptoms**:
```sql
SELECT COUNT(*) FROM dbo.StatisticsInfo WHERE LastUpdated < DATEADD(DAY, -7, GETUTCDATE());
-- Returns large number
```

**Causes & Solutions**:

**1. SQL Agent job not running**:
```sql
-- Check last statistics update job run
EXEC msdb.dbo.sp_help_jobhistory
    @job_name = N'MonitoringDB - Perform Index Maintenance (Weekly)',
    @mode = N'SUMMARY';
```

**2. Job step failure**:
- Step 1 (index maintenance) may complete, but Step 2 (statistics update) fails
- Review job history for specific error message

**3. Permission issue**:
```sql
-- Ensure monitoring login can UPDATE STATISTICS on remote servers
GRANT ALTER ON SCHEMA::dbo TO [MonitoringLogin];
```

### Problem 5: High Maintenance Failure Rate

**Symptoms**:
- "Maintenance Success Rate" panel shows < 95%

**Causes & Solutions**:

**1. Timeout errors**:
- Individual index rebuilds timeout
- **Solution**: Increase retry attempts or split large indexes

**2. Disk space exhaustion**:
- Rebuilds require temporary space (up to 2x index size)
- **Solution**: Monitor disk space, cleanup old backups, expand volume

**3. Lock timeout**:
- Queries holding locks prevent maintenance
- **Solution**: Run maintenance during low-activity window

**View specific failures**:
```sql
SELECT TOP 20
    s.ServerName,
    h.DatabaseName,
    h.TableName,
    h.IndexName,
    h.StartTime,
    h.ErrorMessage
FROM dbo.IndexMaintenanceHistory h
INNER JOIN dbo.Servers s ON h.ServerID = s.ServerID
WHERE h.Status = 'Failed'
ORDER BY h.StartTime DESC;
```

---

## Best Practices

### 1. Start with Dry Run

**Before enabling automatic maintenance**, run dry run to preview actions:

```sql
-- Preview all maintenance that would occur
EXEC dbo.usp_PerformIndexMaintenance @DryRun = 1;

-- Review output:
-- - How many indexes would be rebuilt vs. reorganized?
-- - How long would it take? (estimate: 1-5 min per index)
-- - Are there any very large indexes (> 50 GB)?
```

**Benefits**:
- Understand maintenance scope
- Estimate duration
- Identify potential issues

### 2. Monitor First 3 Weeks

**Week 1**: Review daily
- Check fragmentation collection (should run 4x daily)
- Verify data appears in `IndexFragmentation` table
- Review "Indexes Requiring Maintenance" count

**Week 2**: After first maintenance
- Review maintenance history (did it complete within window?)
- Check fragmentation reduction (should drop significantly)
- Validate no application errors during maintenance

**Week 3**: Normal operation
- Review weekly (not daily)
- Look for trends (fragmentation building up again?)
- Adjust thresholds if needed

### 3. Integrate with Alerting (Feature #3)

Create alert rules for maintenance failures:

```sql
-- Alert if maintenance success rate < 90%
INSERT INTO dbo.AlertRules (
    RuleName, MetricCategory, MetricName,
    LowThreshold, HighThreshold, IsEnabled
)
VALUES (
    'Index Maintenance Failure Rate',
    'Maintenance', 'SuccessRate',
    NULL, 0.90, -- Alert if < 90%
    1
);
```

### 4. Tune for Your Workload

**OLTP (High Transaction Volume)**:
- **Lower thresholds**: `@MinFragmentationPercent = 3.0` (proactive)
- **More frequent maintenance**: 2x per week (Wednesday + Saturday)
- **Prefer REORGANIZE**: `@RebuildThreshold = 50.0` (minimize blocking)

**OLAP (Analytical Workload)**:
- **Higher thresholds**: `@MinFragmentationPercent = 10.0` (less critical)
- **Weekly maintenance**: Once per week sufficient
- **Prefer REBUILD**: `@RebuildThreshold = 20.0` (thorough defrag)

**Hybrid Workload**:
- **Use default thresholds**: 5% / 30%
- **Customize per database**: OLTP databases more aggressive, OLAP less

### 5. Coordinate with Backup Schedule

**Don't overlap maintenance and backups**:
- **Saturday 2:00 AM - 6:00 AM**: Index maintenance
- **Saturday 7:00 AM**: Full backup (after maintenance)

**Benefits**:
- Smaller backup size (indexes defragmented)
- No resource contention
- Maintenance completes before backup starts

### 6. Review Maintenance History Monthly

**Monthly review checklist**:
1. **Success rate**: Should be ≥ 95%
2. **Duration trend**: Is maintenance taking longer each month?
3. **Fragmentation trend**: Are indexes staying defragmented?
4. **Failure patterns**: Are same indexes failing repeatedly?

**SQL for monthly review**:
```sql
EXEC dbo.usp_GetMaintenanceSummary @DaysBack = 30;

-- Review fragmentation trend
SELECT
    DATEPART(WEEK, CollectionTime) AS WeekNumber,
    AVG(FragmentationPercent) AS AvgFragmentation,
    MAX(FragmentationPercent) AS MaxFragmentation
FROM dbo.IndexFragmentation
WHERE CollectionTime >= DATEADD(DAY, -90, GETUTCDATE())
  AND PageCount >= 1000
GROUP BY DATEPART(WEEK, CollectionTime)
ORDER BY WeekNumber;
```

### 7. Leverage Statistics for Query Optimization

**Statistics are more important than defragmentation** for query performance:
- Outdated statistics → wrong query plans → slow queries
- Fragmentation → more I/O → slower scans

**Priority**:
1. **Fix outdated statistics first** (immediate impact)
2. **Then defragment indexes** (gradual improvement)

**Verify statistics freshness**:
```sql
-- Check critical tables
SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    s.name AS StatisticsName,
    sp.last_updated,
    sp.rows,
    sp.modification_counter,
    CAST(sp.modification_counter * 100.0 / NULLIF(sp.rows, 0) AS DECIMAL(5,2)) AS ModificationPercent
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECT_NAME(s.object_id) IN ('YourCriticalTable1', 'YourCriticalTable2')
ORDER BY ModificationPercent DESC;
```

### 8. Exclude Rarely-Used Indexes

**Identify unused indexes**:
```sql
SELECT
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    us.user_seeks,
    us.user_scans,
    us.user_lookups,
    us.user_updates
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us
    ON i.object_id = us.object_id AND i.index_id = us.index_id
WHERE us.user_seeks + us.user_scans + us.user_lookups = 0
  AND us.user_updates > 0; -- Updated but never queried
```

**Consider dropping** (after careful analysis):
- Unused indexes waste maintenance time
- Still incur insert/update overhead
- Consume disk space

### 9. Test Maintenance Impact on Production

**Before deploying to production**:
1. **Run on test/staging environment first**
2. **Monitor application performance during maintenance**
3. **Verify no timeout errors or deadlocks**
4. **Measure actual duration** (may differ from estimate)

**Production deployment**:
1. **Start with least critical servers**
2. **Monitor for 2-3 weeks**
3. **Gradually roll out to production servers**

### 10. Document Custom Configurations

If you deviate from defaults, document why:

```sql
-- Example: Custom configuration for high-volume OLTP server
/*
Server: SQL-PROD-01
Maintenance Window: Wednesday + Saturday 2:00 AM - 5:00 AM
Thresholds: MinFragmentation = 3%, RebuildThreshold = 40%
Reason: Heavy INSERT workload causes rapid fragmentation, but REBUILD causes long blocking
Strategy: Aggressive REORGANIZE (weekly), conservative REBUILD (only critical cases)
*/
```

---

## Appendix: SQL Reference

### Quick Reference Commands

```sql
-- ========================================
-- Collection
-- ========================================

-- Collect fragmentation (manual)
EXEC dbo.usp_CollectIndexFragmentation;

-- Collect statistics (manual)
EXEC dbo.usp_CollectStatisticsInfo;

-- ========================================
-- Maintenance
-- ========================================

-- Preview maintenance (dry run)
EXEC dbo.usp_PerformIndexMaintenance @DryRun = 1;

-- Execute maintenance (default thresholds)
EXEC dbo.usp_PerformIndexMaintenance
    @MinFragmentationPercent = 5.0,
    @RebuildThreshold = 30.0,
    @MaxDurationMinutes = 240;

-- Maintenance for specific server only
EXEC dbo.usp_PerformIndexMaintenance @ServerID = 1;

-- Maintenance for specific database only
EXEC dbo.usp_PerformIndexMaintenance
    @ServerID = 1,
    @DatabaseName = 'MyDatabase';

-- Update outdated statistics
EXEC dbo.usp_UpdateStatistics
    @MinDaysSinceUpdate = 7,
    @MinModificationPercent = 20.0;

-- ========================================
-- Reporting
-- ========================================

-- Get maintenance summary (last 30 days)
EXEC dbo.usp_GetMaintenanceSummary @DaysBack = 30;

-- View current fragmentation
SELECT TOP 20 * FROM dbo.IndexFragmentation
WHERE FragmentationPercent > 30
  AND CollectionTime > DATEADD(HOUR, -12, GETUTCDATE())
ORDER BY FragmentationPercent DESC;

-- View maintenance history
SELECT TOP 50 * FROM dbo.IndexMaintenanceHistory
WHERE StartTime >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY StartTime DESC;

-- View outdated statistics
SELECT TOP 20 * FROM dbo.StatisticsInfo
WHERE (ModificationCounter * 100.0 / NULLIF(RowCount, 0)) >= 20
  AND CollectionTime > DATEADD(HOUR, -12, GETUTCDATE())
ORDER BY ModificationCounter DESC;

-- ========================================
-- SQL Agent Jobs
-- ========================================

-- Start fragmentation collection job
EXEC msdb.dbo.sp_start_job
    @job_name = N'MonitoringDB - Collect Index Fragmentation (6 Hours)';

-- Start statistics collection job
EXEC msdb.dbo.sp_start_job
    @job_name = N'MonitoringDB - Collect Statistics Info (6 Hours)';

-- Start maintenance job (caution: runs during business hours)
EXEC msdb.dbo.sp_start_job
    @job_name = N'MonitoringDB - Perform Index Maintenance (Weekly)';

-- Check job history
EXEC msdb.dbo.sp_help_jobhistory
    @job_name = N'MonitoringDB - Perform Index Maintenance (Weekly)',
    @mode = N'SUMMARY';

-- Disable maintenance job (temporary)
EXEC msdb.dbo.sp_update_job
    @job_name = N'MonitoringDB - Perform Index Maintenance (Weekly)',
    @enabled = 0;
```

---

**End of Index Maintenance & Health Guide**

For questions or issues, review the Troubleshooting section or contact your DBA team.
