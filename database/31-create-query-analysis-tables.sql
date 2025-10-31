-- =====================================================
-- Script: 31-create-query-analysis-tables.sql
-- Description: Create tables for Query Store, Blocking, Deadlocks, Wait Stats, and Index Analysis
-- Author: SQL Server Monitor Project
-- Date: 2025-10-31
-- Purpose: Phase 2 Features - Query tuning, blocking detection, wait stats, index optimization
-- =====================================================

USE MonitoringDB;
GO

PRINT '========================================';
PRINT 'Creating Query Analysis Infrastructure';
PRINT '========================================';
PRINT '';

-- =====================================================
-- FEATURE 1: Query Store Integration
-- =====================================================

PRINT 'Creating Query Store tables...';

-- Table: QueryStoreQueries
-- Stores query text and metadata from Query Store
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.QueryStoreQueries') AND type = 'U')
BEGIN
    CREATE TABLE dbo.QueryStoreQueries
    (
        QueryStoreQueryID   BIGINT          IDENTITY(1,1)   NOT NULL,
        ServerID            INT                             NOT NULL,
        DatabaseName        NVARCHAR(128)                   NOT NULL,
        QueryID             BIGINT                          NOT NULL,    -- From sys.query_store_query
        QueryHash           VARBINARY(8)                    NULL,
        QueryText           NVARCHAR(MAX)                   NOT NULL,
        ObjectID            BIGINT                          NULL,
        BatchSqlHandle      VARBINARY(64)                   NULL,
        LastExecutionTime   DATETIME2                       NULL,
        FirstSeenTime       DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),
        LastSeenTime        DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),
        IsActive            BIT                             NOT NULL DEFAULT 1,

        CONSTRAINT PK_QueryStoreQueries PRIMARY KEY CLUSTERED (QueryStoreQueryID),
        CONSTRAINT FK_QueryStoreQueries_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
        CONSTRAINT UQ_QueryStoreQueries_ServerQuery UNIQUE (ServerID, DatabaseName, QueryID)
    );

    CREATE NONCLUSTERED INDEX IX_QueryStoreQueries_ServerDB
    ON dbo.QueryStoreQueries(ServerID, DatabaseName, IsActive)
    INCLUDE (QueryID, QueryHash, LastExecutionTime);

    PRINT '  ✓ QueryStoreQueries created';
END
ELSE
    PRINT '  - QueryStoreQueries already exists';
GO

-- Table: QueryStoreRuntimeStats
-- Stores execution statistics for queries (time-series)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.QueryStoreRuntimeStats') AND type = 'U')
BEGIN
    CREATE TABLE dbo.QueryStoreRuntimeStats
    (
        RuntimeStatsID          BIGINT          IDENTITY(1,1)   NOT NULL,
        QueryStoreQueryID       BIGINT                          NOT NULL,
        PlanID                  BIGINT                          NOT NULL,
        CollectionTime          DATETIME2                       NOT NULL,
        ExecutionCount          BIGINT                          NOT NULL,
        TotalDurationMs         BIGINT                          NOT NULL,
        AvgDurationMs           DECIMAL(18,4)                   NOT NULL,
        MinDurationMs           DECIMAL(18,4)                   NOT NULL,
        MaxDurationMs           DECIMAL(18,4)                   NOT NULL,
        TotalCPUTimeMs          BIGINT                          NOT NULL,
        TotalLogicalReads       BIGINT                          NOT NULL,
        TotalPhysicalReads      BIGINT                          NOT NULL,
        TotalLogicalWrites      BIGINT                          NOT NULL,
        TotalRowCount           BIGINT                          NOT NULL,

        CONSTRAINT PK_QueryStoreRuntimeStats PRIMARY KEY CLUSTERED (CollectionTime, RuntimeStatsID),
        CONSTRAINT FK_QueryStoreRuntimeStats_Queries FOREIGN KEY (QueryStoreQueryID)
            REFERENCES dbo.QueryStoreQueries(QueryStoreQueryID)
    )
    ON PS_MonitoringByMonth(CollectionTime);

    CREATE NONCLUSTERED COLUMNSTORE INDEX IX_QueryStoreRuntimeStats_CS
    ON dbo.QueryStoreRuntimeStats (QueryStoreQueryID, PlanID, CollectionTime, ExecutionCount,
                                    AvgDurationMs, TotalCPUTimeMs, TotalLogicalReads);

    PRINT '  ✓ QueryStoreRuntimeStats created (partitioned)';
