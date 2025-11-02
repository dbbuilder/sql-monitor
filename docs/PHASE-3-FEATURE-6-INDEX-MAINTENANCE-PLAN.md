# Phase 3 - Feature #6: Automated Index Maintenance

**Date**: 2025-11-02
**Status**: Planning
**Priority**: Medium
**Estimated Effort**: 24 hours budgeted, 6-8 hours estimated actual

---

## Overview

Automated index maintenance system that analyzes index fragmentation, performs intelligent rebuild/reorganize operations, updates statistics, and provides comprehensive maintenance reporting.

### Goals

1. **Automated Fragmentation Detection**: Continuously monitor index fragmentation levels across all databases
2. **Intelligent Maintenance**: Apply industry best practices for rebuild vs. reorganize decisions
3. **Statistics Management**: Identify and update outdated statistics automatically
4. **Minimal Impact**: Schedule maintenance during low-activity periods with resource throttling
5. **Comprehensive Reporting**: Track maintenance history, performance improvements, and duration

### Value Proposition

**vs. Manual Maintenance**:
- Reduce DBA time by 90% (2 hours/week → 12 minutes/week)
- Consistent application of best practices across all databases
- Automated detection of problematic indexes

**vs. SQL Server Maintenance Plans**:
- Intelligent rebuild/reorganize decisions (not all-or-nothing)
- Cross-server maintenance coordination
- Performance impact analysis (before/after metrics)
- Integration with existing monitoring dashboards

**Commercial Equivalent**:
- Ola Hallengren scripts: Free but requires setup/tuning
- Redgate SQL Index Manager: $495/server/year
- **Our Solution**: $0 with superior integration and historical tracking

---

## Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Every 6 Hours (SQL Agent)                 │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  usp_CollectIndexFragmentation (Remote Servers)              │
│  - Query sys.dm_db_index_physical_stats                      │
│  - Capture fragmentation %, page count, record count         │
│  - Store in IndexFragmentation table                         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  usp_CollectStatisticsInfo (Remote Servers)                  │
│  - Query sys.stats, sys.dm_db_stats_properties               │
│  - Capture last update date, modification counter            │
│  - Store in StatisticsInfo table                             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              Weekly Maintenance Window (SQL Agent)           │
│              Saturday 2:00 AM - 6:00 AM                      │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  usp_PerformIndexMaintenance (All Servers)                   │
│                                                               │
│  Decision Logic:                                              │
│  - Fragmentation > 30% + Pages > 1000 → REBUILD             │
│  - Fragmentation 5-30% + Pages > 1000 → REORGANIZE          │
│  - Fragmentation < 5% → SKIP                                 │
│  - Pages < 1000 → SKIP (too small to matter)                │
│                                                               │
│  Execution:                                                   │
│  - Sort by database, then by fragmentation DESC              │
│  - Execute maintenance via OPENQUERY to remote server        │
│  - Log to IndexMaintenanceHistory                            │
│  - Capture duration, before/after fragmentation              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  usp_UpdateStatistics (All Servers)                          │
│  - Update statistics where:                                  │
│    - Last update > 7 days ago                                │
│    - Modification counter > 20% of row count                 │
│  - Use FULLSCAN for critical indexes (PK, unique)            │
│  - Use SAMPLE for non-critical indexes (performance)         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              Grafana Dashboard (Real-Time)                   │
│  - Current fragmentation levels (all servers)                │
│  - Maintenance history (last 30 days)                        │
│  - Time saved by automation                                  │
│  - Next scheduled maintenance                                │
└─────────────────────────────────────────────────────────────┘
```

---

## Database Schema

### Table 1: IndexFragmentation

**Purpose**: Store index fragmentation snapshots for all databases/servers

```sql
CREATE TABLE dbo.IndexFragmentation (
    FragmentationID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    IndexName NVARCHAR(128) NOT NULL,
    IndexID INT NOT NULL,
    IndexType VARCHAR(50) NOT NULL, -- CLUSTERED, NONCLUSTERED, HEAP, COLUMNSTORE
    PartitionNumber INT NOT NULL,
    FragmentationPercent DECIMAL(5,2) NOT NULL,
    PageCount BIGINT NOT NULL,
    RecordCount BIGINT NOT NULL,
    AvgPageSpaceUsedPercent DECIMAL(5,2) NULL,
    CollectionTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_IndexFragmentation_Server FOREIGN KEY (ServerID)
        REFERENCES dbo.Servers(ServerID),

    INDEX IX_IndexFragmentation_Server_Time (ServerID, CollectionTime),
    INDEX IX_IndexFragmentation_Lookup (ServerID, DatabaseName, SchemaName, TableName, IndexName),
    INDEX IX_IndexFragmentation_High (FragmentationPercent DESC)
        WHERE FragmentationPercent > 30.0
);
```

**Key Fields**:
- **FragmentationPercent**: Logical fragmentation percentage (from sys.dm_db_index_physical_stats)
- **PageCount**: Number of 8KB pages (used to filter out small indexes)
- **AvgPageSpaceUsedPercent**: Internal fragmentation indicator (page fullness)

**Retention**: Keep 90 days of fragmentation history for trend analysis

---

### Table 2: IndexMaintenanceHistory

**Purpose**: Log all index maintenance operations (rebuild/reorganize)

```sql
CREATE TABLE dbo.IndexMaintenanceHistory (
    MaintenanceID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    IndexName NVARCHAR(128) NOT NULL,
    IndexID INT NOT NULL,
    PartitionNumber INT NOT NULL,
    MaintenanceType VARCHAR(20) NOT NULL, -- REBUILD, REORGANIZE
    StartTime DATETIME2(7) NOT NULL,
    EndTime DATETIME2(7) NOT NULL,
    DurationSeconds INT NOT NULL,
    FragmentationBefore DECIMAL(5,2) NOT NULL,
    FragmentationAfter DECIMAL(5,2) NULL, -- NULL if not rechecked immediately
    PageCount BIGINT NOT NULL,
    MaintenanceCommand NVARCHAR(MAX) NOT NULL, -- T-SQL executed
    Status VARCHAR(20) NOT NULL DEFAULT 'Success', -- Success, Failed, Timeout
    ErrorMessage NVARCHAR(MAX) NULL,

    CONSTRAINT FK_IndexMaintenanceHistory_Server FOREIGN KEY (ServerID)
        REFERENCES dbo.Servers(ServerID),

    INDEX IX_IndexMaintenanceHistory_Server_Time (ServerID, StartTime),
    INDEX IX_IndexMaintenanceHistory_Status (Status, StartTime)
        WHERE Status <> 'Success'
);
```

**Key Fields**:
- **MaintenanceType**: REBUILD (>30% fragmentation) or REORGANIZE (5-30%)
- **DurationSeconds**: Track time impact (optimize future runs)
- **FragmentationBefore/After**: Measure effectiveness
- **Status**: Track failures for troubleshooting

**Retention**: Keep 180 days for historical analysis

---

### Table 3: StatisticsInfo

**Purpose**: Track statistics freshness and update history

```sql
CREATE TABLE dbo.StatisticsInfo (
    StatID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    StatisticsName NVARCHAR(128) NOT NULL,
    StatisticsID INT NOT NULL,
    IsClustered BIT NOT NULL,
    IsUnique BIT NOT NULL,
    LastUpdated DATETIME2(7) NULL,
    RowCount BIGINT NOT NULL,
    ModificationCounter BIGINT NOT NULL, -- Rows modified since last update
    SamplePercent DECIMAL(5,2) NULL,
    CollectionTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_StatisticsInfo_Server FOREIGN KEY (ServerID)
        REFERENCES dbo.Servers(ServerID),

    INDEX IX_StatisticsInfo_Server_Time (ServerID, CollectionTime),
    INDEX IX_StatisticsInfo_Outdated (LastUpdated, ModificationCounter)
        WHERE ModificationCounter > 1000
);
```

**Key Fields**:
- **LastUpdated**: When statistics were last refreshed
- **ModificationCounter**: Rows modified since last update (from sys.dm_db_stats_properties)
- **SamplePercent**: What sample rate was used (FULLSCAN vs. sample)

**Retention**: Keep 90 days

---

### Table 4: MaintenanceSchedule

**Purpose**: Configure maintenance windows per server (optional customization)

```sql
CREATE TABLE dbo.MaintenanceSchedule (
    ScheduleID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ServerID INT NOT NULL,
    DayOfWeek INT NOT NULL, -- 1=Sunday, 7=Saturday
    StartTime TIME(0) NOT NULL,
    EndTime TIME(0) NOT NULL,
    IsEnabled BIT NOT NULL DEFAULT 1,
    MaxDurationMinutes INT NOT NULL DEFAULT 240, -- 4 hours

    CONSTRAINT FK_MaintenanceSchedule_Server FOREIGN KEY (ServerID)
        REFERENCES dbo.Servers(ServerID),

    UNIQUE (ServerID, DayOfWeek)
);
```

**Default Schedule**:
- Saturday 2:00 AM - 6:00 AM (4-hour window)
- Can be customized per server for production environments

---

## Stored Procedures

### Procedure 1: usp_CollectIndexFragmentation

**Purpose**: Collect fragmentation data from remote SQL Server

```sql
CREATE PROCEDURE dbo.usp_CollectIndexFragmentation
    @ServerID INT = NULL -- NULL = all active servers
