-- =====================================================
-- Script: 08-create-master-collection-procedure.sql
-- Description: Master collection procedure for all metrics
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- Purpose: Single procedure to collect all server + drill-down metrics
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- usp_CollectAllMetrics
-- Master procedure to collect ALL metrics (RDS + Drill-Down)
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectAllMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAllMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectAllMetrics
    @ServerID INT,
    @IncludeServerMetrics BIT = 1,
    @IncludeDrillDownMetrics BIT = 1,
    @VerboseOutput BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = GETUTCDATE();
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ServerMetricsStart DATETIME2;
    DECLARE @ServerMetricsDuration INT;
    DECLARE @DrillDownStart DATETIME2;
    DECLARE @DrillDownDuration INT;
    DECLARE @TotalDuration INT;

    BEGIN TRY
        IF @VerboseOutput = 1
        BEGIN
            PRINT '';
            PRINT '========================================================';
            PRINT 'SQL Server Monitor - Complete Metrics Collection';
            PRINT '========================================================';
            PRINT 'ServerID: ' + CAST(@ServerID AS VARCHAR(10));
            PRINT 'Collection Time: ' + CONVERT(VARCHAR(30), @StartTime, 120);
            PRINT '';
        END;

        -- =====================================================
        -- Phase 1: Server-Level Metrics (RDS Equivalent)
        -- =====================================================
        IF @IncludeServerMetrics = 1
        BEGIN
            IF @VerboseOutput = 1
            BEGIN
                PRINT 'Phase 1: Server-Level Metrics Collection';
                PRINT '-------------------------------------------';
            END;

            SET @ServerMetricsStart = GETUTCDATE();

            -- Memory Metrics
            BEGIN TRY
                EXEC dbo.usp_CollectMemoryMetrics @ServerID;
                IF @VerboseOutput = 1 PRINT '  [OK] Memory metrics collected';
            END TRY
            BEGIN CATCH
                IF @VerboseOutput = 1 PRINT '  [ERROR] Memory metrics failed: ' + ERROR_MESSAGE();
            END CATCH;

            -- Disk I/O Metrics
            BEGIN TRY
                EXEC dbo.usp_CollectDiskIOMetrics @ServerID;
                IF @VerboseOutput = 1 PRINT '  [OK] Disk I/O metrics collected';
            END TRY
            BEGIN CATCH
                IF @VerboseOutput = 1 PRINT '  [ERROR] Disk I/O metrics failed: ' + ERROR_MESSAGE();
            END CATCH;

            -- Connection Metrics
            BEGIN TRY
                EXEC dbo.usp_CollectConnectionMetrics @ServerID;
                IF @VerboseOutput = 1 PRINT '  [OK] Connection metrics collected';
            END TRY
            BEGIN CATCH
                IF @VerboseOutput = 1 PRINT '  [ERROR] Connection metrics failed: ' + ERROR_MESSAGE();
            END CATCH;

            -- Wait Statistics
            BEGIN TRY
                EXEC dbo.usp_CollectWaitStats @ServerID;
                IF @VerboseOutput = 1 PRINT '  [OK] Wait statistics collected';
            END TRY
            BEGIN CATCH
                IF @VerboseOutput = 1 PRINT '  [ERROR] Wait statistics failed: ' + ERROR_MESSAGE();
            END CATCH;

            -- Query Performance
            BEGIN TRY
                EXEC dbo.usp_CollectQueryPerformance @ServerID;
                IF @VerboseOutput = 1 PRINT '  [OK] Query performance metrics collected';
            END TRY
            BEGIN CATCH
                IF @VerboseOutput = 1 PRINT '  [ERROR] Query performance failed: ' + ERROR_MESSAGE();
            END CATCH;

            SET @ServerMetricsDuration = DATEDIFF(MILLISECOND, @ServerMetricsStart, GETUTCDATE());

            IF @VerboseOutput = 1
            BEGIN
                PRINT '';
                PRINT '  Server-level metrics completed in ' + CAST(@ServerMetricsDuration AS VARCHAR(10)) + ' ms';
                PRINT '';
            END;
        END;

        -- =====================================================
        -- Phase 2: Drill-Down Metrics (Database → Procedure → Query)
        -- =====================================================
        IF @IncludeDrillDownMetrics = 1
        BEGIN
            IF @VerboseOutput = 1
            BEGIN
                PRINT 'Phase 2: Drill-Down Metrics Collection';
                PRINT '-------------------------------------------';
            END;

            SET @DrillDownStart = GETUTCDATE();

            -- Database Metrics
            BEGIN TRY
                EXEC dbo.usp_CollectDatabaseMetrics @ServerID;
                IF @VerboseOutput = 1 PRINT '  [OK] Database metrics collected';
            END TRY
            BEGIN CATCH
                IF @VerboseOutput = 1 PRINT '  [ERROR] Database metrics failed: ' + ERROR_MESSAGE();
            END CATCH;

            -- Procedure Metrics
            BEGIN TRY
                EXEC dbo.usp_CollectProcedureMetrics @ServerID;
                IF @VerboseOutput = 1 PRINT '  [OK] Procedure metrics collected';
            END TRY
            BEGIN CATCH
                IF @VerboseOutput = 1 PRINT '  [ERROR] Procedure metrics failed: ' + ERROR_MESSAGE();
            END CATCH;

            -- Query Metrics
            BEGIN TRY
                EXEC dbo.usp_CollectQueryMetrics @ServerID;
                IF @VerboseOutput = 1 PRINT '  [OK] Query metrics collected';
            END TRY
            BEGIN CATCH
                IF @VerboseOutput = 1 PRINT '  [ERROR] Query metrics failed: ' + ERROR_MESSAGE();
            END CATCH;

            -- Wait Events by Database
            BEGIN TRY
                EXEC dbo.usp_CollectWaitEventsByDatabase @ServerID;
                IF @VerboseOutput = 1 PRINT '  [OK] Wait events by database collected';
            END TRY
            BEGIN CATCH
                IF @VerboseOutput = 1 PRINT '  [ERROR] Wait events by database failed: ' + ERROR_MESSAGE();
            END CATCH;

            SET @DrillDownDuration = DATEDIFF(MILLISECOND, @DrillDownStart, GETUTCDATE());

            IF @VerboseOutput = 1
            BEGIN
                PRINT '';
                PRINT '  Drill-down metrics completed in ' + CAST(@DrillDownDuration AS VARCHAR(10)) + ' ms';
                PRINT '';
            END;
        END;

        -- =====================================================
        -- Collection Summary
        -- =====================================================
        SET @TotalDuration = DATEDIFF(MILLISECOND, @StartTime, GETUTCDATE());

        IF @VerboseOutput = 1
        BEGIN
            PRINT '========================================================';
            PRINT 'Collection Summary';
            PRINT '========================================================';
            IF @IncludeServerMetrics = 1
                PRINT '  Server-level metrics: ' + CAST(@ServerMetricsDuration AS VARCHAR(10)) + ' ms (5 procedures)';
            IF @IncludeDrillDownMetrics = 1
                PRINT '  Drill-down metrics: ' + CAST(@DrillDownDuration AS VARCHAR(10)) + ' ms (4 procedures)';
            PRINT '  Total duration: ' + CAST(@TotalDuration AS VARCHAR(10)) + ' ms';
            PRINT '';
            PRINT 'Status: SUCCESS';
            PRINT '========================================================';
            PRINT '';
        END;

        -- Return summary as result set
        SELECT
            @ServerID AS ServerID,
            @StartTime AS CollectionTime,
            @TotalDuration AS TotalDurationMs,
            @ServerMetricsDuration AS ServerMetricsDurationMs,
            @DrillDownDuration AS DrillDownDurationMs,
            CASE
                WHEN @IncludeServerMetrics = 1 AND @IncludeDrillDownMetrics = 1 THEN 'Complete (Server + Drill-Down)'
                WHEN @IncludeServerMetrics = 1 THEN 'Server-Level Only'
                WHEN @IncludeDrillDownMetrics = 1 THEN 'Drill-Down Only'
                ELSE 'No Collection'
            END AS CollectionScope,
            'SUCCESS' AS Status;

    END TRY
    BEGIN CATCH
        SET @ErrorMessage = 'Error collecting metrics: ' + ERROR_MESSAGE() + ' (Line ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')';

        IF @VerboseOutput = 1
        BEGIN
            PRINT '';
            PRINT '========================================================';
            PRINT 'ERROR';
            PRINT '========================================================';
            PRINT @ErrorMessage;
            PRINT '========================================================';
        END;

        -- Return error as result set
        SELECT
            @ServerID AS ServerID,
            @StartTime AS CollectionTime,
            NULL AS TotalDurationMs,
            NULL AS ServerMetricsDurationMs,
            NULL AS DrillDownDurationMs,
            'ERROR' AS CollectionScope,
            @ErrorMessage AS Status;

        THROW;
    END CATCH;