END
ELSE
    PRINT '  - QueryStoreRuntimeStats already exists';
GO

-- Table: QueryStorePlans
-- Stores execution plans from Query Store
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.QueryStorePlans') AND type = 'U')
BEGIN
    CREATE TABLE dbo.QueryStorePlans
    (
        QueryStorePlanID    BIGINT          IDENTITY(1,1)   NOT NULL,
        QueryStoreQueryID   BIGINT                          NOT NULL,
        PlanID              BIGINT                          NOT NULL,
        PlanHash            VARBINARY(8)                    NULL,
        QueryPlan           NVARCHAR(MAX)                   NULL,        -- XML plan
        CompileTime         DATETIME2                       NULL,
        LastExecutionTime   DATETIME2                       NULL,
        AvgCompileDurationMs DECIMAL(18,4)                  NULL,
        LastCompileDurationMs DECIMAL(18,4)                 NULL,
        IsForceplan         BIT                             NOT NULL DEFAULT 0,
        IsForcePlanSuccess  BIT                             NULL,

        CONSTRAINT PK_QueryStorePlans PRIMARY KEY CLUSTERED (QueryStorePlanID),
        CONSTRAINT FK_QueryStorePlans_Queries FOREIGN KEY (QueryStoreQueryID)
            REFERENCES dbo.QueryStoreQueries(QueryStoreQueryID)
    );

    CREATE NONCLUSTERED INDEX IX_QueryStorePlans_QueryID
    ON dbo.QueryStorePlans(QueryStoreQueryID, PlanID)
    INCLUDE (PlanHash, LastExecutionTime);

    PRINT '  ✓ QueryStorePlans created';
END
ELSE
    PRINT '  - QueryStorePlans already exists';
GO

-- =====================================================
-- FEATURE 2: Blocking and Deadlock Detection
-- =====================================================

PRINT '';
PRINT 'Creating Blocking/Deadlock tables...';

-- Table: BlockingEvents
-- Captures real-time blocking chains
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.BlockingEvents') AND type = 'U')
BEGIN
    CREATE TABLE dbo.BlockingEvents
    (
        BlockingEventID     BIGINT          IDENTITY(1,1)   NOT NULL,
        ServerID            INT                             NOT NULL,
        EventTime           DATETIME2                       NOT NULL,
        DatabaseName        NVARCHAR(128)                   NULL,
        BlockingSessionID   INT                             NOT NULL,
        BlockedSessionID    INT                             NOT NULL,
        WaitType            NVARCHAR(60)                    NULL,
        WaitTimeMs          BIGINT                          NULL,
        WaitResource        NVARCHAR(256)                   NULL,
        BlockingSQL         NVARCHAR(MAX)                   NULL,
        BlockedSQL          NVARCHAR(MAX)                   NULL,
        BlockingHostName    NVARCHAR(128)                   NULL,
        BlockingProgramName NVARCHAR(128)                   NULL,
        BlockingLoginName   NVARCHAR(128)                   NULL,
        BlockedHostName     NVARCHAR(128)                   NULL,
        BlockedProgramName  NVARCHAR(128)                   NULL,
        BlockedLoginName    NVARCHAR(128)                   NULL,
        IsolationLevel      SMALLINT                        NULL,
        LockMode            NVARCHAR(20)                    NULL,

        CONSTRAINT PK_BlockingEvents PRIMARY KEY CLUSTERED (EventTime, BlockingEventID),
        CONSTRAINT FK_BlockingEvents_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    )
    ON PS_MonitoringByMonth(EventTime);

    CREATE NONCLUSTERED INDEX IX_BlockingEvents_ServerTime
    ON dbo.BlockingEvents(ServerID, EventTime)
    INCLUDE (BlockingSessionID, BlockedSessionID, WaitType, WaitTimeMs);

    PRINT '  ✓ BlockingEvents created (partitioned)';
END
ELSE
    PRINT '  - BlockingEvents already exists';
GO

