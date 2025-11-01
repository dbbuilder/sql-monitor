-- =====================================================
-- Phase 3 - Feature #1: SQL Server Health Score
-- Tables for health scoring system
-- =====================================================
-- File: 40-create-health-score-tables.sql
-- Purpose: Create tables to track server health scores over time
-- Dependencies: 02-create-tables.sql (Servers table)
-- =====================================================

USE MonitoringDB;
GO

PRINT '======================================';
PRINT 'Creating Health Score Tables';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Table: dbo.ServerHealthScore
-- Purpose: Store calculated health scores for each server
-- Frequency: Calculated every 15 minutes
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'ServerHealthScore')
BEGIN
    CREATE TABLE dbo.ServerHealthScore (
        HealthScoreID BIGINT IDENTITY(1,1) NOT NULL,
        ServerID INT NOT NULL,
        CalculationTime DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

        -- Overall health score (0-100, weighted average of components)
        OverallHealthScore DECIMAL(5,2) NOT NULL,

        -- Component scores (0-100 each)
        CPUHealthScore DECIMAL(5,2) NOT NULL,
        MemoryHealthScore DECIMAL(5,2) NOT NULL,
        DiskIOHealthScore DECIMAL(5,2) NOT NULL,
        WaitStatsHealthScore DECIMAL(5,2) NOT NULL,
        BlockingHealthScore DECIMAL(5,2) NOT NULL,
        IndexHealthScore DECIMAL(5,2) NOT NULL,
        QueryPerformanceHealthScore DECIMAL(5,2) NOT NULL,

        -- Issue summary counts
        CriticalIssueCount INT NOT NULL DEFAULT 0,
        WarningIssueCount INT NOT NULL DEFAULT 0,

        -- Top issue (worst component)
        TopIssueDescription NVARCHAR(500) NULL,
        TopIssueSeverity VARCHAR(20) NULL, -- 'Critical', 'Warning', 'Info'

        CONSTRAINT PK_ServerHealthScore PRIMARY KEY CLUSTERED (HealthScoreID),
        CONSTRAINT FK_ServerHealthScore_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
        CONSTRAINT CK_ServerHealthScore_OverallScore CHECK (OverallHealthScore >= 0 AND OverallHealthScore <= 100),
        CONSTRAINT CK_ServerHealthScore_CPUScore CHECK (CPUHealthScore >= 0 AND CPUHealthScore <= 100),
        CONSTRAINT CK_ServerHealthScore_MemoryScore CHECK (MemoryHealthScore >= 0 AND MemoryHealthScore <= 100),
        CONSTRAINT CK_ServerHealthScore_DiskIOScore CHECK (DiskIOHealthScore >= 0 AND DiskIOHealthScore <= 100),
        CONSTRAINT CK_ServerHealthScore_WaitStatsScore CHECK (WaitStatsHealthScore >= 0 AND WaitStatsHealthScore <= 100),
        CONSTRAINT CK_ServerHealthScore_BlockingScore CHECK (BlockingHealthScore >= 0 AND BlockingHealthScore <= 100),
        CONSTRAINT CK_ServerHealthScore_IndexScore CHECK (IndexHealthScore >= 0 AND IndexHealthScore <= 100),
        CONSTRAINT CK_ServerHealthScore_QueryScore CHECK (QueryPerformanceHealthScore >= 0 AND QueryPerformanceHealthScore <= 100)
    );

    -- Index for querying health scores by server and time
    CREATE NONCLUSTERED INDEX IX_ServerHealthScore_ServerID_CalculationTime
        ON dbo.ServerHealthScore (ServerID, CalculationTime DESC)
        INCLUDE (OverallHealthScore, CriticalIssueCount, WarningIssueCount);

    -- Index for finding latest scores
    CREATE NONCLUSTERED INDEX IX_ServerHealthScore_CalculationTime
        ON dbo.ServerHealthScore (CalculationTime DESC)
        INCLUDE (ServerID, OverallHealthScore, TopIssueDescription);

    PRINT '✅ Created table: dbo.ServerHealthScore';
