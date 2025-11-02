-- =====================================================
-- Feature Integration: Alerting System + Baseline Comparison
-- Create alert rules for anomaly detection
-- =====================================================
-- File: 73-integrate-alerting-with-baselines.sql
-- Purpose: Integrate Feature #3 (Alerting) with Feature #4 (Baseline Comparison)
-- Dependencies: 60-enhance-alerting-system.sql, 71-create-baseline-procedures.sql
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
GO

PRINT '======================================';
PRINT 'Integrating Alerting with Baseline Comparison';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Step 1: Extend AlertRules to Support Anomaly Queries
-- =====================================================

PRINT 'Step 1: Checking AlertRules table schema...';
PRINT '';

-- Check if AlertRules supports custom queries (it should from Feature #3)
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.AlertRules')
    AND name = 'CustomQuery'
)
BEGIN
    PRINT '  Adding CustomQuery column to AlertRules table...';

    ALTER TABLE dbo.AlertRules
    ADD CustomQuery NVARCHAR(MAX) NULL;

    PRINT '  ✅ CustomQuery column added';
    PRINT '';
END
ELSE
BEGIN
    PRINT '  ✅ AlertRules table already supports custom queries';
    PRINT '';
END;

-- =====================================================
-- Step 2: Create Alert Rules for Anomaly Detection
-- =====================================================

PRINT '======================================';
PRINT 'Step 2: Creating Anomaly-Based Alert Rules';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Alert Rule 1: Critical Anomaly Detected
-- =====================================================

IF EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Critical Anomaly Detected')
BEGIN
    DELETE FROM dbo.AlertRules WHERE RuleName = 'Critical Anomaly Detected';
    PRINT '  Removed existing rule: Critical Anomaly Detected';
END;

INSERT INTO dbo.AlertRules (
    RuleName,
    MetricCategory,
    MetricName,
    CriticalThreshold,
    CriticalDurationSeconds,
    IsEnabled,
    CustomMetricQuery
)
VALUES (
    'Critical Anomaly Detected',
    'Anomaly',
    'CriticalCount',
    1.0, -- Alert if 1+ critical anomalies exist
    300, -- Sustained for 5 minutes
    1,   -- Enabled
    'SELECT ServerID, COUNT(*) AS MetricValue FROM dbo.AnomalyDetections WHERE IsResolved = 0 AND Severity = ''Critical'' GROUP BY ServerID HAVING COUNT(*) >= 1'
);

PRINT '  ✅ Created: Critical Anomaly Detected';
PRINT '';

-- =====================================================
-- Alert Rule 2: High Severity Anomaly Detected
-- =====================================================

IF EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'High Severity Anomaly Detected')
BEGIN
    DELETE FROM dbo.AlertRules WHERE RuleName = 'High Severity Anomaly Detected';
    PRINT '  Removed existing rule: High Severity Anomaly Detected';
END;

INSERT INTO dbo.AlertRules (
    RuleName,
    MetricCategory,
    MetricName,
    HighThreshold,
    HighDurationSeconds,
    IsEnabled,
    CustomMetricQuery
)
VALUES (
    'High Severity Anomaly Detected',
    'Anomaly',
    'HighCount',
    3.0, -- Alert if 3+ high anomalies exist
    600, -- Sustained for 10 minutes
    1,   -- Enabled
    'SELECT ServerID, COUNT(*) AS MetricValue FROM dbo.AnomalyDetections WHERE IsResolved = 0 AND Severity = ''High'' GROUP BY ServerID HAVING COUNT(*) >= 3'
);

PRINT '  ✅ Created: High Severity Anomaly Detected';
PRINT '';

-- =====================================================
-- Alert Rule 3: Multiple Simultaneous Anomalies
-- =====================================================

IF EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Multiple Simultaneous Anomalies')
BEGIN
    DELETE FROM dbo.AlertRules WHERE RuleName = 'Multiple Simultaneous Anomalies';
    PRINT '  Removed existing rule: Multiple Simultaneous Anomalies';
END;