END;
GO

-- =====================================================
-- Test the master collection procedure
-- =====================================================

PRINT '';
PRINT '========================================================';
PRINT 'Master Collection Procedure Created Successfully';
PRINT '========================================================';
PRINT 'Procedure: dbo.usp_CollectAllMetrics';
PRINT '';
PRINT 'Usage Examples:';
PRINT '';
PRINT '  -- Collect all metrics (server + drill-down):';
PRINT '  EXEC dbo.usp_CollectAllMetrics @ServerID = 1;';
PRINT '';
PRINT '  -- Collect server-level metrics only:';
PRINT '  EXEC dbo.usp_CollectAllMetrics @ServerID = 1, @IncludeDrillDownMetrics = 0;';
PRINT '';
PRINT '  -- Collect drill-down metrics only:';
PRINT '  EXEC dbo.usp_CollectAllMetrics @ServerID = 1, @IncludeServerMetrics = 0;';
PRINT '';
PRINT '  -- Silent mode (no verbose output):';
PRINT '  EXEC dbo.usp_CollectAllMetrics @ServerID = 1, @VerboseOutput = 0;';
PRINT '';
PRINT 'Parameters:';
PRINT '  @ServerID INT             - Server to monitor';
PRINT '  @IncludeServerMetrics BIT - Collect server-level metrics (default: 1)';
PRINT '  @IncludeDrillDownMetrics BIT - Collect drill-down metrics (default: 1)';
PRINT '  @VerboseOutput BIT        - Show detailed output (default: 1)';
PRINT '========================================================';
GO
