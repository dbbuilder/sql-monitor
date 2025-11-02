-- =====================================================
-- Phase 3 - Feature #2: Query Performance Advisor
-- Database Tables for Query Optimization Recommendations
-- =====================================================
-- File: 50-create-query-advisor-tables.sql
-- Purpose: Create tables for query performance recommendations and plan regressions
-- Dependencies: 02-create-tables.sql (Servers table)
-- =====================================================

USE MonitoringDB;
GO

PRINT '======================================'
PRINT 'Creating Query Performance Advisor Tables';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Table: QueryPerformanceRecommendations
-- Purpose: Store AI-powered query optimization recommendations
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'QueryPerformanceRecommendations')
BEGIN
    CREATE TABLE dbo.QueryPerformanceRecommendations (
        RecommendationID BIGINT IDENTITY(1,1) NOT NULL,
        ServerID INT NOT NULL,
        DatabaseName NVARCHAR(128) NOT NULL,

        -- Query identification
        QueryHash BINARY(8) NOT NULL,
        QueryText NVARCHAR(MAX) NOT NULL,

        -- Performance metrics (from Query Store or DMVs)
        AvgDurationMs DECIMAL(18,2) NOT NULL,
        AvgCPUTimeMs DECIMAL(18,2) NOT NULL,
        AvgLogicalReads BIGINT NOT NULL,
        TotalExecutionCount BIGINT NOT NULL,

        -- Recommendation details
        RecommendationType VARCHAR(50) NOT NULL, -- 'MissingIndex', 'StatisticsUpdate', 'PlanRegression', 'Rewrite', 'Parameterization'
        RecommendationSeverity VARCHAR(20) NOT NULL, -- 'Critical', 'High', 'Medium', 'Low'
        RecommendationText NVARCHAR(MAX) NOT NULL,
        EstimatedImprovementPercent DECIMAL(5,2) NULL,

        -- Implementation
        ImplementationScript NVARCHAR(MAX) NULL, -- SQL to implement the recommendation
        IsImplemented BIT NOT NULL DEFAULT 0,
        ImplementedDate DATETIME2 NULL,
        ImplementedBy NVARCHAR(128) NULL,

        DetectionTime DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

        CONSTRAINT PK_QueryPerformanceRecommendations PRIMARY KEY CLUSTERED (RecommendationID),
        CONSTRAINT FK_QueryPerformanceRecommendations_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
        CONSTRAINT CHK_QueryPerformanceRecommendations_Severity CHECK (RecommendationSeverity IN ('Critical', 'High', 'Medium', 'Low')),
        CONSTRAINT CHK_QueryPerformanceRecommendations_Type CHECK (RecommendationType IN ('MissingIndex', 'StatisticsUpdate', 'PlanRegression', 'Rewrite', 'Parameterization', 'HighLogicalReads', 'HighCPU'))
    );

    -- Index for querying recommendations by server and severity
    CREATE NONCLUSTERED INDEX IX_QueryPerformanceRecommendations_ServerID_Severity
    ON dbo.QueryPerformanceRecommendations (ServerID, RecommendationSeverity, DetectionTime DESC)
    INCLUDE (RecommendationType, EstimatedImprovementPercent, IsImplemented);

    -- Index for finding recent recommendations for a specific query
    CREATE NONCLUSTERED INDEX IX_QueryPerformanceRecommendations_QueryHash
    ON dbo.QueryPerformanceRecommendations (ServerID, QueryHash, DetectionTime DESC);

    PRINT '✅ Created table: QueryPerformanceRecommendations';
END
ELSE
BEGIN
    PRINT '⏭️  Table already exists: QueryPerformanceRecommendations';
END;
PRINT '';

-- =====================================================
-- Table: QueryPlanRegressions
-- Purpose: Track when execution plans change and performance degrades
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'QueryPlanRegressions')
BEGIN
    CREATE TABLE dbo.QueryPlanRegressions (
        RegressionID BIGINT IDENTITY(1,1) NOT NULL,
        ServerID INT NOT NULL,
        DatabaseName NVARCHAR(128) NOT NULL,

        QueryHash BINARY(8) NOT NULL,
        QueryText NVARCHAR(MAX) NOT NULL,

        -- Old plan (good performance)
        OldPlanHandle VARBINARY(64) NULL,
        OldAvgDurationMs DECIMAL(18,2) NOT NULL,
        OldAvgCPUTimeMs DECIMAL(18,2) NOT NULL,
        OldAvgLogicalReads BIGINT NULL,
        OldPlanCreatedTime DATETIME2 NULL,

        -- New plan (degraded performance)
        NewPlanHandle VARBINARY(64) NULL,
        NewAvgDurationMs DECIMAL(18,2) NOT NULL,
        NewAvgCPUTimeMs DECIMAL(18,2) NOT NULL,
        NewAvgLogicalReads BIGINT NULL,
        NewPlanCreatedTime DATETIME2 NULL,

        -- Regression metrics
        DurationIncreasePct DECIMAL(5,2) NOT NULL,
        CPUIncreasePct DECIMAL(5,2) NOT NULL,
        LogicalReadsIncreasePct DECIMAL(5,2) NULL,

        DetectionTime DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        IsResolved BIT NOT NULL DEFAULT 0,
        ResolvedDate DATETIME2 NULL,
        ResolutionNotes NVARCHAR(MAX) NULL,

        CONSTRAINT PK_QueryPlanRegressions PRIMARY KEY CLUSTERED (RegressionID),
        CONSTRAINT FK_QueryPlanRegressions_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    );

    -- Index for querying regressions by server and detection time
    CREATE NONCLUSTERED INDEX IX_QueryPlanRegressions_ServerID_DetectionTime
    ON dbo.QueryPlanRegressions (ServerID, DetectionTime DESC)
    INCLUDE (QueryHash, DurationIncreasePct, IsResolved);

    -- Index for finding regressions for a specific query
    CREATE NONCLUSTERED INDEX IX_QueryPlanRegressions_QueryHash
    ON dbo.QueryPlanRegressions (ServerID, QueryHash, DetectionTime DESC);

    PRINT '✅ Created table: QueryPlanRegressions';