AS
BEGIN
    -- For each active server:
    -- 1. Build dynamic SQL with OPENQUERY to remote server
    -- 2. Query sys.dm_db_index_physical_stats (LIMITED mode for speed)
    -- 3. Filter: PageCount >= 1000 (ignore small indexes)
    -- 4. Insert into IndexFragmentation table
    -- 5. Handle errors gracefully (log but continue)
END;
```

**Performance**: ~5-10 seconds per server (depends on database count)

**Schedule**: Every 6 hours (4x daily) via SQL Agent

---

### Procedure 2: usp_CollectStatisticsInfo

**Purpose**: Collect statistics freshness from remote SQL Server

```sql
CREATE PROCEDURE dbo.usp_CollectStatisticsInfo
    @ServerID INT = NULL -- NULL = all active servers
AS
BEGIN
    -- For each active server:
    -- 1. Query sys.stats + sys.dm_db_stats_properties
    -- 2. Capture LastUpdated, RowCount, ModificationCounter
    -- 3. Insert into StatisticsInfo table
END;
```

**Performance**: ~2-5 seconds per server

**Schedule**: Every 6 hours (4x daily) via SQL Agent

---

### Procedure 3: usp_PerformIndexMaintenance

**Purpose**: Execute intelligent index maintenance (rebuild/reorganize)

```sql
CREATE PROCEDURE dbo.usp_PerformIndexMaintenance
    @ServerID INT = NULL, -- NULL = all servers
    @DatabaseName NVARCHAR(128) = NULL, -- NULL = all databases
    @MinFragmentationPercent DECIMAL(5,2) = 5.0,
    @RebuildThreshold DECIMAL(5,2) = 30.0,
    @MinPageCount INT = 1000,
    @DryRun BIT = 0, -- 1 = preview only, don't execute
    @MaxDurationMinutes INT = 240 -- 4 hours default
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();
    DECLARE @EndTime DATETIME2(7);
    DECLARE @MaintenanceCommand NVARCHAR(MAX);

    -- Decision logic:
    DECLARE @MaintenanceActions TABLE (
        ServerID INT,
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        IndexName NVARCHAR(128),
        IndexID INT,
        PartitionNumber INT,
        FragmentationPercent DECIMAL(5,2),
        PageCount BIGINT,
        MaintenanceType VARCHAR(20), -- REBUILD or REORGANIZE
        Priority INT -- Higher fragmentation = higher priority
    );

    -- Get latest fragmentation snapshot
    INSERT INTO @MaintenanceActions
    SELECT
        f.ServerID,
        f.DatabaseName,
        f.SchemaName,
        f.TableName,
        f.IndexName,
        f.IndexID,
        f.PartitionNumber,
        f.FragmentationPercent,
        f.PageCount,
        CASE
            WHEN f.FragmentationPercent >= @RebuildThreshold THEN 'REBUILD'
            WHEN f.FragmentationPercent >= @MinFragmentationPercent THEN 'REORGANIZE'
        END AS MaintenanceType,
        CAST(f.FragmentationPercent AS INT) AS Priority
    FROM dbo.IndexFragmentation f
    INNER JOIN (
        SELECT ServerID, DatabaseName, SchemaName, TableName, IndexName,
               MAX(CollectionTime) AS LastCollection
        FROM dbo.IndexFragmentation
        WHERE CollectionTime > DATEADD(HOUR, -12, GETUTCDATE())
        GROUP BY ServerID, DatabaseName, SchemaName, TableName, IndexName
    ) latest ON f.ServerID = latest.ServerID
            AND f.DatabaseName = latest.DatabaseName
            AND f.SchemaName = latest.SchemaName
            AND f.TableName = latest.TableName
            AND f.IndexName = latest.IndexName
            AND f.CollectionTime = latest.LastCollection
    WHERE f.PageCount >= @MinPageCount
      AND f.FragmentationPercent >= @MinFragmentationPercent
      AND (@ServerID IS NULL OR f.ServerID = @ServerID)
      AND (@DatabaseName IS NULL OR f.DatabaseName = @DatabaseName)
    ORDER BY Priority DESC, f.PageCount DESC; -- High fragmentation + large indexes first

    -- Execute maintenance
    DECLARE @CurrentServerID INT, @CurrentDB NVARCHAR(128),
            @CurrentSchema NVARCHAR(128), @CurrentTable NVARCHAR(128),
            @CurrentIndex NVARCHAR(128), @CurrentType VARCHAR(20);

    DECLARE maintenance_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ServerID, DatabaseName, SchemaName, TableName, IndexName, MaintenanceType
        FROM @MaintenanceActions;

    OPEN maintenance_cursor;
    FETCH NEXT FROM maintenance_cursor INTO @CurrentServerID, @CurrentDB,
        @CurrentSchema, @CurrentTable, @CurrentIndex, @CurrentType;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Check if we've exceeded max duration
        IF DATEDIFF(MINUTE, @StartTime, GETUTCDATE()) >= @MaxDurationMinutes
        BEGIN
            PRINT 'Max duration reached. Stopping maintenance.';
            BREAK;
        END;

        -- Build maintenance command
        IF @CurrentType = 'REBUILD'
        BEGIN
            SET @MaintenanceCommand =
                'ALTER INDEX [' + @CurrentIndex + '] ON [' + @CurrentDB + '].[' +
                @CurrentSchema + '].[' + @CurrentTable + '] REBUILD WITH (ONLINE = OFF);';
        END
        ELSE -- REORGANIZE
        BEGIN
            SET @MaintenanceCommand =
                'ALTER INDEX [' + @CurrentIndex + '] ON [' + @CurrentDB + '].[' +
                @CurrentSchema + '].[' + @CurrentTable + '] REORGANIZE;';
        END;

        IF @DryRun = 1
        BEGIN
            PRINT @MaintenanceCommand;
        END
        ELSE
        BEGIN
            -- Execute maintenance on remote server
            DECLARE @LinkedServerName NVARCHAR(128);
            SELECT @LinkedServerName = LinkedServerName
            FROM dbo.Servers
            WHERE ServerID = @CurrentServerID;

            BEGIN TRY
                SET @EndTime = GETUTCDATE();

                -- Execute via OPENQUERY (or sp_executesql if local)
                EXEC sp_executesql @MaintenanceCommand;

                -- Log success
                INSERT INTO dbo.IndexMaintenanceHistory (
                    ServerID, DatabaseName, SchemaName, TableName, IndexName, IndexID,
                    PartitionNumber, MaintenanceType, StartTime, EndTime, DurationSeconds,
                    FragmentationBefore, PageCount, MaintenanceCommand, Status
                )
                SELECT
                    @CurrentServerID, @CurrentDB, @CurrentSchema, @CurrentTable,
                    @CurrentIndex, IndexID, PartitionNumber, @CurrentType, @EndTime,
                    GETUTCDATE(), DATEDIFF(SECOND, @EndTime, GETUTCDATE()),
                    FragmentationPercent, PageCount, @MaintenanceCommand, 'Success'
                FROM @MaintenanceActions
                WHERE ServerID = @CurrentServerID
                  AND DatabaseName = @CurrentDB
                  AND SchemaName = @CurrentSchema
                  AND TableName = @CurrentTable
                  AND IndexName = @CurrentIndex;

            END TRY
            BEGIN CATCH
                -- Log failure
                INSERT INTO dbo.IndexMaintenanceHistory (
                    ServerID, DatabaseName, SchemaName, TableName, IndexName, IndexID,
                    PartitionNumber, MaintenanceType, StartTime, EndTime, DurationSeconds,
                    FragmentationBefore, PageCount, MaintenanceCommand, Status, ErrorMessage
                )
                SELECT
                    @CurrentServerID, @CurrentDB, @CurrentSchema, @CurrentTable,
                    @CurrentIndex, IndexID, PartitionNumber, @CurrentType, @EndTime,
                    GETUTCDATE(), DATEDIFF(SECOND, @EndTime, GETUTCDATE()),
                    FragmentationPercent, PageCount, @MaintenanceCommand, 'Failed',
                    ERROR_MESSAGE()
                FROM @MaintenanceActions
                WHERE ServerID = @CurrentServerID
                  AND DatabaseName = @CurrentDB
                  AND SchemaName = @CurrentSchema
                  AND TableName = @CurrentTable
                  AND IndexName = @CurrentIndex;
            END CATCH;
        END;

        FETCH NEXT FROM maintenance_cursor INTO @CurrentServerID, @CurrentDB,
            @CurrentSchema, @CurrentTable, @CurrentIndex, @CurrentType;
    END;

    CLOSE maintenance_cursor;
    DEALLOCATE maintenance_cursor;

    -- Return summary
    SELECT
        COUNT(*) AS TotalActions,
        SUM(CASE WHEN MaintenanceType = 'REBUILD' THEN 1 ELSE 0 END) AS Rebuilds,
        SUM(CASE WHEN MaintenanceType = 'REORGANIZE' THEN 1 ELSE 0 END) AS Reorganizes
    FROM @MaintenanceActions;
