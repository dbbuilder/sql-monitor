# DBA Operational Guide
## SQL Server Monitor - Phase 1.9

**Last Updated:** 2025-10-28
**Target Audience:** Database Administrators (DBAs)

## Overview

This guide covers day-to-day DBA operations for the sql-monitor system, including monitoring, maintenance, troubleshooting, and performance optimization.

## Quick Reference

### System Health Check (Daily)

```sql
-- Connect to MonitoringDB
USE MonitoringDB;

-- 1. Check collection status
SELECT
    ServerName,
    MAX(CollectionTime) AS LastCollection,
    DATEDIFF(MINUTE, MAX(CollectionTime), GETUTCDATE()) AS MinutesSinceLastCollection,
    COUNT(*) AS MetricsLast24Hours
FROM PerformanceMetrics pm
INNER JOIN Servers s ON pm.ServerID = s.ServerID
WHERE CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
GROUP BY ServerName
ORDER BY MinutesSinceLastCollection DESC;

-- 2. Check data volume
SELECT
    'PerformanceMetrics' AS TableName,
    COUNT(*) AS RowCount,
    COUNT(*) / NULLIF(DATEDIFF(DAY, MIN(CollectionTime), MAX(CollectionTime)), 0) AS RowsPerDay
FROM PerformanceMetrics
UNION ALL
SELECT 'QueryMetrics', COUNT(*), COUNT(*) / NULLIF(DATEDIFF(DAY, MIN(CollectionTime), MAX(CollectionTime)), 0)
FROM QueryMetrics
UNION ALL
SELECT 'DatabaseMetrics', COUNT(*), COUNT(*) / NULLIF(DATEDIFF(DAY, MIN(CollectionTime), MAX(CollectionTime)), 0)
FROM DatabaseMetrics;

-- 3. Check for errors
SELECT TOP 10 *
FROM AuditLog
WHERE EventType = 'Error'
ORDER BY Timestamp DESC;
```

### Grafana Dashboard Access

- **URL**: http://localhost:3000 (or your configured port)
- **Credentials**: admin / (your configured password)
- **Dashboards**: Navigate to "SQL Monitor" folder

## Data Collection

### Collection Architecture

**SQL Agent Jobs** on each monitored SQL Server collect metrics every 5 minutes and insert into MonitoringDB.

### Verify Collection Jobs

```sql
-- Run on each MONITORED server (not MonitoringDB)
USE msdb;
GO

-- Check if collection job exists
SELECT
    j.name AS JobName,
    j.enabled AS IsEnabled,
    s.name AS ScheduleName,
    CASE s.freq_type
        WHEN 4 THEN 'Daily'
        WHEN 8 THEN 'Weekly'
        WHEN 16 THEN 'Monthly'
        WHEN 64 THEN 'On SQL Server Agent start'
        WHEN 128 THEN 'Runs when CPU idle'
    END AS Frequency,
    s.freq_interval AS Interval,
    STUFF(STUFF(RIGHT('000000' + CAST(s.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS StartTime,
    ja.run_requested_date AS LastRunDate,
    ja.next_scheduled_run_date AS NextRunDate
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
WHERE j.name LIKE '%Monitor%' OR j.name LIKE '%Collect%'
ORDER BY j.name;

-- Check recent job history
SELECT TOP 20
    j.name AS JobName,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS RunDateTime,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS RunStatus,
    h.run_duration AS DurationSeconds,
    h.message AS Message
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name LIKE '%Monitor%'
ORDER BY h.run_date DESC, h.run_time DESC;
```

### Manually Trigger Collection

```sql
-- Run on MONITORED server
EXEC msdb.dbo.sp_start_job @job_name = 'SQL Monitor - Collect Metrics';
```

### Add New Server to Monitoring

