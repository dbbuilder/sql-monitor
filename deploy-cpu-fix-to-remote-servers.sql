-- =============================================
-- Deploy CPU Fix to Remote Servers via Linked Server
-- This script deploys the new CPU collection procedures to svweb and suncity
-- Execute this FROM sqltest
-- =============================================

USE MonitoringDB;
GO

PRINT '========================================';
PRINT 'Deploying CPU Collection Fix to Remote Servers';
PRINT '========================================';
PRINT '';

-- =============================================
-- Deploy to SVWEB
-- =============================================
PRINT 'Deploying to SVWEB...';

-- Check if MonitoringDB exists on svweb
EXEC('
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = ''MonitoringDB'')
BEGIN
    PRINT ''ERROR: MonitoringDB does not exist on SVWEB'';
    RETURN;
END
') AT SVWEB;

-- Deploy usp_GetLocalCPUMetrics to svweb
EXEC('
USE MonitoringDB;
IF OBJECT_ID(''dbo.usp_GetLocalCPUMetrics'', ''P'') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetLocalCPUMetrics;
') AT SVWEB;

EXEC('
USE MonitoringDB;
CREATE PROCEDURE dbo.usp_GetLocalCPUMetrics
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @SQLProcessUtilization INT;
    DECLARE @SystemIdle INT;
    SELECT TOP 1
        @SQLProcessUtilization = record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]'', ''int''),
        @SystemIdle = record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]'', ''int'')
    FROM (
        SELECT TOP 1 timestamp, CONVERT(xml, record) AS record
        FROM sys.dm_os_ring_buffers WITH (NOLOCK)
        WHERE ring_buffer_type = N''RING_BUFFER_SCHEDULER_MONITOR''
          AND record LIKE ''%<SystemHealth>%''
        ORDER BY timestamp DESC
    ) AS rb;
    SELECT
        GETUTCDATE() AS CollectionTime,
        ''CPU'' AS MetricCategory,
        ''SQLServerCPUPercent'' AS MetricName,
        CAST(@SQLProcessUtilization AS DECIMAL(10,4)) AS MetricValue
    UNION ALL
    SELECT GETUTCDATE(), ''CPU'', ''SystemIdlePercent'', CAST(@SystemIdle AS DECIMAL(10,4))
    UNION ALL
    SELECT GETUTCDATE(), ''CPU'', ''OtherProcessCPUPercent'', CAST(100 - @SQLProcessUtilization - @SystemIdle AS DECIMAL(10,4))
    WHERE @SQLProcessUtilization IS NOT NULL;
END;
') AT SVWEB;

PRINT '  ✓ usp_GetLocalCPUMetrics deployed to SVWEB';

-- Deploy usp_CollectAndInsertCPUMetrics to svweb
EXEC('
USE MonitoringDB;
IF OBJECT_ID(''dbo.usp_CollectAndInsertCPUMetrics'', ''P'') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAndInsertCPUMetrics;
') AT SVWEB;

EXEC('
USE MonitoringDB;
CREATE PROCEDURE dbo.usp_CollectAndInsertCPUMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [sqltest.schoolvision.net].MonitoringDB.dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    EXEC dbo.usp_GetLocalCPUMetrics;
    PRINT ''CPU metrics collected and inserted for ServerID '' + CAST(@ServerID AS VARCHAR(10));
END;
') AT SVWEB;

PRINT '  ✓ usp_CollectAndInsertCPUMetrics deployed to SVWEB';
PRINT '';

-- =============================================
-- Deploy to SUNCITY
-- =============================================
PRINT 'Deploying to SUNCITY...';

-- Check if MonitoringDB exists on suncity
EXEC('
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = ''MonitoringDB'')
BEGIN
    PRINT ''ERROR: MonitoringDB does not exist on SUNCITY'';
    RETURN;
END
') AT [suncity.schoolvision.net];

-- Deploy usp_GetLocalCPUMetrics to suncity
EXEC('
USE MonitoringDB;
IF OBJECT_ID(''dbo.usp_GetLocalCPUMetrics'', ''P'') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetLocalCPUMetrics;
') AT [suncity.schoolvision.net];

EXEC('
USE MonitoringDB;
CREATE PROCEDURE dbo.usp_GetLocalCPUMetrics
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @SQLProcessUtilization INT;
    DECLARE @SystemIdle INT;
    SELECT TOP 1
        @SQLProcessUtilization = record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]'', ''int''),
        @SystemIdle = record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]'', ''int'')
    FROM (
        SELECT TOP 1 timestamp, CONVERT(xml, record) AS record
        FROM sys.dm_os_ring_buffers WITH (NOLOCK)
        WHERE ring_buffer_type = N''RING_BUFFER_SCHEDULER_MONITOR''
          AND record LIKE ''%<SystemHealth>%''
        ORDER BY timestamp DESC
    ) AS rb;
    SELECT
        GETUTCDATE() AS CollectionTime,
        ''CPU'' AS MetricCategory,
        ''SQLServerCPUPercent'' AS MetricName,
        CAST(@SQLProcessUtilization AS DECIMAL(10,4)) AS MetricValue
    UNION ALL
    SELECT GETUTCDATE(), ''CPU'', ''SystemIdlePercent'', CAST(@SystemIdle AS DECIMAL(10,4))
    UNION ALL
    SELECT GETUTCDATE(), ''CPU'', ''OtherProcessCPUPercent'', CAST(100 - @SQLProcessUtilization - @SystemIdle AS DECIMAL(10,4))
    WHERE @SQLProcessUtilization IS NOT NULL;
END;
') AT [suncity.schoolvision.net];

PRINT '  ✓ usp_GetLocalCPUMetrics deployed to SUNCITY';

-- Deploy usp_CollectAndInsertCPUMetrics to suncity
EXEC('
USE MonitoringDB;
IF OBJECT_ID(''dbo.usp_CollectAndInsertCPUMetrics'', ''P'') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAndInsertCPUMetrics;
') AT [suncity.schoolvision.net];

EXEC('
USE MonitoringDB;
CREATE PROCEDURE dbo.usp_CollectAndInsertCPUMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [sqltest.schoolvision.net].MonitoringDB.dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    EXEC dbo.usp_GetLocalCPUMetrics;
    PRINT ''CPU metrics collected and inserted for ServerID '' + CAST(@ServerID AS VARCHAR(10));
END;
') AT [suncity.schoolvision.net];

PRINT '  ✓ usp_CollectAndInsertCPUMetrics deployed to SUNCITY';
PRINT '';

PRINT '========================================';
PRINT 'Deployment Complete!';
PRINT '========================================';
PRINT '';
PRINT 'Next step: Update SQL Agent jobs to call the new procedures';
GO
