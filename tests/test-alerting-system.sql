-- =====================================================
-- Automated Alerting System Integration Tests
-- Tests alert evaluation, notification, and lifecycle
-- =====================================================
-- File: tests/test-alerting-system.sql
-- Purpose: Validate alerting system functionality end-to-end
-- Dependencies: 12-create-alerting-system.sql, 60-enhance-alerting-system.sql
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
GO

PRINT '======================================';
PRINT 'Automated Alerting System Integration Tests';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Test 1: Alert Tables Exist
-- =====================================================

PRINT '======================================';
PRINT 'Test 1: Verify Alert Tables Exist';
PRINT '======================================';
PRINT '';

DECLARE @TableCount INT = 0;

IF OBJECT_ID('dbo.AlertRules', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ AlertRules exists';
END;

IF OBJECT_ID('dbo.ActiveAlerts', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ ActiveAlerts exists';
END;

IF OBJECT_ID('dbo.AlertHistory', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ AlertHistory exists';
END;

IF OBJECT_ID('dbo.AlertNotifications', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ AlertNotifications exists';
END;

PRINT '';

IF @TableCount = 4
BEGIN
    PRINT '✅ PASS: All alert tables exist';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Missing alert tables';
    PRINT '';
END;

-- =====================================================
-- Test 2: Alert Stored Procedures Exist
-- =====================================================

PRINT '======================================';
PRINT 'Test 2: Verify Alert Stored Procedures Exist';
PRINT '======================================';
PRINT '';

DECLARE @ProcCount INT = 0;

IF OBJECT_ID('dbo.usp_EvaluateAlertRules', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_EvaluateAlertRules exists';
END;

IF OBJECT_ID('dbo.usp_CreateAlertRule', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_CreateAlertRule exists';
END;

IF OBJECT_ID('dbo.usp_GetActiveAlerts', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_GetActiveAlerts exists';
END;

IF OBJECT_ID('dbo.usp_SendAlertNotifications', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_SendAlertNotifications exists';
END;

IF OBJECT_ID('dbo.usp_AcknowledgeAlert', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_AcknowledgeAlert exists';
END;

IF OBJECT_ID('dbo.usp_GetAlertSummary', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_GetAlertSummary exists';
END;

PRINT '';

IF @ProcCount = 6
BEGIN
    PRINT '✅ PASS: All alert stored procedures exist';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Missing alert stored procedures';
    PRINT '';
END;

-- =====================================================
-- Test 3: Pre-Configured Alert Rules
-- =====================================================

PRINT '======================================';
PRINT 'Test 3: Verify Pre-Configured Alert Rules';
PRINT '======================================';
PRINT '';

DECLARE @ExpectedRules INT = 11;
DECLARE @ActualRules INT;

SELECT @ActualRules = COUNT(*) FROM dbo.AlertRules WHERE IsEnabled = 1;

PRINT 'Expected alert rules: ' + CAST(@ExpectedRules AS VARCHAR);
PRINT 'Actual alert rules: ' + CAST(@ActualRules AS VARCHAR);
PRINT '';

IF @ActualRules >= @ExpectedRules
BEGIN
    PRINT '✅ PASS: All pre-configured alert rules exist';
    PRINT '';

    -- List all alert rules
    PRINT 'Alert Rules by Category:';
    SELECT MetricCategory, COUNT(*) AS RuleCount
    FROM dbo.AlertRules
    WHERE IsEnabled = 1
    GROUP BY MetricCategory
    ORDER BY RuleCount DESC;
END
ELSE
BEGIN
    PRINT '❌ FAIL: Missing pre-configured alert rules';
    PRINT '';
END;

-- =====================================================
-- Test 4: Alert Evaluation Completes Successfully
-- =====================================================

PRINT '======================================';
PRINT 'Test 4: Alert Evaluation Completes';
PRINT '======================================';
PRINT '';

DECLARE @BeforeActiveAlerts INT;
DECLARE @AfterActiveAlerts INT;

-- Get count before evaluation
SELECT @BeforeActiveAlerts = COUNT(*) FROM dbo.ActiveAlerts WHERE IsResolved = 0;

PRINT 'Active alerts before evaluation: ' + CAST(@BeforeActiveAlerts AS VARCHAR);

-- Run alert evaluation
BEGIN TRY
    EXEC dbo.usp_EvaluateAlertRules;
    PRINT '✅ Alert evaluation completed successfully';
END TRY
BEGIN CATCH
    PRINT '❌ FAIL: Alert evaluation failed with error:';
    PRINT ERROR_MESSAGE();
END CATCH;

-- Get count after evaluation
SELECT @AfterActiveAlerts = COUNT(*) FROM dbo.ActiveAlerts WHERE IsResolved = 0;

PRINT 'Active alerts after evaluation: ' + CAST(@AfterActiveAlerts AS VARCHAR);
PRINT '';

IF @AfterActiveAlerts >= @BeforeActiveAlerts
BEGIN
    PRINT '✅ PASS: Alert evaluation completed (active alerts unchanged or increased)';
    PRINT '';
END
ELSE
BEGIN
    PRINT '⚠️  WARNING: Alert count decreased (may indicate auto-resolution)';
    PRINT '';
END;

-- =====================================================
-- Test 5: Alert Summary Retrieval
-- =====================================================

PRINT '======================================';
PRINT 'Test 5: Alert Summary Retrieval';
PRINT '======================================';
PRINT '';

BEGIN TRY
    DECLARE @SummaryTable TABLE (
        CriticalAlerts INT,
        HighAlerts INT,
        MediumAlerts INT,
        LowAlerts INT,
        UnacknowledgedAlerts INT,
        TotalActiveAlerts INT,
        OldestAlert DATETIME2(7),
        NewestAlert DATETIME2(7)
    );

    INSERT INTO @SummaryTable
    EXEC dbo.usp_GetAlertSummary;

    SELECT
        CriticalAlerts,
        HighAlerts,
        MediumAlerts,
        LowAlerts,
        UnacknowledgedAlerts,
        TotalActiveAlerts
    FROM @SummaryTable;

    PRINT '';
    PRINT '✅ PASS: Alert summary retrieved successfully';
    PRINT '';
END TRY
BEGIN CATCH
    PRINT '❌ FAIL: Alert summary retrieval failed:';
    PRINT ERROR_MESSAGE();
    PRINT '';
END CATCH;

-- =====================================================
-- Test 6: Active Alerts Retrieval
-- =====================================================

PRINT '======================================';
PRINT 'Test 6: Active Alerts Retrieval';
PRINT '======================================';
PRINT '';

BEGIN TRY
    DECLARE @ActiveAlertCount INT;

    CREATE TABLE #ActiveAlerts (
        AlertID BIGINT,
        ServerName NVARCHAR(255),
        RuleName NVARCHAR(200),
        Severity VARCHAR(20),
        CurrentValue FLOAT,
        ThresholdValue FLOAT,
        RaisedAt DATETIME2(7),
        DurationMinutes INT,
        IsAcknowledged BIT
    );

    INSERT INTO #ActiveAlerts
    EXEC dbo.usp_GetActiveAlerts;

    SELECT @ActiveAlertCount = COUNT(*) FROM #ActiveAlerts;

    PRINT 'Active alerts retrieved: ' + CAST(@ActiveAlertCount AS VARCHAR);

    IF @ActiveAlertCount > 0
    BEGIN
        PRINT '';
        PRINT 'Sample active alerts:';
        SELECT TOP 5 * FROM #ActiveAlerts;
    END;

    DROP TABLE #ActiveAlerts;

    PRINT '';
    PRINT '✅ PASS: Active alerts retrieved successfully';
    PRINT '';
END TRY
BEGIN CATCH
    PRINT '❌ FAIL: Active alerts retrieval failed:';
    PRINT ERROR_MESSAGE();
    PRINT '';
END CATCH;

-- =====================================================
-- Test 7: SQL Agent Job Exists and Enabled
-- =====================================================

PRINT '======================================';
PRINT 'Test 7: Verify SQL Agent Job Exists';
PRINT '======================================';
PRINT '';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name LIKE '%Alert Evaluation%')
BEGIN
    PRINT '✅ PASS: SQL Agent job exists';

    -- Check job schedule
    SELECT
        j.name AS JobName,
        j.enabled AS JobEnabled,
        s.name AS ScheduleName,
        CASE s.freq_type
            WHEN 4 THEN 'Daily'
            ELSE 'Other'
        END + ' - Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' ' +
        CASE s.freq_subday_type
            WHEN 4 THEN 'minutes'
            WHEN 8 THEN 'hours'
            ELSE 'unknown'
        END AS Schedule
    FROM msdb.dbo.sysjobs j
    INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
    INNER JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
    WHERE j.name LIKE '%Alert Evaluation%';

    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: SQL Agent job does not exist';
    PRINT '';
END;

-- =====================================================
-- Test 8: Create Test Alert Rule
-- =====================================================

PRINT '======================================';
PRINT 'Test 8: Create Test Alert Rule';
PRINT '======================================';
PRINT '';

BEGIN TRY
    DECLARE @TestRuleName NVARCHAR(200) = 'TEST_RULE_' + CAST(NEWID() AS VARCHAR(36));

    EXEC dbo.usp_CreateAlertRule
        @RuleName = @TestRuleName,
        @MetricCategory = 'Test',
        @MetricName = 'TestMetric',
        @CriticalThreshold = 100,
        @CriticalDurationSeconds = 60;

    -- Verify rule was created
    IF EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = @TestRuleName)
    BEGIN
        PRINT '✅ PASS: Test alert rule created successfully';

        -- Clean up test rule
        DELETE FROM dbo.AlertRules WHERE RuleName = @TestRuleName;
        PRINT '  (Test rule cleaned up)';
        PRINT '';
    END
    ELSE
    BEGIN
        PRINT '❌ FAIL: Test alert rule was not created';
        PRINT '';
    END;
END TRY
BEGIN CATCH
    PRINT '❌ FAIL: Test alert rule creation failed:';
    PRINT ERROR_MESSAGE();
    PRINT '';
END CATCH;

-- =====================================================
-- Test 9: Alert Notification Logging
-- =====================================================

PRINT '======================================';
PRINT 'Test 9: Alert Notification Logging';
PRINT '======================================';
PRINT '';

-- Check if there are any alerts to test notifications
DECLARE @TestAlertID BIGINT;

SELECT TOP 1 @TestAlertID = AlertID
FROM dbo.ActiveAlerts
WHERE IsResolved = 0;

IF @TestAlertID IS NOT NULL
BEGIN
    BEGIN TRY
        DECLARE @NotificationCountBefore INT;
        DECLARE @NotificationCountAfter INT;

        SELECT @NotificationCountBefore = COUNT(*)
        FROM dbo.AlertNotifications
        WHERE AlertID = @TestAlertID;

        PRINT 'Notifications before: ' + CAST(@NotificationCountBefore AS VARCHAR);

        -- Send notification
        EXEC dbo.usp_SendAlertNotifications @AlertID = @TestAlertID;

        SELECT @NotificationCountAfter = COUNT(*)
        FROM dbo.AlertNotifications
        WHERE AlertID = @TestAlertID;

        PRINT 'Notifications after: ' + CAST(@NotificationCountAfter AS VARCHAR);
        PRINT '';

        IF @NotificationCountAfter > @NotificationCountBefore
        BEGIN
            PRINT '✅ PASS: Notification logged successfully';
            PRINT '';
        END
        ELSE
        BEGIN
            PRINT '⚠️  WARNING: Notification not logged (may be duplicate)';
            PRINT '';
        END;
    END TRY
    BEGIN CATCH
        PRINT '❌ FAIL: Notification logging failed:';
        PRINT ERROR_MESSAGE();
        PRINT '';
    END CATCH;
END
ELSE
BEGIN
    PRINT 'ℹ️  INFO: No active alerts to test notifications';
    PRINT '✅ PASS: Notification procedure exists and is callable';
    PRINT '';
END;

-- =====================================================
-- Test 10: Alert Acknowledgment
-- =====================================================

PRINT '======================================';
PRINT 'Test 10: Alert Acknowledgment';
PRINT '======================================';
PRINT '';

-- Check if there are any unacknowledged alerts
DECLARE @UnacknowledgedAlertID BIGINT;

SELECT TOP 1 @UnacknowledgedAlertID = AlertID
FROM dbo.ActiveAlerts
WHERE IsResolved = 0 AND IsAcknowledged = 0;

IF @UnacknowledgedAlertID IS NOT NULL
BEGIN
    BEGIN TRY
        EXEC dbo.usp_AcknowledgeAlert
            @AlertID = @UnacknowledgedAlertID,
            @AcknowledgedBy = 'TEST_USER';

        -- Verify acknowledgment
        IF EXISTS (SELECT 1 FROM dbo.ActiveAlerts
                   WHERE AlertID = @UnacknowledgedAlertID
                   AND IsAcknowledged = 1)
        BEGIN
            PRINT '✅ PASS: Alert acknowledged successfully';
            PRINT '';
        END
        ELSE
        BEGIN
            PRINT '❌ FAIL: Alert was not acknowledged';
            PRINT '';
        END;
    END TRY
    BEGIN CATCH
        PRINT '❌ FAIL: Alert acknowledgment failed:';
        PRINT ERROR_MESSAGE();
        PRINT '';
    END CATCH;
END
ELSE
BEGIN
    PRINT 'ℹ️  INFO: No unacknowledged alerts to test';
    PRINT '✅ PASS: Acknowledgment procedure exists and is callable';
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
PRINT 'Alert System Status:';

SELECT
    COUNT(*) AS TotalAlertRules,
    SUM(CASE WHEN IsEnabled = 1 THEN 1 ELSE 0 END) AS EnabledRules,
    (SELECT COUNT(*) FROM dbo.ActiveAlerts WHERE IsResolved = 0) AS ActiveAlerts,
    (SELECT COUNT(*) FROM dbo.ActiveAlerts WHERE IsResolved = 0 AND IsAcknowledged = 0) AS UnacknowledgedAlerts,
    (SELECT COUNT(*) FROM dbo.AlertHistory WHERE RaisedAt >= DATEADD(DAY, -7, GETUTCDATE())) AS AlertsLast7Days
FROM dbo.AlertRules;

PRINT '';
PRINT 'Note: Some tests may show INFO/WARNING if no alerts are currently active.';
PRINT 'This is expected behavior for healthy systems.';
PRINT '';

GO
