-- =============================================
-- Phase 1.25: TDD Tests for Schema Metadata System
-- Test Framework: tSQLt
-- Created: 2025-10-26
-- =============================================

USE [MonitoringDB];
GO

-- =============================================
-- Create test class for schema metadata tests
-- =============================================

EXEC tSQLt.NewTestClass 'SchemaMetadata_Tests';
GO

-- =============================================
-- Test 1: SchemaChangeLog table exists and has correct structure
-- =============================================

CREATE PROCEDURE SchemaMetadata_Tests.[test SchemaChangeLog table exists with correct columns]
AS
BEGIN
    -- Arrange & Act
    DECLARE @ColumnCount INT;
    SELECT @ColumnCount = COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo'
      AND TABLE_NAME = 'SchemaChangeLog';

    -- Assert
    EXEC tSQLt.AssertGreaterThan 5, @ColumnCount;

    -- Verify key columns exist
    DECLARE @HasServerName BIT = 0, @HasDatabaseName BIT = 0, @HasEventType BIT = 0;

    SELECT @HasServerName = CASE WHEN EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'SchemaChangeLog' AND COLUMN_NAME = 'ServerName'
    ) THEN 1 ELSE 0 END;

    SELECT @HasDatabaseName = CASE WHEN EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'SchemaChangeLog' AND COLUMN_NAME = 'DatabaseName'
    ) THEN 1 ELSE 0 END;

    SELECT @HasEventType = CASE WHEN EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'SchemaChangeLog' AND COLUMN_NAME = 'EventType'
    ) THEN 1 ELSE 0 END;

    EXEC tSQLt.AssertEquals 1, @HasServerName, 'ServerName column missing';
    EXEC tSQLt.AssertEquals 1, @HasDatabaseName, 'DatabaseName column missing';
    EXEC tSQLt.AssertEquals 1, @HasEventType, 'EventType column missing';
END;
GO

-- =============================================
-- Test 2: DatabaseMetadataCache table exists and has correct structure
-- =============================================

CREATE PROCEDURE SchemaMetadata_Tests.[test DatabaseMetadataCache table exists with correct columns]
AS
BEGIN
    -- Arrange & Act
    DECLARE @HasIsCurrent BIT = 0;

    SELECT @HasIsCurrent = CASE WHEN EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'DatabaseMetadataCache' AND COLUMN_NAME = 'IsCurrent'
    ) THEN 1 ELSE 0 END;

    -- Assert
    EXEC tSQLt.AssertEquals 1, @HasIsCurrent, 'IsCurrent column missing from DatabaseMetadataCache';
END;
GO

-- =============================================
-- Test 3: Can insert schema change log entry
-- =============================================

CREATE PROCEDURE SchemaMetadata_Tests.[test can insert schema change log entry]
AS
BEGIN
    -- Arrange
    DECLARE @RowCountBefore INT, @RowCountAfter INT;
    SELECT @RowCountBefore = COUNT(*) FROM dbo.SchemaChangeLog;

    -- Act
    INSERT INTO dbo.SchemaChangeLog (ServerName, DatabaseName, SchemaName, ObjectName, EventType, EventTime)
    VALUES ('TestServer', 'TestDB', 'dbo', 'TestTable', 'CREATE_TABLE', GETUTCDATE());

    SELECT @RowCountAfter = COUNT(*) FROM dbo.SchemaChangeLog;

    -- Assert
    EXEC tSQLt.AssertEquals @RowCountBefore + 1, @RowCountAfter;

    -- Cleanup
    DELETE FROM dbo.SchemaChangeLog WHERE ServerName = 'TestServer' AND DatabaseName = 'TestDB';
END;
GO

-- =============================================
-- Test 4: usp_DetectSchemaChanges procedure exists
-- (Test will fail until procedure is implemented - TDD Red phase)
-- =============================================

CREATE PROCEDURE SchemaMetadata_Tests.[test usp_DetectSchemaChanges procedure exists]
AS
BEGIN
    -- Arrange & Act
    DECLARE @ProcExists BIT = 0;

    IF OBJECT_ID('dbo.usp_DetectSchemaChanges', 'P') IS NOT NULL
        SET @ProcExists = 1;

    -- Assert
    EXEC tSQLt.AssertEquals 1, @ProcExists, 'usp_DetectSchemaChanges procedure does not exist';
END;
GO