-- Table: DeadlockEvents
-- Captures deadlock graphs and victim information
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.DeadlockEvents') AND type = 'U')
BEGIN
    CREATE TABLE dbo.DeadlockEvents
    (
        DeadlockEventID     BIGINT          IDENTITY(1,1)   NOT NULL,
        ServerID            INT                             NOT NULL,
        EventTime           DATETIME2                       NOT NULL,
        DatabaseName        NVARCHAR(128)                   NULL,
        DeadlockGraph       XML                             NULL,        -- Full deadlock XML
        VictimSessionID     INT                             NULL,
        VictimHostName      NVARCHAR(128)                   NULL,
        VictimProgramName   NVARCHAR(128)                   NULL,
        VictimLoginName     NVARCHAR(128)                   NULL,
        Process1SessionID   INT                             NULL,
        Process1SQL         NVARCHAR(MAX)                   NULL,
        Process2SessionID   INT                             NULL,
        Process2SQL         NVARCHAR(MAX)                   NULL,
        LockMode            NVARCHAR(20)                    NULL,
        ObjectName          NVARCHAR(256)                   NULL,

        CONSTRAINT PK_DeadlockEvents PRIMARY KEY CLUSTERED (EventTime, DeadlockEventID),
        CONSTRAINT FK_DeadlockEvents_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    )
    ON PS_MonitoringByMonth(EventTime);

    CREATE NONCLUSTERED INDEX IX_DeadlockEvents_ServerTime
    ON dbo.DeadlockEvents(ServerID, EventTime)
    INCLUDE (DatabaseName, VictimSessionID, ObjectName);

    PRINT '  ✓ DeadlockEvents created (partitioned)';
END
ELSE
    PRINT '  - DeadlockEvents already exists';
GO

-- =====================================================
-- FEATURE 3: Wait Statistics Deep Dive
-- =====================================================

PRINT '';
PRINT 'Creating Wait Statistics tables...';

-- Table: WaitStatsSnapshot
-- Stores cumulative wait stats snapshots for delta calculation
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.WaitStatsSnapshot') AND type = 'U')
BEGIN
    CREATE TABLE dbo.WaitStatsSnapshot
    (
        SnapshotID          BIGINT          IDENTITY(1,1)   NOT NULL,
        ServerID            INT                             NOT NULL,
        SnapshotTime        DATETIME2                       NOT NULL,
        WaitType            NVARCHAR(60)                    NOT NULL,
        WaitingTasksCount   BIGINT                          NOT NULL,
        WaitTimeMs          BIGINT                          NOT NULL,
        MaxWaitTimeMs       BIGINT                          NOT NULL,
        SignalWaitTimeMs    BIGINT                          NOT NULL,
        ResourceWaitTimeMs  BIGINT                          NOT NULL,    -- Calculated: WaitTimeMs - SignalWaitTimeMs

        CONSTRAINT PK_WaitStatsSnapshot PRIMARY KEY CLUSTERED (SnapshotTime, ServerID, WaitType),
        CONSTRAINT FK_WaitStatsSnapshot_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    )
    ON PS_MonitoringByMonth(SnapshotTime);

    CREATE NONCLUSTERED INDEX IX_WaitStatsSnapshot_ServerType
    ON dbo.WaitStatsSnapshot(ServerID, WaitType, SnapshotTime)
    INCLUDE (WaitingTasksCount, WaitTimeMs, SignalWaitTimeMs);

    PRINT '  ✓ WaitStatsSnapshot created (partitioned)';
END
ELSE
    PRINT '  - WaitStatsSnapshot already exists';
GO

-- Table: WaitStatsBaseline
-- Stores calculated baselines for wait stats (hourly/daily/weekly)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.WaitStatsBaseline') AND type = 'U')
BEGIN
    CREATE TABLE dbo.WaitStatsBaseline
    (
        BaselineID          BIGINT          IDENTITY(1,1)   NOT NULL,
        ServerID            INT                             NOT NULL,
        WaitType            NVARCHAR(60)                    NOT NULL,
        BaselineType        NVARCHAR(20)                    NOT NULL,    -- Hourly, Daily, Weekly
        BaselineDate        DATE                            NOT NULL,
        BaselineHour        TINYINT                         NULL,        -- 0-23 for hourly
        AvgWaitTimeMs       DECIMAL(18,4)                   NOT NULL,
        MaxWaitTimeMs       BIGINT                          NOT NULL,
        AvgWaitingTasks     DECIMAL(18,4)                   NOT NULL,
        StdDevWaitTimeMs    DECIMAL(18,4)                   NULL,
        CalculatedTime      DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),

        CONSTRAINT PK_WaitStatsBaseline PRIMARY KEY CLUSTERED (BaselineID),
        CONSTRAINT FK_WaitStatsBaseline_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
        CONSTRAINT UQ_WaitStatsBaseline UNIQUE (ServerID, WaitType, BaselineType, BaselineDate, BaselineHour)
    );

    CREATE NONCLUSTERED INDEX IX_WaitStatsBaseline_ServerTypeDate
    ON dbo.WaitStatsBaseline(ServerID, WaitType, BaselineType, BaselineDate)
    INCLUDE (AvgWaitTimeMs, MaxWaitTimeMs);

    PRINT '  ✓ WaitStatsBaseline created';
