-- =====================================================
-- Script: 28-create-remote-cpu-memory-collection.sql
-- Description: Collect CPU and Memory Percent via linked servers
-- Author: SQL Server Monitor Project
-- Date: 2025-10-30
-- Phase: 1.9 - DBATools Integration (Remote Collection)
-- Purpose: Collect CPU/Memory metrics for remote servers
-- =====================================================

USE MonitoringDB;
GO

PRINT '=========================================================================';
PRINT 'Phase 1.9: Creating Remote CPU/Memory Collection Procedure';
PRINT '=========================================================================';
PRINT '';
GO

-- =====================================================
-- Create remote metrics collection procedure
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectRemoteCPUMemoryMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectRemoteCPUMemoryMetrics;
GO

PRINT 'Creating stored procedure: dbo.usp_CollectRemoteCPUMemoryMetrics';
GO

CREATE PROCEDURE dbo.usp_CollectRemoteCPUMemoryMetrics
    @ServerID           INT,
    @LinkedServerName   SYSNAME,
    @Debug              BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- =====================================================
    -- Variables
    -- =====================================================

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @CPUPercent DECIMAL(10,2);
    DECLARE @MemoryPercent DECIMAL(10,2);
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ServerName NVARCHAR(256);

    -- =====================================================
    -- Validate Parameters
    -- =====================================================

    SELECT @ServerName = ServerName
    FROM dbo.Servers
    WHERE ServerID = @ServerID AND IsActive = 1;

    IF @ServerName IS NULL
    BEGIN
        SET @ErrorMessage = 'ServerID ' + CAST(@ServerID AS VARCHAR(10)) + ' not found or inactive';
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN;
    END;

    IF @Debug = 1
    BEGIN
        PRINT '=========================================================================';
        PRINT 'Remote CPU/Memory Collection Starting: ' + CONVERT(VARCHAR(30), @CollectionTime, 121);
        PRINT '=========================================================================';
        PRINT 'ServerID: ' + CAST(@ServerID AS VARCHAR(10));
        PRINT 'Server: ' + @ServerName;
        PRINT 'Linked Server: ' + @LinkedServerName;
        PRINT '';
    END;

    -- =====================================================
    -- Collect Memory Percent
    -- =====================================================

    BEGIN TRY
        SET @SQL = N'
        SELECT @MemoryPercent =
            CAST((total_physical_memory_kb - available_physical_memory_kb) * 100.0 / NULLIF(total_physical_memory_kb, 0) AS DECIMAL(10,2))
        FROM OPENQUERY(' + QUOTENAME(@LinkedServerName) + ', ''SELECT total_physical_memory_kb, available_physical_memory_kb FROM sys.dm_os_sys_memory'');
        ';

        EXEC sp_executesql @SQL,
            N'@MemoryPercent DECIMAL(10,2) OUTPUT',
            @MemoryPercent = @MemoryPercent OUTPUT;

        IF @Debug = 1
            PRINT 'Memory Percent: ' + CAST(@MemoryPercent AS VARCHAR(20)) + '%';

    END TRY
    BEGIN CATCH
        SET @ErrorMessage = 'Failed to collect Memory metric: ' + ERROR_MESSAGE();
        IF @Debug = 1
            PRINT @ErrorMessage;
        SET @MemoryPercent = NULL;
    END CATCH;

    -- =====================================================
    -- Collect CPU Percent
    -- =====================================================

    BEGIN TRY
        -- Build the OPENQUERY string with proper escaping
        DECLARE @OpenQuerySQL NVARCHAR(4000);
        SET @OpenQuerySQL =
            'SELECT TOP 1 ' +
            'record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]'', ''int'') AS SQLProcessUtilization ' +
            'FROM ( ' +
            '    SELECT CONVERT(xml, record) AS record ' +
            '    FROM sys.dm_os_ring_buffers ' +
            '    WHERE ring_buffer_type = ''RING_BUFFER_SCHEDULER_MONITOR'' ' +
            '      AND record LIKE ''%<SystemHealth>%'' ' +
            ') AS rb ' +
            'ORDER BY rb.record.value(''(./Record/@time)[1]'', ''bigint'') DESC';

        SET @SQL = N'SELECT @CPUPercent = CAST(SQLProcessUtilization AS DECIMAL(10,2)) FROM OPENQUERY(' + QUOTENAME(@LinkedServerName) + ', ''' + REPLACE(@OpenQuerySQL, '''', '''''') + ''')';

        EXEC sp_executesql @SQL,
            N'@CPUPercent DECIMAL(10,2) OUTPUT',
            @CPUPercent = @CPUPercent OUTPUT;

        IF @Debug = 1
            PRINT 'CPU Percent: ' + CAST(@CPUPercent AS VARCHAR(20)) + '%';

    END TRY
    BEGIN CATCH
        SET @ErrorMessage = 'Failed to collect CPU metric: ' + ERROR_MESSAGE();
        IF @Debug = 1
            PRINT @ErrorMessage;
        SET @CPUPercent = NULL;
    END CATCH;

    -- =====================================================
    -- Insert Metrics
    -- =====================================================

    IF @MemoryPercent IS NOT NULL
    BEGIN
        INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
        VALUES (@ServerID, @CollectionTime, 'Memory', 'Percent', @MemoryPercent);

        IF @Debug = 1
            PRINT 'Memory metric inserted';
    END;

    IF @CPUPercent IS NOT NULL
    BEGIN
        INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
        VALUES (@ServerID, @CollectionTime, 'CPU', 'Percent', @CPUPercent);

        IF @Debug = 1
            PRINT 'CPU metric inserted';
    END;

    IF @Debug = 1
    BEGIN
        PRINT '';
        PRINT '=========================================================================';
        PRINT 'Remote CPU/Memory Collection COMPLETED';
        PRINT '=========================================================================';
    END;

    RETURN 0;
END;
GO

PRINT '  ✓ Stored procedure created: dbo.usp_CollectRemoteCPUMemoryMetrics';
PRINT '';
PRINT '=========================================================================';
PRINT 'Usage Example:';
PRINT '=========================================================================';
PRINT 'EXEC dbo.usp_CollectRemoteCPUMemoryMetrics';
PRINT '    @ServerID = 5,';
PRINT '    @LinkedServerName = ''SVWEB'',';
PRINT '    @Debug = 1;';
PRINT '';
PRINT '=========================================================================';
PRINT 'Phase 1.9 Remote CPU/Memory Collection: COMPLETE';
PRINT '=========================================================================';
GO
