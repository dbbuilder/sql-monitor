-- =============================================
-- SQL Monitor - Complete Data Collection Setup
-- Rollout to: sqltest, svweb, suncity
-- =============================================
-- Purpose: Configure all 3 servers to collect metrics into MonitoringDB
-- Target: sqltest.schoolvision.net,14333 (MonitoringDB host)
-- =============================================

USE [MonitoringDB];
GO

PRINT '========================================';
PRINT 'SQL MONITOR - DATA COLLECTION SETUP';
PRINT '========================================';
PRINT '';

-- =============================================
-- STEP 1: Register All Servers
-- =============================================
PRINT 'STEP 1: Registering servers in MonitoringDB...';
PRINT '';

-- Server 1: sqltest (MonitoringDB host)
IF NOT EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerName = 'sqltest.schoolvision.net,14333')
BEGIN
    INSERT INTO dbo.Servers (ServerName, InstanceName, IsActive, Description)
    VALUES ('sqltest.schoolvision.net,14333', 'SQLTEST', 1, 'MonitoringDB Host - Test Environment');

    PRINT '  ✓ Registered: sqltest.schoolvision.net,14333';
END
ELSE
BEGIN
    UPDATE dbo.Servers
    SET IsActive = 1, Description = 'MonitoringDB Host - Test Environment'
    WHERE ServerName = 'sqltest.schoolvision.net,14333';

    PRINT '  ○ Updated: sqltest.schoolvision.net,14333';
END

-- Server 2: svweb
IF NOT EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerName = 'svweb,14333')
BEGIN
    INSERT INTO dbo.Servers (ServerName, InstanceName, IsActive, Description)
    VALUES ('svweb,14333', 'SVWEB', 1, 'Production Web Server');

    PRINT '  ✓ Registered: svweb,14333';
END
ELSE
BEGIN
    UPDATE dbo.Servers
    SET IsActive = 1, Description = 'Production Web Server'
    WHERE ServerName = 'svweb,14333';

    PRINT '  ○ Updated: svweb,14333';
END

-- Server 3: suncity
IF NOT EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerName = 'suncity.schoolvision.net,14333')
BEGIN
    INSERT INTO dbo.Servers (ServerName, InstanceName, IsActive, Description)
    VALUES ('suncity.schoolvision.net,14333', 'SUNCITY', 1, 'Suncity Production Server');

    PRINT '  ✓ Registered: suncity.schoolvision.net,14333';
END
ELSE
BEGIN
    UPDATE dbo.Servers
    SET IsActive = 1, Description = 'Suncity Production Server'
    WHERE ServerName = 'suncity.schoolvision.net,14333';

    PRINT '  ○ Updated: suncity.schoolvision.net,14333';
END

PRINT '';
PRINT 'Server registration complete!';
PRINT '';

-- Show registered servers
SELECT
    ServerID,
    ServerName,
    InstanceName,
    IsActive,
    Description,
    CreatedAt
FROM dbo.Servers
ORDER BY ServerID;

GO

-- =============================================
-- STEP 2: Verify RDS Collection Procedures Exist
-- =============================================
PRINT '';
PRINT 'STEP 2: Verifying RDS collection procedures...';
PRINT '';

DECLARE @ProcedureCount INT;

SELECT @ProcedureCount = COUNT(*)
FROM sys.objects
WHERE type = 'P' AND name LIKE 'usp_Collect%RDS%' OR name = 'usp_CollectAllRDSMetrics';

IF @ProcedureCount >= 7
BEGIN
    PRINT '  ✓ RDS collection procedures found: ' + CAST(@ProcedureCount AS VARCHAR(10));

    -- List procedures
    SELECT name AS ProcedureName
    FROM sys.objects
    WHERE type = 'P' AND (name LIKE 'usp_Collect%' OR name LIKE 'usp_Get%')
    ORDER BY name;
END
ELSE
BEGIN
    PRINT '  ✗ WARNING: RDS collection procedures missing!';
    PRINT '  Expected: usp_CollectCPUMetrics, usp_CollectMemoryMetrics, etc.';
    PRINT '  Run: database/05-create-rds-equivalent-procedures.sql';
END

GO

-- =============================================
-- STEP 3: Test Manual Collection (All Servers)
-- =============================================
PRINT '';
PRINT 'STEP 3: Testing manual metric collection...';
PRINT '';

DECLARE @ServerID INT;
DECLARE @ServerName VARCHAR(255);
DECLARE @ErrorMessage VARCHAR(MAX);

-- Get all active servers
DECLARE server_cursor CURSOR FOR
SELECT ServerID, ServerName
FROM dbo.Servers
WHERE IsActive = 1
ORDER BY ServerID;

OPEN server_cursor;

FETCH NEXT FROM server_cursor INTO @ServerID, @ServerName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '  Testing: ' + @ServerName + ' (ServerID=' + CAST(@ServerID AS VARCHAR(10)) + ')';

    BEGIN TRY
        -- Test collection
        EXEC dbo.usp_CollectAllRDSMetrics @ServerID = @ServerID;

        -- Count collected metrics
        DECLARE @MetricCount INT;
        SELECT @MetricCount = COUNT(*)
        FROM dbo.PerformanceMetrics
        WHERE ServerID = @ServerID
          AND CollectionTime >= DATEADD(MINUTE, -5, GETUTCDATE());

        PRINT '    ✓ Success! Metrics collected: ' + CAST(@MetricCount AS VARCHAR(10));
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = ERROR_MESSAGE();
        PRINT '    ✗ Error: ' + @ErrorMessage;
    END CATCH

    FETCH NEXT FROM server_cursor INTO @ServerID, @ServerName;