END
ELSE
    PRINT '  - WaitStatsBaseline already exists';
GO

-- =====================================================
-- FEATURE 4: Index Optimization
-- =====================================================

PRINT '';
PRINT 'Creating Index Optimization tables...';

-- Table: IndexFragmentation
-- Stores index fragmentation snapshots
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.IndexFragmentation') AND type = 'U')
BEGIN
    CREATE TABLE dbo.IndexFragmentation
    (
        FragmentationID     BIGINT          IDENTITY(1,1)   NOT NULL,
        ServerID            INT                             NOT NULL,
        DatabaseName        NVARCHAR(128)                   NOT NULL,
        SchemaName          NVARCHAR(128)                   NOT NULL,
        TableName           NVARCHAR(128)                   NOT NULL,
        IndexName           NVARCHAR(128)                   NULL,
        IndexID             INT                             NOT NULL,
        IndexType           NVARCHAR(60)                    NOT NULL,    -- CLUSTERED, NONCLUSTERED, etc.
        PartitionNumber     INT                             NOT NULL,
        FragmentationPercent DECIMAL(5,2)                   NOT NULL,
        PageCount           BIGINT                          NOT NULL,
        AvgPageSpaceUsedPercent DECIMAL(5,2)                NULL,
        RecordCount         BIGINT                          NULL,
        ScanDate            DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),

        CONSTRAINT PK_IndexFragmentation PRIMARY KEY CLUSTERED (ScanDate, FragmentationID),
        CONSTRAINT FK_IndexFragmentation_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    )
    ON PS_MonitoringByMonth(ScanDate);

    CREATE NONCLUSTERED INDEX IX_IndexFragmentation_ServerDB
    ON dbo.IndexFragmentation(ServerID, DatabaseName, ScanDate)
    INCLUDE (SchemaName, TableName, IndexName, FragmentationPercent);

    PRINT '  ✓ IndexFragmentation created (partitioned)';
END
ELSE
    PRINT '  - IndexFragmentation already exists';
GO

-- Table: MissingIndexRecommendations
-- Stores SQL Server's missing index recommendations
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.MissingIndexRecommendations') AND type = 'U')
BEGIN
    CREATE TABLE dbo.MissingIndexRecommendations
    (
        RecommendationID    BIGINT          IDENTITY(1,1)   NOT NULL,
        ServerID            INT                             NOT NULL,
        DatabaseName        NVARCHAR(128)                   NOT NULL,
        SchemaName          NVARCHAR(128)                   NOT NULL,
        TableName           NVARCHAR(128)                   NOT NULL,
        EqualityColumns     NVARCHAR(4000)                  NULL,
        InequalityColumns   NVARCHAR(4000)                  NULL,
        IncludedColumns     NVARCHAR(4000)                  NULL,
        UniqueCompiles      BIGINT                          NOT NULL,
        UserSeeks           BIGINT                          NOT NULL,
        UserScans           BIGINT                          NOT NULL,
        AvgTotalUserCost    DECIMAL(18,4)                   NOT NULL,
        AvgUserImpactPercent DECIMAL(5,2)                   NOT NULL,
        ImpactScore         DECIMAL(18,4)                   NOT NULL,    -- Calculated: (UserSeeks + UserScans) * AvgTotalUserCost * AvgUserImpactPercent
        CreateIndexStatement NVARCHAR(MAX)                  NULL,
        CaptureDate         DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),
        IsImplemented       BIT                             NOT NULL DEFAULT 0,
        ImplementedDate     DATETIME2                       NULL,

        CONSTRAINT PK_MissingIndexRecommendations PRIMARY KEY CLUSTERED (CaptureDate, RecommendationID),
        CONSTRAINT FK_MissingIndexRecommendations_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    )
    ON PS_MonitoringByMonth(CaptureDate);

    CREATE NONCLUSTERED INDEX IX_MissingIndexRecommendations_Impact
    ON dbo.MissingIndexRecommendations(ServerID, DatabaseName, ImpactScore DESC, IsImplemented)
    INCLUDE (SchemaName, TableName, AvgUserImpactPercent);

    PRINT '  ✓ MissingIndexRecommendations created (partitioned)';