```sql
-- Run on MonitoringDB
USE MonitoringDB;

-- 1. Register server
INSERT INTO Servers (ServerName, Environment, IsActive)
VALUES ('SQL-NEW-SERVER', 'Production', 1);

-- 2. On the NEW server, create linked server to MonitoringDB
EXEC sp_addlinkedserver
    @server = 'MONITORINGDB_SERVER',
    @srvproduct = '',
    @provider = 'SQLNCLI',
    @datasrc = 'sqltest.schoolvision.net,14333';

EXEC sp_addlinkedsrvlogin
    @rmtsrvname = 'MONITORINGDB_SERVER',
    @useself = 'FALSE',
    @locallogin = NULL,
    @rmtuser = 'sv',
    @rmtpassword = 'Gv51076!';

-- 3. Create SQL Agent job on NEW server (see database/09-create-sql-agent-jobs.sql)
-- Or manually create job that calls stored procedures every 5 minutes

-- 4. Test collection
EXEC msdb.dbo.sp_start_job @job_name = 'SQL Monitor - Collect Metrics';

-- 5. Verify data in MonitoringDB
SELECT TOP 10 *
FROM PerformanceMetrics pm
INNER JOIN Servers s ON pm.ServerID = s.ServerID
WHERE s.ServerName = 'SQL-NEW-SERVER'
ORDER BY CollectionTime DESC;
```

## Data Retention

### Current Retention Policies

- **PerformanceMetrics**: 90 days (configurable)
- **QueryMetrics**: 30 days
- **DatabaseMetrics**: 90 days
- **AuditLog**: 365 days

### Manual Cleanup

```sql
-- Cleanup old performance metrics (older than 90 days)
DELETE FROM PerformanceMetrics
WHERE CollectionTime < DATEADD(DAY, -90, GETUTCDATE());

-- Cleanup old query metrics (older than 30 days)
DELETE FROM QueryMetrics
WHERE CollectionTime < DATEADD(DAY, -30, GETUTCDATE());

-- Check database size after cleanup
SELECT
    DB_NAME() AS DatabaseName,
    SUM(size) * 8.0 / 1024 / 1024 AS SizeGB
FROM sys.database_files;
```

### Automated Cleanup (Recommended)

Create a SQL Agent job to run nightly:

```sql
USE MonitoringDB;
GO

-- Create cleanup procedure
CREATE OR ALTER PROCEDURE dbo.usp_CleanupOldMetrics
    @RetentionDays INT = 90
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@RetentionDays, GETUTCDATE());
    DECLARE @RowsDeleted INT;

    -- Performance Metrics
    DELETE FROM PerformanceMetrics WHERE CollectionTime < @CutoffDate;
    SET @RowsDeleted = @@ROWCOUNT;
    PRINT 'Deleted ' + CAST(@RowsDeleted AS VARCHAR(20)) + ' rows from PerformanceMetrics';

    -- Query Metrics (30 day retention)
    DELETE FROM QueryMetrics WHERE CollectionTime < DATEADD(DAY, -30, GETUTCDATE());
    SET @RowsDeleted = @@ROWCOUNT;
    PRINT 'Deleted ' + CAST(@RowsDeleted AS VARCHAR(20)) + ' rows from QueryMetrics';

    -- Database Metrics
    DELETE FROM DatabaseMetrics WHERE CollectionTime < @CutoffDate;
    SET @RowsDeleted = @@ROWCOUNT;
    PRINT 'Deleted ' + CAST(@RowsDeleted AS VARCHAR(20)) + ' rows from DatabaseMetrics';
END
GO

-- Test the procedure
EXEC dbo.usp_CleanupOldMetrics @RetentionDays = 90;
```

## Performance Optimization

### Index Maintenance

```sql
-- Check index fragmentation
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    CASE
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
        ELSE 'OK'
    END AS Recommendation
FROM sys.dm_db_index_physical_stats(DB_ID('MonitoringDB'), NULL, NULL, NULL, 'SAMPLED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0  -- Exclude heaps
  AND ips.page_count > 1000  -- Only tables with significant pages
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Rebuild fragmented indexes
ALTER INDEX ALL ON dbo.PerformanceMetrics REBUILD WITH (ONLINE = ON);
ALTER INDEX ALL ON dbo.QueryMetrics REBUILD WITH (ONLINE = ON);
ALTER INDEX ALL ON dbo.DatabaseMetrics REBUILD WITH (ONLINE = ON);

-- Update statistics
UPDATE STATISTICS dbo.PerformanceMetrics WITH FULLSCAN;
UPDATE STATISTICS dbo.QueryMetrics WITH FULLSCAN;
UPDATE STATISTICS dbo.DatabaseMetrics WITH FULLSCAN;
```