END
ELSE
BEGIN
    PRINT '⏭️  Table already exists: QueryPlanRegressions';
END;
PRINT '';

-- =====================================================
-- Table: QueryOptimizationHistory
-- Purpose: Track before/after performance when recommendations are implemented
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'QueryOptimizationHistory')
BEGIN
    CREATE TABLE dbo.QueryOptimizationHistory (
        OptimizationID BIGINT IDENTITY(1,1) NOT NULL,
        RecommendationID BIGINT NOT NULL,
        ServerID INT NOT NULL,
        DatabaseName NVARCHAR(128) NOT NULL,
        QueryHash BINARY(8) NOT NULL,

        -- Before metrics
        BeforeAvgDurationMs DECIMAL(18,2) NOT NULL,
        BeforeAvgCPUTimeMs DECIMAL(18,2) NOT NULL,
        BeforeAvgLogicalReads BIGINT NOT NULL,
        BeforeMeasurementTime DATETIME2 NOT NULL,

        -- After metrics
        AfterAvgDurationMs DECIMAL(18,2) NULL,
        AfterAvgCPUTimeMs DECIMAL(18,2) NULL,
        AfterAvgLogicalReads BIGINT NULL,
        AfterMeasurementTime DATETIME2 NULL,

        -- Actual improvement
        ActualDurationImprovementPct DECIMAL(5,2) NULL,
        ActualCPUImprovementPct DECIMAL(5,2) NULL,
        ActualLogicalReadsImprovementPct DECIMAL(5,2) NULL,

        -- Estimated vs. actual comparison
        EstimatedImprovementPct DECIMAL(5,2) NULL,
        AccuracyScore DECIMAL(5,2) NULL, -- How close was our estimate?

        CONSTRAINT PK_QueryOptimizationHistory PRIMARY KEY CLUSTERED (OptimizationID),
        CONSTRAINT FK_QueryOptimizationHistory_Recommendations FOREIGN KEY (RecommendationID) REFERENCES dbo.QueryPerformanceRecommendations(RecommendationID),
        CONSTRAINT FK_QueryOptimizationHistory_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    );

    -- Index for querying optimization results by server
    CREATE NONCLUSTERED INDEX IX_QueryOptimizationHistory_ServerID
    ON dbo.QueryOptimizationHistory (ServerID, BeforeMeasurementTime DESC)
    INCLUDE (ActualDurationImprovementPct, EstimatedImprovementPct);

    PRINT '✅ Created table: QueryOptimizationHistory';
END
ELSE
BEGIN
    PRINT '⏭️  Table already exists: QueryOptimizationHistory';
END;
PRINT '';

-- =====================================================
-- Verification
-- =====================================================

PRINT '======================================';
PRINT 'Verification';
PRINT '======================================';
PRINT '';

SELECT
    t.name AS TableName,
    SUM(CASE WHEN i.type_desc = 'CLUSTERED' THEN 1 ELSE 0 END) AS ClusteredIndexes,
    SUM(CASE WHEN i.type_desc = 'NONCLUSTERED' THEN 1 ELSE 0 END) AS NonClusteredIndexes,
    SUM(CASE WHEN fk.object_id IS NOT NULL THEN 1 ELSE 0 END) AS ForeignKeys
FROM sys.tables t
LEFT JOIN sys.indexes i ON t.object_id = i.object_id
LEFT JOIN sys.foreign_keys fk ON t.object_id = fk.parent_object_id
WHERE t.name IN ('QueryPerformanceRecommendations', 'QueryPlanRegressions', 'QueryOptimizationHistory')
GROUP BY t.name
ORDER BY t.name;

PRINT '';
PRINT '======================================';
PRINT 'Query Performance Advisor Tables Created Successfully';
PRINT '======================================';
PRINT '';
PRINT 'Tables Created:';
PRINT '  1. QueryPerformanceRecommendations - Store optimization recommendations';
PRINT '  2. QueryPlanRegressions - Track execution plan regressions';
PRINT '  3. QueryOptimizationHistory - Track before/after performance';
PRINT '';
PRINT 'Next Steps:';
PRINT '  1. Create stored procedures (51-create-query-advisor-procedures.sql)';
PRINT '  2. Create SQL Agent job for automated analysis';
PRINT '  3. Create Grafana dashboard';
PRINT '';

GO