END;
GO
```

**Industry Best Practices**:
- **< 5% fragmentation**: Do nothing (overhead not worth it)
- **5-30% fragmentation**: REORGANIZE (online operation, minimal impact)
- **> 30% fragmentation**: REBUILD (offline for non-Enterprise, but more thorough)
- **< 1000 pages**: Skip (small indexes, fragmentation irrelevant)

**Safety Features**:
- Max duration timeout (prevent runaway maintenance)
- Dry run mode for testing
- Error handling (log failures, continue with next index)

---

### Procedure 4: usp_UpdateStatistics

**Purpose**: Update outdated statistics

```sql
CREATE PROCEDURE dbo.usp_UpdateStatistics
    @ServerID INT = NULL,
    @DatabaseName NVARCHAR(128) = NULL,
    @MinDaysSinceUpdate INT = 7,
    @MinModificationPercent DECIMAL(5,2) = 20.0,
    @DryRun BIT = 0
AS
BEGIN
    -- Decision logic:
    -- 1. LastUpdated > @MinDaysSinceUpdate OR
    -- 2. (ModificationCounter / RowCount * 100) >= @MinModificationPercent

    -- For critical statistics (PK, unique constraints):
    --   UPDATE STATISTICS ... WITH FULLSCAN

    -- For non-critical statistics:
    --   UPDATE STATISTICS ... WITH SAMPLE 50 PERCENT