INSERT INTO dbo.AlertRules (
    RuleName,
    MetricCategory,
    MetricName,
    HighThreshold,
    CriticalThreshold,
    HighDurationSeconds,
    CriticalDurationSeconds,
    IsEnabled,
    CustomMetricQuery
)
VALUES (
    'Multiple Simultaneous Anomalies',
    'Anomaly',
    'MultipleCategories',
    5.0,  -- Warning if 5+ anomalies
    10.0, -- Critical if 10+ anomalies
    300,  -- High: 5 minutes
    180,  -- Critical: 3 minutes
    1,    -- Enabled
    'SELECT ServerID, COUNT(*) AS MetricValue FROM dbo.AnomalyDetections WHERE IsResolved = 0 GROUP BY ServerID HAVING COUNT(*) >= 5'
);

PRINT '  ✅ Created: Multiple Simultaneous Anomalies';
PRINT '';

-- =====================================================
-- Alert Rule 4: CPU Anomaly (Spike)
-- =====================================================

IF EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'CPU Anomaly - Sustained Spike')
BEGIN
    DELETE FROM dbo.AlertRules WHERE RuleName = 'CPU Anomaly - Sustained Spike';
    PRINT '  Removed existing rule: CPU Anomaly - Sustained Spike';
END;

INSERT INTO dbo.AlertRules (
    RuleName,
    MetricCategory,
    MetricName,
    HighThreshold,
    CriticalThreshold,
    HighDurationSeconds,
    CriticalDurationSeconds,
    IsEnabled,
    CustomMetricQuery
)
VALUES (
    'CPU Anomaly - Sustained Spike',
    'Anomaly',
    'CPUSpike',
    1.0,  -- High if 1+ CPU anomaly
    2.0,  -- Critical if 2+ CPU anomalies (multiple cores/metrics)
    600,  -- High: 10 minutes
    300,  -- Critical: 5 minutes
    1,    -- Enabled
    'SELECT ServerID, COUNT(*) AS MetricValue FROM dbo.AnomalyDetections WHERE IsResolved = 0 AND MetricCategory = ''CPU'' AND AnomalyType = ''Spike'' AND Severity IN (''High'', ''Critical'') GROUP BY ServerID HAVING COUNT(*) >= 1'
);

PRINT '  ✅ Created: CPU Anomaly - Sustained Spike';
PRINT '';

-- =====================================================
-- Alert Rule 5: Memory Anomaly (Drop)
-- =====================================================

IF EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Memory Anomaly - Significant Drop')
BEGIN
    DELETE FROM dbo.AlertRules WHERE RuleName = 'Memory Anomaly - Significant Drop';
    PRINT '  Removed existing rule: Memory Anomaly - Significant Drop';
END;

INSERT INTO dbo.AlertRules (
    RuleName,
    MetricCategory,
    MetricName,
    HighThreshold,
    CriticalThreshold,
    HighDurationSeconds,
    CriticalDurationSeconds,
    IsEnabled,
    CustomMetricQuery
)
VALUES (
    'Memory Anomaly - Significant Drop',
    'Anomaly',
    'MemoryDrop',
    1.0,  -- High if 1+ memory anomaly
    2.0,  -- Critical if 2+ memory anomalies
    600,  -- High: 10 minutes
    300,  -- Critical: 5 minutes
    1,    -- Enabled
    'SELECT ServerID, COUNT(*) AS MetricValue FROM dbo.AnomalyDetections WHERE IsResolved = 0 AND MetricCategory = ''Memory'' AND AnomalyType = ''Drop'' AND Severity IN (''High'', ''Critical'') GROUP BY ServerID HAVING COUNT(*) >= 1'
);

PRINT '  ✅ Created: Memory Anomaly - Significant Drop';
PRINT '';

-- =====================================================
-- Alert Rule 6: Disk I/O Anomaly
-- =====================================================

IF EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Disk I/O Anomaly - High Latency')
BEGIN
    DELETE FROM dbo.AlertRules WHERE RuleName = 'Disk I/O Anomaly - High Latency';
    PRINT '  Removed existing rule: Disk I/O Anomaly - High Latency';
END;

INSERT INTO dbo.AlertRules (
    RuleName,
    MetricCategory,
    MetricName,
    HighThreshold,
    CriticalThreshold,
    HighDurationSeconds,
    CriticalDurationSeconds,
    IsEnabled,
    CustomMetricQuery
)
VALUES (
    'Disk I/O Anomaly - High Latency',
    'Anomaly',
    'DiskLatency',
    1.0,  -- High if 1+ disk anomaly
    3.0,  -- Critical if 3+ disk anomalies (multiple disks)
    900,  -- High: 15 minutes
    600,  -- Critical: 10 minutes
    1,    -- Enabled
    'SELECT ServerID, COUNT(*) AS MetricValue FROM dbo.AnomalyDetections WHERE IsResolved = 0 AND MetricCategory = ''Disk'' AND AnomalyType = ''Spike'' AND Severity IN (''High'', ''Critical'') GROUP BY ServerID HAVING COUNT(*) >= 1'
);

