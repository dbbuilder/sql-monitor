-- =====================================================
-- Phase 3 - Feature #1: SQL Server Health Score
-- Stored Procedures for Health Score Calculation
-- =====================================================
-- File: 41-create-health-score-procedures.sql
-- Purpose: Calculate and retrieve server health scores
-- Dependencies: 40-create-health-score-tables.sql
-- =====================================================

USE MonitoringDB;
GO

SET QUOTED_IDENTIFIER ON;
GO

PRINT '======================================';
PRINT 'Creating Health Score Procedures';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Procedure: usp_CalculateHealthScore
-- Purpose: Calculate comprehensive health score for a server
-- Frequency: Called every 15 minutes by SQL Agent job
-- =====================================================

IF OBJECT_ID('dbo.usp_CalculateHealthScore', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CalculateHealthScore;
GO

CREATE PROCEDURE dbo.usp_CalculateHealthScore
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    -- Declare variables for component scores
    DECLARE @OverallScore DECIMAL(5,2) = 100;
    DECLARE @CPUScore DECIMAL(5,2) = 100;
    DECLARE @MemoryScore DECIMAL(5,2) = 100;
    DECLARE @DiskIOScore DECIMAL(5,2) = 100;
    DECLARE @WaitStatsScore DECIMAL(5,2) = 100;
    DECLARE @BlockingScore DECIMAL(5,2) = 100;
    DECLARE @IndexScore DECIMAL(5,2) = 100;
    DECLARE @QueryScore DECIMAL(5,2) = 100;

    DECLARE @CriticalCount INT = 0;
    DECLARE @WarningCount INT = 0;
    DECLARE @TopIssue NVARCHAR(500);
    DECLARE @TopSeverity VARCHAR(20);

    DECLARE @HealthScoreID BIGINT;

    -- =====================================================
    -- 1. CPU Health Score
    -- Based on average CPU usage in last hour
    -- =====================================================

    DECLARE @AvgCPU DECIMAL(10,2);

    SELECT @AvgCPU = AVG(CAST(MetricValue AS DECIMAL(10,2)))
    FROM dbo.PerformanceMetrics
    WHERE ServerID = @ServerID
      AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
      AND MetricCategory = 'CPU'
      AND MetricName = 'ProcessorTimePercent';

    SET @CPUScore = CASE
        WHEN @AvgCPU IS NULL THEN 100 -- No data
        WHEN @AvgCPU > 95 THEN 10 -- Critical
        WHEN @AvgCPU > 90 THEN 20
        WHEN @AvgCPU > 85 THEN 30
        WHEN @AvgCPU > 80 THEN 40
        WHEN @AvgCPU > 70 THEN 60
        WHEN @AvgCPU > 60 THEN 80
        ELSE 100 - @AvgCPU
    END;

    -- =====================================================
    -- 2. Memory Health Score
    -- Based on Page Life Expectancy (PLE)
    -- =====================================================

    DECLARE @AvgPLE DECIMAL(10,2);

    SELECT @AvgPLE = AVG(CAST(MetricValue AS DECIMAL(10,2)))
    FROM dbo.PerformanceMetrics
    WHERE ServerID = @ServerID
      AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
      AND MetricCategory = 'Memory'
      AND MetricName = 'PageLifeExpectancy';

    SET @MemoryScore = CASE
        WHEN @AvgPLE IS NULL THEN 100 -- No data
        WHEN @AvgPLE < 100 THEN 20 -- Critical
        WHEN @AvgPLE < 200 THEN 50 -- Warning
        WHEN @AvgPLE < 300 THEN 70
        WHEN @AvgPLE >= 300 THEN 100 -- Good
        ELSE 100
    END;

    -- =====================================================
    -- 3. Disk I/O Health Score
    -- Based on average read/write latency
    -- =====================================================

    DECLARE @AvgLatency DECIMAL(10,2);

    SELECT @AvgLatency = AVG(CAST(MetricValue AS DECIMAL(10,2)))
    FROM dbo.PerformanceMetrics
    WHERE ServerID = @ServerID
      AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
      AND MetricCategory = 'Disk'
      AND MetricName IN ('AvgDiskSecRead', 'AvgDiskSecWrite');

    -- Convert from seconds to milliseconds
    SET @AvgLatency = @AvgLatency * 1000;

    SET @DiskIOScore = CASE
        WHEN @AvgLatency IS NULL THEN 100 -- No data
        WHEN @AvgLatency > 100 THEN 10 -- Critical (>100ms latency)
        WHEN @AvgLatency > 50 THEN 20 -- Very bad
        WHEN @AvgLatency > 20 THEN 50 -- Warning
        WHEN @AvgLatency > 10 THEN 80 -- Acceptable
        ELSE 100 -- Good (<10ms)
    END;

    -- =====================================================
    -- 4. Wait Stats Health Score
    -- Based on percentage of "bad" waits (I/O, Locking, Parallelism)
    -- =====================================================

    DECLARE @BadWaitPct DECIMAL(5,2) = 0;

    WITH WaitCategories AS (
        SELECT
            CASE
                WHEN WaitType IN ('PAGEIOLATCH_SH', 'PAGEIOLATCH_EX', 'WRITELOG', 'IO_COMPLETION',
                                  'ASYNC_IO_COMPLETION', 'BACKUPIO') THEN 'IO'
                WHEN WaitType IN ('LCK_M_S', 'LCK_M_X', 'LCK_M_U', 'LCK_M_IX', 'LCK_M_IS') THEN 'Locking'
                WHEN WaitType IN ('CXPACKET', 'CXCONSUMER') THEN 'Parallelism'
                WHEN WaitType LIKE 'PREEMPTIVE%' THEN 'Preemptive'
                ELSE 'Other'
            END AS WaitCategory,
            SUM(WaitTimeMs) AS TotalWaitMs
        FROM dbo.WaitStatsSnapshot
        WHERE ServerID = @ServerID
          AND SnapshotTime >= DATEADD(HOUR, -1, GETUTCDATE())
        GROUP BY CASE
            WHEN WaitType IN ('PAGEIOLATCH_SH', 'PAGEIOLATCH_EX', 'WRITELOG', 'IO_COMPLETION',
                              'ASYNC_IO_COMPLETION', 'BACKUPIO') THEN 'IO'
            WHEN WaitType IN ('LCK_M_S', 'LCK_M_X', 'LCK_M_U', 'LCK_M_IX', 'LCK_M_IS') THEN 'Locking'
            WHEN WaitType IN ('CXPACKET', 'CXCONSUMER') THEN 'Parallelism'
            WHEN WaitType LIKE 'PREEMPTIVE%' THEN 'Preemptive'
            ELSE 'Other'
        END
    )
    SELECT @BadWaitPct =
        CASE
            WHEN SUM(TotalWaitMs) = 0 THEN 0
            ELSE (SUM(CASE WHEN WaitCategory IN ('IO', 'Locking', 'Parallelism') THEN TotalWaitMs ELSE 0 END) * 100.0 / SUM(TotalWaitMs))
        END
    FROM WaitCategories;

    SET @WaitStatsScore = CASE
        WHEN @BadWaitPct > 50 THEN 20 -- Critical (>50% bad waits)
        WHEN @BadWaitPct > 30 THEN 40 -- Warning
        WHEN @BadWaitPct > 10 THEN 70 -- Acceptable
        ELSE 100 -- Good (<10% bad waits)
    END;

    -- =====================================================
    -- 5. Blocking Health Score
    -- Based on number of blocking events in last hour
    -- =====================================================

    DECLARE @BlockingCount INT = 0;

    SELECT @BlockingCount = COUNT(*)
    FROM dbo.BlockingEvents
    WHERE ServerID = @ServerID
      AND EventTime >= DATEADD(HOUR, -1, GETUTCDATE());

    SET @BlockingScore = CASE
        WHEN @BlockingCount > 50 THEN 10 -- Critical
        WHEN @BlockingCount > 20 THEN 20 -- Very bad
        WHEN @BlockingCount > 10 THEN 40 -- Warning
        WHEN @BlockingCount > 5 THEN 60 -- Acceptable
        WHEN @BlockingCount > 0 THEN 80 -- Minimal blocking
        ELSE 100 -- No blocking
    END;

    -- =====================================================
    -- 6. Index Health Score
    -- Based on average fragmentation of large indexes (>1000 pages)
    -- =====================================================

    DECLARE @AvgFragmentation DECIMAL(5,2) = 0;

    SELECT @AvgFragmentation = AVG(FragmentationPercent)
    FROM dbo.IndexFragmentation
    WHERE ServerID = @ServerID
      AND ScanDate >= DATEADD(DAY, -1, GETUTCDATE())
      AND PageCount > 1000; -- Only consider indexes with >1000 pages

    SET @IndexScore = CASE
        WHEN @AvgFragmentation IS NULL THEN 100 -- No data
        WHEN @AvgFragmentation > 50 THEN 20 -- Critical
        WHEN @AvgFragmentation > 30 THEN 40 -- Warning
        WHEN @AvgFragmentation > 10 THEN 70 -- Acceptable
        ELSE 100 -- Good (<10% fragmentation)
    END;

    -- =====================================================
    -- 7. Query Performance Health Score
    -- Based on Query Store average query duration
    -- =====================================================

    DECLARE @AvgQueryDuration DECIMAL(10,2) = 0;

    SELECT @AvgQueryDuration = AVG(rs.AvgDurationMs)
    FROM dbo.QueryStoreRuntimeStats rs
    INNER JOIN dbo.QueryStoreQueries q ON rs.QueryStoreQueryID = q.QueryStoreQueryID
    WHERE q.ServerID = @ServerID
      AND rs.CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE());

    SET @QueryScore = CASE
        WHEN @AvgQueryDuration IS NULL THEN 100 -- No data (Query Store not enabled)
        WHEN @AvgQueryDuration > 1000 THEN 20 -- Critical (>1 second avg)
        WHEN @AvgQueryDuration > 500 THEN 50 -- Warning
        WHEN @AvgQueryDuration > 100 THEN 80 -- Acceptable
        ELSE 100 -- Good (<100ms)
    END;

    -- =====================================================
    -- Calculate Overall Weighted Score
    -- Weights: CPU(20%), Memory(20%), DiskIO(15%), WaitStats(15%), Blocking(10%), Index(10%), Query(10%)
    -- =====================================================

    SET @OverallScore = (
        (@CPUScore * 0.20) +
        (@MemoryScore * 0.20) +
        (@DiskIOScore * 0.15) +
        (@WaitStatsScore * 0.15) +
        (@BlockingScore * 0.10) +
        (@IndexScore * 0.10) +
        (@QueryScore * 0.10)
    );

    -- =====================================================
    -- Determine Critical/Warning Counts
    -- =====================================================

    SET @CriticalCount = (
        (CASE WHEN @CPUScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @MemoryScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @DiskIOScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @WaitStatsScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @BlockingScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @IndexScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @QueryScore < 30 THEN 1 ELSE 0 END)
    );

    SET @WarningCount = (
        (CASE WHEN @CPUScore >= 30 AND @CPUScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @MemoryScore >= 30 AND @MemoryScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @DiskIOScore >= 30 AND @DiskIOScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @WaitStatsScore >= 30 AND @WaitStatsScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @BlockingScore >= 30 AND @BlockingScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @IndexScore >= 30 AND @IndexScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @QueryScore >= 30 AND @QueryScore < 60 THEN 1 ELSE 0 END)
    );

    -- =====================================================
    -- Find Top Issue (component with lowest score)
    -- =====================================================

    SELECT TOP 1
        @TopIssue = Description,
        @TopSeverity = Severity
    FROM (
        SELECT @CPUScore AS Score,
               'High CPU usage detected (' + ISNULL(CAST(@AvgCPU AS VARCHAR), 'N/A') + '% avg)' AS Description,
               CASE WHEN @CPUScore < 30 THEN 'Critical' WHEN @CPUScore < 60 THEN 'Warning' ELSE 'Info' END AS Severity
        UNION ALL
        SELECT @MemoryScore,
               'Low page life expectancy (' + ISNULL(CAST(@AvgPLE AS VARCHAR), 'N/A') + ' seconds avg)',
               CASE WHEN @MemoryScore < 30 THEN 'Critical' WHEN @MemoryScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @DiskIOScore,
               'High disk I/O latency (' + ISNULL(CAST(@AvgLatency AS VARCHAR), 'N/A') + ' ms avg)',
               CASE WHEN @DiskIOScore < 30 THEN 'Critical' WHEN @DiskIOScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @WaitStatsScore,
               'Excessive wait statistics (' + ISNULL(CAST(@BadWaitPct AS VARCHAR), 'N/A') + '% bad waits)',
               CASE WHEN @WaitStatsScore < 30 THEN 'Critical' WHEN @WaitStatsScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @BlockingScore,
               'Blocking events detected (' + CAST(@BlockingCount AS VARCHAR) + ' events in last hour)',
               CASE WHEN @BlockingScore < 30 THEN 'Critical' WHEN @BlockingScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @IndexScore,
               'High index fragmentation (' + ISNULL(CAST(@AvgFragmentation AS VARCHAR), 'N/A') + '% avg)',
               CASE WHEN @IndexScore < 30 THEN 'Critical' WHEN @IndexScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @QueryScore,
               'Slow query performance (' + ISNULL(CAST(@AvgQueryDuration AS VARCHAR), 'N/A') + ' ms avg)',
               CASE WHEN @QueryScore < 30 THEN 'Critical' WHEN @QueryScore < 60 THEN 'Warning' ELSE 'Info' END
    ) AS Issues
    WHERE Score < 100
    ORDER BY Score ASC;

    -- =====================================================
    -- Insert Health Score Record
    -- =====================================================

    INSERT INTO dbo.ServerHealthScore (
        ServerID, CalculationTime,
        OverallHealthScore,
        CPUHealthScore, MemoryHealthScore, DiskIOHealthScore,
        WaitStatsHealthScore, BlockingHealthScore, IndexHealthScore, QueryPerformanceHealthScore,
        CriticalIssueCount, WarningIssueCount,
        TopIssueDescription, TopIssueSeverity
    )
    VALUES (
        @ServerID, GETUTCDATE(),
        @OverallScore,
        @CPUScore, @MemoryScore, @DiskIOScore,
        @WaitStatsScore, @BlockingScore, @IndexScore, @QueryScore,
        @CriticalCount, @WarningCount,
        @TopIssue, @TopSeverity
    );

    SET @HealthScoreID = SCOPE_IDENTITY();

    -- =====================================================
    -- Insert Detailed Issues
    -- =====================================================

    INSERT INTO dbo.HealthScoreIssues (HealthScoreID, IssueCategory, IssueSeverity, IssueDescription, ImpactOnScore, RecommendedAction)
    SELECT @HealthScoreID, Category, Severity, Description, Impact, Recommendation
    FROM (
        -- CPU Issue
        SELECT 'CPU' AS Category,
               CASE WHEN @CPUScore < 30 THEN 'Critical' WHEN @CPUScore < 60 THEN 'Warning' ELSE 'Info' END AS Severity,
               'High CPU usage: ' + ISNULL(CAST(@AvgCPU AS VARCHAR), 'N/A') + '%' AS Description,
               (100 - @CPUScore) * 0.20 AS Impact,
               'Review top CPU-consuming queries and consider query optimization or hardware upgrades' AS Recommendation
        WHERE @CPUScore < 100

        UNION ALL

        -- Memory Issue
        SELECT 'Memory',
               CASE WHEN @MemoryScore < 30 THEN 'Critical' WHEN @MemoryScore < 60 THEN 'Warning' ELSE 'Info' END,
               'Low page life expectancy: ' + ISNULL(CAST(@AvgPLE AS VARCHAR), 'N/A') + ' seconds',
               (100 - @MemoryScore) * 0.20,
               'Consider adding more memory or reducing memory pressure by optimizing queries and indexes'
        WHERE @MemoryScore < 100

        UNION ALL

        -- Disk I/O Issue
        SELECT 'DiskIO',
               CASE WHEN @DiskIOScore < 30 THEN 'Critical' WHEN @DiskIOScore < 60 THEN 'Warning' ELSE 'Info' END,
               'High disk I/O latency: ' + ISNULL(CAST(@AvgLatency AS VARCHAR), 'N/A') + ' ms',
               (100 - @DiskIOScore) * 0.15,
               'Check disk subsystem performance, consider faster storage (SSD) or improve indexing'
        WHERE @DiskIOScore < 100

        UNION ALL

        -- Wait Stats Issue
        SELECT 'WaitStats',
               CASE WHEN @WaitStatsScore < 30 THEN 'Critical' WHEN @WaitStatsScore < 60 THEN 'Warning' ELSE 'Info' END,
               'Excessive wait statistics: ' + CAST(@BadWaitPct AS VARCHAR) + '% bad waits',
               (100 - @WaitStatsScore) * 0.15,
               'Review wait statistics dashboard to identify specific bottlenecks (I/O, locking, or parallelism)'
        WHERE @WaitStatsScore < 100

        UNION ALL

        -- Blocking Issue
        SELECT 'Blocking',
               CASE WHEN @BlockingScore < 30 THEN 'Critical' WHEN @BlockingScore < 60 THEN 'Warning' ELSE 'Info' END,
               'Blocking events detected: ' + CAST(@BlockingCount AS VARCHAR) + ' events in last hour',
               (100 - @BlockingScore) * 0.10,
               'Review blocking events and optimize queries to reduce lock duration and improve concurrency'
        WHERE @BlockingScore < 100

        UNION ALL

        -- Index Issue
        SELECT 'Index',
               CASE WHEN @IndexScore < 30 THEN 'Critical' WHEN @IndexScore < 60 THEN 'Warning' ELSE 'Info' END,
               'High index fragmentation: ' + ISNULL(CAST(@AvgFragmentation AS VARCHAR), 'N/A') + '% average',
               (100 - @IndexScore) * 0.10,
               'Schedule index maintenance to rebuild or reorganize fragmented indexes'
        WHERE @IndexScore < 100

        UNION ALL

        -- Query Performance Issue
        SELECT 'Query',
               CASE WHEN @QueryScore < 30 THEN 'Critical' WHEN @QueryScore < 60 THEN 'Warning' ELSE 'Info' END,
               'Slow query performance: ' + ISNULL(CAST(@AvgQueryDuration AS VARCHAR), 'N/A') + ' ms average',
               (100 - @QueryScore) * 0.10,
               'Review Query Store for slow queries, missing indexes, and plan regressions'
        WHERE @QueryScore < 100
    ) AS DetailedIssues;

    -- =====================================================
    -- Return Health Score Summary
    -- =====================================================

    SELECT
        @HealthScoreID AS HealthScoreID,
        @OverallScore AS OverallHealthScore,
        @CPUScore AS CPUHealthScore,
        @MemoryScore AS MemoryHealthScore,
        @DiskIOScore AS DiskIOHealthScore,
        @WaitStatsScore AS WaitStatsHealthScore,
        @BlockingScore AS BlockingHealthScore,
        @IndexScore AS IndexHealthScore,
        @QueryScore AS QueryPerformanceHealthScore,
        @CriticalCount AS CriticalIssueCount,
        @WarningCount AS WarningIssueCount,
        @TopIssue AS TopIssueDescription,
        @TopSeverity AS TopIssueSeverity;