END;
GO
```

**Schedule**: Run after index maintenance (statistics invalidated by rebuild)

---

### Procedure 5: usp_GetMaintenanceSummary

**Purpose**: Summary report for dashboards

```sql
CREATE PROCEDURE dbo.usp_GetMaintenanceSummary
    @ServerID INT = NULL,
    @DaysBack INT = 30
AS
BEGIN
    SELECT
        s.ServerName,
        COUNT(DISTINCT h.MaintenanceID) AS TotalMaintenanceOperations,
        SUM(CASE WHEN h.MaintenanceType = 'REBUILD' THEN 1 ELSE 0 END) AS TotalRebuilds,
        SUM(CASE WHEN h.MaintenanceType = 'REORGANIZE' THEN 1 ELSE 0 END) AS TotalReorganizes,
        SUM(CASE WHEN h.Status = 'Success' THEN 1 ELSE 0 END) AS SuccessfulOperations,
        SUM(CASE WHEN h.Status = 'Failed' THEN 1 ELSE 0 END) AS FailedOperations,
        SUM(h.DurationSeconds) / 60.0 AS TotalMaintenanceMinutes,
        AVG(h.FragmentationBefore) AS AvgFragmentationBefore,
        AVG(h.FragmentationAfter) AS AvgFragmentationAfter
    FROM dbo.IndexMaintenanceHistory h
    INNER JOIN dbo.Servers s ON h.ServerID = s.ServerID
    WHERE h.StartTime >= DATEADD(DAY, -@DaysBack, GETUTCDATE())
      AND (@ServerID IS NULL OR h.ServerID = @ServerID)
    GROUP BY s.ServerName
    ORDER BY s.ServerName;
