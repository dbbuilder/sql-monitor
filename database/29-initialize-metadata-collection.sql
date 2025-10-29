-- =============================================
-- Initialize Metadata Collection for All User Databases
-- Purpose: Auto-discover and register all user databases for monitoring
-- Created: 2025-10-28
-- =============================================

USE [MonitoringDB];
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

PRINT '========================================';
PRINT 'Initializing Metadata Collection';
PRINT '========================================';
PRINT '';

-- =============================================
-- Step 1: Ensure we have a server registered
-- =============================================

DECLARE @ServerID INT = 1;
DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME;

-- Check if local server is registered
IF NOT EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerID = @ServerID)
BEGIN
    PRINT 'Registering local server...';

    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES (@ServerName, 'Production', 1);

    SET @ServerID = SCOPE_IDENTITY();
    PRINT CONCAT('  ✓ Registered server: ', @ServerName, ' (ServerID: ', @ServerID, ')');
END
ELSE
BEGIN
    SELECT @ServerID = ServerID FROM dbo.Servers WHERE ServerName = @ServerName;
    PRINT CONCAT('✓ Server already registered: ', @ServerName, ' (ServerID: ', @ServerID, ')');
END;

PRINT '';

-- =============================================
-- Step 2: Auto-discover all user databases
-- =============================================

PRINT 'Discovering user databases...';
PRINT '';

DECLARE @DatabaseName NVARCHAR(128);
DECLARE @DatabaseCount INT = 0;

-- Cursor to iterate through all user databases
DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4  -- Exclude system databases (1=master, 2=tempdb, 3=model, 4=msdb)
        AND name NOT IN ('ReportServer', 'ReportServerTempDB')  -- Exclude SSRS
        AND state = 0  -- ONLINE only
        AND is_read_only = 0  -- Exclude read-only
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Check if database already registered for metadata collection
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.DatabaseMetadataCache
        WHERE ServerID = @ServerID
            AND DatabaseName = @DatabaseName
    )
    BEGIN
        -- Register database for metadata collection
        INSERT INTO dbo.DatabaseMetadataCache (
            ServerID,
            DatabaseName,
            LastRefreshTime,
            IsCurrent
        )
        VALUES (
            @ServerID,
            @DatabaseName,
            GETUTCDATE(),
            0  -- Needs initial refresh
        );

        PRINT CONCAT('  + Registered: ', @DatabaseName);
        SET @DatabaseCount = @DatabaseCount + 1;
    END
    ELSE
    BEGIN
        PRINT CONCAT('  ✓ Already registered: ', @DatabaseName);
    END;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

PRINT '';
IF @DatabaseCount > 0
    PRINT CONCAT('✓ Registered ', @DatabaseCount, ' new database(s) for monitoring');
ELSE
    PRINT '✓ All databases already registered';

PRINT '';

-- =============================================
-- Step 3: Show databases that need collection
-- =============================================

PRINT 'Databases needing metadata collection:';
PRINT '';

SELECT
    dmc.DatabaseName,
    dmc.LastRefreshTime,
    CASE WHEN dmc.IsCurrent = 0 THEN 'Needs Refresh' ELSE 'Current' END AS Status,
    COALESCE(dmc.TableCount, 0) AS TableCount,
    COALESCE(dmc.ProcedureCount, 0) AS ProcedureCount
FROM dbo.DatabaseMetadataCache dmc
WHERE dmc.ServerID = @ServerID
ORDER BY dmc.IsCurrent ASC, dmc.DatabaseName;

PRINT '';

-- =============================================
-- Step 4: Collect metadata for all databases
-- =============================================

DECLARE @CollectNow BIT = 1;  -- Set to 0 to skip initial collection (manual trigger later)

IF @CollectNow = 1
BEGIN
    PRINT '========================================';
    PRINT 'Collecting Metadata (This may take 1-5 minutes per database)';
    PRINT '========================================';
    PRINT '';

    -- Run metadata collection for all databases needing refresh
    EXEC dbo.usp_RefreshMetadataCache
        @ServerID = @ServerID,
        @DatabaseName = NULL,  -- NULL = all databases
        @ForceRefresh = 0;  -- 0 = only refresh databases marked as IsCurrent = 0

    PRINT '';
    PRINT '✓ Metadata collection complete';
END
ELSE
BEGIN
    PRINT '⚠️  Automatic collection skipped (@CollectNow = 0)';
    PRINT '';
    PRINT 'To manually trigger collection, run:';
    PRINT '  EXEC dbo.usp_RefreshMetadataCache @ServerID = ' + CAST(@ServerID AS VARCHAR(10)) + ';';
END;

PRINT '';

-- =============================================
-- Step 5: Verify data collected
-- =============================================

PRINT '========================================';
PRINT 'Verification';
PRINT '========================================';
PRINT '';

-- Show summary
SELECT
    'Total Databases Registered' AS Metric,
    COUNT(*) AS Value
FROM dbo.DatabaseMetadataCache
WHERE ServerID = @ServerID

UNION ALL

SELECT
    'Databases with Current Metadata',
    COUNT(*)
FROM dbo.DatabaseMetadataCache
WHERE ServerID = @ServerID AND IsCurrent = 1

UNION ALL

SELECT
    'Databases Needing Refresh',
    COUNT(*)
FROM dbo.DatabaseMetadataCache
WHERE ServerID = @ServerID AND IsCurrent = 0

UNION ALL

SELECT
    'Total Tables Cached',
    COUNT(*)
FROM dbo.TableMetadata
WHERE ServerID = @ServerID

UNION ALL

SELECT
    'Total Code Objects Cached',
    COUNT(*)
FROM dbo.CodeObjectMetadata
WHERE ServerID = @ServerID

UNION ALL

SELECT
    'Total Dependencies Cached',
    COUNT(*)
FROM dbo.DependencyMetadata
WHERE ServerID = @ServerID;

PRINT '';

-- Show per-database breakdown
PRINT 'Per-Database Summary:';
SELECT
    dmc.DatabaseName,
    CASE WHEN dmc.IsCurrent = 1 THEN '✓ Current' ELSE '⚠ Needs Refresh' END AS Status,
    COALESCE(dmc.TableCount, 0) AS Tables,
    COALESCE(dmc.ViewCount, 0) AS Views,
    COALESCE(dmc.ProcedureCount, 0) AS Procedures,
    COALESCE(dmc.FunctionCount, 0) AS Functions,
    dmc.LastRefreshTime
FROM dbo.DatabaseMetadataCache dmc
WHERE dmc.ServerID = @ServerID
ORDER BY dmc.DatabaseName;

PRINT '';
PRINT '========================================';
PRINT 'Next Steps';
PRINT '========================================';
PRINT '';
PRINT '1. Open Grafana dashboards and verify data appears:';
PRINT '   - Table Browser: Should show tables from all databases';
PRINT '   - Code Browser: Should show procedures/functions/views';
PRINT '';
PRINT '2. Set up automatic refresh (optional):';
PRINT '   - Create SQL Agent Job to run usp_RefreshMetadataCache daily';
PRINT '   - Or run manually when schema changes occur';
PRINT '';
PRINT '3. To force refresh all databases:';
PRINT '   EXEC dbo.usp_RefreshMetadataCache @ServerID = ' + CAST(@ServerID AS VARCHAR(10)) + ', @ForceRefresh = 1;';
PRINT '';

GO