END;
GO

PRINT '✅ Created procedure: dbo.usp_CalculateHealthScore';
PRINT '';

-- =====================================================
-- Procedure: usp_GetHealthScoreHistory
-- Purpose: Retrieve health score history for a server
-- =====================================================

IF OBJECT_ID('dbo.usp_GetHealthScoreHistory', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetHealthScoreHistory;
GO

CREATE PROCEDURE dbo.usp_GetHealthScoreHistory
    @ServerID INT,
    @StartTime DATETIME2 = NULL,
    @EndTime DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to last 7 days if not specified
    IF @StartTime IS NULL SET @StartTime = DATEADD(DAY, -7, GETUTCDATE());
    IF @EndTime IS NULL SET @EndTime = GETUTCDATE();

    SELECT
        hs.HealthScoreID,
        hs.ServerID,
        s.ServerName,
        hs.CalculationTime,
        hs.OverallHealthScore,
        hs.CPUHealthScore,
        hs.MemoryHealthScore,
        hs.DiskIOHealthScore,
        hs.WaitStatsHealthScore,
        hs.BlockingHealthScore,
        hs.IndexHealthScore,
        hs.QueryPerformanceHealthScore,
        hs.CriticalIssueCount,
        hs.WarningIssueCount,
        hs.TopIssueDescription,
        hs.TopIssueSeverity
    FROM dbo.ServerHealthScore hs
    INNER JOIN dbo.Servers s ON hs.ServerID = s.ServerID
    WHERE hs.ServerID = @ServerID
      AND hs.CalculationTime >= @StartTime
      AND hs.CalculationTime <= @EndTime
    ORDER BY hs.CalculationTime DESC;
END;
GO

PRINT '✅ Created procedure: dbo.usp_GetHealthScoreHistory';
PRINT '';

-- =====================================================
-- Procedure: usp_GetHealthScoreIssues
-- Purpose: Retrieve detailed issues for a health score
-- =====================================================

IF OBJECT_ID('dbo.usp_GetHealthScoreIssues', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetHealthScoreIssues;
GO

CREATE PROCEDURE dbo.usp_GetHealthScoreIssues
    @HealthScoreID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.IssueID,
        i.HealthScoreID,
        i.IssueCategory,
        i.IssueSeverity,
        i.IssueDescription,
        i.ImpactOnScore,
        i.RecommendedAction
    FROM dbo.HealthScoreIssues i
    WHERE i.HealthScoreID = @HealthScoreID
    ORDER BY i.ImpactOnScore DESC, i.IssueSeverity DESC;
END;
GO

PRINT '✅ Created procedure: dbo.usp_GetHealthScoreIssues';
PRINT '';

-- =====================================================
-- Procedure: usp_GetLatestHealthScores
-- Purpose: Get latest health scores for all servers
-- =====================================================

IF OBJECT_ID('dbo.usp_GetLatestHealthScores', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetLatestHealthScores;
GO

CREATE PROCEDURE dbo.usp_GetLatestHealthScores
AS
BEGIN
    SET NOCOUNT ON;

    WITH LatestScores AS (
        SELECT
            hs.ServerID,
            hs.HealthScoreID,
            hs.CalculationTime,
            hs.OverallHealthScore,
            hs.CriticalIssueCount,
            hs.WarningIssueCount,
            hs.TopIssueDescription,
            hs.TopIssueSeverity,
            ROW_NUMBER() OVER (PARTITION BY hs.ServerID ORDER BY hs.CalculationTime DESC) AS rn
        FROM dbo.ServerHealthScore hs
    )
    SELECT
        s.ServerID,
        s.ServerName,
        s.Environment,
        ls.HealthScoreID,
        ls.CalculationTime,
        ls.OverallHealthScore,
        CASE
            WHEN ls.OverallHealthScore >= 80 THEN 'Healthy'
            WHEN ls.OverallHealthScore >= 60 THEN 'Warning'
            ELSE 'Critical'
        END AS HealthStatus,
        ls.CriticalIssueCount,
        ls.WarningIssueCount,
        ls.TopIssueDescription,
        ls.TopIssueSeverity
    FROM dbo.Servers s
    LEFT JOIN LatestScores ls ON s.ServerID = ls.ServerID AND ls.rn = 1
    WHERE s.IsActive = 1
    ORDER BY
        CASE WHEN ls.OverallHealthScore IS NULL THEN 1 ELSE 0 END,
        ls.OverallHealthScore ASC,
        s.ServerName;
END;
GO

PRINT '✅ Created procedure: dbo.usp_GetLatestHealthScores';
PRINT '';

PRINT '======================================';
PRINT 'Health Score Procedures Created Successfully';
PRINT '======================================';
PRINT '';
PRINT 'Available procedures:';
PRINT '  1. usp_CalculateHealthScore - Calculate health score for a server';
PRINT '  2. usp_GetHealthScoreHistory - Get historical health scores';
PRINT '  3. usp_GetHealthScoreIssues - Get detailed issues for a score';
PRINT '  4. usp_GetLatestHealthScores - Get latest scores for all servers';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Test: EXEC dbo.usp_CalculateHealthScore @ServerID = 1;';
PRINT '  2. Create SQL Agent job to run every 15 minutes';
PRINT '  3. Create Grafana dashboard';
PRINT '';

GO
