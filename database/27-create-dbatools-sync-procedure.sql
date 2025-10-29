-- =====================================================
-- Script: 27-create-dbatools-sync-procedure.sql
-- Description: Automated sync from DBATools → MonitoringDB
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Automated Sync)
-- Purpose: Incremental sync without re-collecting data
-- =====================================================

-- This procedure runs on MonitoringDB and pulls new data from DBATools
-- It respects the sql-monitor-agent v1.0 codebase (no changes)
-- Data flow: sql-monitor-agent → DBATools → MonitoringDB → API/Grafana

USE MonitoringDB;
GO

PRINT '========================================================================='
PRINT 'Phase 1.9: Creating DBATools Sync Procedure'
PRINT '========================================================================='
PRINT ''
GO

-- =====================================================
-- Create sync tracking table (if not exists)
-- =====================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.DBAToolsSyncLog') AND type = 'U')
BEGIN
    PRINT 'Creating dbo.DBAToolsSyncLog (tracks last sync per server)';

    CREATE TABLE dbo.DBAToolsSyncLog
    (
        SyncLogID           INT             IDENTITY(1,1)   NOT NULL,
        ServerID            INT                             NOT NULL,
        ServerName          NVARCHAR(256)                   NOT NULL,
        DBAToolsDatabase    SYSNAME                         NOT NULL,
        LastSyncUTC         DATETIME2                       NULL,        -- Last successful sync time
        LastRunID           BIGINT                          NULL,        -- Last PerfSnapshotRunID synced
        LastSyncDuration    INT                             NULL,        -- Duration in ms
        RowsCopied          INT                             NULL,        -- Rows copied in last sync
        SyncStatus          VARCHAR(50)                     NOT NULL DEFAULT 'Initial',  -- Initial, Success, Failed
        ErrorMessage        NVARCHAR(4000)                  NULL,
        CreatedUTC          DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),
        ModifiedUTC         DATETIME2                       NULL,

        CONSTRAINT PK_DBAToolsSyncLog PRIMARY KEY CLUSTERED (SyncLogID),
        CONSTRAINT FK_DBAToolsSyncLog_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    );

    CREATE NONCLUSTERED INDEX IX_DBAToolsSyncLog_ServerID_LastSync
    ON dbo.DBAToolsSyncLog(ServerID, LastSyncUTC DESC)
    INCLUDE (LastRunID, SyncStatus);

    PRINT '  ✓ dbo.DBAToolsSyncLog created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.DBAToolsSyncLog already exists';
END
GO

-- =====================================================
-- Create incremental sync stored procedure
-- =====================================================

