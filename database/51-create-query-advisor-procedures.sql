-- =====================================================
-- Phase 3 - Feature #2: Query Performance Advisor
-- Stored Procedures for Query Optimization Analysis
-- =====================================================
-- File: 51-create-query-advisor-procedures.sql
-- Purpose: Analyze query performance and generate optimization recommendations
-- Dependencies: 50-create-query-advisor-tables.sql
-- =====================================================

USE MonitoringDB;
GO

PRINT '======================================';
PRINT 'Creating Query Performance Advisor Procedures';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Procedure: usp_AnalyzeQueryPerformance
-- Purpose: Analyze queries and generate optimization recommendations
-- =====================================================

IF OBJECT_ID('dbo.usp_AnalyzeQueryPerformance', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_AnalyzeQueryPerformance;
GO

CREATE PROCEDURE dbo.usp_AnalyzeQueryPerformance
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RecommendationsGenerated INT = 0;
    DECLARE @ServerName NVARCHAR(255);

    -- Get server name for logging
    SELECT @ServerName = ServerName FROM dbo.Servers WHERE ServerID = @ServerID;

    PRINT '======================================';
    PRINT 'Analyzing Query Performance for ' + @ServerName;
    PRINT '======================================';
    PRINT '';

    -- =====================================================
    -- Analysis #1: Queries with Missing Indexes
    -- =====================================================

    PRINT 'Analysis #1: Missing Index Recommendations...';

    INSERT INTO dbo.QueryPerformanceRecommendations (
        ServerID, DatabaseName, QueryHash, QueryText,
        AvgDurationMs, AvgCPUTimeMs, AvgLogicalReads, TotalExecutionCount,
        RecommendationType, RecommendationSeverity, RecommendationText,
        EstimatedImprovementPercent, ImplementationScript
    )
    SELECT
        qs.ServerID,
        qs.DatabaseName,
        qs.QueryHash,
        qs.QueryText,
        rs.AvgDurationMs,
        (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgCPUTimeMs,
        (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgLogicalReads,
        rs.ExecutionCount AS TotalExecutionCount,
        'MissingIndex' AS RecommendationType,
        CASE
            WHEN mi.AvgUserImpactPercent > 90 THEN 'Critical'
            WHEN mi.AvgUserImpactPercent > 70 THEN 'High'
            WHEN mi.AvgUserImpactPercent > 50 THEN 'Medium'
            ELSE 'Low'
        END AS RecommendationSeverity,
        'Missing index on ' + mi.DatabaseName + '.' + ISNULL(mi.SchemaName, 'dbo') + '.' + mi.TableName +
        ' - Expected improvement: ' + CAST(CAST(mi.AvgUserImpactPercent AS INT) AS VARCHAR) + '%' +
        CHAR(13) + CHAR(10) + 'Columns: ' + ISNULL(mi.EqualityColumns, '') +
        CASE WHEN mi.InequalityColumns IS NOT NULL THEN ', ' + mi.InequalityColumns ELSE '' END AS RecommendationText,
        mi.AvgUserImpactPercent AS EstimatedImprovementPercent,
        mi.CreateIndexStatement AS ImplementationScript
    FROM dbo.QueryStoreQueries qs
    INNER JOIN (
        -- Get latest runtime stats for each query
        SELECT
            QueryStoreQueryID,
            SUM(ExecutionCount) AS ExecutionCount,
            AVG(AvgDurationMs) AS AvgDurationMs,
            SUM(TotalCPUTimeMs) AS TotalCPUTimeMs,
            SUM(TotalLogicalReads) AS TotalLogicalReads
        FROM dbo.QueryStoreRuntimeStats
        WHERE CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
        GROUP BY QueryStoreQueryID
    ) rs ON qs.QueryStoreQueryID = rs.QueryStoreQueryID
    INNER JOIN dbo.MissingIndexRecommendations mi
        ON qs.ServerID = mi.ServerID
        AND qs.DatabaseName = mi.DatabaseName
    WHERE qs.ServerID = @ServerID
      AND rs.AvgDurationMs > 100 -- Only slow queries (>100ms)
      AND rs.ExecutionCount > 10 -- Only frequently executed queries
      AND mi.AvgUserImpactPercent > 50 -- Only high-impact indexes
      AND mi.IsImplemented = 0
      AND NOT EXISTS (
          -- Don't create duplicate recommendations within 7 days
          SELECT 1 FROM dbo.QueryPerformanceRecommendations qpr
          WHERE qpr.ServerID = qs.ServerID
            AND qpr.QueryHash = qs.QueryHash
            AND qpr.RecommendationType = 'MissingIndex'
            AND qpr.DetectionTime >= DATEADD(DAY, -7, GETUTCDATE())
      );

    SET @RecommendationsGenerated = @RecommendationsGenerated + @@ROWCOUNT;
    PRINT '  Found ' + CAST(@@ROWCOUNT AS VARCHAR) + ' missing index recommendations';
    PRINT '';

    -- =====================================================
    -- Analysis #2: High Logical Reads (Potential Index Issues)
    -- =====================================================

    PRINT 'Analysis #2: High Logical Reads...';

    INSERT INTO dbo.QueryPerformanceRecommendations (
        ServerID, DatabaseName, QueryHash, QueryText,
        AvgDurationMs, AvgCPUTimeMs, AvgLogicalReads, TotalExecutionCount,
        RecommendationType, RecommendationSeverity, RecommendationText,
        EstimatedImprovementPercent, ImplementationScript
    )
    SELECT TOP 10
        qs.ServerID,
        qs.DatabaseName,
        qs.QueryHash,
        qs.QueryText,
        rs.AvgDurationMs,
        (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgCPUTimeMs,
        (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgLogicalReads,
        rs.ExecutionCount AS TotalExecutionCount,
        'HighLogicalReads' AS RecommendationType,
        CASE
            WHEN (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 100000 THEN 'Critical'
            WHEN (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 50000 THEN 'High'
            WHEN (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 10000 THEN 'Medium'
            ELSE 'Low'
        END AS RecommendationSeverity,
        'High logical reads: ' +
        CAST(CAST((rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS BIGINT) AS VARCHAR) +
        ' per execution. Consider adding indexes, rewriting query, or updating statistics.' AS RecommendationText,
        CASE
            WHEN (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 100000 THEN 80.0
            WHEN (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 50000 THEN 60.0
            WHEN (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 10000 THEN 40.0
            ELSE 20.0
        END AS EstimatedImprovementPercent,
        '-- Review execution plan and consider:' + CHAR(13) + CHAR(10) +
        '-- 1. Adding missing indexes' + CHAR(13) + CHAR(10) +
        '-- 2. Updating statistics: UPDATE STATISTICS ' + qs.DatabaseName + '..TableName WITH FULLSCAN;' + CHAR(13) + CHAR(10) +
        '-- 3. Rewriting query to reduce table scans' AS ImplementationScript
    FROM dbo.QueryStoreQueries qs
    INNER JOIN (
        SELECT
            QueryStoreQueryID,
            SUM(ExecutionCount) AS ExecutionCount,
            AVG(AvgDurationMs) AS AvgDurationMs,
            SUM(TotalCPUTimeMs) AS TotalCPUTimeMs,
            SUM(TotalLogicalReads) AS TotalLogicalReads
        FROM dbo.QueryStoreRuntimeStats
        WHERE CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
        GROUP BY QueryStoreQueryID
    ) rs ON qs.QueryStoreQueryID = rs.QueryStoreQueryID
    WHERE qs.ServerID = @ServerID
      AND rs.ExecutionCount > 10
      AND (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 10000 -- Avg > 10K reads
      AND NOT EXISTS (
          SELECT 1 FROM dbo.QueryPerformanceRecommendations qpr
          WHERE qpr.ServerID = qs.ServerID
            AND qpr.QueryHash = qs.QueryHash
            AND qpr.RecommendationType = 'HighLogicalReads'
            AND qpr.DetectionTime >= DATEADD(DAY, -7, GETUTCDATE())
      )
    ORDER BY (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) DESC;

    SET @RecommendationsGenerated = @RecommendationsGenerated + @@ROWCOUNT;
    PRINT '  Found ' + CAST(@@ROWCOUNT AS VARCHAR) + ' high logical reads recommendations';
    PRINT '';

    -- =====================================================
    -- Analysis #3: High CPU Usage
    -- =====================================================

    PRINT 'Analysis #3: High CPU Usage...';

    INSERT INTO dbo.QueryPerformanceRecommendations (
        ServerID, DatabaseName, QueryHash, QueryText,
        AvgDurationMs, AvgCPUTimeMs, AvgLogicalReads, TotalExecutionCount,
        RecommendationType, RecommendationSeverity, RecommendationText,
        EstimatedImprovementPercent, ImplementationScript
    )
    SELECT TOP 10
        qs.ServerID,
        qs.DatabaseName,
        qs.QueryHash,
        qs.QueryText,
        rs.AvgDurationMs,
        (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgCPUTimeMs,
        (rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgLogicalReads,
        rs.ExecutionCount AS TotalExecutionCount,
        'HighCPU' AS RecommendationType,
        CASE
            WHEN (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 5000 THEN 'Critical'
            WHEN (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 1000 THEN 'High'
            WHEN (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 500 THEN 'Medium'
            ELSE 'Low'
        END AS RecommendationSeverity,
        'High CPU usage: ' +
        CAST(CAST((rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS INT) AS VARCHAR) +
        'ms per execution. Review for expensive operations (sorts, aggregations, functions).' AS RecommendationText,
        CASE
            WHEN (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 5000 THEN 70.0
            WHEN (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 1000 THEN 50.0
            WHEN (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 500 THEN 30.0
            ELSE 15.0
        END AS EstimatedImprovementPercent,
        '-- Review execution plan for:' + CHAR(13) + CHAR(10) +
        '-- 1. Expensive sorts (add indexes to avoid sorts)' + CHAR(13) + CHAR(10) +
        '-- 2. Scalar functions in WHERE clause (consider inline TVFs)' + CHAR(13) + CHAR(10) +
        '-- 3. Implicit conversions (match data types)' + CHAR(13) + CHAR(10) +
        '-- 4. Key lookups (add INCLUDE columns to indexes)' AS ImplementationScript
    FROM dbo.QueryStoreQueries qs
    INNER JOIN (
        SELECT
            QueryStoreQueryID,
            SUM(ExecutionCount) AS ExecutionCount,
            AVG(AvgDurationMs) AS AvgDurationMs,
            SUM(TotalCPUTimeMs) AS TotalCPUTimeMs,
            SUM(TotalLogicalReads) AS TotalLogicalReads
        FROM dbo.QueryStoreRuntimeStats
        WHERE CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
        GROUP BY QueryStoreQueryID
    ) rs ON qs.QueryStoreQueryID = rs.QueryStoreQueryID
    WHERE qs.ServerID = @ServerID
      AND rs.ExecutionCount > 10
      AND (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) > 500 -- Avg > 500ms CPU
      AND NOT EXISTS (
          SELECT 1 FROM dbo.QueryPerformanceRecommendations qpr
          WHERE qpr.ServerID = qs.ServerID
            AND qpr.QueryHash = qs.QueryHash
            AND qpr.RecommendationType = 'HighCPU'
            AND qpr.DetectionTime >= DATEADD(DAY, -7, GETUTCDATE())
      )
    ORDER BY (rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) DESC;

    SET @RecommendationsGenerated = @RecommendationsGenerated + @@ROWCOUNT;
    PRINT '  Found ' + CAST(@@ROWCOUNT AS VARCHAR) + ' high CPU recommendations';
    PRINT '';

    -- =====================================================
    -- Summary
    -- =====================================================

    PRINT '======================================';
    PRINT 'Analysis Complete';
    PRINT '======================================';
    PRINT 'Total recommendations generated: ' + CAST(@RecommendationsGenerated AS VARCHAR);
    PRINT '';

    -- Return summary
    SELECT
        @ServerID AS ServerID,
        @ServerName AS ServerName,
        @RecommendationsGenerated AS RecommendationsGenerated,
        GETUTCDATE() AS AnalysisTime;
END;
GO

PRINT '✅ Created procedure: usp_AnalyzeQueryPerformance';
PRINT '';

-- =====================================================
-- Procedure: usp_DetectPlanRegressions
-- Purpose: Detect execution plan changes that degrade performance
-- =====================================================

IF OBJECT_ID('dbo.usp_DetectPlanRegressions', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_DetectPlanRegressions;
GO

CREATE PROCEDURE dbo.usp_DetectPlanRegressions
    @ServerID INT,
    @RegressionThresholdPercent DECIMAL(5,2) = 50.0 -- Default: 50% performance degradation
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RegressionsDetected INT = 0;
    DECLARE @ServerName NVARCHAR(255);

    SELECT @ServerName = ServerName FROM dbo.Servers WHERE ServerID = @ServerID;

    PRINT '======================================';
    PRINT 'Detecting Plan Regressions for ' + @ServerName;
    PRINT '======================================';
    PRINT '';

    -- Detect plan regressions by comparing recent performance to historical baseline
    INSERT INTO dbo.QueryPlanRegressions (
        ServerID, DatabaseName, QueryHash, QueryText,
        OldPlanHandle, OldAvgDurationMs, OldAvgCPUTimeMs, OldAvgLogicalReads, OldPlanCreatedTime,
        NewPlanHandle, NewAvgDurationMs, NewAvgCPUTimeMs, NewAvgLogicalReads, NewPlanCreatedTime,
        DurationIncreasePct, CPUIncreasePct, LogicalReadsIncreasePct
    )
    SELECT
        qs.ServerID,
        qs.DatabaseName,
        qs.QueryHash,
        qs.QueryText,
        old_stats.PlanHandle AS OldPlanHandle,
        old_stats.AvgDurationMs AS OldAvgDurationMs,
        old_stats.AvgCPUTimeMs AS OldAvgCPUTimeMs,
        old_stats.AvgLogicalReads AS OldAvgLogicalReads,
        old_stats.CollectionTime AS OldPlanCreatedTime,
        new_stats.PlanHandle AS NewPlanHandle,
        new_stats.AvgDurationMs AS NewAvgDurationMs,
        new_stats.AvgCPUTimeMs AS NewAvgCPUTimeMs,
        new_stats.AvgLogicalReads AS NewAvgLogicalReads,
        new_stats.CollectionTime AS NewPlanCreatedTime,
        ((new_stats.AvgDurationMs - old_stats.AvgDurationMs) * 100.0 / NULLIF(old_stats.AvgDurationMs, 0)) AS DurationIncreasePct,
        ((new_stats.AvgCPUTimeMs - old_stats.AvgCPUTimeMs) * 100.0 / NULLIF(old_stats.AvgCPUTimeMs, 0)) AS CPUIncreasePct,
        ((new_stats.AvgLogicalReads - old_stats.AvgLogicalReads) * 100.0 / NULLIF(old_stats.AvgLogicalReads, 0)) AS LogicalReadsIncreasePct
    FROM dbo.QueryStoreQueries qs
    CROSS APPLY (
        -- Old stats (7-14 days ago, good baseline)
        SELECT TOP 1
            rs.PlanID AS PlanHandle,
            AVG(rs.AvgDurationMs) AS AvgDurationMs,
            AVG(rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgCPUTimeMs,
            AVG(rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgLogicalReads,
            MAX(rs.CollectionTime) AS CollectionTime
        FROM dbo.QueryStoreRuntimeStats rs
        WHERE rs.QueryStoreQueryID = qs.QueryStoreQueryID
          AND rs.CollectionTime BETWEEN DATEADD(DAY, -14, GETUTCDATE()) AND DATEADD(DAY, -7, GETUTCDATE())
          AND rs.ExecutionCount > 10
        GROUP BY rs.PlanID
        ORDER BY COUNT(*) DESC
    ) old_stats
    CROSS APPLY (
        -- New stats (last 24 hours)
        SELECT TOP 1
            rs.PlanID AS PlanHandle,
            AVG(rs.AvgDurationMs) AS AvgDurationMs,
            AVG(rs.TotalCPUTimeMs * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgCPUTimeMs,
            AVG(rs.TotalLogicalReads * 1.0 / NULLIF(rs.ExecutionCount, 0)) AS AvgLogicalReads,
            MAX(rs.CollectionTime) AS CollectionTime
        FROM dbo.QueryStoreRuntimeStats rs
        WHERE rs.QueryStoreQueryID = qs.QueryStoreQueryID
          AND rs.CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
          AND rs.ExecutionCount > 10
        GROUP BY rs.PlanID
        ORDER BY COUNT(*) DESC
    ) new_stats
    WHERE qs.ServerID = @ServerID
      AND old_stats.PlanHandle <> new_stats.PlanHandle -- Plan changed
      AND ((new_stats.AvgDurationMs - old_stats.AvgDurationMs) * 100.0 / NULLIF(old_stats.AvgDurationMs, 0)) > @RegressionThresholdPercent -- Duration increased by threshold
      AND NOT EXISTS (
          SELECT 1 FROM dbo.QueryPlanRegressions qpr
          WHERE qpr.ServerID = qs.ServerID
            AND qpr.QueryHash = qs.QueryHash
            AND qpr.DetectionTime >= DATEADD(DAY, -7, GETUTCDATE())
            AND qpr.IsResolved = 0
      );

    SET @RegressionsDetected = @@ROWCOUNT;

    PRINT 'Plan regressions detected: ' + CAST(@RegressionsDetected AS VARCHAR);
    PRINT '';

    -- Create high-severity recommendations for regressions
    IF @RegressionsDetected > 0
    BEGIN
        INSERT INTO dbo.QueryPerformanceRecommendations (
            ServerID, DatabaseName, QueryHash, QueryText,
            AvgDurationMs, AvgCPUTimeMs, AvgLogicalReads, TotalExecutionCount,
            RecommendationType, RecommendationSeverity, RecommendationText,
            EstimatedImprovementPercent, ImplementationScript
        )
        SELECT
            r.ServerID,
            r.DatabaseName,
            r.QueryHash,
            r.QueryText,
            r.NewAvgDurationMs,
            r.NewAvgCPUTimeMs,
            r.NewAvgLogicalReads,
            0 AS TotalExecutionCount, -- Not tracking execution count for regressions
            'PlanRegression' AS RecommendationType,
            'Critical' AS RecommendationSeverity,
            'Plan regression detected: Duration increased by ' +
            CAST(CAST(r.DurationIncreasePct AS INT) AS VARCHAR) + '%. ' +
            'Old duration: ' + CAST(CAST(r.OldAvgDurationMs AS INT) AS VARCHAR) + 'ms, ' +
            'New duration: ' + CAST(CAST(r.NewAvgDurationMs AS INT) AS VARCHAR) + 'ms. ' +
            'Consider forcing old plan or updating statistics.' AS RecommendationText,
            (r.DurationIncreasePct * -1.0) AS EstimatedImprovementPercent, -- Negative because we want to reverse the regression
            '-- Force old plan (use with caution):' + CHAR(13) + CHAR(10) +
            '-- EXEC sp_query_store_force_plan @query_id = <query_id>, @plan_id = ' +
            CAST(r.OldPlanHandle AS VARCHAR) + ';' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
            '-- OR update statistics:' + CHAR(13) + CHAR(10) +
            '-- UPDATE STATISTICS ' + r.DatabaseName + '..TableName WITH FULLSCAN;' AS ImplementationScript
        FROM dbo.QueryPlanRegressions r
        WHERE r.ServerID = @ServerID
          AND r.DetectionTime >= DATEADD(MINUTE, -5, GETUTCDATE()) -- Just detected
          AND NOT EXISTS (
              SELECT 1 FROM dbo.QueryPerformanceRecommendations qpr
              WHERE qpr.ServerID = r.ServerID
                AND qpr.QueryHash = r.QueryHash
                AND qpr.RecommendationType = 'PlanRegression'
                AND qpr.DetectionTime >= DATEADD(DAY, -7, GETUTCDATE())
          );

        PRINT '✅ Created ' + CAST(@@ROWCOUNT AS VARCHAR) + ' plan regression recommendations';
    END;

    PRINT '';
    PRINT '======================================';
    PRINT 'Plan Regression Detection Complete';
    PRINT '======================================';
    PRINT '';

    -- Return summary
    SELECT
        @ServerID AS ServerID,
        @ServerName AS ServerName,
        @RegressionsDetected AS RegressionsDetected,
        GETUTCDATE() AS AnalysisTime;
END;
GO

PRINT '✅ Created procedure: usp_DetectPlanRegressions';
PRINT '';

-- =====================================================
-- Procedure: usp_GetTopRecommendations
-- Purpose: Retrieve top optimization recommendations
-- =====================================================

IF OBJECT_ID('dbo.usp_GetTopRecommendations', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetTopRecommendations;
GO

CREATE PROCEDURE dbo.usp_GetTopRecommendations
    @ServerID INT = NULL,
    @TopN INT = 20,
    @IncludeImplemented BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@TopN)
        r.RecommendationID,
        s.ServerName,
        r.DatabaseName,
        r.RecommendationType,
        r.RecommendationSeverity,
        r.RecommendationText,
        r.EstimatedImprovementPercent,
        r.AvgDurationMs,
        r.AvgCPUTimeMs,
        r.AvgLogicalReads,
        r.TotalExecutionCount,
        r.ImplementationScript,
        r.IsImplemented,
        r.ImplementedDate,
        r.ImplementedBy,
        r.DetectionTime,
        LEFT(r.QueryText, 500) AS QueryTextPreview
    FROM dbo.QueryPerformanceRecommendations r
    INNER JOIN dbo.Servers s ON r.ServerID = s.ServerID
    WHERE (@ServerID IS NULL OR r.ServerID = @ServerID)
      AND (@IncludeImplemented = 1 OR r.IsImplemented = 0)
    ORDER BY
        CASE r.RecommendationSeverity
            WHEN 'Critical' THEN 1
            WHEN 'High' THEN 2
            WHEN 'Medium' THEN 3
            WHEN 'Low' THEN 4
        END,
        r.EstimatedImprovementPercent DESC,
        r.DetectionTime DESC;
END;
GO

PRINT '✅ Created procedure: usp_GetTopRecommendations';
PRINT '';

-- =====================================================
-- Procedure: usp_MarkRecommendationImplemented
-- Purpose: Mark a recommendation as implemented and track before/after metrics
-- =====================================================

IF OBJECT_ID('dbo.usp_MarkRecommendationImplemented', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MarkRecommendationImplemented;
GO

CREATE PROCEDURE dbo.usp_MarkRecommendationImplemented
    @RecommendationID BIGINT,
    @ImplementedBy NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerID INT;
    DECLARE @DatabaseName NVARCHAR(128);
    DECLARE @QueryHash BINARY(8);
    DECLARE @BeforeAvgDurationMs DECIMAL(18,2);
    DECLARE @BeforeAvgCPUTimeMs DECIMAL(18,2);
    DECLARE @BeforeAvgLogicalReads BIGINT;

    -- Get recommendation details
    SELECT
        @ServerID = ServerID,
        @DatabaseName = DatabaseName,
        @QueryHash = QueryHash,
        @BeforeAvgDurationMs = AvgDurationMs,
        @BeforeAvgCPUTimeMs = AvgCPUTimeMs,
        @BeforeAvgLogicalReads = AvgLogicalReads
    FROM dbo.QueryPerformanceRecommendations
    WHERE RecommendationID = @RecommendationID;

    IF @ServerID IS NULL
    BEGIN
        RAISERROR('Recommendation ID %d not found', 16, 1, @RecommendationID);
        RETURN;
    END;

    -- Mark as implemented
    UPDATE dbo.QueryPerformanceRecommendations
    SET
        IsImplemented = 1,
        ImplementedDate = GETUTCDATE(),
        ImplementedBy = @ImplementedBy
    WHERE RecommendationID = @RecommendationID;

    -- Create optimization history record (before metrics captured)
    INSERT INTO dbo.QueryOptimizationHistory (
        RecommendationID, ServerID, DatabaseName, QueryHash,
        BeforeAvgDurationMs, BeforeAvgCPUTimeMs, BeforeAvgLogicalReads,
        BeforeMeasurementTime,
        EstimatedImprovementPct
    )
    SELECT
        @RecommendationID,
        @ServerID,
        @DatabaseName,
        @QueryHash,
        @BeforeAvgDurationMs,
        @BeforeAvgCPUTimeMs,
        @BeforeAvgLogicalReads,
        GETUTCDATE(),
        EstimatedImprovementPercent
    FROM dbo.QueryPerformanceRecommendations
    WHERE RecommendationID = @RecommendationID;

    PRINT '✅ Marked recommendation ' + CAST(@RecommendationID AS VARCHAR) + ' as implemented';
    PRINT '⏳ After-metrics will be captured automatically after 24 hours';
END;
GO

PRINT '✅ Created procedure: usp_MarkRecommendationImplemented';
PRINT '';

-- =====================================================
-- Verification
-- =====================================================

PRINT '======================================';
PRINT 'Verification';
PRINT '======================================';
PRINT '';

SELECT
    ROUTINE_NAME AS ProcedureName,
    CREATED AS Created
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_TYPE = 'PROCEDURE'
  AND ROUTINE_NAME LIKE '%Query%Advisor%' OR ROUTINE_NAME LIKE '%Recommendation%' OR ROUTINE_NAME LIKE '%Regression%'
ORDER BY ROUTINE_NAME;

PRINT '';
PRINT '======================================';
PRINT 'Query Performance Advisor Procedures Created Successfully';
PRINT '======================================';
PRINT '';
PRINT 'Procedures Created:';
PRINT '  1. usp_AnalyzeQueryPerformance - Main analysis procedure';
PRINT '  2. usp_DetectPlanRegressions - Plan regression detection';
PRINT '  3. usp_GetTopRecommendations - Retrieve recommendations';
PRINT '  4. usp_MarkRecommendationImplemented - Track implementation';
PRINT '';
PRINT 'Next Steps:';
PRINT '  1. Create SQL Agent job for automated analysis';
PRINT '  2. Test procedures with real data';
PRINT '  3. Create Grafana dashboard';
PRINT '';

GO