END

CLOSE server_cursor;
DEALLOCATE server_cursor;

GO

-- =============================================
-- STEP 4: Show Collected Metrics Summary
-- =============================================
PRINT '';
PRINT 'STEP 4: Metrics collection summary...';
PRINT '';

SELECT
    s.ServerName,
    COUNT(*) AS TotalMetrics,
    MIN(pm.CollectionTime) AS FirstCollection,
    MAX(pm.CollectionTime) AS LastCollection,
    COUNT(DISTINCT pm.MetricCategory) AS UniqueCategories
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
GROUP BY s.ServerName
ORDER BY s.ServerName;

PRINT '';
PRINT 'Metrics by category:';

SELECT
    s.ServerName,
    pm.MetricCategory,
    COUNT(*) AS MetricCount,
    MAX(pm.CollectionTime) AS LastCollectionTime
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY s.ServerName, pm.MetricCategory
ORDER BY s.ServerName, pm.MetricCategory;

GO

-- =============================================
-- STEP 5: SQL Agent Job Creation Script
-- =============================================
PRINT '';
PRINT '========================================';
PRINT 'STEP 5: SQL AGENT JOB DEPLOYMENT';
PRINT '========================================';
PRINT '';
PRINT 'Next steps: Deploy SQL Agent jobs to each server';
PRINT '';
PRINT 'Run the following scripts on EACH server:';
PRINT '  1. sqltest.schoolvision.net,14333';
PRINT '  2. svweb,14333';
PRINT '  3. suncity.schoolvision.net,14333';
PRINT '';
PRINT 'Script: CREATE-SQL-AGENT-JOB-TEMPLATE.sql';
PRINT 'Purpose: Collect metrics every 5 minutes';
PRINT '';

-- Generate script for reference
PRINT '-- =============================================';
PRINT '-- SQL AGENT JOB TEMPLATE (Run on EACH server)';
PRINT '-- =============================================';
PRINT '';
PRINT 'USE [msdb];';
PRINT 'GO';
PRINT '';
PRINT '-- REPLACE @ServerID with correct value:';
PRINT '--   sqltest = 1';
PRINT '--   svweb   = 2';
PRINT '--   suncity = 3';
PRINT '';
PRINT 'DECLARE @ServerID INT = 1; -- CHANGE THIS!';
PRINT '';
PRINT 'EXEC dbo.sp_add_job';
PRINT '    @job_name = N''SQL Monitor - Collect RDS Metrics'',';
PRINT '    @enabled = 1;';
PRINT '';
PRINT 'EXEC dbo.sp_add_jobstep';
PRINT '    @job_name = N''SQL Monitor - Collect RDS Metrics'',';
PRINT '    @step_name = N''Collect All Metrics'',';
PRINT '    @subsystem = N''TSQL'',';
PRINT '    @database_name = N''MonitoringDB'',';
PRINT '    @command = N''EXEC dbo.usp_CollectAllRDSMetrics @ServerID = '' + CAST(@ServerID AS VARCHAR(10)) + '';'',';
PRINT '    @retry_attempts = 3,';
PRINT '    @retry_interval = 1;';
PRINT '';
PRINT 'EXEC dbo.sp_add_schedule';
PRINT '    @schedule_name = N''Every 5 Minutes'',';
PRINT '    @freq_type = 4,';
PRINT '    @freq_interval = 1,';
PRINT '    @freq_subday_type = 4,';
PRINT '    @freq_subday_interval = 5;';
PRINT '';
PRINT 'EXEC dbo.sp_attach_schedule';
PRINT '    @job_name = N''SQL Monitor - Collect RDS Metrics'',';
PRINT '    @schedule_name = N''Every 5 Minutes'';';
PRINT '';
PRINT 'EXEC dbo.sp_add_jobserver';
PRINT '    @job_name = N''SQL Monitor - Collect RDS Metrics'';';
PRINT '';

GO

-- =============================================
-- STEP 6: Verification Checklist
-- =============================================
PRINT '';
PRINT '========================================';
PRINT 'DEPLOYMENT CHECKLIST';
PRINT '========================================';
PRINT '';
PRINT '[ ] Step 1: Servers registered (3 servers)';
PRINT '[ ] Step 2: RDS procedures exist (7 procedures)';
PRINT '[ ] Step 3: Manual collection tested (all servers)';
PRINT '[ ] Step 4: Metrics verified in PerformanceMetrics table';
PRINT '[ ] Step 5: SQL Agent jobs created on each server';
PRINT '[ ] Step 6: Wait 10 minutes, verify automated collection';
PRINT '[ ] Step 7: Check Grafana dashboards for data';
PRINT '';
PRINT '========================================';
PRINT 'SETUP COMPLETE';
PRINT '========================================';
PRINT '';
PRINT 'Monitor collection status:';
PRINT '  SELECT * FROM dbo.Servers WHERE IsActive = 1;';
PRINT '';
PRINT 'View latest metrics:';
PRINT '  SELECT TOP 100 * FROM dbo.PerformanceMetrics ORDER BY CollectionTime DESC;';
PRINT '';
PRINT 'Troubleshooting:';
PRINT '  EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1; -- Test collection';
PRINT '';

GO
