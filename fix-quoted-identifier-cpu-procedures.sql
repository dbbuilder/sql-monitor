-- =============================================
-- Fix QUOTED_IDENTIFIER Error in CPU Collection Procedures
-- Problem: Procedures were created without SET QUOTED_IDENTIFIER ON
-- Solution: Recreate with proper settings for sys.dm_os_ring_buffers access
-- =============================================

USE MonitoringDB;
GO

PRINT '========================================'
PRINT 'Fixing QUOTED_IDENTIFIER Settings'
PRINT '========================================'
PRINT ''

-- =============================================
-- Fix usp_GetLocalCPUMetrics
-- =============================================
PRINT 'Recreating usp_GetLocalCPUMetrics with QUOTED_IDENTIFIER ON...'

IF OBJECT_ID('dbo.usp_GetLocalCPUMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetLocalCPUMetrics;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE PROCEDURE dbo.usp_GetLocalCPUMetrics
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;  -- Explicit setting within procedure

    DECLARE @SQLProcessUtilization INT;
    DECLARE @SystemIdle INT;

    -- Read LOCAL ring buffer
    SELECT TOP 1
        @SQLProcessUtilization = record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int'),
        @SystemIdle = record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
    FROM (
        SELECT TOP 1 timestamp, CONVERT(xml, record) AS record
        FROM sys.dm_os_ring_buffers WITH (NOLOCK)
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
          AND record LIKE '%<SystemHealth>%'
        ORDER BY timestamp DESC
    ) AS rb;

    -- Return CPU metrics as result set
    SELECT
        GETUTCDATE() AS CollectionTime,
        'CPU' AS MetricCategory,
        'SQLServerCPUPercent' AS MetricName,
        CAST(@SQLProcessUtilization AS DECIMAL(10,4)) AS MetricValue
    UNION ALL
    SELECT
        GETUTCDATE(),
        'CPU',
        'SystemIdlePercent',
        CAST(@SystemIdle AS DECIMAL(10,4))
    UNION ALL
    SELECT
        GETUTCDATE(),
        'CPU',
        'OtherProcessCPUPercent',
        CAST(100 - @SQLProcessUtilization - @SystemIdle AS DECIMAL(10,4))
    WHERE @SQLProcessUtilization IS NOT NULL;
END;
GO

PRINT '  ✓ usp_GetLocalCPUMetrics recreated'

-- =============================================
-- Fix usp_CollectAndInsertCPUMetrics
-- =============================================
PRINT 'Recreating usp_CollectAndInsertCPUMetrics with QUOTED_IDENTIFIER ON...'

IF OBJECT_ID('dbo.usp_CollectAndInsertCPUMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAndInsertCPUMetrics;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE PROCEDURE dbo.usp_CollectAndInsertCPUMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;  -- Explicit setting within procedure

    -- Get LOCAL CPU metrics and insert
    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    EXEC dbo.usp_GetLocalCPUMetrics;

    PRINT 'CPU metrics collected and inserted for ServerID ' + CAST(@ServerID AS VARCHAR(10));
END;
GO

PRINT '  ✓ usp_CollectAndInsertCPUMetrics recreated'

-- =============================================
-- Verify Settings
-- =============================================
PRINT ''
PRINT 'Verifying QUOTED_IDENTIFIER settings...'

SELECT
    OBJECT_NAME(object_id) AS ProcedureName,
    uses_quoted_identifier AS QuotedIdentifier,
    CASE uses_quoted_identifier
        WHEN 1 THEN '✓ CORRECT'
        WHEN 0 THEN '✗ WRONG'
    END AS Status
FROM sys.sql_modules
WHERE OBJECT_NAME(object_id) IN ('usp_GetLocalCPUMetrics', 'usp_CollectAndInsertCPUMetrics')
ORDER BY ProcedureName;

PRINT ''
PRINT '========================================'
PRINT 'QUOTED_IDENTIFIER Fix Complete!'
PRINT '========================================'
PRINT ''
PRINT 'Next: Verify SQL Agent jobs succeed on next run'
GO
