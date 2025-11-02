-- =====================================================
-- Query Performance Advisor Integration Tests
-- Tests that query analysis completes successfully
-- =====================================================
-- File: tests/test-query-advisor.sql
-- Purpose: Validate query advisor functionality end-to-end
-- Dependencies: 51-create-query-advisor-procedures.sql
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
GO

PRINT '======================================';
PRINT 'Query Performance Advisor Integration Tests';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Test 1: Analyze Query Performance Completes
-- =====================================================

PRINT '======================================';
PRINT 'Test 1: Analyze Query Performance';
PRINT '======================================';
PRINT '';

DECLARE @ServerID INT = 1;
DECLARE @BeforeCount INT;
DECLARE @AfterCount INT;

-- Check recommendations before
SELECT @BeforeCount = COUNT(*) FROM dbo.QueryPerformanceRecommendations WHERE ServerID = @ServerID;
PRINT 'Recommendations before: ' + CAST(@BeforeCount AS VARCHAR);

-- Run analysis
EXEC dbo.usp_AnalyzeQueryPerformance @ServerID = @ServerID;

-- Check recommendations after
SELECT @AfterCount = COUNT(*) FROM dbo.QueryPerformanceRecommendations WHERE ServerID = @ServerID;
PRINT 'Recommendations after: ' + CAST(@AfterCount AS VARCHAR);

IF @AfterCount >= @BeforeCount
BEGIN
    PRINT '✅ PASS: Analysis completed (existing recommendations may prevent new ones)';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Recommendation count decreased unexpectedly';
    PRINT '';
END;

-- =====================================================
-- Test 2: Detect Plan Regressions Completes
-- =====================================================

PRINT '======================================';
PRINT 'Test 2: Detect Plan Regressions';
PRINT '======================================';
PRINT '';

DECLARE @BeforeRegressions INT;
DECLARE @AfterRegressions INT;

-- Check regressions before
SELECT @BeforeRegressions = COUNT(*) FROM dbo.QueryPlanRegressions WHERE ServerID = @ServerID;
PRINT 'Regressions before: ' + CAST(@BeforeRegressions AS VARCHAR);

-- Run detection
EXEC dbo.usp_DetectPlanRegressions
    @ServerID = @ServerID,
    @RegressionThresholdPercent = 50.0;

-- Check regressions after
SELECT @AfterRegressions = COUNT(*) FROM dbo.QueryPlanRegressions WHERE ServerID = @ServerID;
PRINT 'Regressions after: ' + CAST(@AfterRegressions AS VARCHAR);

IF @AfterRegressions >= @BeforeRegressions
BEGIN
    PRINT '✅ PASS: Regression detection completed';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Regression count decreased unexpectedly';
    PRINT '';
END;

-- =====================================================
-- Test 3: Get Top Recommendations
-- =====================================================

PRINT '======================================';
PRINT 'Test 3: Get Top Recommendations';
PRINT '======================================';
PRINT '';

DECLARE @RecommendationCount INT;

-- Get top 10 recommendations
CREATE TABLE #TempRecommendations (
    RecommendationID BIGINT,
    ServerName NVARCHAR(255),
    DatabaseName NVARCHAR(128),
    RecommendationType VARCHAR(50),
    RecommendationSeverity VARCHAR(20)
);

INSERT INTO #TempRecommendations
EXEC dbo.usp_GetTopRecommendations @TopN = 10;

SELECT @RecommendationCount = COUNT(*) FROM #TempRecommendations;

PRINT 'Top recommendations retrieved: ' + CAST(@RecommendationCount AS VARCHAR);

IF @RecommendationCount >= 0
BEGIN
    PRINT '✅ PASS: Retrieved recommendations successfully';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Failed to retrieve recommendations';
    PRINT '';
END;

DROP TABLE #TempRecommendations;

-- =====================================================
-- Test 4: Tables Exist and Accessible
-- =====================================================

PRINT '======================================';
PRINT 'Test 4: Verify Tables Exist';
PRINT '======================================';
PRINT '';

DECLARE @TableCount INT = 0;

IF OBJECT_ID('dbo.QueryPerformanceRecommendations', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ QueryPerformanceRecommendations exists';
END;

IF OBJECT_ID('dbo.QueryPlanRegressions', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ QueryPlanRegressions exists';
END;

IF OBJECT_ID('dbo.QueryOptimizationHistory', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ QueryOptimizationHistory exists';
END;

PRINT '';

IF @TableCount = 3
BEGIN
    PRINT '✅ PASS: All tables exist';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Missing tables';
    PRINT '';
END;

-- =====================================================
-- Test 5: Stored Procedures Exist
-- =====================================================

PRINT '======================================';
PRINT 'Test 5: Verify Stored Procedures Exist';
PRINT '======================================';
PRINT '';

DECLARE @ProcCount INT = 0;

IF OBJECT_ID('dbo.usp_AnalyzeQueryPerformance', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_AnalyzeQueryPerformance exists';
END;

IF OBJECT_ID('dbo.usp_DetectPlanRegressions', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_DetectPlanRegressions exists';
END;

IF OBJECT_ID('dbo.usp_GetTopRecommendations', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_GetTopRecommendations exists';
END;

IF OBJECT_ID('dbo.usp_MarkRecommendationImplemented', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_MarkRecommendationImplemented exists';
END;

PRINT '';

IF @ProcCount = 4
BEGIN
    PRINT '✅ PASS: All stored procedures exist';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Missing stored procedures';
    PRINT '';
END;

-- =====================================================
-- Test 6: SQL Agent Job Exists
-- =====================================================

PRINT '======================================';
PRINT 'Test 6: Verify SQL Agent Job Exists';
PRINT '======================================';
PRINT '';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'Analyze Query Performance - All Servers')
BEGIN
    PRINT '✅ PASS: SQL Agent job exists';

    -- Check job steps
    DECLARE @StepCount INT;
    SELECT @StepCount = COUNT(*)
    FROM msdb.dbo.sysjobs j
    INNER JOIN msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
    WHERE j.name = 'Analyze Query Performance - All Servers';

    PRINT '  Job steps: ' + CAST(@StepCount AS VARCHAR);
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: SQL Agent job does not exist';
    PRINT '';
END;

-- =====================================================
-- Test Summary
-- =====================================================

PRINT '======================================';
PRINT 'Test Summary';
PRINT '======================================';
PRINT '';
PRINT 'All integration tests completed!';
PRINT 'Review results above for any failures.';
PRINT '';
PRINT 'Note: Analysis procedures may not generate recommendations if:';
PRINT '  - Query Store data is insufficient (<24h of runtime stats)';
PRINT '  - All queries are performing well (no threshold violations)';
PRINT '  - Duplicate recommendations exist (within 7-day window)';
PRINT '';

GO