END;
GO
```

---

## SQL Agent Jobs

### Job 1: Collect Index Fragmentation (Every 6 Hours)

**Name**: `MonitoringDB - Collect Index Fragmentation (6 Hours)`
**Schedule**: Every 6 hours (00:00, 06:00, 12:00, 18:00)
**Command**:
```sql
EXEC MonitoringDB.dbo.usp_CollectIndexFragmentation;
```

**Duration**: ~1-2 minutes per 10 servers

---

### Job 2: Collect Statistics Info (Every 6 Hours)

**Name**: `MonitoringDB - Collect Statistics Info (6 Hours)`
**Schedule**: Every 6 hours (00:30, 06:30, 12:30, 18:30)
**Command**:
```sql
EXEC MonitoringDB.dbo.usp_CollectStatisticsInfo;
```

**Duration**: ~30-60 seconds per 10 servers

---

### Job 3: Weekly Index Maintenance (Saturday 2:00 AM)

**Name**: `MonitoringDB - Perform Index Maintenance (Weekly)`
**Schedule**: Saturday at 2:00 AM
**Command**:
```sql
-- Step 1: Index Maintenance
EXEC MonitoringDB.dbo.usp_PerformIndexMaintenance
    @MinFragmentationPercent = 5.0,
    @RebuildThreshold = 30.0,
    @MaxDurationMinutes = 240; -- 4 hours max

-- Step 2: Update Statistics (after maintenance)
EXEC MonitoringDB.dbo.usp_UpdateStatistics
    @MinDaysSinceUpdate = 7,
    @MinModificationPercent = 20.0;