PRINT '  ✅ Created: Disk I/O Anomaly - High Latency';
PRINT '';

-- =====================================================
-- Alert Rule 7: Wait Stats Anomaly
-- =====================================================

IF EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Wait Stats Anomaly - Abnormal Waits')
BEGIN
    DELETE FROM dbo.AlertRules WHERE RuleName = 'Wait Stats Anomaly - Abnormal Waits';
    PRINT '  Removed existing rule: Wait Stats Anomaly - Abnormal Waits';
END;

INSERT INTO dbo.AlertRules (
    RuleName,
    MetricCategory,
    MetricName,
    HighThreshold,
    CriticalThreshold,
    HighDurationSeconds,
    CriticalDurationSeconds,
    IsEnabled,
    CustomMetricQuery
)
VALUES (
    'Wait Stats Anomaly - Abnormal Waits',
    'Anomaly',
    'WaitStats',
    2.0,  -- High if 2+ wait stat anomalies
    5.0,  -- Critical if 5+ wait stat anomalies
    600,  -- High: 10 minutes
    300,  -- Critical: 5 minutes
    1,    -- Enabled
    'SELECT ServerID, COUNT(*) AS MetricValue FROM dbo.AnomalyDetections WHERE IsResolved = 0 AND (MetricCategory = ''WaitStats'' OR MetricCategory = ''Wait'') AND AnomalyType = ''Spike'' AND Severity IN (''High'', ''Critical'') GROUP BY ServerID HAVING COUNT(*) >= 2'
);

PRINT '  ✅ Created: Wait Stats Anomaly - Abnormal Waits';
PRINT '';

-- =====================================================
-- Alert Rule 8: Health Score Anomaly
-- =====================================================

IF EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Health Score Anomaly - Score Degradation')
BEGIN
    DELETE FROM dbo.AlertRules WHERE RuleName = 'Health Score Anomaly - Score Degradation';
    PRINT '  Removed existing rule: Health Score Anomaly - Score Degradation';
END;

INSERT INTO dbo.AlertRules (
    RuleName,
    MetricCategory,
    MetricName,
    HighThreshold,
    CriticalThreshold,
    HighDurationSeconds,
    CriticalDurationSeconds,
    IsEnabled,
    CustomMetricQuery
)
VALUES (
    'Health Score Anomaly - Score Degradation',
    'Anomaly',
    'HealthScore',
    1.0,  -- High if 1+ health score anomaly
    2.0,  -- Critical if 2+ health score anomalies
    900,  -- High: 15 minutes
    600,  -- Critical: 10 minutes
    1,    -- Enabled
    'SELECT ServerID, COUNT(*) AS MetricValue FROM dbo.AnomalyDetections WHERE IsResolved = 0 AND MetricCategory = ''Health'' AND AnomalyType = ''Drop'' AND Severity IN (''High'', ''Critical'') GROUP BY ServerID HAVING COUNT(*) >= 1'
);

PRINT '  ✅ Created: Health Score Anomaly - Score Degradation';
PRINT '';

-- =====================================================
-- Step 3: Create Helper Procedure for Anomaly Alert Evaluation
-- =====================================================

PRINT '======================================';
PRINT 'Step 3: Creating Anomaly Alert Evaluation Procedure';
PRINT '======================================';
PRINT '';

