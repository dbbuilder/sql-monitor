-- =====================================================
-- Phase 3 - Feature #3: Automated Alerting System Enhancements
-- Integration with Health Score and Query Performance Advisor
-- =====================================================
-- File: 60-enhance-alerting-system.sql
-- Purpose: Add notification procedures and integrate with Features #1 and #2
-- Dependencies: 12-create-alerting-system.sql, 40-create-health-score-tables.sql, 50-create-query-advisor-tables.sql
-- =====================================================

USE MonitoringDB;
GO

PRINT '======================================';
PRINT 'Enhancing Alerting System';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Stored Procedure: Send Alert Notifications
-- =====================================================

IF OBJECT_ID('dbo.usp_SendAlertNotifications', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_SendAlertNotifications;
GO

CREATE PROCEDURE dbo.usp_SendAlertNotifications
    @AlertID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RuleID INT;
    DECLARE @ServerID INT;
    DECLARE @Severity VARCHAR(20);
    DECLARE @Message NVARCHAR(MAX);
    DECLARE @SendEmail BIT;
    DECLARE @EmailRecipients NVARCHAR(MAX);
    DECLARE @SendWebhook BIT;
    DECLARE @WebhookURL NVARCHAR(500);
    DECLARE @ServerName NVARCHAR(255);
    DECLARE @RuleName NVARCHAR(200);

    -- Get alert and rule details
    SELECT
        @RuleID = aa.RuleID,
        @ServerID = aa.ServerID,
        @Severity = aa.Severity,
        @Message = aa.Message,
        @SendEmail = ar.SendEmail,
        @EmailRecipients = ar.EmailRecipients,
        @SendWebhook = ar.SendWebhook,
        @WebhookURL = ar.WebhookURL,
        @RuleName = ar.RuleName
    FROM dbo.ActiveAlerts aa
    INNER JOIN dbo.AlertRules ar ON aa.RuleID = ar.RuleID
    WHERE aa.AlertID = @AlertID;

    -- Get server name
    SELECT @ServerName = ServerName
    FROM dbo.Servers
    WHERE ServerID = @ServerID;

    -- Send Email Notification (if configured)
    IF @SendEmail = 1 AND @EmailRecipients IS NOT NULL
    BEGIN
        BEGIN TRY
            -- In production, this would use sp_send_dbmail or external service
            -- For now, just log the notification attempt
            INSERT INTO dbo.AlertNotifications (AlertID, SentAt, NotificationType, Recipients, Status, ErrorMessage)
            VALUES (@AlertID, GETUTCDATE(), 'Email', @EmailRecipients, 'Pending',
                    'Email notifications require Database Mail configuration');

            PRINT 'Email notification queued for ' + @EmailRecipients;
        END TRY
        BEGIN CATCH
            INSERT INTO dbo.AlertNotifications (AlertID, SentAt, NotificationType, Recipients, Status, ErrorMessage)
            VALUES (@AlertID, GETUTCDATE(), 'Email', @EmailRecipients, 'Failed', ERROR_MESSAGE());
        END CATCH;
    END;

    -- Send Webhook Notification (if configured)
    IF @SendWebhook = 1 AND @WebhookURL IS NOT NULL
    BEGIN
        BEGIN TRY
            -- In production, this would use CLR or external service
            -- For now, just log the notification attempt
            INSERT INTO dbo.AlertNotifications (AlertID, SentAt, NotificationType, Recipients, Status, ErrorMessage)
            VALUES (@AlertID, GETUTCDATE(), 'Webhook', @WebhookURL, 'Pending',
                    'Webhook notifications require CLR or external service');

            PRINT 'Webhook notification queued for ' + @WebhookURL;
        END TRY
        BEGIN CATCH
            INSERT INTO dbo.AlertNotifications (AlertID, SentAt, NotificationType, Recipients, Status, ErrorMessage)
            VALUES (@AlertID, GETUTCDATE(), 'Webhook', @WebhookURL, 'Failed', ERROR_MESSAGE());
        END CATCH;
    END;

    -- If no notification methods configured, log as informational
    IF @SendEmail = 0 AND @SendWebhook = 0
    BEGIN
        INSERT INTO dbo.AlertNotifications (AlertID, SentAt, NotificationType, Recipients, Status, ErrorMessage)
        VALUES (@AlertID, GETUTCDATE(), 'None', NULL, 'Sent', 'No notification methods configured for this rule');
    END;

END;
GO

PRINT '✅ Created: dbo.usp_SendAlertNotifications';
PRINT '';

-- =====================================================
-- Stored Procedure: Acknowledge Alert
-- =====================================================

IF OBJECT_ID('dbo.usp_AcknowledgeAlert', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_AcknowledgeAlert;
GO

CREATE PROCEDURE dbo.usp_AcknowledgeAlert
    @AlertID BIGINT,
    @AcknowledgedBy NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.ActiveAlerts
    SET IsAcknowledged = 1,
        AcknowledgedBy = @AcknowledgedBy,
        AcknowledgedAt = GETUTCDATE()
    WHERE AlertID = @AlertID
      AND IsAcknowledged = 0;

    IF @@ROWCOUNT > 0
        PRINT 'Alert ' + CAST(@AlertID AS VARCHAR) + ' acknowledged by ' + @AcknowledgedBy;
    ELSE
        PRINT 'Alert ' + CAST(@AlertID AS VARCHAR) + ' not found or already acknowledged';
END;
GO

PRINT '✅ Created: dbo.usp_AcknowledgeAlert';
PRINT '';

-- =====================================================
-- Stored Procedure: Get Alert Summary
-- =====================================================

IF OBJECT_ID('dbo.usp_GetAlertSummary', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetAlertSummary;
GO

CREATE PROCEDURE dbo.usp_GetAlertSummary
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        COUNT(CASE WHEN Severity = 'Critical' AND IsResolved = 0 THEN 1 END) AS CriticalAlerts,
        COUNT(CASE WHEN Severity = 'High' AND IsResolved = 0 THEN 1 END) AS HighAlerts,
        COUNT(CASE WHEN Severity = 'Medium' AND IsResolved = 0 THEN 1 END) AS MediumAlerts,
        COUNT(CASE WHEN Severity = 'Low' AND IsResolved = 0 THEN 1 END) AS LowAlerts,
        COUNT(CASE WHEN IsResolved = 0 AND IsAcknowledged = 0 THEN 1 END) AS UnacknowledgedAlerts,
        COUNT(CASE WHEN IsResolved = 0 THEN 1 END) AS TotalActiveAlerts,
        MIN(CASE WHEN IsResolved = 0 THEN RaisedAt END) AS OldestAlert,
        MAX(CASE WHEN IsResolved = 0 THEN RaisedAt END) AS NewestAlert
    FROM dbo.ActiveAlerts;
END;
GO

PRINT '✅ Created: dbo.usp_GetAlertSummary';
PRINT '';

-- =====================================================
-- Add Alert Rules for Health Score (Feature #1)
-- =====================================================

PRINT '======================================';
PRINT 'Adding Health Score Alert Rules';
PRINT '======================================';
PRINT '';

-- Health Score Degradation Alert
IF NOT EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Health Score Degradation')
BEGIN
    EXEC dbo.usp_CreateAlertRule
        @RuleName = 'Health Score Degradation',
        @MetricCategory = 'HealthScore',
        @MetricName = 'OverallScore',
        @MediumThreshold = 75,
        @MediumDurationSeconds = 900,
        @HighThreshold = 60,
        @HighDurationSeconds = 600,
        @CriticalThreshold = 40,
        @CriticalDurationSeconds = 300;

    PRINT '✅ Created: Health Score Degradation alert rule';
END
ELSE
    PRINT 'ℹ️  Health Score Degradation alert rule already exists';
GO

-- Critical Health Issues Alert
IF NOT EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Critical Health Issues')
BEGIN
    EXEC dbo.usp_CreateAlertRule
        @RuleName = 'Critical Health Issues',
        @MetricCategory = 'HealthScore',
        @MetricName = 'CriticalIssueCount',
        @MediumThreshold = 1,
        @MediumDurationSeconds = 600,
        @HighThreshold = 3,
        @HighDurationSeconds = 300,
        @CriticalThreshold = 5,
        @CriticalDurationSeconds = 180;

    PRINT '✅ Created: Critical Health Issues alert rule';
END
ELSE
    PRINT 'ℹ️  Critical Health Issues alert rule already exists';
GO

PRINT '';

-- =====================================================
-- Add Alert Rules for Query Performance Advisor (Feature #2)
-- =====================================================

PRINT '======================================';
PRINT 'Adding Query Performance Alert Rules';
PRINT '======================================';
PRINT '';

-- High-Severity Recommendations Alert
IF NOT EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'High-Severity Query Recommendations')
BEGIN
    EXEC dbo.usp_CreateAlertRule
        @RuleName = 'High-Severity Query Recommendations',
        @MetricCategory = 'QueryPerformance',
        @MetricName = 'CriticalRecommendations',
        @MediumThreshold = 3,
        @MediumDurationSeconds = 1800,
        @HighThreshold = 5,
        @HighDurationSeconds = 900,
        @CriticalThreshold = 10,
        @CriticalDurationSeconds = 600;

    PRINT '✅ Created: High-Severity Query Recommendations alert rule';
END
ELSE
    PRINT 'ℹ️  High-Severity Query Recommendations alert rule already exists';
GO

-- Plan Regressions Alert
IF NOT EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Active Plan Regressions')
BEGIN
    EXEC dbo.usp_CreateAlertRule
        @RuleName = 'Active Plan Regressions',
        @MetricCategory = 'QueryPerformance',
        @MetricName = 'UnresolvedRegressions',
        @MediumThreshold = 2,
        @MediumDurationSeconds = 1800,
        @HighThreshold = 5,
        @HighDurationSeconds = 900,
        @CriticalThreshold = 10,
        @CriticalDurationSeconds = 600;

    PRINT '✅ Created: Active Plan Regressions alert rule';
END
ELSE
    PRINT 'ℹ️  Active Plan Regressions alert rule already exists';
GO

PRINT '';

-- =====================================================
-- Add Alert Rules for Blocking and Deadlocks
-- =====================================================

PRINT '======================================';
PRINT 'Adding Blocking/Deadlock Alert Rules';
PRINT '======================================';
PRINT '';

-- Long-Running Blocking Alert
IF NOT EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Long-Running Blocking')
BEGIN
    EXEC dbo.usp_CreateAlertRule
        @RuleName = 'Long-Running Blocking',
        @MetricCategory = 'Blocking',
        @MetricName = 'MaxWaitDuration',
        @MediumThreshold = 30000,
        @MediumDurationSeconds = 300,
        @HighThreshold = 60000,
        @HighDurationSeconds = 180,
        @CriticalThreshold = 120000,
        @CriticalDurationSeconds = 120;

    PRINT '✅ Created: Long-Running Blocking alert rule';
END
ELSE
    PRINT 'ℹ️  Long-Running Blocking alert rule already exists';
GO

-- Deadlock Frequency Alert
IF NOT EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'High Deadlock Frequency')
BEGIN
    EXEC dbo.usp_CreateAlertRule
        @RuleName = 'High Deadlock Frequency',
        @MetricCategory = 'Deadlocks',
        @MetricName = 'DeadlocksPerHour',
        @MediumThreshold = 5,
        @MediumDurationSeconds = 3600,
        @HighThreshold = 10,
        @HighDurationSeconds = 1800,
        @CriticalThreshold = 20,
        @CriticalDurationSeconds = 900;

    PRINT '✅ Created: High Deadlock Frequency alert rule';
END
ELSE
    PRINT 'ℹ️  High Deadlock Frequency alert rule already exists';
GO

PRINT '';

-- =====================================================
-- Add Alert Rules for Index Maintenance
-- =====================================================

PRINT '======================================';
PRINT 'Adding Index Maintenance Alert Rules';
PRINT '======================================';
PRINT '';

-- High Index Fragmentation Alert
IF NOT EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'High Index Fragmentation')
BEGIN
    EXEC dbo.usp_CreateAlertRule
        @RuleName = 'High Index Fragmentation',
        @MetricCategory = 'Index',
        @MetricName = 'AvgFragmentation',
        @MediumThreshold = 30,
        @MediumDurationSeconds = 86400,
        @HighThreshold = 50,
        @HighDurationSeconds = 43200,
        @CriticalThreshold = 70,
        @CriticalDurationSeconds = 21600;

    PRINT '✅ Created: High Index Fragmentation alert rule';
END
ELSE
    PRINT 'ℹ️  High Index Fragmentation alert rule already exists';
GO

-- Missing Indexes Alert
IF NOT EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'High-Impact Missing Indexes')
BEGIN
    EXEC dbo.usp_CreateAlertRule
        @RuleName = 'High-Impact Missing Indexes',
        @MetricCategory = 'Index',
        @MetricName = 'MissingIndexCount',
        @MediumThreshold = 10,
        @MediumDurationSeconds = 86400,
        @HighThreshold = 20,
        @HighDurationSeconds = 43200,
        @CriticalThreshold = 50,
        @CriticalDurationSeconds = 21600;

    PRINT '✅ Created: High-Impact Missing Indexes alert rule';
END
ELSE
    PRINT 'ℹ️  High-Impact Missing Indexes alert rule already exists';
GO

PRINT '';

-- =====================================================
-- Summary
-- =====================================================

PRINT '======================================';
PRINT 'Alert System Enhancement Complete';
PRINT '======================================';
PRINT '';
PRINT 'Summary:';
PRINT '  ✅ Notification procedures: usp_SendAlertNotifications, usp_AcknowledgeAlert, usp_GetAlertSummary';
PRINT '  ✅ Health Score alerts: 2 new rules';
PRINT '  ✅ Query Performance alerts: 2 new rules';
PRINT '  ✅ Blocking/Deadlock alerts: 2 new rules';
PRINT '  ✅ Index Maintenance alerts: 2 new rules';
PRINT '';
PRINT 'Total Alert Rules:';

SELECT COUNT(*) AS TotalRules,
       SUM(CASE WHEN IsEnabled = 1 THEN 1 ELSE 0 END) AS EnabledRules
FROM dbo.AlertRules;

PRINT '';
PRINT 'Alert Rules by Category:';

SELECT MetricCategory, COUNT(*) AS RuleCount
FROM dbo.AlertRules
WHERE IsEnabled = 1
GROUP BY MetricCategory
ORDER BY RuleCount DESC;

PRINT '';
PRINT '======================================';
PRINT 'Next Steps:';
PRINT '1. Configure email/webhook recipients for critical rules';
PRINT '2. Test alert generation with synthetic threshold violations';
PRINT '3. Create Grafana dashboard for alert visualization';
PRINT '4. Write user documentation';
PRINT '======================================';
PRINT '';

GO