```

**Duration**: Up to 4 hours (configurable)

---

## Grafana Dashboard

**Dashboard 14: Index Maintenance & Health**

### Panel 1: Indexes Requiring Maintenance (Stat)
```sql
SELECT COUNT(*) AS IndexCount
FROM dbo.IndexFragmentation f
INNER JOIN (
    SELECT ServerID, DatabaseName, SchemaName, TableName, IndexName,
           MAX(CollectionTime) AS LastCollection
    FROM dbo.IndexFragmentation
    WHERE CollectionTime > DATEADD(HOUR, -12, GETUTCDATE())
    GROUP BY ServerID, DatabaseName, SchemaName, TableName, IndexName
) latest ON f.ServerID = latest.ServerID
        AND f.DatabaseName = latest.DatabaseName
        AND f.SchemaName = latest.SchemaName
        AND f.TableName = latest.TableName
        AND f.IndexName = latest.IndexName
        AND f.CollectionTime = latest.LastCollection
WHERE f.FragmentationPercent >= 5.0
  AND f.PageCount >= 1000;
```

**Thresholds**: Green (0), Yellow (1-10), Orange (11-50), Red (51+)

---

### Panel 2: Total Maintenance Operations (Last 30 Days) (Stat)
```sql
SELECT COUNT(*) AS TotalOperations
FROM dbo.IndexMaintenanceHistory
WHERE StartTime >= DATEADD(DAY, -30, GETUTCDATE())
  AND Status = 'Success';
```

---

### Panel 3: Fragmentation Trend (Time Series)
```sql
SELECT
    $__timeGroup(CollectionTime, '1d') AS time,
    AVG(FragmentationPercent) AS [Avg Fragmentation %],
    MAX(FragmentationPercent) AS [Max Fragmentation %]
FROM dbo.IndexFragmentation
WHERE $__timeFilter(CollectionTime)
  AND PageCount >= 1000
GROUP BY $__timeGroup(CollectionTime, '1d')
ORDER BY time;
```

---

### Panel 4: Top 20 Fragmented Indexes (Table)
```sql
SELECT TOP 20
    s.ServerName,
    f.DatabaseName,
    f.SchemaName + '.' + f.TableName AS [Table],
    f.IndexName,
    CAST(f.FragmentationPercent AS DECIMAL(5,2)) AS [Fragmentation %],
    f.PageCount,
    CAST(f.PageCount * 8.0 / 1024 AS DECIMAL(10,2)) AS [Size MB],
    f.CollectionTime AS [Last Checked]
FROM dbo.IndexFragmentation f
INNER JOIN dbo.Servers s ON f.ServerID = s.ServerID
INNER JOIN (
    SELECT ServerID, DatabaseName, SchemaName, TableName, IndexName,
           MAX(CollectionTime) AS LastCollection
    FROM dbo.IndexFragmentation
    WHERE CollectionTime > DATEADD(HOUR, -12, GETUTCDATE())
    GROUP BY ServerID, DatabaseName, SchemaName, TableName, IndexName
) latest ON f.ServerID = latest.ServerID
        AND f.DatabaseName = latest.DatabaseName
        AND f.SchemaName = latest.SchemaName
        AND f.TableName = latest.TableName
        AND f.IndexName = latest.IndexName
        AND f.CollectionTime = latest.LastCollection
WHERE f.PageCount >= 1000
ORDER BY f.FragmentationPercent DESC;
```

---

### Panel 5: Maintenance History (Last 30 Days) (Table)
```sql
SELECT
    s.ServerName,
    h.DatabaseName,
    h.SchemaName + '.' + h.TableName AS [Table],
    h.IndexName,
    h.MaintenanceType,
    CAST(h.FragmentationBefore AS DECIMAL(5,2)) AS [Frag Before %],
    CAST(h.FragmentationAfter AS DECIMAL(5,2)) AS [Frag After %],
    h.DurationSeconds,
    h.StartTime,
    h.Status