END
ELSE
BEGIN
    PRINT '⚠️  Table already exists: dbo.ServerHealthScore';
END;
PRINT '';

-- =====================================================
-- Table: dbo.HealthScoreIssues
-- Purpose: Store detailed issues affecting health score
-- Frequency: Calculated every 15 minutes (linked to ServerHealthScore)
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'HealthScoreIssues')
BEGIN
    CREATE TABLE dbo.HealthScoreIssues (
        IssueID BIGINT IDENTITY(1,1) NOT NULL,
        HealthScoreID BIGINT NOT NULL,

        -- Issue classification
        IssueCategory VARCHAR(50) NOT NULL, -- 'CPU', 'Memory', 'DiskIO', 'WaitStats', 'Blocking', 'Index', 'Query'
        IssueSeverity VARCHAR(20) NOT NULL, -- 'Critical', 'Warning', 'Info'
        IssueDescription NVARCHAR(500) NOT NULL,

        -- Impact metrics
        ImpactOnScore DECIMAL(5,2) NOT NULL, -- How much this issue reduces the overall score (0-100)

        -- Recommendations
        RecommendedAction NVARCHAR(1000) NULL,

        CONSTRAINT PK_HealthScoreIssues PRIMARY KEY CLUSTERED (IssueID),
        CONSTRAINT FK_HealthScoreIssues_ServerHealthScore FOREIGN KEY (HealthScoreID) REFERENCES dbo.ServerHealthScore(HealthScoreID),
        CONSTRAINT CK_HealthScoreIssues_Severity CHECK (IssueSeverity IN ('Critical', 'Warning', 'Info')),
        CONSTRAINT CK_HealthScoreIssues_Category CHECK (IssueCategory IN ('CPU', 'Memory', 'DiskIO', 'WaitStats', 'Blocking', 'Index', 'Query')),
        CONSTRAINT CK_HealthScoreIssues_Impact CHECK (ImpactOnScore >= 0 AND ImpactOnScore <= 100)
    );

    -- Index for querying issues by health score
    CREATE NONCLUSTERED INDEX IX_HealthScoreIssues_HealthScoreID
        ON dbo.HealthScoreIssues (HealthScoreID)
        INCLUDE (IssueCategory, IssueSeverity, IssueDescription, ImpactOnScore);

    -- Index for finding critical issues
    CREATE NONCLUSTERED INDEX IX_HealthScoreIssues_Severity
        ON dbo.HealthScoreIssues (IssueSeverity, ImpactOnScore DESC)
        INCLUDE (HealthScoreID, IssueCategory, IssueDescription);

    PRINT '✅ Created table: dbo.HealthScoreIssues';
END
ELSE
BEGIN
    PRINT '⚠️  Table already exists: dbo.HealthScoreIssues';
END;
PRINT '';

-- =====================================================
-- Table: dbo.HealthScoreThresholds
-- Purpose: Store configurable thresholds for health scoring
-- Frequency: Manually configured (defaults provided below)
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'HealthScoreThresholds')
BEGIN
    CREATE TABLE dbo.HealthScoreThresholds (
        ThresholdID INT IDENTITY(1,1) NOT NULL,
        ComponentName VARCHAR(50) NOT NULL, -- 'CPU', 'Memory', 'DiskIO', etc.
        MetricName VARCHAR(100) NOT NULL, -- 'CPUPercent', 'PageLifeExpectancy', etc.

        -- Threshold values
        CriticalThreshold DECIMAL(18,2) NOT NULL, -- Below this = Critical (score < 30)
        WarningThreshold DECIMAL(18,2) NOT NULL, -- Below this = Warning (score < 60)
        GoodThreshold DECIMAL(18,2) NOT NULL, -- Above this = Good (score >= 80)

        -- Weighting for overall score
        ComponentWeight DECIMAL(5,2) NOT NULL DEFAULT 0.10, -- Weight in overall score calculation (should sum to 1.0)

        IsActive BIT NOT NULL DEFAULT 1,

        CONSTRAINT PK_HealthScoreThresholds PRIMARY KEY CLUSTERED (ThresholdID),
        CONSTRAINT UQ_HealthScoreThresholds_Component_Metric UNIQUE (ComponentName, MetricName),
        CONSTRAINT CK_HealthScoreThresholds_Component CHECK (ComponentName IN ('CPU', 'Memory', 'DiskIO', 'WaitStats', 'Blocking', 'Index', 'Query')),
        CONSTRAINT CK_HealthScoreThresholds_Weight CHECK (ComponentWeight >= 0 AND ComponentWeight <= 1.0)
    );

    PRINT '✅ Created table: dbo.HealthScoreThresholds';
