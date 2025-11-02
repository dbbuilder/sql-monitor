-- =====================================================
-- Phase 3 - Feature #6: Automated Index Maintenance
-- Database Tables and Indexes
-- =====================================================
-- File: 84-create-index-maintenance-tables.sql
-- Purpose: Create tables for index fragmentation tracking, maintenance history, and statistics management
-- Dependencies: 02-create-tables.sql (Servers table)
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '======================================'
PRINT 'Creating Index Maintenance Tables'
PRINT '======================================'
PRINT ''

-- =====================================================
-- Table 1: IndexFragmentation
-- Purpose: Store index fragmentation snapshots for all databases/servers
-- =====================================================

IF OBJECT_ID('dbo.IndexFragmentation', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.IndexFragmentation;
    PRINT 'Dropped existing table: dbo.IndexFragmentation';
END;
GO

CREATE TABLE dbo.IndexFragmentation (
    FragmentationID BIGINT IDENTITY(1,1) NOT NULL,
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

    CONSTRAINT PK_IndexFragmentation PRIMARY KEY CLUSTERED (FragmentationID),
    CONSTRAINT FK_IndexFragmentation_Server FOREIGN KEY (ServerID)
        REFERENCES dbo.Servers(ServerID)
);
GO

-- Indexes for common query patterns
CREATE NONCLUSTERED INDEX IX_IndexFragmentation_Server_Time
    ON dbo.IndexFragmentation(ServerID, CollectionTime)
    INCLUDE (DatabaseName, FragmentationPercent, PageCount);
GO

CREATE NONCLUSTERED INDEX IX_IndexFragmentation_Lookup
    ON dbo.IndexFragmentation(ServerID, DatabaseName, SchemaName, TableName, IndexName)
    INCLUDE (FragmentationPercent, PageCount, CollectionTime);
GO

CREATE NONCLUSTERED INDEX IX_IndexFragmentation_High
    ON dbo.IndexFragmentation(FragmentationPercent DESC)
    INCLUDE (ServerID, DatabaseName, SchemaName, TableName, IndexName, PageCount, CollectionTime)
    WHERE FragmentationPercent > 30.0;
GO

PRINT 'Created table: dbo.IndexFragmentation';
PRINT '  - Primary key: PK_IndexFragmentation';
PRINT '  - Foreign key: FK_IndexFragmentation_Server';
PRINT '  - Index: IX_IndexFragmentation_Server_Time';
PRINT '  - Index: IX_IndexFragmentation_Lookup';
PRINT '  - Index: IX_IndexFragmentation_High (filtered)';
PRINT ''

-- =====================================================
-- Table 2: IndexMaintenanceHistory
-- Purpose: Log all index maintenance operations (rebuild/reorganize)
-- =====================================================

IF OBJECT_ID('dbo.IndexMaintenanceHistory', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.IndexMaintenanceHistory;
    PRINT 'Dropped existing table: dbo.IndexMaintenanceHistory';
END;
GO

CREATE TABLE dbo.IndexMaintenanceHistory (
    MaintenanceID BIGINT IDENTITY(1,1) NOT NULL,
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

    CONSTRAINT PK_IndexMaintenanceHistory PRIMARY KEY CLUSTERED (MaintenanceID),
    CONSTRAINT FK_IndexMaintenanceHistory_Server FOREIGN KEY (ServerID)
        REFERENCES dbo.Servers(ServerID),
    CONSTRAINT CHK_IndexMaintenanceHistory_Type
        CHECK (MaintenanceType IN ('REBUILD', 'REORGANIZE')),
    CONSTRAINT CHK_IndexMaintenanceHistory_Status
        CHECK (Status IN ('Success', 'Failed', 'Timeout'))
);
GO

-- Indexes for reporting and analysis
CREATE NONCLUSTERED INDEX IX_IndexMaintenanceHistory_Server_Time
    ON dbo.IndexMaintenanceHistory(ServerID, StartTime)
    INCLUDE (MaintenanceType, DurationSeconds, Status);
GO

CREATE NONCLUSTERED INDEX IX_IndexMaintenanceHistory_Status
    ON dbo.IndexMaintenanceHistory(Status, StartTime)
    INCLUDE (ServerID, DatabaseName, SchemaName, TableName, IndexName, ErrorMessage)
    WHERE Status <> 'Success';
GO

PRINT 'Created table: dbo.IndexMaintenanceHistory';
PRINT '  - Primary key: PK_IndexMaintenanceHistory';
PRINT '  - Foreign key: FK_IndexMaintenanceHistory_Server';
PRINT '  - Check constraint: CHK_IndexMaintenanceHistory_Type';
PRINT '  - Check constraint: CHK_IndexMaintenanceHistory_Status';
PRINT '  - Index: IX_IndexMaintenanceHistory_Server_Time';
PRINT '  - Index: IX_IndexMaintenanceHistory_Status (filtered)';
PRINT ''

-- =====================================================
-- Table 3: StatisticsInfo
-- Purpose: Track statistics freshness and update history
-- =====================================================

IF OBJECT_ID('dbo.StatisticsInfo', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.StatisticsInfo;
    PRINT 'Dropped existing table: dbo.StatisticsInfo';
END;
GO

CREATE TABLE dbo.StatisticsInfo (
    StatID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    StatisticsName NVARCHAR(128) NOT NULL,
    StatisticsID INT NOT NULL,
    IsClustered BIT NOT NULL DEFAULT 0,
    IsUnique BIT NOT NULL DEFAULT 0,
    LastUpdated DATETIME2(7) NULL,
    RowCount BIGINT NOT NULL,
    ModificationCounter BIGINT NOT NULL, -- Rows modified since last update
    SamplePercent DECIMAL(5,2) NULL,
    CollectionTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT PK_StatisticsInfo PRIMARY KEY CLUSTERED (StatID),
    CONSTRAINT FK_StatisticsInfo_Server FOREIGN KEY (ServerID)
        REFERENCES dbo.Servers(ServerID)
);
GO

-- Indexes for finding outdated statistics
CREATE NONCLUSTERED INDEX IX_StatisticsInfo_Server_Time
    ON dbo.StatisticsInfo(ServerID, CollectionTime)
    INCLUDE (DatabaseName, SchemaName, TableName, StatisticsName, LastUpdated, ModificationCounter);
GO

CREATE NONCLUSTERED INDEX IX_StatisticsInfo_Outdated
    ON dbo.StatisticsInfo(LastUpdated, ModificationCounter)
    INCLUDE (ServerID, DatabaseName, SchemaName, TableName, StatisticsName, RowCount)
    WHERE ModificationCounter > 1000;
GO

PRINT 'Created table: dbo.StatisticsInfo';
PRINT '  - Primary key: PK_StatisticsInfo';
PRINT '  - Foreign key: FK_StatisticsInfo_Server';
PRINT '  - Index: IX_StatisticsInfo_Server_Time';
PRINT '  - Index: IX_StatisticsInfo_Outdated (filtered)';
PRINT ''

-- =====================================================
-- Table 4: MaintenanceSchedule
-- Purpose: Configure maintenance windows per server (optional customization)
-- =====================================================

IF OBJECT_ID('dbo.MaintenanceSchedule', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.MaintenanceSchedule;
    PRINT 'Dropped existing table: dbo.MaintenanceSchedule';
END;
GO

CREATE TABLE dbo.MaintenanceSchedule (
    ScheduleID INT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DayOfWeek INT NOT NULL, -- 1=Sunday, 7=Saturday
    StartTime TIME(0) NOT NULL,
    EndTime TIME(0) NOT NULL,
    IsEnabled BIT NOT NULL DEFAULT 1,
    MaxDurationMinutes INT NOT NULL DEFAULT 240, -- 4 hours

    CONSTRAINT PK_MaintenanceSchedule PRIMARY KEY CLUSTERED (ScheduleID),
    CONSTRAINT FK_MaintenanceSchedule_Server FOREIGN KEY (ServerID)
        REFERENCES dbo.Servers(ServerID),
    CONSTRAINT UQ_MaintenanceSchedule_Server_Day UNIQUE (ServerID, DayOfWeek),
    CONSTRAINT CHK_MaintenanceSchedule_DayOfWeek
        CHECK (DayOfWeek BETWEEN 1 AND 7),
    CONSTRAINT CHK_MaintenanceSchedule_Duration
        CHECK (MaxDurationMinutes > 0 AND MaxDurationMinutes <= 480) -- Max 8 hours
);
GO

PRINT 'Created table: dbo.MaintenanceSchedule';
PRINT '  - Primary key: PK_MaintenanceSchedule';
PRINT '  - Foreign key: FK_MaintenanceSchedule_Server';
PRINT '  - Unique constraint: UQ_MaintenanceSchedule_Server_Day';
PRINT '  - Check constraint: CHK_MaintenanceSchedule_DayOfWeek';
PRINT '  - Check constraint: CHK_MaintenanceSchedule_Duration';
PRINT ''

-- =====================================================
-- Insert Default Maintenance Schedules
-- Saturday 2:00 AM - 6:00 AM for all active servers
-- =====================================================

INSERT INTO dbo.MaintenanceSchedule (ServerID, DayOfWeek, StartTime, EndTime, IsEnabled, MaxDurationMinutes)
SELECT
    ServerID,
    7 AS DayOfWeek, -- Saturday
    '02:00:00' AS StartTime,
    '06:00:00' AS EndTime,
    1 AS IsEnabled,
    240 AS MaxDurationMinutes -- 4 hours
FROM dbo.Servers
WHERE IsActive = 1
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.MaintenanceSchedule ms
      WHERE ms.ServerID = Servers.ServerID
        AND ms.DayOfWeek = 7
  );

DECLARE @SchedulesCreated INT = @@ROWCOUNT;
PRINT 'Inserted ' + CAST(@SchedulesCreated AS VARCHAR) + ' default maintenance schedules (Saturday 2:00 AM - 6:00 AM)';
PRINT ''

-- =====================================================
-- Summary and Verification
-- =====================================================

PRINT '======================================'
PRINT 'Index Maintenance Tables Summary'
PRINT '======================================'
PRINT ''

PRINT 'Tables Created:'
SELECT
    t.name AS TableName,
    SUM(CASE WHEN i.type = 1 THEN 1 ELSE 0 END) AS ClusteredIndexes,
    SUM(CASE WHEN i.type = 2 THEN 1 ELSE 0 END) AS NonClusteredIndexes,
    COUNT(DISTINCT fk.name) AS ForeignKeys,
    COUNT(DISTINCT cc.name) AS CheckConstraints
FROM sys.tables t
LEFT JOIN sys.indexes i ON t.object_id = i.object_id
LEFT JOIN sys.foreign_keys fk ON t.object_id = fk.parent_object_id
LEFT JOIN sys.check_constraints cc ON t.object_id = cc.parent_object_id
WHERE t.name IN ('IndexFragmentation', 'IndexMaintenanceHistory', 'StatisticsInfo', 'MaintenanceSchedule')
GROUP BY t.name
ORDER BY t.name;

PRINT ''
PRINT 'Total Tables: 4'
PRINT 'Total Indexes: 10'
PRINT 'Total Foreign Keys: 4'
PRINT 'Total Check Constraints: 4'
PRINT ''

PRINT 'Sample Queries:'
PRINT '  -- View current fragmentation across all servers'
PRINT '  SELECT TOP 20 * FROM dbo.IndexFragmentation'
PRINT '  WHERE FragmentationPercent > 30 ORDER BY PageCount DESC;'
PRINT ''
PRINT '  -- View maintenance history (last 7 days)'
PRINT '  SELECT * FROM dbo.IndexMaintenanceHistory'
PRINT '  WHERE StartTime >= DATEADD(DAY, -7, GETUTCDATE())'
PRINT '  ORDER BY StartTime DESC;'
PRINT ''
PRINT '  -- View outdated statistics'
PRINT '  SELECT TOP 20 * FROM dbo.StatisticsInfo'
PRINT '  WHERE ModificationCounter * 100.0 / NULLIF(RowCount, 0) > 20'
PRINT '  ORDER BY ModificationCounter DESC;'
PRINT ''
PRINT '  -- View maintenance schedules'
PRINT '  SELECT s.ServerName, ms.DayOfWeek, ms.StartTime, ms.EndTime'
PRINT '  FROM dbo.MaintenanceSchedule ms'
PRINT '  INNER JOIN dbo.Servers s ON ms.ServerID = s.ServerID;'
PRINT ''

PRINT '======================================'
PRINT 'Index Maintenance Tables Created Successfully'
PRINT '======================================'
PRINT ''

GO