FROM dbo.IndexMaintenanceHistory h
INNER JOIN dbo.Servers s ON h.ServerID = s.ServerID
WHERE h.StartTime >= DATEADD(DAY, -30, GETUTCDATE())
ORDER BY h.StartTime DESC;
```

---

### Panel 6: Maintenance Duration by Server (Bar Chart)
```sql
SELECT
    s.ServerName,
    SUM(h.DurationSeconds) / 60.0 AS [Total Minutes]
FROM dbo.IndexMaintenanceHistory h
INNER JOIN dbo.Servers s ON h.ServerID = s.ServerID
WHERE h.StartTime >= DATEADD(DAY, -30, GETUTCDATE())
  AND h.Status = 'Success'
GROUP BY s.ServerName
ORDER BY [Total Minutes] DESC;
```

---

### Panel 7: Outdated Statistics (Table)
```sql
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
INNER JOIN (
    SELECT ServerID, DatabaseName, SchemaName, TableName, StatisticsName,
           MAX(CollectionTime) AS LastCollection
    FROM dbo.StatisticsInfo
    WHERE CollectionTime > DATEADD(HOUR, -12, GETUTCDATE())
    GROUP BY ServerID, DatabaseName, SchemaName, TableName, StatisticsName
) latest ON si.ServerID = latest.ServerID
        AND si.DatabaseName = latest.DatabaseName
        AND si.SchemaName = latest.SchemaName
        AND si.TableName = latest.TableName
        AND si.StatisticsName = latest.StatisticsName
        AND si.CollectionTime = latest.LastCollection
WHERE si.RowCount > 0
  AND (
      DATEDIFF(DAY, si.LastUpdated, GETUTCDATE()) >= 7
      OR (si.ModificationCounter * 100.0 / NULLIF(si.RowCount, 0)) >= 20.0
  )
ORDER BY [Modification %] DESC;
```

---

## Documentation

**INDEX-MAINTENANCE-GUIDE.md** (User guide with 10 sections):

1. Quick Start
2. Overview & Architecture
3. Index Fragmentation Explained
4. Maintenance Strategies (Rebuild vs. Reorganize)
5. Statistics Management
6. Scheduling & Windows
7. Dashboard Usage
8. Customization & Tuning
9. Troubleshooting
10. Best Practices

---

## Integration Tests

**test-index-maintenance.sql** (12 comprehensive tests):

1. ✅ Index maintenance tables exist (4 tables)
2. ✅ Stored procedures exist (5 procedures)
3. ✅ SQL Agent jobs exist (3 jobs)
4. ✅ Collect fragmentation data (insert test records)
5. ✅ Identify high fragmentation indexes (>30%)
6. ✅ Perform maintenance (dry run mode)
7. ✅ Execute rebuild operation
8. ✅ Execute reorganize operation
9. ✅ Log maintenance history
10. ✅ Collect statistics info
11. ✅ Identify outdated statistics
12. ✅ Get maintenance summary report

---

## Success Criteria

1. **Fragmentation Detection**: All indexes >30% fragmentation identified within 6 hours
2. **Automated Maintenance**: Weekly maintenance reduces fragmentation to <5% for all indexes
3. **Performance**: Maintenance completes within 4-hour window for 50+ databases
4. **Reliability**: <1% failure rate for maintenance operations
5. **Dashboard**: Real-time visibility into fragmentation levels and maintenance history

---

## Estimated Timeline

| Task | Estimated Time |
|------|----------------|
| Database tables + indexes | 30 minutes |
| Stored procedures (5) | 2 hours |
| SQL Agent jobs (3) | 30 minutes |
| Grafana dashboard (7 panels) | 1.5 hours |
| Documentation | 1.5 hours |
| Integration tests | 1 hour |
| **Total** | **7 hours** |

**Buffer**: 1 hour for testing/debugging
**Final Estimate**: 8 hours actual (vs. 24 hours budgeted = 67% efficiency)

---

**Status**: Ready to implement
**Next Step**: Create database tables and indexes
