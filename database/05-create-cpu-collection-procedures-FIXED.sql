-- =====================================================
-- Script: 05-create-cpu-collection-procedures-FIXED.sql
-- Description: Create CPU collection procedures with QUOTED_IDENTIFIER fix
-- Author: SQL Server Monitor Project
-- Date: 2025-10-31 (UPDATED AFTER FIX)
-- Purpose: Create procedures for collecting CPU metrics from sys.dm_os_ring_buffers
--
-- CRITICAL FIX:
-- sys.dm_os_ring_buffers requires QUOTED_IDENTIFIER ON for XML methods (.value())
-- Must be set BOTH at procedure creation time AND at execution time
--
-- DEPLOYMENT: Deploy to ALL servers (sqltest, svweb, suncity)
-- =====================================================

USE MonitoringDB;
GO

PRINT '========================================';
PRINT 'Creating CPU Collection Procedures';
PRINT '========================================';
PRINT '';

-- =====================================================
-- Procedure: usp_GetLocalCPUMetrics
-- Returns: 3 rows (SQLServerCPUPercent, SystemIdlePercent, OtherProcessCPUPercent)
-- =====================================================

IF OBJECT_ID('dbo.usp_GetLocalCPUMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetLocalCPUMetrics;
GO

SET QUOTED_IDENTIFIER ON;  -- CRITICAL: Must be ON at creation time
GO

CREATE PROCEDURE dbo.usp_GetLocalCPUMetrics
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;  -- CRITICAL: Must be ON at execution time

    DECLARE @SQLProcessUtilization INT;
    DECLARE @SystemIdle INT;

    -- Read LOCAL ring buffer (most recent entry)
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

    -- Return CPU metrics as result set (3 rows)
    SELECT
        GETUTCDATE() AS CollectionTime,
        'CPU' AS MetricCategory,
        'SQLServerCPUPercent' AS MetricName,
        CAST(@SQLProcessUtilization AS DECIMAL(10,4)) AS MetricValue
    WHERE @SQLProcessUtilization IS NOT NULL
    UNION ALL
    SELECT
        GETUTCDATE(),
        'CPU',
        'SystemIdlePercent',
        CAST(@SystemIdle AS DECIMAL(10,4))
    WHERE @SQLProcessUtilization IS NOT NULL
    UNION ALL
    SELECT
        GETUTCDATE(),
        'CPU',
        'OtherProcessCPUPercent',
        CAST(100 - @SQLProcessUtilization - @SystemIdle AS DECIMAL(10,4))
    WHERE @SQLProcessUtilization IS NOT NULL;
END;
GO

PRINT '  ✓ usp_GetLocalCPUMetrics created';

-- =====================================================
-- Procedure: usp_CollectAndInsertCPUMetrics
-- Collects CPU metrics and inserts to PerformanceMetrics table
-- Uses table variable pattern to add ServerID column
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectAndInsertCPUMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAndInsertCPUMetrics;
GO

SET QUOTED_IDENTIFIER ON;  -- CRITICAL: Must be ON at creation time
GO

CREATE PROCEDURE dbo.usp_CollectAndInsertCPUMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;  -- CRITICAL: Must be ON at execution time

    -- Table variable to capture procedure results
    DECLARE @CPUMetrics TABLE (
        CollectionTime DATETIME2,
        MetricCategory NVARCHAR(50),
        MetricName NVARCHAR(100),
        MetricValue DECIMAL(20,4)
    );

    -- Capture results from usp_GetLocalCPUMetrics
    INSERT INTO @CPUMetrics (CollectionTime, MetricCategory, MetricName, MetricValue)
    EXEC dbo.usp_GetLocalCPUMetrics;

    -- Insert with ServerID column (this is why we need table variable)
    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    SELECT @ServerID, CollectionTime, MetricCategory, MetricName, MetricValue
    FROM @CPUMetrics;

    PRINT 'CPU metrics collected and inserted for ServerID ' + CAST(@ServerID AS VARCHAR(10));
END;
GO

PRINT '  ✓ usp_CollectAndInsertCPUMetrics created';

-- =====================================================
-- Verify QUOTED_IDENTIFIER settings
-- =====================================================

PRINT '';
PRINT 'Verifying QUOTED_IDENTIFIER settings...';

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

PRINT '';
PRINT '========================================';
PRINT 'CPU Collection Procedures Created!';
PRINT '========================================';
PRINT '';
PRINT 'Procedures created:';
PRINT '  - dbo.usp_GetLocalCPUMetrics';
PRINT '  - dbo.usp_CollectAndInsertCPUMetrics (@ServerID)';
PRINT '';
PRINT 'IMPORTANT: SQL Agent job steps must also include:';
PRINT '  SET QUOTED_IDENTIFIER ON;';
PRINT '';
PRINT 'Test manually:';
PRINT '  SET QUOTED_IDENTIFIER ON;';
PRINT '  EXEC dbo.usp_CollectAndInsertCPUMetrics @ServerID = 1;';
PRINT '';
GO