### Recommended Indexes

```sql
-- Performance Metrics (if not already created)
CREATE NONCLUSTERED INDEX IX_PerformanceMetrics_Collection
ON dbo.PerformanceMetrics (CollectionTime, ServerID)
INCLUDE (MetricCategory, MetricName, MetricValue);

CREATE NONCLUSTERED INDEX IX_PerformanceMetrics_Category
ON dbo.PerformanceMetrics (MetricCategory, MetricName, CollectionTime)
INCLUDE (ServerID, MetricValue);

-- Query Metrics
CREATE NONCLUSTERED INDEX IX_QueryMetrics_Collection
ON dbo.QueryMetrics (CollectionTime, ServerID)
INCLUDE (QueryText, ExecutionCount, AvgDuration);

-- Database Metrics
CREATE NONCLUSTERED INDEX IX_DatabaseMetrics_Collection
ON dbo.DatabaseMetrics (CollectionTime, ServerID)
INCLUDE (DatabaseName, TotalSizeMB);
```

## Troubleshooting

### Collection Stopped/Failing

**Symptom**: No new metrics in last hour

**Diagnosis**:
```sql
-- 1. Check last collection time per server
SELECT
    s.ServerName,
    MAX(pm.CollectionTime) AS LastCollection,
    DATEDIFF(MINUTE, MAX(pm.CollectionTime), GETUTCDATE()) AS MinutesAgo
FROM Servers s
LEFT JOIN PerformanceMetrics pm ON s.ServerID = pm.ServerID
WHERE s.IsActive = 1
GROUP BY s.ServerName
ORDER BY MinutesAgo DESC;

-- 2. Check for errors
SELECT TOP 20 *
FROM AuditLog
WHERE EventType = 'Error'
  AND Timestamp >= DATEADD(HOUR, -2, GETUTCDATE())
ORDER BY Timestamp DESC;
```

**Solutions**:
1. Check SQL Agent service is running on monitored servers
2. Verify SQL Agent job is enabled
3. Check network connectivity between servers
4. Verify linked server configuration
5. Check MonitoringDB disk space

### Slow Dashboard Queries

**Symptom**: Grafana dashboards taking > 5 seconds to load

**Diagnosis**:
```sql
-- Check for missing indexes
SELECT
    OBJECT_NAME(mid.object_id) AS TableName,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.avg_user_impact,
    migs.user_seeks,
    migs.user_scans
FROM sys.dm_db_missing_index_details mid
INNER JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
WHERE mid.database_id = DB_ID('MonitoringDB')
ORDER BY migs.avg_user_impact * (migs.user_seeks + migs.user_scans) DESC;
```

**Solutions**:
1. Create recommended indexes (see above)
2. Reduce dashboard time range (e.g., 24 hours instead of 7 days)
3. Run cleanup procedure to delete old data
4. Update statistics

### Database Growing Too Fast

**Symptom**: MonitoringDB > 50GB

**Diagnosis**:
```sql
-- Check table sizes
SELECT
    t.name AS TableName,
    SUM(p.rows) AS RowCount,
    SUM(a.total_pages) * 8.0 / 1024 / 1024 AS SizeGB,
    SUM(a.used_pages) * 8.0 / 1024 / 1024 AS UsedGB
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE p.index_id IN (0, 1)  -- Heap or clustered index
GROUP BY t.name
ORDER BY SizeGB DESC;
```

**Solutions**:
1. Reduce retention period
2. Run cleanup procedure more frequently
3. Archive old data to separate database
4. Implement table partitioning

## Backup and Recovery

### Backup MonitoringDB

```sql
-- Full backup (recommended: nightly)
BACKUP DATABASE MonitoringDB
TO DISK = 'D:\Backups\MonitoringDB_Full.bak'
WITH INIT, COMPRESSION;

-- Transaction log backup (recommended: every hour)
BACKUP LOG MonitoringDB
TO DISK = 'D:\Backups\MonitoringDB_Log.trn'
WITH INIT, COMPRESSION;
```

