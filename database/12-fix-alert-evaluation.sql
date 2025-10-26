-- =============================================
-- Fix: usp_EvaluateAlertRules - Remove inline computations
-- Created: 2025-10-26
-- =============================================

USE [MonitoringDB];
GO

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

        -- Evaluate standard metrics (skip custom metrics for now)
        IF @CustomQuery IS NULL
        BEGIN
            -- Determine which servers to evaluate
            DECLARE @EvalServerID INT;
            DECLARE @AvgValue FLOAT;
            DECLARE @EvalDuration INT;

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
                    -- FIX: Pre-compute duration value
                    IF @CriticalDuration IS NULL
                        SET @EvalDuration = 60;
                    ELSE
                        SET @EvalDuration = @CriticalDuration;

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
                    -- FIX: Pre-compute duration value
                    IF @HighDuration IS NULL
                        SET @EvalDuration = 120;
                    ELSE
                        SET @EvalDuration = @HighDuration;

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
                    -- FIX: Pre-compute duration value
                    IF @MediumDuration IS NULL
                        SET @EvalDuration = 180;
                    ELSE
                        SET @EvalDuration = @MediumDuration;

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
                    -- FIX: Pre-compute duration value
                    IF @LowDuration IS NULL
                        SET @EvalDuration = 300;
                    ELSE
                        SET @EvalDuration = @LowDuration;

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

    DECLARE @NewAlerts INT;
    SET @NewAlerts = @@ROWCOUNT;

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

    DECLARE @Escalated INT;
    SET @Escalated = @@ROWCOUNT;

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

    DECLARE @Resolved INT;
    SET @Resolved = @@ROWCOUNT;

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

    DECLARE @ActiveCount INT;
    SELECT @ActiveCount = COUNT(*)
    FROM dbo.ActiveAlerts
    WHERE IsResolved = 0;

    PRINT CONCAT('Alert evaluation completed. New: ', @NewAlerts, ', Escalated: ', @Escalated, ', Resolved: ', @Resolved, ', Active: ', @ActiveCount);
END;
GO

PRINT 'Stored procedure fixed: dbo.usp_EvaluateAlertRules';
PRINT 'Fixed inline computation constraints (ISNULL replaced with IF/ELSE)';
GO
