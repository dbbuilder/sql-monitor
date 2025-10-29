-- =============================================
-- System Database Cleanup Script
-- Purpose: Remove system databases from metadata cache and all related tables
-- Created: 2025-10-28
-- =============================================
-- System databases should NEVER be monitored or cached:
--   - master, model, msdb, tempdb (SQL Server core system databases)
--   - ReportServer, ReportServerTempDB (SSRS databases)
-- =============================================

USE [MonitoringDB];
GO

PRINT '========================================';
PRINT 'System Database Cleanup';
PRINT '========================================';
PRINT '';

-- List of system databases to exclude
DECLARE @SystemDatabases TABLE (DatabaseName NVARCHAR(128));
INSERT INTO @SystemDatabases VALUES
    ('master'),
    ('model'),
    ('msdb'),
    ('tempdb'),
    ('ReportServer'),
    ('ReportServerTempDB');

PRINT 'System databases to be removed:';
SELECT DatabaseName FROM @SystemDatabases;
PRINT '';

-- Check if any system databases exist in cache
DECLARE @SystemDBCount INT;
SELECT @SystemDBCount = COUNT(*)
FROM dbo.DatabaseMetadataCache dmc
INNER JOIN @SystemDatabases sd ON dmc.DatabaseName = sd.DatabaseName;

IF @SystemDBCount = 0
BEGIN
    PRINT '✓ No system databases found in cache (already clean)';
    PRINT '';
END
ELSE
BEGIN
    PRINT CONCAT('Found ', @SystemDBCount, ' system database entries in cache');
    PRINT '';

    -- Show what will be deleted
    SELECT
        s.ServerName,
        dmc.DatabaseName,
        dmc.TableCount,
        dmc.ViewCount,
        dmc.ProcedureCount,
        dmc.FunctionCount,
        dmc.LastRefreshTime
    FROM dbo.DatabaseMetadataCache dmc
    INNER JOIN dbo.Servers s ON dmc.ServerID = s.ServerID
    INNER JOIN @SystemDatabases sd ON dmc.DatabaseName = sd.DatabaseName;

    PRINT '';
    PRINT 'Deleting system database metadata...';

    -- Delete from all metadata tables
    DELETE tm
    FROM dbo.TableMetadata tm
    INNER JOIN @SystemDatabases sd ON tm.DatabaseName = sd.DatabaseName;
    PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' rows from TableMetadata');

    DELETE cm
    FROM dbo.ColumnMetadata cm
    INNER JOIN @SystemDatabases sd ON cm.DatabaseName = sd.DatabaseName;
    PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' rows from ColumnMetadata');

    DELETE im
    FROM dbo.IndexMetadata im
    INNER JOIN @SystemDatabases sd ON im.DatabaseName = sd.DatabaseName;
    PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' rows from IndexMetadata');

    DELETE pm
    FROM dbo.PartitionMetadata pm
    INNER JOIN @SystemDatabases sd ON pm.DatabaseName = sd.DatabaseName;
    PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' rows from PartitionMetadata');

    DELETE fk
    FROM dbo.ForeignKeyMetadata fk
    INNER JOIN @SystemDatabases sd ON fk.DatabaseName = sd.DatabaseName;
    PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' rows from ForeignKeyMetadata');

    DELETE co
    FROM dbo.CodeObjectMetadata co
    INNER JOIN @SystemDatabases sd ON co.DatabaseName = sd.DatabaseName;
    PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' rows from CodeObjectMetadata');

    DELETE dm
    FROM dbo.DependencyMetadata dm
    INNER JOIN @SystemDatabases sd ON dm.DatabaseName = sd.DatabaseName;
    PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' rows from DependencyMetadata');

    DELETE oc
    FROM dbo.ObjectCode oc
    INNER JOIN @SystemDatabases sd ON oc.DatabaseName = sd.DatabaseName;
    PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' rows from ObjectCode');

    -- Finally, delete from cache table
    DELETE dmc
    FROM dbo.DatabaseMetadataCache dmc
    INNER JOIN @SystemDatabases sd ON dmc.DatabaseName = sd.DatabaseName;
    PRINT CONCAT('  Deleted ', @@ROWCOUNT, ' rows from DatabaseMetadataCache');

    PRINT '';
    PRINT '✓ System database cleanup completed';
END;

PRINT '';
PRINT '========================================';
PRINT 'Verification';
PRINT '========================================';
PRINT '';

-- Verify no system databases remain
SELECT @SystemDBCount = COUNT(*)
FROM dbo.DatabaseMetadataCache dmc
INNER JOIN @SystemDatabases sd ON dmc.DatabaseName = sd.DatabaseName;

IF @SystemDBCount = 0
BEGIN
    PRINT '✓ VERIFIED: No system databases in cache';
END
ELSE
BEGIN
    PRINT CONCAT('✗ WARNING: Still found ', @SystemDBCount, ' system database entries!');
END;

-- Show remaining databases in cache
PRINT '';
PRINT 'Databases currently in cache (user databases only):';
SELECT
    s.ServerName,
    dmc.DatabaseName,
    dmc.TableCount,
    dmc.ViewCount,
    dmc.ProcedureCount,
    dmc.FunctionCount,
    dmc.IsCurrent,
    dmc.LastRefreshTime
FROM dbo.DatabaseMetadataCache dmc
INNER JOIN dbo.Servers s ON dmc.ServerID = s.ServerID
ORDER BY s.ServerName, dmc.DatabaseName;

PRINT '';
PRINT '========================================';
PRINT 'Next Steps';
PRINT '========================================';
PRINT '';
PRINT '1. Update SQL Agent jobs to exclude system databases when adding new databases';
PRINT '2. Grafana dashboards already exclude system databases (updated 2025-10-28)';
PRINT '3. Collection procedures use is_ms_shipped = 0 to exclude system tables';
PRINT '';
PRINT 'To manually register a new user database for monitoring:';
PRINT '  INSERT INTO dbo.DatabaseMetadataCache (ServerID, DatabaseName, LastRefreshTime, IsCurrent)';
PRINT '  VALUES (@ServerID, @DatabaseName, GETUTCDATE(), 0);';
PRINT '';
PRINT '  EXEC dbo.usp_RefreshMetadataCache @ServerID = @ServerID, @DatabaseName = @DatabaseName;';
PRINT '';
GO