-- =============================================
-- Test 5: usp_DetectSchemaChanges marks databases as stale when changes exist
-- (Test will fail until procedure is implemented - TDD Red phase)
-- =============================================

CREATE PROCEDURE SchemaMetadata_Tests.[test usp_DetectSchemaChanges marks database as stale]
AS
BEGIN
    -- Arrange
    -- Get a real server for testing
    DECLARE @TestServerID INT;
    SELECT TOP 1 @TestServerID = ServerID FROM dbo.Servers WHERE IsActive = 1;

    IF @TestServerID IS NULL
    BEGIN
        EXEC tSQLt.Fail 'No active servers available for testing';
        RETURN;
    END;

    DECLARE @TestServerName NVARCHAR(128);
    SELECT @TestServerName = ServerName FROM dbo.Servers WHERE ServerID = @TestServerID;

    -- Insert test database cache entry (current)
    IF EXISTS (SELECT 1 FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB_SchemaChange')
        DELETE FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB_SchemaChange';

    INSERT INTO dbo.DatabaseMetadataCache (ServerID, DatabaseName, LastRefreshTime, IsCurrent)
    VALUES (@TestServerID, 'TestDB_SchemaChange', GETUTCDATE(), 1);

    -- Insert pending schema change
    DELETE FROM dbo.SchemaChangeLog WHERE ServerName = @TestServerName AND DatabaseName = 'TestDB_SchemaChange';

    INSERT INTO dbo.SchemaChangeLog (ServerName, DatabaseName, SchemaName, ObjectName, EventType, EventTime, ProcessedAt)
    VALUES (@TestServerName, 'TestDB_SchemaChange', 'dbo', 'TestTable', 'CREATE_TABLE', GETUTCDATE(), NULL);

    -- Act
    IF OBJECT_ID('dbo.usp_DetectSchemaChanges', 'P') IS NOT NULL
        EXEC dbo.usp_DetectSchemaChanges;

    -- Assert
    DECLARE @IsCurrent BIT;
    SELECT @IsCurrent = IsCurrent
    FROM dbo.DatabaseMetadataCache
    WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB_SchemaChange';

    EXEC tSQLt.AssertEquals 0, @IsCurrent, 'Database should be marked as stale (IsCurrent=0) after schema change';

    -- Cleanup
    DELETE FROM dbo.SchemaChangeLog WHERE ServerName = @TestServerName AND DatabaseName = 'TestDB_SchemaChange';
    DELETE FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB_SchemaChange';
END;
GO

-- =============================================
-- Test 6: usp_DetectSchemaChanges does not mark databases as stale when no pending changes
-- =============================================

CREATE PROCEDURE SchemaMetadata_Tests.[test usp_DetectSchemaChanges does not mark current database as stale]
AS
BEGIN
    -- Arrange
    DECLARE @TestServerID INT;
    SELECT TOP 1 @TestServerID = ServerID FROM dbo.Servers WHERE IsActive = 1;

    IF @TestServerID IS NULL
    BEGIN
        EXEC tSQLt.Fail 'No active servers available for testing';
        RETURN;
    END;

    DECLARE @TestServerName NVARCHAR(128);
    SELECT @TestServerName = ServerName FROM dbo.Servers WHERE ServerID = @TestServerID;

    -- Insert test database cache entry (current, no pending changes)
    IF EXISTS (SELECT 1 FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB_NoChanges')
        DELETE FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB_NoChanges';

    INSERT INTO dbo.DatabaseMetadataCache (ServerID, DatabaseName, LastRefreshTime, IsCurrent)
    VALUES (@TestServerID, 'TestDB_NoChanges', GETUTCDATE(), 1);

    -- Ensure no pending changes
    DELETE FROM dbo.SchemaChangeLog WHERE ServerName = @TestServerName AND DatabaseName = 'TestDB_NoChanges' AND ProcessedAt IS NULL;

    -- Act
    IF OBJECT_ID('dbo.usp_DetectSchemaChanges', 'P') IS NOT NULL
        EXEC dbo.usp_DetectSchemaChanges;

    -- Assert
    DECLARE @IsCurrent BIT;
    SELECT @IsCurrent = IsCurrent
    FROM dbo.DatabaseMetadataCache
    WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB_NoChanges';

    EXEC tSQLt.AssertEquals 1, @IsCurrent, 'Database should remain current (IsCurrent=1) when no pending schema changes';

    -- Cleanup
    DELETE FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB_NoChanges';
END;
GO

-- =============================================
-- Test 7: usp_RefreshMetadataCache procedure exists
-- (Test will fail until procedure is implemented - TDD Red phase)
-- =============================================

CREATE PROCEDURE SchemaMetadata_Tests.[test usp_RefreshMetadataCache procedure exists]
AS
BEGIN
    -- Arrange & Act
    DECLARE @ProcExists BIT = 0;

    IF OBJECT_ID('dbo.usp_RefreshMetadataCache', 'P') IS NOT NULL
        SET @ProcExists = 1;

    -- Assert
    EXEC tSQLt.AssertEquals 1, @ProcExists, 'usp_RefreshMetadataCache procedure does not exist';
END;
GO

-- =============================================
-- Test 8: TableMetadata table can store metadata
-- =============================================

CREATE PROCEDURE SchemaMetadata_Tests.[test TableMetadata table can store table metadata]
AS
BEGIN
    -- Arrange
    DECLARE @TestServerID INT;
    SELECT TOP 1 @TestServerID = ServerID FROM dbo.Servers WHERE IsActive = 1;

    IF @TestServerID IS NULL
    BEGIN
        EXEC tSQLt.Fail 'No active servers available for testing';
        RETURN;
    END;

    -- Cleanup any existing test data
    DELETE FROM dbo.TableMetadata WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB' AND TableName = 'TestTable';

    DECLARE @RowCountBefore INT, @RowCountAfter INT;
    SELECT @RowCountBefore = COUNT(*) FROM dbo.TableMetadata WHERE ServerID = @TestServerID;

    -- Act
    INSERT INTO dbo.TableMetadata (
        ServerID, DatabaseName, SchemaName, TableName, ObjectID,
        [RowCount], TotalSizeMB, DataSizeMB, IndexSizeMB,
        ColumnCount, IndexCount, PartitionCount, IsPartitioned
    )
    VALUES (
        @TestServerID, 'TestDB', 'dbo', 'TestTable', 123456,
        1000, 10.5, 8.2, 2.3,
        5, 2, 1, 0
    );

    SELECT @RowCountAfter = COUNT(*) FROM dbo.TableMetadata WHERE ServerID = @TestServerID;

    -- Assert
    EXEC tSQLt.AssertEquals @RowCountBefore + 1, @RowCountAfter, 'TableMetadata should have one more row';

    -- Verify data was stored correctly
    DECLARE @StoredRowCount BIGINT, @StoredSize DECIMAL(18,2);
    SELECT @StoredRowCount = [RowCount], @StoredSize = TotalSizeMB
    FROM dbo.TableMetadata
    WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB' AND TableName = 'TestTable';

    EXEC tSQLt.AssertEquals 1000, @StoredRowCount, 'RowCount should be 1000';
    EXEC tSQLt.AssertEquals 10.5, @StoredSize, 'TotalSizeMB should be 10.5';

    -- Cleanup
    DELETE FROM dbo.TableMetadata WHERE ServerID = @TestServerID AND DatabaseName = 'TestDB' AND TableName = 'TestTable';
END;
GO

-- =============================================
-- Summary: Print test instructions
-- =============================================

PRINT '';
PRINT '========================================';
PRINT 'Schema Metadata Tests Created';
PRINT '========================================';
PRINT 'Test Class: SchemaMetadata_Tests';
PRINT 'Total Tests: 8';
PRINT '';
PRINT 'Tests Created:';
PRINT '  1. SchemaChangeLog table structure';
PRINT '  2. DatabaseMetadataCache table structure';
PRINT '  3. Can insert schema change log entry';
PRINT '  4. usp_DetectSchemaChanges exists (RED - will fail)';
PRINT '  5. usp_DetectSchemaChanges marks stale (RED - will fail)';
PRINT '  6. usp_DetectSchemaChanges keeps current (RED - will fail)';
PRINT '  7. usp_RefreshMetadataCache exists (RED - will fail)';
PRINT '  8. TableMetadata can store metadata';
PRINT '';
PRINT 'Run tests:';
PRINT '  EXEC tSQLt.Run ''SchemaMetadata_Tests'';';
PRINT '';
PRINT 'Expected: Tests 4-7 will FAIL (TDD Red phase)';
PRINT 'Next Step: Implement stored procedures to make tests pass (TDD Green phase)';
PRINT '========================================';
GO
