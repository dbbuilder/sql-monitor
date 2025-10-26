-- =====================================================
-- Script: 10-create-extended-events-tables.sql
-- Description: Tables for Extended Events (blocking, deadlocks, long queries)
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- 1. BlockingEvents - Track blocking chains
-- =====================================================

IF OBJECT_ID('dbo.BlockingEvents', 'U') IS NOT NULL
    DROP TABLE dbo.BlockingEvents;
GO

CREATE TABLE dbo.BlockingEvents (
    EventID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    EventTime DATETIME2(7) NOT NULL,
    DatabaseName NVARCHAR(128) NULL,
    BlockedSessionID INT NOT NULL,
    BlockingSessionID INT NOT NULL,
    WaitType NVARCHAR(60) NULL,
    WaitDurationMs BIGINT NOT NULL,
    BlockedQuery NVARCHAR(MAX) NULL,
    BlockingQuery NVARCHAR(MAX) NULL,
    BlockedObjectName NVARCHAR(256) NULL,
    BlockingObjectName NVARCHAR(256) NULL,
    CONSTRAINT PK_BlockingEvents PRIMARY KEY CLUSTERED (EventID),
    CONSTRAINT FK_BlockingEvents_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_BlockingEvents_Time
ON dbo.BlockingEvents(ServerID, EventTime DESC)
INCLUDE (DatabaseName, BlockedSessionID, BlockingSessionID, WaitDurationMs);
GO

-- =====================================================
-- 2. DeadlockEvents - Capture deadlock details
-- =====================================================

IF OBJECT_ID('dbo.DeadlockEvents', 'U') IS NOT NULL
    DROP TABLE dbo.DeadlockEvents;
GO

CREATE TABLE dbo.DeadlockEvents (
    DeadlockID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    EventTime DATETIME2(7) NOT NULL,
    DatabaseName NVARCHAR(128) NULL,
    DeadlockGraph XML NULL,
    VictimSessionID INT NULL,
    VictimQuery NVARCHAR(MAX) NULL,
    SurvivorSessionID INT NULL,
    SurvivorQuery NVARCHAR(MAX) NULL,
    CONSTRAINT PK_DeadlockEvents PRIMARY KEY CLUSTERED (DeadlockID),
    CONSTRAINT FK_DeadlockEvents_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_DeadlockEvents_Time
ON dbo.DeadlockEvents(ServerID, EventTime DESC)
INCLUDE (DatabaseName, VictimSessionID);
GO

-- =====================================================
-- 3. LongRunningQueries - Queries exceeding threshold
-- =====================================================

IF OBJECT_ID('dbo.LongRunningQueries', 'U') IS NOT NULL
    DROP TABLE dbo.LongRunningQueries;
GO

CREATE TABLE dbo.LongRunningQueries (
    EventID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    EventTime DATETIME2(7) NOT NULL,
    DatabaseName NVARCHAR(128) NULL,
    SessionID INT NOT NULL,
    QueryText NVARCHAR(MAX) NULL,
    DurationMs BIGINT NOT NULL,
    CPUMs BIGINT NOT NULL,
    LogicalReads BIGINT NOT NULL,
    PhysicalReads BIGINT NOT NULL,
    WaitType NVARCHAR(60) NULL,
    CONSTRAINT PK_LongRunningQueries PRIMARY KEY CLUSTERED (EventID),
    CONSTRAINT FK_LongRunningQueries_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_LongRunningQueries_Time
ON dbo.LongRunningQueries(ServerID, EventTime DESC)
INCLUDE (DatabaseName, DurationMs);
GO

-- =====================================================
-- 4. QueryStoreData - Query Store analysis
-- =====================================================

IF OBJECT_ID('dbo.QueryStoreData', 'U') IS NOT NULL
    DROP TABLE dbo.QueryStoreData;
GO

CREATE TABLE dbo.QueryStoreData (
    QueryStoreID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    CollectionTime DATETIME2(7) NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    QueryID BIGINT NOT NULL,
    QueryHash BINARY(8) NULL,
    QueryText NVARCHAR(MAX) NULL,
    ObjectName NVARCHAR(256) NULL,
    ExecutionCount BIGINT NOT NULL,
    AvgDurationMs DECIMAL(18,4) NOT NULL,
    LastDurationMs DECIMAL(18,4) NOT NULL,
    MinDurationMs DECIMAL(18,4) NOT NULL,
    MaxDurationMs DECIMAL(18,4) NOT NULL,
    AvgCPUMs DECIMAL(18,4) NOT NULL,
    AvgLogicalReads DECIMAL(18,4) NOT NULL,
    PlanRegression BIT DEFAULT 0,
    CONSTRAINT PK_QueryStoreData PRIMARY KEY CLUSTERED (QueryStoreID),
    CONSTRAINT FK_QueryStoreData_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_QueryStoreData_Lookup
ON dbo.QueryStoreData(ServerID, DatabaseName, CollectionTime DESC)
INCLUDE (QueryID, AvgDurationMs);
GO

-- =====================================================
-- 5. IndexAnalysis - Missing and fragmented indexes
-- =====================================================

IF OBJECT_ID('dbo.IndexAnalysis', 'U') IS NOT NULL
    DROP TABLE dbo.IndexAnalysis;
GO

CREATE TABLE dbo.IndexAnalysis (
    AnalysisID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    CollectionTime DATETIME2(7) NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    IndexName NVARCHAR(128) NULL,
    AnalysisType VARCHAR(20) NOT NULL, -- 'Missing', 'Fragmented', 'Unused'
    FragmentationPercent DECIMAL(5,2) NULL,
    PageCount BIGINT NULL,
    AvgFragmentationPercent DECIMAL(5,2) NULL,
    ImprovementMeasure DECIMAL(18,4) NULL,
    IncludeColumns NVARCHAR(500) NULL,
    EqualityColumns NVARCHAR(500) NULL,
    InequalityColumns NVARCHAR(500) NULL,
    Recommendation NVARCHAR(MAX) NULL,
    CONSTRAINT PK_IndexAnalysis PRIMARY KEY CLUSTERED (AnalysisID),
    CONSTRAINT FK_IndexAnalysis_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_IndexAnalysis_Lookup
ON dbo.IndexAnalysis(ServerID, DatabaseName, CollectionTime DESC, AnalysisType)
INCLUDE (SchemaName, TableName, FragmentationPercent);
GO

-- =====================================================
-- 6. ObjectCode - Cached object definitions for preview
-- =====================================================

IF OBJECT_ID('dbo.ObjectCode', 'U') IS NOT NULL
    DROP TABLE dbo.ObjectCode;
GO

CREATE TABLE dbo.ObjectCode (
    CodeID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    ObjectName NVARCHAR(128) NOT NULL,
    ObjectType VARCHAR(20) NOT NULL, -- 'Procedure', 'Function', 'View', 'Trigger'
    Definition NVARCHAR(MAX) NULL,
    LastUpdated DATETIME2(7) NOT NULL,
    CONSTRAINT PK_ObjectCode PRIMARY KEY CLUSTERED (CodeID),
    CONSTRAINT FK_ObjectCode_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX IX_ObjectCode_Lookup
ON dbo.ObjectCode(ServerID, DatabaseName, SchemaName, ObjectName, ObjectType);
GO

PRINT '';
PRINT '========================================================';
PRINT 'Extended Events & Analysis Tables Created Successfully';
PRINT '========================================================';
PRINT 'Tables created:';
PRINT '  1. BlockingEvents - Blocking chain tracking';
PRINT '  2. DeadlockEvents - Deadlock capture';
PRINT '  3. LongRunningQueries - Long query tracking';
PRINT '  4. QueryStoreData - Query Store analysis';
PRINT '  5. IndexAnalysis - Missing/fragmented indexes';
PRINT '  6. ObjectCode - Object definitions for preview';
PRINT '========================================================';
GO
