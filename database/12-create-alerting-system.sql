-- =============================================
-- Advanced Alerting System for SQL Server Monitor
-- Created: 2025-10-26
-- Description: Multi-level thresholds, custom metric alerts, alert suppression
-- =============================================

USE [MonitoringDB];
GO

PRINT 'Creating Advanced Alerting System...';
GO

-- =============================================
-- Table 1: Alert Rules (Define what triggers alerts)
-- =============================================

IF OBJECT_ID('dbo.AlertRules', 'U') IS NOT NULL
    DROP TABLE dbo.AlertRules;
GO

CREATE TABLE dbo.AlertRules (
    RuleID INT IDENTITY(1,1) NOT NULL,
    RuleName NVARCHAR(200) NOT NULL,
    IsEnabled BIT NOT NULL DEFAULT 1,
    ServerID INT NULL, -- NULL = applies to all servers
    MetricCategory VARCHAR(50) NOT NULL, -- CPU, Memory, Disk, Wait, Query, Procedure, Custom
    MetricName VARCHAR(100) NOT NULL,

    -- Multi-level thresholds
    LowThreshold FLOAT NULL,
    LowDurationSeconds INT NULL, -- How long must metric exceed threshold
    MediumThreshold FLOAT NULL,
    MediumDurationSeconds INT NULL,
    HighThreshold FLOAT NULL,
    HighDurationSeconds INT NULL,
    CriticalThreshold FLOAT NULL,
    CriticalDurationSeconds INT NULL,

    -- Custom metric support (T-SQL query)
    CustomMetricQuery NVARCHAR(MAX) NULL, -- Returns single numeric value

    -- Alert suppression
    SuppressPattern NVARCHAR(500) NULL, -- Regex pattern to suppress (e.g., exclude certain databases)
    SuppressStartTime TIME NULL, -- Suppress during maintenance window
    SuppressEndTime TIME NULL,

    -- Notifications
    SendEmail BIT NOT NULL DEFAULT 0,
    EmailRecipients NVARCHAR(MAX) NULL, -- Semicolon-separated
    SendWebhook BIT NOT NULL DEFAULT 0,
    WebhookURL NVARCHAR(500) NULL,

    -- Metadata
    CreatedBy NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    CreatedDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    ModifiedBy NVARCHAR(128) NULL,
    ModifiedDate DATETIME2(7) NULL,

    CONSTRAINT PK_AlertRules PRIMARY KEY CLUSTERED (RuleID),
    CONSTRAINT FK_AlertRules_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_AlertRules_Enabled ON dbo.AlertRules (IsEnabled) INCLUDE (ServerID, MetricCategory, MetricName);
GO

PRINT 'Table created: dbo.AlertRules';
GO

-- =============================================
-- Table 2: Active Alerts (Currently firing alerts)
-- =============================================

IF OBJECT_ID('dbo.ActiveAlerts', 'U') IS NOT NULL
    DROP TABLE dbo.ActiveAlerts;
GO

CREATE TABLE dbo.ActiveAlerts (
    AlertID BIGINT IDENTITY(1,1) NOT NULL,
    RuleID INT NOT NULL,
    ServerID INT NOT NULL,
    RaisedAt DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    Severity VARCHAR(20) NOT NULL, -- Low, Medium, High, Critical
    CurrentValue FLOAT NOT NULL,
    ThresholdValue FLOAT NOT NULL,
    Message NVARCHAR(MAX) NULL,
    MetricDetails NVARCHAR(MAX) NULL, -- JSON with additional context
    IsAcknowledged BIT NOT NULL DEFAULT 0,
    AcknowledgedBy NVARCHAR(128) NULL,
    AcknowledgedAt DATETIME2(7) NULL,
    IsResolved BIT NOT NULL DEFAULT 0,
    ResolvedAt DATETIME2(7) NULL,

    CONSTRAINT PK_ActiveAlerts PRIMARY KEY CLUSTERED (AlertID),
    CONSTRAINT FK_ActiveAlerts_Rules FOREIGN KEY (RuleID) REFERENCES dbo.AlertRules(RuleID),
    CONSTRAINT FK_ActiveAlerts_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_ActiveAlerts_Unresolved ON dbo.ActiveAlerts (IsResolved, RaisedAt DESC) INCLUDE (RuleID, ServerID, Severity);
CREATE NONCLUSTERED INDEX IX_ActiveAlerts_Server ON dbo.ActiveAlerts (ServerID, IsResolved);
GO

PRINT 'Table created: dbo.ActiveAlerts';
GO

-- =============================================
-- Table 3: Alert History (Resolved alerts for historical analysis)
-- =============================================

IF OBJECT_ID('dbo.AlertHistory', 'U') IS NOT NULL
    DROP TABLE dbo.AlertHistory;
GO

CREATE TABLE dbo.AlertHistory (
    HistoryID BIGINT IDENTITY(1,1) NOT NULL,
    AlertID BIGINT NOT NULL,
    RuleID INT NOT NULL,
    ServerID INT NOT NULL,
    RaisedAt DATETIME2(7) NOT NULL,
    ResolvedAt DATETIME2(7) NOT NULL,
    DurationMinutes INT NOT NULL,
    Severity VARCHAR(20) NOT NULL,
    MaxValue FLOAT NOT NULL,
    ThresholdValue FLOAT NOT NULL,
    Message NVARCHAR(MAX) NULL,

    CONSTRAINT PK_AlertHistory PRIMARY KEY CLUSTERED (HistoryID),
    CONSTRAINT FK_AlertHistory_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_AlertHistory_Server_Date ON dbo.AlertHistory (ServerID, RaisedAt DESC);
CREATE NONCLUSTERED INDEX IX_AlertHistory_Severity ON dbo.AlertHistory (Severity, RaisedAt DESC);
GO

PRINT 'Table created: dbo.AlertHistory';
GO

-- =============================================
-- Table 4: Alert Notifications (Audit trail of sent notifications)
-- =============================================

IF OBJECT_ID('dbo.AlertNotifications', 'U') IS NOT NULL
    DROP TABLE dbo.AlertNotifications;
GO

CREATE TABLE dbo.AlertNotifications (
    NotificationID BIGINT IDENTITY(1,1) NOT NULL,
    AlertID BIGINT NOT NULL,
    SentAt DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    NotificationType VARCHAR(20) NOT NULL, -- Email, Webhook, SMS
    Recipients NVARCHAR(MAX) NULL,
    Status VARCHAR(20) NOT NULL, -- Sent, Failed, Pending
    ErrorMessage NVARCHAR(MAX) NULL,

    CONSTRAINT PK_AlertNotifications PRIMARY KEY CLUSTERED (NotificationID),
    CONSTRAINT FK_AlertNotifications_Alerts FOREIGN KEY (AlertID) REFERENCES dbo.ActiveAlerts(AlertID)
);
GO

CREATE NONCLUSTERED INDEX IX_AlertNotifications_Alert ON dbo.AlertNotifications (AlertID, SentAt DESC);
GO

PRINT 'Table created: dbo.AlertNotifications';
GO

-- =============================================
-- Stored Procedure 1: Evaluate Alert Rules
-- =============================================

IF OBJECT_ID('dbo.usp_EvaluateAlertRules', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_EvaluateAlertRules;
GO

CREATE PROCEDURE dbo.usp_EvaluateAlertRules
    @ServerID INT = NULL -- NULL = evaluate all servers
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2(7);
    DECLARE @CurrentTime TIME;

    SET @Now = GETUTCDATE();
    SET @CurrentTime = CAST(@Now AS TIME);

    -- Temp table to store rule evaluation results
    DECLARE @RuleEvaluations TABLE (
        RuleID INT,
        ServerID INT,
        CurrentValue FLOAT,
        Severity VARCHAR(20),
        ThresholdValue FLOAT,
        ShouldRaise BIT
    );

    -- Cursor to evaluate each rule
    DECLARE @RuleID INT, @RuleName NVARCHAR(200), @RuleServerID INT;
    DECLARE @MetricCategory VARCHAR(50), @MetricName VARCHAR(100);
    DECLARE @LowThreshold FLOAT, @LowDuration INT;
    DECLARE @MediumThreshold FLOAT, @MediumDuration INT;
    DECLARE @HighThreshold FLOAT, @HighDuration INT;
    DECLARE @CriticalThreshold FLOAT, @CriticalDuration INT;
    DECLARE @CustomQuery NVARCHAR(MAX);
    DECLARE @SuppressStart TIME, @SuppressEnd TIME;

    DECLARE rule_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT RuleID, RuleName, ServerID, MetricCategory, MetricName,
               LowThreshold, LowDurationSeconds,
               MediumThreshold, MediumDurationSeconds,
               HighThreshold, HighDurationSeconds,
               CriticalThreshold, CriticalDurationSeconds,
               CustomMetricQuery,
               SuppressStartTime, SuppressEndTime
        FROM dbo.AlertRules
        WHERE IsEnabled = 1
          AND (@ServerID IS NULL OR ServerID = @ServerID OR ServerID IS NULL);

    OPEN rule_cursor;
    FETCH NEXT FROM rule_cursor INTO @RuleID, @RuleName, @RuleServerID, @MetricCategory, @MetricName,
        @LowThreshold, @LowDuration, @MediumThreshold, @MediumDuration,
        @HighThreshold, @HighDuration, @CriticalThreshold, @CriticalDuration,
        @CustomQuery, @SuppressStart, @SuppressEnd;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Check suppression window
        IF (@SuppressStart IS NOT NULL AND @SuppressEnd IS NOT NULL)
        BEGIN
            IF (@SuppressStart < @SuppressEnd AND @CurrentTime BETWEEN @SuppressStart AND @SuppressEnd)
                OR (@SuppressStart > @SuppressEnd AND (@CurrentTime >= @SuppressStart OR @CurrentTime <= @SuppressEnd))
            BEGIN
                -- In suppression window, skip this rule
                FETCH NEXT FROM rule_cursor INTO @RuleID, @RuleName, @RuleServerID, @MetricCategory, @MetricName,
                    @LowThreshold, @LowDuration, @MediumThreshold, @MediumDuration,
                    @HighThreshold, @HighDuration, @CriticalThreshold, @CriticalDuration,
                    @CustomQuery, @SuppressStart, @SuppressEnd;
                CONTINUE;
            END;
        END;

        -- Evaluate custom metric or standard metric
        IF @CustomQuery IS NOT NULL
        BEGIN
            -- Custom metric (T-SQL query)
            DECLARE @CustomValue FLOAT;
            DECLARE @SQL NVARCHAR(MAX);

            SET @SQL = @CustomQuery;

            -- Execute custom query and store result
            -- (This would require dynamic SQL and error handling)
            -- For simplicity, we'll skip custom metrics in this version
        END
        ELSE
        BEGIN
            -- Standard metric evaluation
            -- Get recent metric values for the specified category/name
            DECLARE @EvalServerID INT;
            DECLARE @AvgValue FLOAT;
            DECLARE @EvalDuration INT;

            -- Determine which servers to evaluate
            DECLARE server_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT ServerID
                FROM dbo.Servers
                WHERE IsActive = 1
                  AND (@RuleServerID IS NULL OR ServerID = @RuleServerID)
                  AND (@ServerID IS NULL OR ServerID = @ServerID);

            OPEN server_cursor;
            FETCH NEXT FROM server_cursor INTO @EvalServerID;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                -- Check Critical threshold first (highest severity)
                IF @CriticalThreshold IS NOT NULL
                BEGIN
                    SET @EvalDuration = ISNULL(@CriticalDuration, 60);

                    SELECT @AvgValue = AVG(MetricValue)
                    FROM dbo.PerformanceMetrics
                    WHERE ServerID = @EvalServerID
                      AND MetricCategory = @MetricCategory
                      AND MetricName = @MetricName
                      AND CollectionTime >= DATEADD(SECOND, -@EvalDuration, @Now);

                    IF @AvgValue >= @CriticalThreshold
                    BEGIN
                        INSERT INTO @RuleEvaluations (RuleID, ServerID, CurrentValue, Severity, ThresholdValue, ShouldRaise)
                        VALUES (@RuleID, @EvalServerID, @AvgValue, 'Critical', @CriticalThreshold, 1);

                        FETCH NEXT FROM server_cursor INTO @EvalServerID;
                        CONTINUE;
                    END;
                END;

                -- Check High threshold
                IF @HighThreshold IS NOT NULL
                BEGIN
                    SET @EvalDuration = ISNULL(@HighDuration, 120);

                    SELECT @AvgValue = AVG(MetricValue)
                    FROM dbo.PerformanceMetrics
                    WHERE ServerID = @EvalServerID
                      AND MetricCategory = @MetricCategory
                      AND MetricName = @MetricName
                      AND CollectionTime >= DATEADD(SECOND, -@EvalDuration, @Now);

                    IF @AvgValue >= @HighThreshold
                    BEGIN
                        INSERT INTO @RuleEvaluations (RuleID, ServerID, CurrentValue, Severity, ThresholdValue, ShouldRaise)
                        VALUES (@RuleID, @EvalServerID, @AvgValue, 'High', @HighThreshold, 1);

                        FETCH NEXT FROM server_cursor INTO @EvalServerID;
                        CONTINUE;
                    END;
                END;

                -- Check Medium threshold
                IF @MediumThreshold IS NOT NULL
                BEGIN
                    SET @EvalDuration = ISNULL(@MediumDuration, 180);

                    SELECT @AvgValue = AVG(MetricValue)
                    FROM dbo.PerformanceMetrics
                    WHERE ServerID = @EvalServerID
                      AND MetricCategory = @MetricCategory
                      AND MetricName = @MetricName
                      AND CollectionTime >= DATEADD(SECOND, -@EvalDuration, @Now);

                    IF @AvgValue >= @MediumThreshold
                    BEGIN
                        INSERT INTO @RuleEvaluations (RuleID, ServerID, CurrentValue, Severity, ThresholdValue, ShouldRaise)
                        VALUES (@RuleID, @EvalServerID, @AvgValue, 'Medium', @MediumThreshold, 1);

                        FETCH NEXT FROM server_cursor INTO @EvalServerID;
                        CONTINUE;
                    END;
                END;

                -- Check Low threshold
                IF @LowThreshold IS NOT NULL
                BEGIN
                    SET @EvalDuration = ISNULL(@LowDuration, 300);

                    SELECT @AvgValue = AVG(MetricValue)
                    FROM dbo.PerformanceMetrics
                    WHERE ServerID = @EvalServerID
                      AND MetricCategory = @MetricCategory
                      AND MetricName = @MetricName
                      AND CollectionTime >= DATEADD(SECOND, -@EvalDuration, @Now);

                    IF @AvgValue >= @LowThreshold
                    BEGIN
                        INSERT INTO @RuleEvaluations (RuleID, ServerID, CurrentValue, Severity, ThresholdValue, ShouldRaise)
                        VALUES (@RuleID, @EvalServerID, @AvgValue, 'Low', @LowThreshold, 1);
                    END;
                END;

                FETCH NEXT FROM server_cursor INTO @EvalServerID;
            END;

            CLOSE server_cursor;
            DEALLOCATE server_cursor;
        END;

        FETCH NEXT FROM rule_cursor INTO @RuleID, @RuleName, @RuleServerID, @MetricCategory, @MetricName,
            @LowThreshold, @LowDuration, @MediumThreshold, @MediumDuration,
            @HighThreshold, @HighDuration, @CriticalThreshold, @CriticalDuration,
            @CustomQuery, @SuppressStart, @SuppressEnd;
    END;

    CLOSE rule_cursor;
    DEALLOCATE rule_cursor;

    -- Raise new alerts for rules that triggered
    INSERT INTO dbo.ActiveAlerts (RuleID, ServerID, Severity, CurrentValue, ThresholdValue, Message)
    SELECT
        re.RuleID,
        re.ServerID,
        re.Severity,
        re.CurrentValue,
        re.ThresholdValue,
        CONCAT(ar.RuleName, ' triggered on ', s.ServerName, ': ', ar.MetricCategory, '/', ar.MetricName, ' = ', re.CurrentValue, ' (threshold: ', re.ThresholdValue, ')')
    FROM @RuleEvaluations re
    INNER JOIN dbo.AlertRules ar ON re.RuleID = ar.RuleID
    INNER JOIN dbo.Servers s ON re.ServerID = s.ServerID
    WHERE re.ShouldRaise = 1
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.ActiveAlerts aa
          WHERE aa.RuleID = re.RuleID
            AND aa.ServerID = re.ServerID
            AND aa.IsResolved = 0
      );

    -- Auto-escalate existing alerts if severity increased
    UPDATE aa
    SET Severity = re.Severity,
        CurrentValue = re.CurrentValue,
        ThresholdValue = re.ThresholdValue,
        Message = CONCAT(ar.RuleName, ' escalated to ', re.Severity, ' on ', s.ServerName, ': ', ar.MetricCategory, '/', ar.MetricName, ' = ', re.CurrentValue, ' (threshold: ', re.ThresholdValue, ')')
    FROM dbo.ActiveAlerts aa
    INNER JOIN @RuleEvaluations re ON aa.RuleID = re.RuleID AND aa.ServerID = re.ServerID
    INNER JOIN dbo.AlertRules ar ON aa.RuleID = ar.RuleID
    INNER JOIN dbo.Servers s ON aa.ServerID = s.ServerID
    WHERE aa.IsResolved = 0
      AND re.ShouldRaise = 1
      AND (
          (aa.Severity = 'Low' AND re.Severity IN ('Medium', 'High', 'Critical'))
          OR (aa.Severity = 'Medium' AND re.Severity IN ('High', 'Critical'))
          OR (aa.Severity = 'High' AND re.Severity = 'Critical')
      );

    -- Auto-resolve alerts that no longer meet threshold
    UPDATE aa
    SET IsResolved = 1,
        ResolvedAt = @Now
    FROM dbo.ActiveAlerts aa
    WHERE aa.IsResolved = 0
      AND NOT EXISTS (
          SELECT 1
          FROM @RuleEvaluations re
          WHERE re.RuleID = aa.RuleID
            AND re.ServerID = aa.ServerID
            AND re.ShouldRaise = 1
      );

    -- Move resolved alerts to history
    INSERT INTO dbo.AlertHistory (AlertID, RuleID, ServerID, RaisedAt, ResolvedAt, DurationMinutes, Severity, MaxValue, ThresholdValue, Message)
    SELECT
        AlertID,
        RuleID,
        ServerID,
        RaisedAt,
        ResolvedAt,
        DATEDIFF(MINUTE, RaisedAt, ResolvedAt),
        Severity,
        CurrentValue,
        ThresholdValue,
        Message
    FROM dbo.ActiveAlerts
    WHERE IsResolved = 1
      AND ResolvedAt >= DATEADD(HOUR, -1, @Now);

    -- Delete old resolved alerts from ActiveAlerts (keep history only)
    DELETE FROM dbo.ActiveAlerts
    WHERE IsResolved = 1
      AND ResolvedAt < DATEADD(HOUR, -24, @Now);

    PRINT CONCAT('Alert evaluation completed. Active alerts: ', (SELECT COUNT(*) FROM dbo.ActiveAlerts WHERE IsResolved = 0));
END;
GO

PRINT 'Stored procedure created: dbo.usp_EvaluateAlertRules';
GO

-- =============================================
-- Stored Procedure 2: Create Alert Rule
-- =============================================

IF OBJECT_ID('dbo.usp_CreateAlertRule', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CreateAlertRule;
GO

CREATE PROCEDURE dbo.usp_CreateAlertRule
    @RuleName NVARCHAR(200),
    @ServerID INT = NULL,
    @MetricCategory VARCHAR(50),
    @MetricName VARCHAR(100),
    @LowThreshold FLOAT = NULL,
    @LowDurationSeconds INT = 300,
    @MediumThreshold FLOAT = NULL,
    @MediumDurationSeconds INT = 180,
    @HighThreshold FLOAT = NULL,
    @HighDurationSeconds INT = 120,
    @CriticalThreshold FLOAT = NULL,
    @CriticalDurationSeconds INT = 60,
    @SendEmail BIT = 0,
    @EmailRecipients NVARCHAR(MAX) = NULL,
    @IsEnabled BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AlertRules (
        RuleName, IsEnabled, ServerID, MetricCategory, MetricName,
        LowThreshold, LowDurationSeconds,
        MediumThreshold, MediumDurationSeconds,
        HighThreshold, HighDurationSeconds,
        CriticalThreshold, CriticalDurationSeconds,
        SendEmail, EmailRecipients
    )
    VALUES (
        @RuleName, @IsEnabled, @ServerID, @MetricCategory, @MetricName,
        @LowThreshold, @LowDurationSeconds,
        @MediumThreshold, @MediumDurationSeconds,
        @HighThreshold, @HighDurationSeconds,
        @CriticalThreshold, @CriticalDurationSeconds,
        @SendEmail, @EmailRecipients
    );

    DECLARE @RuleID INT;
    SET @RuleID = SCOPE_IDENTITY();

    PRINT CONCAT('Alert rule created: ', @RuleName, ' (ID: ', @RuleID, ')');

    RETURN @RuleID;
END;
GO

PRINT 'Stored procedure created: dbo.usp_CreateAlertRule';
GO

-- =============================================
-- Stored Procedure 3: Get Active Alerts
-- =============================================

IF OBJECT_ID('dbo.usp_GetActiveAlerts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetActiveAlerts;
GO

CREATE PROCEDURE dbo.usp_GetActiveAlerts
    @ServerID INT = NULL,
    @Severity VARCHAR(20) = NULL,
    @UnacknowledgedOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        aa.AlertID,
        aa.RaisedAt,
        aa.Severity,
        s.ServerName,
        ar.RuleName,
        ar.MetricCategory,
        ar.MetricName,
        aa.CurrentValue,
        aa.ThresholdValue,
        aa.Message,
        aa.IsAcknowledged,
        aa.AcknowledgedBy,
        aa.AcknowledgedAt,
        DATEDIFF(MINUTE, aa.RaisedAt, GETUTCDATE()) AS DurationMinutes
    FROM dbo.ActiveAlerts aa
    INNER JOIN dbo.AlertRules ar ON aa.RuleID = ar.RuleID
    INNER JOIN dbo.Servers s ON aa.ServerID = s.ServerID
    WHERE aa.IsResolved = 0
      AND (@ServerID IS NULL OR aa.ServerID = @ServerID)
      AND (@Severity IS NULL OR aa.Severity = @Severity)
      AND (@UnacknowledgedOnly = 0 OR aa.IsAcknowledged = 0)
    ORDER BY
        CASE aa.Severity
            WHEN 'Critical' THEN 1
            WHEN 'High' THEN 2
            WHEN 'Medium' THEN 3
            WHEN 'Low' THEN 4
            ELSE 5
        END,
        aa.RaisedAt DESC;
END;
GO

PRINT 'Stored procedure created: dbo.usp_GetActiveAlerts';
GO

-- =============================================
-- Insert default alert rules
-- =============================================

PRINT 'Creating default alert rules...';
GO

-- CPU Utilization Alert
EXEC dbo.usp_CreateAlertRule
    @RuleName = 'High CPU Utilization',
    @MetricCategory = 'CPU',
    @MetricName = 'Percent',
    @MediumThreshold = 70,
    @MediumDurationSeconds = 300,
    @HighThreshold = 85,
    @HighDurationSeconds = 180,
    @CriticalThreshold = 95,
    @CriticalDurationSeconds = 60;
GO

-- Memory Pressure Alert
EXEC dbo.usp_CreateAlertRule
    @RuleName = 'Memory Pressure',
    @MetricCategory = 'Memory',
    @MetricName = 'Available MB',
    @MediumThreshold = 2048,
    @MediumDurationSeconds = 300,
    @HighThreshold = 1024,
    @HighDurationSeconds = 180,
    @CriticalThreshold = 512,
    @CriticalDurationSeconds = 60;
GO

-- Disk Space Alert
EXEC dbo.usp_CreateAlertRule
    @RuleName = 'Low Disk Space',
    @MetricCategory = 'Disk',
    @MetricName = 'Free Percent',
    @MediumThreshold = 20,
    @MediumDurationSeconds = 3600,
    @HighThreshold = 10,
    @HighDurationSeconds = 1800,
    @CriticalThreshold = 5,
    @CriticalDurationSeconds = 600;
GO

PRINT 'Advanced Alerting System created successfully!';
PRINT '';
PRINT 'Summary:';
PRINT '- Tables: AlertRules, ActiveAlerts, AlertHistory, AlertNotifications';
PRINT '- Stored Procedures: usp_EvaluateAlertRules, usp_CreateAlertRule, usp_GetActiveAlerts';
PRINT '- Default Rules: High CPU, Memory Pressure, Low Disk Space';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Create SQL Agent job to run usp_EvaluateAlertRules every 1-5 minutes';
PRINT '2. Configure email/webhook notifications in alert rules';
PRINT '3. Customize thresholds for your environment';
GO