END
ELSE
BEGIN
    PRINT '⚠️  Table already exists: dbo.HealthScoreThresholds';
END;
PRINT '';

-- =====================================================
-- Populate default thresholds
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM dbo.HealthScoreThresholds)
BEGIN
    PRINT 'Populating default health score thresholds...';

    INSERT INTO dbo.HealthScoreThresholds (ComponentName, MetricName, CriticalThreshold, WarningThreshold, GoodThreshold, ComponentWeight)
    VALUES
        -- CPU: < 90% = good, 90-95% = warning, > 95% = critical
        ('CPU', 'CPUPercent', 95.0, 90.0, 80.0, 0.20),

        -- Memory: PLE < 100 = critical, PLE < 200 = warning, PLE > 300 = good
        ('Memory', 'PageLifeExpectancy', 100.0, 200.0, 300.0, 0.20),

        -- Disk I/O: Latency > 50ms = critical, > 20ms = warning, < 10ms = good
        ('DiskIO', 'AvgDiskLatencyMs', 50.0, 20.0, 10.0, 0.15),

        -- Wait Stats: > 50% bad waits = critical, > 30% = warning, < 10% = good
        ('WaitStats', 'BadWaitPercentage', 50.0, 30.0, 10.0, 0.15),

        -- Blocking: > 50 events/hour = critical, > 20 = warning, < 5 = good
        ('Blocking', 'BlockingEventsPerHour', 50.0, 20.0, 5.0, 0.10),

        -- Index: > 50% fragmentation = critical, > 30% = warning, < 10% = good
        ('Index', 'AvgFragmentationPercent', 50.0, 30.0, 10.0, 0.10),

        -- Query: Avg duration > 1000ms = critical, > 500ms = warning, < 100ms = good
        ('Query', 'AvgQueryDurationMs', 1000.0, 500.0, 100.0, 0.10);

    PRINT '✅ Inserted ' + CAST(@@ROWCOUNT AS VARCHAR) + ' default threshold configurations';
END
ELSE
BEGIN
    PRINT '⚠️  Default thresholds already exist';
END;
PRINT '';

-- =====================================================
-- Verification
-- =====================================================

PRINT '======================================';
PRINT 'Verification';
PRINT '======================================';

SELECT 'ServerHealthScore' AS TableName, COUNT(*) AS RecordCount FROM dbo.ServerHealthScore
UNION ALL
SELECT 'HealthScoreIssues', COUNT(*) FROM dbo.HealthScoreIssues
UNION ALL
SELECT 'HealthScoreThresholds', COUNT(*) FROM dbo.HealthScoreThresholds;

PRINT '';
PRINT '======================================';
PRINT 'Health Score Tables Created Successfully';
PRINT '======================================';
PRINT '';
PRINT 'Next Steps:';
PRINT '  1. Create stored procedure: usp_CalculateHealthScore';
PRINT '  2. Create stored procedure: usp_GetHealthScoreHistory';
PRINT '  3. Create SQL Agent job to calculate scores every 15 minutes';
PRINT '  4. Create Grafana dashboard to visualize health scores';
PRINT '';

GO