IF OBJECT_ID('dbo.usp_SyncDBAToolsData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_SyncDBAToolsData
GO

PRINT 'Creating stored procedure: dbo.usp_SyncDBAToolsData'
GO

CREATE PROCEDURE dbo.usp_SyncDBAToolsData
    @ServerID           INT,                            -- Target server in Servers table
    @DBAToolsDatabase   SYSNAME = 'DBATools',          -- Source DBATools database name
    @DBAToolsServer     SYSNAME = NULL,                -- NULL = same server, else linked server name
    @MaxBatchSize       INT = 1000,                    -- Max rows to sync per execution
    @Debug              BIT = 0                        -- 1 = verbose logging
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- =====================================================
    -- Variables
    -- =====================================================

    DECLARE @StartTime          DATETIME2 = GETUTCDATE();
    DECLARE @EndTime            DATETIME2;
    DECLARE @Duration           INT;
    DECLARE @ErrorMessage       NVARCHAR(4000);
    DECLARE @ErrorNumber        INT;
    DECLARE @ServerName         NVARCHAR(256);
    DECLARE @LastRunID          BIGINT;
    DECLARE @NewRunID           BIGINT;
    DECLARE @RowsCopied         INT = 0;
    DECLARE @TotalRows          INT = 0;
    DECLARE @SQL                NVARCHAR(MAX);
    DECLARE @SourceTable        SYSNAME;
    DECLARE @SyncLogID          INT;

    -- =====================================================
    -- Step 1: Validate Parameters
    -- =====================================================

    IF @Debug = 1
    BEGIN
        PRINT '========================================================================='
        PRINT 'DBATools Sync Starting: ' + CONVERT(VARCHAR(30), @StartTime, 121)
        PRINT '========================================================================='
        PRINT 'ServerID: ' + CAST(@ServerID AS VARCHAR(10))
        PRINT 'DBAToolsDatabase: ' + @DBAToolsDatabase
        PRINT 'DBAToolsServer: ' + ISNULL(@DBAToolsServer, 'Same server')
        PRINT 'MaxBatchSize: ' + CAST(@MaxBatchSize AS VARCHAR(10))
        PRINT ''
    END

    -- Get server name
    SELECT @ServerName = ServerName
    FROM dbo.Servers
    WHERE ServerID = @ServerID AND IsActive = 1;

    IF @ServerName IS NULL
    BEGIN
        SET @ErrorMessage = 'ServerID ' + CAST(@ServerID AS VARCHAR(10)) + ' not found or inactive in Servers table';
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN;
    END

    IF @Debug = 1
        PRINT 'Server: ' + @ServerName

    -- =====================================================
    -- Step 2: Get Last Sync Status
    -- =====================================================

    -- Get last successful sync info
    SELECT TOP 1
        @LastRunID = LastRunID,
        @SyncLogID = SyncLogID
    FROM dbo.DBAToolsSyncLog
    WHERE ServerID = @ServerID
      AND DBAToolsDatabase = @DBAToolsDatabase
      AND SyncStatus = 'Success'
    ORDER BY LastSyncUTC DESC;

    IF @LastRunID IS NULL
        SET @LastRunID = 0;  -- First sync

    IF @Debug = 1
        PRINT 'Last synced RunID: ' + CAST(@LastRunID AS VARCHAR(20))

    -- =====================================================
    -- Step 3: Build Source Query (DBATools)
    -- =====================================================

    -- Construct source database reference
    DECLARE @SourceDB NVARCHAR(512);
    IF @DBAToolsServer IS NULL
        SET @SourceDB = QUOTENAME(@DBAToolsDatabase);
    ELSE
        SET @SourceDB = QUOTENAME(@DBAToolsServer) + '.' + QUOTENAME(@DBAToolsDatabase);

    -- =====================================================
    -- Step 4: Sync PerfSnapshotRun Data
    -- =====================================================

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Debug = 1
            PRINT 'Syncing PerfSnapshotRun data...'

        -- Construct dynamic SQL to read from DBATools
        SET @SQL = N'
        INSERT INTO MonitoringDB.dbo.PerfSnapshotRun
        (
            ServerID, ServerName, SnapshotUTC, SqlVersion,
            SessionsCount, RequestsCount, BlockingSessionCount,
            CpuSignalWaitPct, TopWaitType, TopWaitMsPerSec,
            DeadlockCountRecent, MemoryGrantWarningCount
        )
        SELECT TOP (@MaxBatchSize)
            @ServerID AS ServerID,
            ServerName,
            SnapshotUTC,
            SqlVersion,
            SessionsCount,
            RequestsCount,
            BlockingSessionCount,
            CpuSignalWaitPct,
            TopWaitType,
            TopWaitMsPerSec,
            DeadlockCountRecent,
            MemoryGrantWarningCount
        FROM ' + @SourceDB + N'.dbo.PerfSnapshotRun
        WHERE PerfSnapshotRunID > @LastRunID
        ORDER BY PerfSnapshotRunID ASC;

        SELECT @RowsCopied = @@ROWCOUNT;
        ';

        EXEC sp_executesql @SQL,
            N'@ServerID INT, @LastRunID BIGINT, @MaxBatchSize INT, @RowsCopied INT OUTPUT',
            @ServerID = @ServerID,
            @LastRunID = @LastRunID,
            @MaxBatchSize = @MaxBatchSize,
            @RowsCopied = @RowsCopied OUTPUT;

        SET @TotalRows = @TotalRows + @RowsCopied;

        IF @Debug = 1
            PRINT '  Copied ' + CAST(@RowsCopied AS VARCHAR(10)) + ' PerfSnapshotRun rows'

        -- Get the latest RunID we just copied
        SELECT @NewRunID = MAX(PerfSnapshotRunID)
        FROM dbo.PerfSnapshotRun
        WHERE ServerID = @ServerID;

        IF @Debug = 1
            PRINT '  New highest RunID: ' + CAST(@NewRunID AS VARCHAR(20))

        -- =====================================================
        -- Step 5: Transform to PerformanceMetrics (WIDE → TALL)
        -- =====================================================

        IF @RowsCopied > 0
        BEGIN
            IF @Debug = 1
                PRINT 'Transforming to PerformanceMetrics (WIDE → TALL)...'

            -- Transform WIDE schema (PerfSnapshotRun) to TALL schema (PerformanceMetrics)
            -- This unpivots the server-level metrics into individual rows
            INSERT INTO dbo.PerformanceMetrics
            (
                ServerID,
                CollectionTime,
                MetricCategory,
                MetricName,
                MetricValue
            )
            SELECT
                psr.ServerID,
                psr.SnapshotUTC AS CollectionTime,
                m.MetricCategory,
                m.MetricName,
                m.MetricValue
            FROM dbo.PerfSnapshotRun psr
            CROSS APPLY (
                VALUES
                    -- Server-level metrics
                    ('Server', 'SessionsCount',          CAST(psr.SessionsCount AS DECIMAL(18,4))),
                    ('Server', 'RequestsCount',          CAST(psr.RequestsCount AS DECIMAL(18,4))),
                    ('Server', 'BlockingSessionCount',   CAST(psr.BlockingSessionCount AS DECIMAL(18,4))),

                    -- CPU metrics
                    ('CPU',    'SignalWaitPercent',      psr.CpuSignalWaitPct),

                    -- Wait statistics
                    ('Waits',  'TopWaitMsPerSec',        psr.TopWaitMsPerSec),

                    -- Health metrics
                    ('Health', 'DeadlockCountRecent',    CAST(psr.DeadlockCountRecent AS DECIMAL(18,4))),
                    ('Health', 'MemoryGrantWarningCount', CAST(psr.MemoryGrantWarningCount AS DECIMAL(18,4)))
            ) AS m(MetricCategory, MetricName, MetricValue)
            WHERE psr.ServerID = @ServerID
              AND psr.PerfSnapshotRunID > @LastRunID
              AND psr.PerfSnapshotRunID <= @NewRunID
              AND m.MetricValue IS NOT NULL;  -- Skip NULL metrics

            SET @RowsCopied = @@ROWCOUNT;

            IF @Debug = 1
                PRINT '  Inserted ' + CAST(@RowsCopied AS VARCHAR(10)) + ' PerformanceMetrics rows'
        END

        -- =====================================================
        -- Step 6: Update Sync Log
        -- =====================================================

        SET @EndTime = GETUTCDATE();
        SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

        -- Insert new sync log entry
        INSERT INTO dbo.DBAToolsSyncLog
        (
            ServerID, ServerName, DBAToolsDatabase,
            LastSyncUTC, LastRunID, LastSyncDuration,
            RowsCopied, SyncStatus, ModifiedUTC
        )
        VALUES
        (
            @ServerID, @ServerName, @DBAToolsDatabase,
            @EndTime, @NewRunID, @Duration,
            @TotalRows, 'Success', @EndTime
        );

        COMMIT TRANSACTION;

        IF @Debug = 1
        BEGIN
            PRINT ''
            PRINT '========================================================================='
            PRINT 'Sync COMPLETED Successfully'
            PRINT '========================================================================='
            PRINT 'Duration: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
            PRINT 'Rows Copied: ' + CAST(@TotalRows AS VARCHAR(10))
            PRINT 'Last RunID: ' + CAST(@NewRunID AS VARCHAR(20))
            PRINT ''
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @ErrorNumber = ERROR_NUMBER();
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @EndTime = GETUTCDATE();
        SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

        -- Log failure
        INSERT INTO dbo.DBAToolsSyncLog
        (
            ServerID, ServerName, DBAToolsDatabase,
            LastSyncUTC, LastRunID, LastSyncDuration,
            RowsCopied, SyncStatus, ErrorMessage, ModifiedUTC
        )
        VALUES
        (
            @ServerID, @ServerName, @DBAToolsDatabase,
            @EndTime, @LastRunID, @Duration,
            @TotalRows, 'Failed', @ErrorMessage, @EndTime
        );

        IF @Debug = 1
        BEGIN
            PRINT ''
            PRINT '========================================================================='
            PRINT 'Sync FAILED'
            PRINT '========================================================================='
            PRINT 'Error: ' + @ErrorMessage
            PRINT 'Error Number: ' + CAST(@ErrorNumber AS VARCHAR(10))
            PRINT ''
        END

        -- Re-throw error
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH

    RETURN 0;
END
GO

PRINT '  ✓ Stored procedure created: dbo.usp_SyncDBAToolsData'
PRINT ''
PRINT '========================================================================='
PRINT 'Usage Example:'
PRINT '========================================================================='
PRINT 'EXEC dbo.usp_SyncDBAToolsData'
PRINT '    @ServerID = 1,'
PRINT '    @DBAToolsDatabase = ''DBATools'','
PRINT '    @DBAToolsServer = NULL,  -- Same server'
PRINT '    @MaxBatchSize = 1000,'
PRINT '    @Debug = 1;'
PRINT ''
PRINT '========================================================================='
PRINT 'Phase 1.9 DBATools Sync Procedure: COMPLETE'
PRINT '========================================================================='
GO