### Restore MonitoringDB

```sql
-- Restore full backup
USE master;
GO

RESTORE DATABASE MonitoringDB
FROM DISK = 'D:\Backups\MonitoringDB_Full.bak'
WITH REPLACE, RECOVERY;
```

### Disaster Recovery

If MonitoringDB is lost, you can:
1. Restore from backup
2. Redeploy schema using `database/deploy-all.sql`
3. Collection will resume automatically from all monitored servers

**Note**: Historical data will be lost if no backup exists.

## Security

### Least Privilege Access

```sql
-- Create read-only user for Grafana
USE MonitoringDB;
GO

CREATE LOGIN grafana_reader WITH PASSWORD = 'StrongPassword123!';
CREATE USER grafana_reader FOR LOGIN grafana_reader;

GRANT SELECT ON SCHEMA::dbo TO grafana_reader;
GRANT EXECUTE ON dbo.usp_GetServerHealthStatus TO grafana_reader;
GRANT EXECUTE ON dbo.usp_GetMetricHistory TO grafana_reader;
GRANT EXECUTE ON dbo.usp_GetTopQueries TO grafana_reader;
GRANT EXECUTE ON dbo.usp_GetDatabaseSummary TO grafana_reader;

-- Create write user for collection agents
CREATE LOGIN collection_agent WITH PASSWORD = 'AnotherStrongPassword456!';
CREATE USER collection_agent FOR LOGIN collection_agent;

GRANT SELECT, INSERT ON dbo.PerformanceMetrics TO collection_agent;
GRANT SELECT, INSERT ON dbo.QueryMetrics TO collection_agent;
GRANT SELECT, INSERT ON dbo.DatabaseMetrics TO collection_agent;
GRANT SELECT ON dbo.Servers TO collection_agent;
```

### Audit Access

```sql
-- Enable auditing
SELECT *
FROM AuditLog
WHERE EventType IN ('Login', 'PermissionChange', 'DataAccess')
ORDER BY Timestamp DESC;
```

## Monitoring the Monitor

### Key Metrics to Watch

1. **Collection Lag**: Should be < 10 minutes
2. **Database Size**: Should grow linearly (predictable)
3. **Query Performance**: Dashboard queries < 1 second
4. **Job Failures**: Should be 0

### Alerting (Future)

Consider setting up alerts for:
- Collection stopped for > 30 minutes
- Database size > 80% of disk capacity
- Job failures > 3 in 1 hour
- Dashboard query duration > 5 seconds

## Common Tasks

### Export Data for Analysis

```sql
-- Export CPU metrics to CSV (via BCP or SSMS)
SELECT
    s.ServerName,
    pm.CollectionTime,
    pm.MetricValue AS CPU_Percent
FROM PerformanceMetrics pm
INNER JOIN Servers s ON pm.ServerID = s.ServerID
WHERE pm.MetricCategory = 'CPU'
  AND pm.MetricName = 'Percent'
  AND pm.CollectionTime >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY s.ServerName, pm.CollectionTime;
```

### Reset/Re-initialize

```sql
-- WARNING: This deletes ALL collected data!
USE MonitoringDB;
GO

TRUNCATE TABLE PerformanceMetrics;
TRUNCATE TABLE QueryMetrics;
TRUNCATE TABLE DatabaseMetrics;
TRUNCATE TABLE ProcedureMetrics;
TRUNCATE TABLE AuditLog;

-- Servers table is preserved (registration remains)
```

## Resources

- **Documentation**: `/docs/` folder
- **Database Scripts**: `/database/` folder
- **Dashboard Files**: `/dashboards/grafana/dashboards/`
- **Troubleshooting**: See `TROUBLESHOOTING.md`

## Support

For issues:
1. Check Grafana logs: `docker logs sql-monitor-grafana`
2. Check MonitoringDB error log
3. Review `AuditLog` table for errors
4. Consult documentation in `/docs/guides/`

---

**DBA Guide Complete** - For end-user dashboard usage, see `END-USER-DASHBOARD-GUIDE.md`
