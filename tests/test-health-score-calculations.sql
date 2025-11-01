-- =====================================================
-- Health Score Integration Tests
-- Tests that health score calculation completes successfully
-- =====================================================
-- File: tests/test-health-score-calculations.sql
-- Purpose: Validate health score calculation works end-to-end
-- Dependencies: 41-create-health-score-procedures.sql
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
GO

PRINT '======================================';
PRINT 'Health Score Integration Tests';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Test 1: Health Score Calculation Completes Successfully
-- =====================================================

PRINT '======================================';
PRINT 'Test 1: Calculate Health Score for Server 1';
PRINT '======================================';
PRINT '';

DECLARE @ServerID INT = 1;
DECLARE @BeforeCount INT;
DECLARE @AfterCount INT;
DECLARE @HealthScoreID BIGINT;

-- Check how many health scores exist before
SELECT @BeforeCount = COUNT(*) FROM dbo.ServerHealthScore WHERE ServerID = @ServerID;
PRINT 'Health scores before test: ' + CAST(@BeforeCount AS VARCHAR);

-- Calculate health score
EXEC dbo.usp_CalculateHealthScore @ServerID = @ServerID;

-- Check how many health scores exist after
SELECT @AfterCount = COUNT(*) FROM dbo.ServerHealthScore WHERE ServerID = @ServerID;
PRINT 'Health scores after test: ' + CAST(@AfterCount AS VARCHAR);

-- Verify a new score was created
IF @AfterCount > @BeforeCount
BEGIN
    PRINT '✅ PASS: New health score record created';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: No new health score record created';
    PRINT '';
END;

-- Get the latest health score details
SELECT TOP 1
    @HealthScoreID = HealthScoreID
FROM dbo.ServerHealthScore
WHERE ServerID = @ServerID
ORDER BY CalculationTime DESC;

PRINT 'Latest Health Score Details:';
PRINT '====================================';

SELECT
    HealthScoreID,
    CalculationTime,
    OverallHealthScore,
    CPUHealthScore,
    MemoryHealthScore,
    DiskIOHealthScore,
    WaitStatsHealthScore,
    BlockingHealthScore,
    IndexHealthScore,
    QueryPerformanceHealthScore,
    CriticalIssueCount,
    WarningIssueCount,
    TopIssueDescription,
    TopIssueSeverity
FROM dbo.ServerHealthScore
WHERE HealthScoreID = @HealthScoreID;

PRINT '';
PRINT 'Health Score Issues:';
PRINT '====================================';

SELECT
    IssueCategory,
    IssueSeverity,
    IssueDescription,
    ImpactOnScore,
    RecommendedAction
FROM dbo.HealthScoreIssues
WHERE HealthScoreID = @HealthScoreID
ORDER BY ImpactOnScore DESC;

PRINT '';

-- =====================================================
-- Test 2: Validate Score Ranges (0-100)
-- =====================================================

PRINT '======================================';
PRINT 'Test 2: Validate Score Ranges';
PRINT '======================================';
PRINT '';

DECLARE @InvalidScores INT;

SELECT @InvalidScores = COUNT(*)
FROM dbo.ServerHealthScore
WHERE HealthScoreID = @HealthScoreID
  AND (
    OverallHealthScore < 0 OR OverallHealthScore > 100 OR
    CPUHealthScore < 0 OR CPUHealthScore > 100 OR
    MemoryHealthScore < 0 OR MemoryHealthScore > 100 OR
    DiskIOHealthScore < 0 OR DiskIOHealthScore > 100 OR
    WaitStatsHealthScore < 0 OR WaitStatsHealthScore > 100 OR
    BlockingHealthScore < 0 OR BlockingHealthScore > 100 OR
    IndexHealthScore < 0 OR IndexHealthScore > 100 OR
    QueryPerformanceHealthScore < 0 OR QueryPerformanceHealthScore > 100
  );

IF @InvalidScores = 0
BEGIN
    PRINT '✅ PASS: All scores are within 0-100 range';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: ' + CAST(@InvalidScores AS VARCHAR) + ' scores are outside 0-100 range';
    PRINT '';
END;

-- =====================================================
-- Test 3: Weighted Score Calculation Accuracy
-- =====================================================

PRINT '======================================';
PRINT 'Test 3: Weighted Score Calculation';
PRINT '======================================';
PRINT '';

DECLARE @ExpectedScore DECIMAL(5,2);
DECLARE @ActualScore DECIMAL(5,2);
DECLARE @ScoreDifference DECIMAL(5,2);
DECLARE @CPU DECIMAL(5,2), @Memory DECIMAL(5,2), @DiskIO DECIMAL(5,2);
DECLARE @WaitStats DECIMAL(5,2), @Blocking DECIMAL(5,2), @Index DECIMAL(5,2), @Query DECIMAL(5,2);

-- Get component scores
SELECT
    @ActualScore = OverallHealthScore,
    @CPU = CPUHealthScore,
    @Memory = MemoryHealthScore,
    @DiskIO = DiskIOHealthScore,
    @WaitStats = WaitStatsHealthScore,
    @Blocking = BlockingHealthScore,
    @Index = IndexHealthScore,
    @Query = QueryPerformanceHealthScore
