-- =====================================================
-- Script: 06-create-drilldown-tables.sql
-- Description: Creates drill-down tables for hierarchical analysis
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- Purpose: Enable drill-down from Server → Database → Procedure/Query
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- 1. DatabaseMetrics - Database-level performance
-- =====================================================

IF OBJECT_ID('dbo.DatabaseMetrics', 'U') IS NOT NULL
    DROP TABLE dbo.DatabaseMetrics;
GO

CREATE TABLE dbo.DatabaseMetrics (
    MetricID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    CollectionTime DATETIME2(7) NOT NULL,
    MetricCategory VARCHAR(50) NOT NULL, -- 'CPU', 'Memory', 'IO', 'Waits', 'Connections'
    MetricName VARCHAR(100) NOT NULL,
    MetricValue DECIMAL(18,4) NOT NULL,
    CONSTRAINT PK_DatabaseMetrics PRIMARY KEY CLUSTERED (MetricID),
    CONSTRAINT FK_DatabaseMetrics_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_DatabaseMetrics_Lookup
ON dbo.DatabaseMetrics(ServerID, DatabaseName, CollectionTime)
INCLUDE (MetricCategory, MetricName, MetricValue);
GO

CREATE NONCLUSTERED INDEX IX_DatabaseMetrics_Category
ON dbo.DatabaseMetrics(MetricCategory, CollectionTime)
INCLUDE (ServerID, DatabaseName, MetricValue);
GO

-- =====================================================
-- 2. ProcedureMetrics - Stored Procedure performance
-- =====================================================

IF OBJECT_ID('dbo.ProcedureMetrics', 'U') IS NOT NULL
    DROP TABLE dbo.ProcedureMetrics;
GO

CREATE TABLE dbo.ProcedureMetrics (
    MetricID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    ProcedureName NVARCHAR(128) NOT NULL,
    CollectionTime DATETIME2(7) NOT NULL,
    ExecutionCount BIGINT NOT NULL,
    TotalCPUMs BIGINT NOT NULL,
    AvgCPUMs DECIMAL(18,4) NOT NULL,
    TotalDurationMs BIGINT NOT NULL,
    AvgDurationMs DECIMAL(18,4) NOT NULL,
    TotalLogicalReads BIGINT NOT NULL,
    AvgLogicalReads DECIMAL(18,4) NOT NULL,
    TotalPhysicalReads BIGINT NOT NULL,
    LastExecutionTime DATETIME2(7) NULL,
    CONSTRAINT PK_ProcedureMetrics PRIMARY KEY CLUSTERED (MetricID),
    CONSTRAINT FK_ProcedureMetrics_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_ProcedureMetrics_Lookup
ON dbo.ProcedureMetrics(ServerID, DatabaseName, ProcedureName, CollectionTime);
GO

CREATE NONCLUSTERED INDEX IX_ProcedureMetrics_CPU
ON dbo.ProcedureMetrics(CollectionTime, AvgCPUMs DESC)
INCLUDE (ServerID, DatabaseName, ProcedureName, ExecutionCount);
GO

-- =====================================================
-- 3. QueryMetrics - Individual query performance
-- =====================================================

IF OBJECT_ID('dbo.QueryMetrics', 'U') IS NOT NULL
    DROP TABLE dbo.QueryMetrics;
GO

CREATE TABLE dbo.QueryMetrics (
    MetricID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NULL,
    QueryHash BINARY(8) NOT NULL, -- Unique identifier for query
    QueryPlanHash BINARY(8) NULL,
    CollectionTime DATETIME2(7) NOT NULL,
    QueryText NVARCHAR(MAX) NULL,
    ExecutionCount BIGINT NOT NULL,
    TotalCPUMs BIGINT NOT NULL,
    AvgCPUMs DECIMAL(18,4) NOT NULL,
    MaxCPUMs BIGINT NOT NULL,
    TotalDurationMs BIGINT NOT NULL,
    AvgDurationMs DECIMAL(18,4) NOT NULL,
    MaxDurationMs BIGINT NOT NULL,
    TotalLogicalReads BIGINT NOT NULL,
    AvgLogicalReads DECIMAL(18,4) NOT NULL,
    TotalPhysicalReads BIGINT NOT NULL,
    TotalWrites BIGINT NOT NULL,
    LastExecutionTime DATETIME2(7) NULL,
    CONSTRAINT PK_QueryMetrics PRIMARY KEY CLUSTERED (MetricID),
    CONSTRAINT FK_QueryMetrics_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_QueryMetrics_QueryHash
ON dbo.QueryMetrics(QueryHash, CollectionTime)
INCLUDE (ServerID, DatabaseName, AvgCPUMs, AvgDurationMs);
GO

CREATE NONCLUSTERED INDEX IX_QueryMetrics_CPU
ON dbo.QueryMetrics(CollectionTime, AvgCPUMs DESC)
INCLUDE (ServerID, DatabaseName, QueryHash, ExecutionCount);
GO

-- =====================================================
-- 4. WaitEventsByDatabase - Wait stats per database
-- =====================================================

IF OBJECT_ID('dbo.WaitEventsByDatabase', 'U') IS NOT NULL
    DROP TABLE dbo.WaitEventsByDatabase;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE dbo.WaitEventsByDatabase (
    MetricID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    WaitType NVARCHAR(60) NOT NULL,
    CollectionTime DATETIME2(7) NOT NULL,
    WaitingTasksCount BIGINT NOT NULL,
    WaitTimeMs BIGINT NOT NULL,
    MaxWaitTimeMs BIGINT NOT NULL,
    SignalWaitTimeMs BIGINT NOT NULL,
    ResourceWaitTimeMs AS (WaitTimeMs - SignalWaitTimeMs) PERSISTED,
    CONSTRAINT PK_WaitEventsByDatabase PRIMARY KEY CLUSTERED (MetricID),
    CONSTRAINT FK_WaitEventsByDatabase_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_WaitEventsByDatabase_Lookup
ON dbo.WaitEventsByDatabase(ServerID, DatabaseName, CollectionTime, WaitType);
GO

-- =====================================================
-- 5. ConnectionsByDatabase - Connections per database
-- =====================================================

IF OBJECT_ID('dbo.ConnectionsByDatabase', 'U') IS NOT NULL
    DROP TABLE dbo.ConnectionsByDatabase;
GO

CREATE TABLE dbo.ConnectionsByDatabase (
    MetricID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    CollectionTime DATETIME2(7) NOT NULL,
    TotalConnections INT NOT NULL,
    ActiveConnections INT NOT NULL,
    SleepingConnections INT NOT NULL,
    BlockedConnections INT NOT NULL,
    CONSTRAINT PK_ConnectionsByDatabase PRIMARY KEY CLUSTERED (MetricID),
    CONSTRAINT FK_ConnectionsByDatabase_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_ConnectionsByDatabase_Lookup
ON dbo.ConnectionsByDatabase(ServerID, DatabaseName, CollectionTime);
GO

PRINT '';
PRINT '========================================================';
PRINT 'Drill-Down Tables Created Successfully';
PRINT '========================================================';
PRINT 'Tables created:';
PRINT '  1. DatabaseMetrics - Database-level performance metrics';
PRINT '  2. ProcedureMetrics - Stored procedure performance';
PRINT '  3. QueryMetrics - Individual query performance';
PRINT '  4. WaitEventsByDatabase - Wait stats per database';
PRINT '  5. ConnectionsByDatabase - Connections per database';
PRINT '';
PRINT 'Hierarchy: Server → Database → Procedure/Query → Metric';
PRINT '========================================================';
GO