IF OBJECT_ID('dbo.usp_EvaluateAnomalyAlerts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_EvaluateAnomalyAlerts;
GO

CREATE PROCEDURE dbo.usp_EvaluateAnomalyAlerts
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AlertsRaised INT = 0;
    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();

    PRINT 'Evaluating anomaly-based alert rules...';
    PRINT '';

    -- Evaluate alert rules for anomaly category
    -- This uses the existing usp_EvaluateAlertRules with a filter
    DECLARE @RuleID INT;
    DECLARE @RuleName NVARCHAR(255);
    DECLARE @CustomQuery NVARCHAR(MAX);
    DECLARE @MetricValue DECIMAL(18,4);
    DECLARE @ServerID INT;

    DECLARE rule_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT RuleID, RuleName, CustomMetricQuery
        FROM dbo.AlertRules
        WHERE IsEnabled = 1
          AND MetricCategory = 'Anomaly'
          AND CustomMetricQuery IS NOT NULL
        ORDER BY RuleName;

    OPEN rule_cursor;
    FETCH NEXT FROM rule_cursor INTO @RuleID, @RuleName, @CustomQuery;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Execute custom query to get metric values
            CREATE TABLE #AnomalyMetrics (
                ServerID INT,
                MetricValue DECIMAL(18,4)
            );

            INSERT INTO #AnomalyMetrics (ServerID, MetricValue)
            EXEC sp_executesql @CustomQuery;

            -- Check each server's anomaly count against thresholds
            DECLARE metric_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT ServerID, MetricValue
                FROM #AnomalyMetrics;

            OPEN metric_cursor;
            FETCH NEXT FROM metric_cursor INTO @ServerID, @MetricValue;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                -- Get thresholds for this rule
                DECLARE @HighThreshold DECIMAL(18,4);
                DECLARE @CriticalThreshold DECIMAL(18,4);
                DECLARE @Severity VARCHAR(20);

                SELECT
                    @HighThreshold = HighThreshold,
                    @CriticalThreshold = CriticalThreshold
                FROM dbo.AlertRules
                WHERE RuleID = @RuleID;

                -- Determine severity
                IF @MetricValue >= @CriticalThreshold
                    SET @Severity = 'Critical';
                ELSE IF @MetricValue >= @HighThreshold
                    SET @Severity = 'High';
                ELSE
                    SET @Severity = NULL;

                -- Raise alert if threshold exceeded
                IF @Severity IS NOT NULL
                BEGIN
                    -- Check if alert already exists
                    IF NOT EXISTS (
                        SELECT 1 FROM dbo.ActiveAlerts
                        WHERE RuleID = @RuleID
                          AND ServerID = @ServerID
                          AND IsResolved = 0
                    )
                    BEGIN
                        -- Create new alert
                        DECLARE @AlertMessage NVARCHAR(MAX);
                        SET @AlertMessage = @RuleName + ': ' + CAST(@MetricValue AS VARCHAR) + ' anomalies detected';

                        -- Insert into ActiveAlerts first (generates AlertID)
                        INSERT INTO dbo.ActiveAlerts (
                            RuleID,
                            ServerID,
                            Severity,
                            CurrentValue,
                            ThresholdValue,
                            Message,
                            RaisedAt
                        )
                        VALUES (
                            @RuleID,
                            @ServerID,
                            @Severity,
                            @MetricValue,
                            ISNULL(@HighThreshold, @CriticalThreshold),
                            @AlertMessage,
                            GETUTCDATE()
                        );

                        DECLARE @AlertID BIGINT = SCOPE_IDENTITY();

                        -- Insert into AlertHistory (references AlertID from ActiveAlerts)
                        INSERT INTO dbo.AlertHistory (
                            AlertID,
                            RuleID,
                            ServerID,
                            Severity,
                            MaxValue,
                            ThresholdValue,
                            Message,
                            RaisedAt
                        )
                        VALUES (
                            @AlertID,
                            @RuleID,
                            @ServerID,
                            @Severity,
                            @MetricValue,
                            ISNULL(@HighThreshold, @CriticalThreshold),
                            @AlertMessage,
                            GETUTCDATE()
                        );

                        SET @AlertsRaised = @AlertsRaised + 1;

                        -- Send notification
                        EXEC dbo.usp_SendAlertNotifications @AlertID;
                    END;
                END;

                FETCH NEXT FROM metric_cursor INTO @ServerID, @MetricValue;
            END;

            CLOSE metric_cursor;
            DEALLOCATE metric_cursor;

            DROP TABLE #AnomalyMetrics;
        END TRY
        BEGIN CATCH
            PRINT 'Error evaluating rule: ' + @RuleName;
            PRINT ERROR_MESSAGE();

            IF CURSOR_STATUS('local', 'metric_cursor') >= 0
            BEGIN
                CLOSE metric_cursor;
                DEALLOCATE metric_cursor;
            END;

            IF OBJECT_ID('tempdb..#AnomalyMetrics') IS NOT NULL
                DROP TABLE #AnomalyMetrics;
        END CATCH;

        FETCH NEXT FROM rule_cursor INTO @RuleID, @RuleName, @CustomQuery;
    END;

    CLOSE rule_cursor;
    DEALLOCATE rule_cursor;

    DECLARE @DurationMs INT = DATEDIFF(MILLISECOND, @StartTime, GETUTCDATE());

    PRINT '';
    PRINT 'Anomaly alert evaluation complete';
    PRINT 'Alerts raised: ' + CAST(@AlertsRaised AS VARCHAR);
    PRINT 'Duration: ' + CAST(@DurationMs AS VARCHAR) + ' ms';