END
ELSE
    PRINT '  - MissingIndexRecommendations already exists';
GO

-- Table: UnusedIndexes
-- Tracks indexes with no usage or low usage
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.UnusedIndexes') AND type = 'U')
BEGIN
    CREATE TABLE dbo.UnusedIndexes
    (
        UnusedIndexID       BIGINT          IDENTITY(1,1)   NOT NULL,
        ServerID            INT                             NOT NULL,
        DatabaseName        NVARCHAR(128)                   NOT NULL,
        SchemaName          NVARCHAR(128)                   NOT NULL,
        TableName           NVARCHAR(128)                   NOT NULL,
        IndexName           NVARCHAR(128)                   NOT NULL,
        IndexID             INT                             NOT NULL,
        IndexType           NVARCHAR(60)                    NOT NULL,
        UserSeeks           BIGINT                          NOT NULL,
        UserScans           BIGINT                          NOT NULL,
        UserLookups         BIGINT                          NOT NULL,
        UserUpdates         BIGINT                          NOT NULL,
        TotalReads          BIGINT                          NOT NULL,    -- Seeks + Scans + Lookups
        ReadWriteRatio      DECIMAL(18,4)                   NULL,        -- TotalReads / UserUpdates
        IndexSizeMB         DECIMAL(18,2)                   NOT NULL,
        IndexRowCount       BIGINT                          NULL,
        CaptureDate         DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),
        IsCandidate         BIT                             NOT NULL DEFAULT 0,  -- Candidate for removal
        DropIndexStatement  NVARCHAR(MAX)                   NULL,

        CONSTRAINT PK_UnusedIndexes PRIMARY KEY CLUSTERED (CaptureDate, UnusedIndexID),
        CONSTRAINT FK_UnusedIndexes_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    )
    ON PS_MonitoringByMonth(CaptureDate);

    CREATE NONCLUSTERED INDEX IX_UnusedIndexes_Candidates
    ON dbo.UnusedIndexes(ServerID, DatabaseName, IsCandidate, IndexSizeMB DESC)
    INCLUDE (SchemaName, TableName, IndexName, UserUpdates);

    PRINT '  ✓ UnusedIndexes created (partitioned)';
END
ELSE
    PRINT '  - UnusedIndexes already exists';
GO

-- =====================================================
-- Verification
-- =====================================================

PRINT '';
PRINT '========================================';
PRINT 'Query Analysis Tables Created!';
PRINT '========================================';
PRINT '';
PRINT 'Feature 1: Query Store Integration';
PRINT '  - QueryStoreQueries (query text and metadata)';
PRINT '  - QueryStoreRuntimeStats (execution statistics)';
PRINT '  - QueryStorePlans (execution plans)';
PRINT '';
PRINT 'Feature 2: Blocking and Deadlock Detection';
PRINT '  - BlockingEvents (real-time blocking chains)';
PRINT '  - DeadlockEvents (deadlock graphs and victims)';
PRINT '';
PRINT 'Feature 3: Wait Statistics Deep Dive';
PRINT '  - WaitStatsSnapshot (cumulative snapshots)';
PRINT '  - WaitStatsBaseline (hourly/daily/weekly baselines)';
PRINT '';
PRINT 'Feature 4: Index Optimization';
PRINT '  - IndexFragmentation (fragmentation tracking)';
PRINT '  - MissingIndexRecommendations (missing indexes)';
PRINT '  - UnusedIndexes (low-usage index candidates)';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Create collection procedures (32-create-query-analysis-procedures.sql)';
PRINT '  2. Update SQL Agent jobs to collect new metrics';
PRINT '  3. Create Grafana dashboards for visualization';
PRINT '========================================';
GO

-- Show created tables
SELECT
    t.name AS TableName,
    SUM(p.rows) AS ApproxRowCount,
    COUNT(DISTINCT c.column_id) AS ColumnCount,
    COUNT(DISTINCT i.index_id) AS IndexCount
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
LEFT JOIN sys.columns c ON t.object_id = c.object_id
LEFT JOIN sys.indexes i ON t.object_id = i.object_id
WHERE t.name IN (
    'QueryStoreQueries', 'QueryStoreRuntimeStats', 'QueryStorePlans',
    'BlockingEvents', 'DeadlockEvents',
    'WaitStatsSnapshot', 'WaitStatsBaseline',
    'IndexFragmentation', 'MissingIndexRecommendations', 'UnusedIndexes'
)
GROUP BY t.name
ORDER BY t.name;
GO