FROM dbo.ServerHealthScore
WHERE HealthScoreID = @HealthScoreID;

-- Calculate expected weighted score
SET @ExpectedScore = (
    (@CPU * 0.20) +
    (@Memory * 0.20) +
    (@DiskIO * 0.15) +
    (@WaitStats * 0.15) +
    (@Blocking * 0.10) +
    (@Index * 0.10) +
    (@Query * 0.10)
);

SET @ScoreDifference = ABS(@ExpectedScore - @ActualScore);

PRINT 'Component Scores:';
PRINT '  CPU: ' + CAST(@CPU AS VARCHAR) + ' × 0.20 = ' + CAST(@CPU * 0.20 AS VARCHAR);
PRINT '  Memory: ' + CAST(@Memory AS VARCHAR) + ' × 0.20 = ' + CAST(@Memory * 0.20 AS VARCHAR);
PRINT '  Disk I/O: ' + CAST(@DiskIO AS VARCHAR) + ' × 0.15 = ' + CAST(@DiskIO * 0.15 AS VARCHAR);
PRINT '  Wait Stats: ' + CAST(@WaitStats AS VARCHAR) + ' × 0.15 = ' + CAST(@WaitStats * 0.15 AS VARCHAR);
PRINT '  Blocking: ' + CAST(@Blocking AS VARCHAR) + ' × 0.10 = ' + CAST(@Blocking * 0.10 AS VARCHAR);
PRINT '  Index: ' + CAST(@Index AS VARCHAR) + ' × 0.10 = ' + CAST(@Index * 0.10 AS VARCHAR);
PRINT '  Query: ' + CAST(@Query AS VARCHAR) + ' × 0.10 = ' + CAST(@Query * 0.10 AS VARCHAR);
PRINT '';
PRINT 'Expected Overall Score: ' + CAST(@ExpectedScore AS VARCHAR);
PRINT 'Actual Overall Score: ' + CAST(@ActualScore AS VARCHAR);
PRINT 'Difference: ' + CAST(@ScoreDifference AS VARCHAR);
PRINT '';

-- Allow 0.01 tolerance for rounding
IF @ScoreDifference < 0.01
BEGIN
    PRINT '✅ PASS: Weighted score calculation is accurate';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Weighted score calculation differs by ' + CAST(@ScoreDifference AS VARCHAR);
    PRINT '';
END;

-- =====================================================
-- Test 4: Issue Detection
-- =====================================================

PRINT '======================================';
PRINT 'Test 4: Issue Detection';
PRINT '======================================';
PRINT '';

DECLARE @IssueCount INT;
DECLARE @ExpectedIssueCount INT;

SELECT @IssueCount = COUNT(*) FROM dbo.HealthScoreIssues WHERE HealthScoreID = @HealthScoreID;
SELECT @ExpectedIssueCount = CriticalIssueCount + WarningIssueCount
FROM dbo.ServerHealthScore WHERE HealthScoreID = @HealthScoreID;

PRINT 'Total issues found: ' + CAST(@IssueCount AS VARCHAR);
PRINT 'Expected issue count (Critical + Warning): ' + CAST(@ExpectedIssueCount AS VARCHAR);
PRINT '';

IF @IssueCount = @ExpectedIssueCount
BEGIN
    PRINT '✅ PASS: Issue count matches expected';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Issue count mismatch';
    PRINT '';
END;

-- =====================================================
-- Test 5: Test All Active Servers
-- =====================================================

PRINT '======================================';
PRINT 'Test 5: Calculate for All Active Servers';
PRINT '======================================';
PRINT '';

DECLARE @TotalServers INT;
DECLARE @SuccessfulServers INT = 0;
DECLARE @FailedServers INT = 0;
DECLARE @CurrentServerID INT;
DECLARE @ServerName NVARCHAR(255);

DECLARE server_cursor CURSOR FOR
    SELECT ServerID, ServerName FROM dbo.Servers WHERE IsActive = 1;

OPEN server_cursor;
FETCH NEXT FROM server_cursor INTO @CurrentServerID, @ServerName;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC dbo.usp_CalculateHealthScore @ServerID = @CurrentServerID;
        SET @SuccessfulServers = @SuccessfulServers + 1;
        PRINT '✅ ' + @ServerName + ' (ServerID=' + CAST(@CurrentServerID AS VARCHAR) + ')';
    END TRY
    BEGIN CATCH
        SET @FailedServers = @FailedServers + 1;
        PRINT '❌ ' + @ServerName + ' (ServerID=' + CAST(@CurrentServerID AS VARCHAR) + '): ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM server_cursor INTO @CurrentServerID, @ServerName;
END;

CLOSE server_cursor;
DEALLOCATE server_cursor;

PRINT '';
PRINT 'Summary:';
PRINT '  Successful: ' + CAST(@SuccessfulServers AS VARCHAR);
PRINT '  Failed: ' + CAST(@FailedServers AS VARCHAR);
PRINT '';

IF @FailedServers = 0
BEGIN
    PRINT '✅ PASS: All servers calculated successfully';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: ' + CAST(@FailedServers AS VARCHAR) + ' servers failed';
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

GO