END;
GO

PRINT '✅ Created: dbo.usp_EvaluateAnomalyAlerts';
PRINT '';

-- =====================================================
-- Step 4: Update SQL Agent Job to Include Anomaly Alert Evaluation
-- =====================================================

PRINT '======================================';
PRINT 'Step 4: Updating Alert Evaluation SQL Agent Job';
PRINT '======================================';
PRINT '';

-- Check if alert evaluation job exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name LIKE '%Alert Evaluation%')
BEGIN
    DECLARE @JobName NVARCHAR(128);
    SELECT @JobName = name FROM msdb.dbo.sysjobs WHERE name LIKE '%Alert Evaluation%';

    PRINT '  Found alert evaluation job: ' + @JobName;

    -- Update job step to include anomaly alert evaluation
    DECLARE @StepCommand NVARCHAR(MAX);
    SET @StepCommand = N'
-- Evaluate standard alert rules
EXEC MonitoringDB.dbo.usp_EvaluateAlertRules;

-- Evaluate anomaly-based alert rules
EXEC MonitoringDB.dbo.usp_EvaluateAnomalyAlerts;
';

    -- Get existing step ID
    DECLARE @StepID INT;
    SELECT @StepID = step_id
    FROM msdb.dbo.sysjobsteps
    WHERE job_id = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = @JobName)
      AND step_name LIKE '%Evaluate%';

    IF @StepID IS NOT NULL
    BEGIN
        EXEC msdb.dbo.sp_update_jobstep
            @job_name = @JobName,
            @step_id = @StepID,
            @command = @StepCommand;

        PRINT '  ✅ Updated job step to include anomaly alert evaluation';
        PRINT '';
    END
    ELSE
    BEGIN
        PRINT '  ⚠️  Could not find alert evaluation step (job may need manual update)';
        PRINT '';
    END;
END
ELSE
BEGIN
    PRINT '  ℹ️  Alert evaluation job not found (may need to be created manually)';
    PRINT '';
END;

-- =====================================================
-- Step 5: Summary and Verification
-- =====================================================

PRINT '======================================';
PRINT 'Integration Complete';
PRINT '======================================';
PRINT '';

PRINT 'Anomaly-Based Alert Rules:';
SELECT
    RuleID,
    RuleName,
    HighThreshold,
    CriticalThreshold,
    CASE IsEnabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS Status
FROM dbo.AlertRules
WHERE MetricCategory = 'Anomaly'
ORDER BY RuleName;

PRINT '';
PRINT '✅ Integration Summary:';
PRINT '  • 8 anomaly-based alert rules created';
PRINT '  • Alert rules monitor AnomalyDetections table';
PRINT '  • Automatic notification on High/Critical anomalies';
PRINT '  • Integration with existing alerting infrastructure';
PRINT '';
PRINT 'Next Steps:';
PRINT '  1. Wait 7-30 days for baseline stabilization';
PRINT '  2. Monitor for false positive alerts';
PRINT '  3. Tune alert thresholds based on environment';
PRINT '  4. Test notification delivery (email/webhook)';
PRINT '';
PRINT 'Test Commands:';
PRINT '  -- Manually evaluate anomaly alerts';
PRINT '  EXEC dbo.usp_EvaluateAnomalyAlerts;';
PRINT '';
PRINT '  -- View active anomaly alerts';
PRINT '  SELECT * FROM dbo.ActiveAlerts WHERE RuleID IN (SELECT RuleID FROM dbo.AlertRules WHERE MetricCategory = ''Anomaly'');';
PRINT '';
PRINT '======================================';

GO
