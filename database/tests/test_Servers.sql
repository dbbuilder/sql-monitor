-- =====================================================
-- Test Suite: Servers Table Tests
-- Description: TDD tests for dbo.Servers table
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- TDD Phase: RED (Write tests FIRST, expect failures)
-- =====================================================

USE MonitoringDB;
GO

-- Create test class for Servers table tests
EXEC tSQLt.NewTestClass 'ServerTests';
GO

-- =====================================================
-- Test 1: Servers table should exist
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test Servers table should exist]
AS
BEGIN
    -- Arrange & Act & Assert
    EXEC tSQLt.AssertObjectExists @ObjectName = 'dbo.Servers';
END
GO

-- =====================================================
-- Test 2: Servers table should have ServerID as primary key
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test Servers table should have ServerID as primary key]
AS
BEGIN
    -- Arrange
    DECLARE @ConstraintName NVARCHAR(128);

    -- Act
    SELECT @ConstraintName = name
    FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.Servers')
      AND type = 'PK';

    -- Assert
    EXEC tSQLt.AssertNotEquals
        @Expected = NULL,
        @Actual = @ConstraintName,
        @Message = 'Servers table should have a primary key';
END
GO

-- =====================================================
-- Test 3: ServerID should be IDENTITY column
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test ServerID should be IDENTITY column]
AS
BEGIN
    -- Arrange
    DECLARE @IsIdentity BIT;

    -- Act
    SELECT @IsIdentity = is_identity
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Servers')
      AND name = 'ServerID';

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @IsIdentity,
        @Message = 'ServerID should be an IDENTITY column';
END
GO

-- =====================================================
-- Test 4: ServerName should be unique
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test ServerName should have unique constraint]
AS
BEGIN
    -- Arrange
    DECLARE @HasUniqueConstraint BIT = 0;

    -- Act
    IF EXISTS (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.object_id = OBJECT_ID('dbo.Servers')
          AND i.is_unique = 1
          AND c.name = 'ServerName'
    )
    SET @HasUniqueConstraint = 1;

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @HasUniqueConstraint,
        @Message = 'ServerName should have a unique constraint';
END
GO

-- =====================================================
-- Test 5: ServerName should be NOT NULL
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test ServerName should be NOT NULL]
AS
BEGIN
    -- Arrange
    DECLARE @IsNullable BIT;

    -- Act
    SELECT @IsNullable = is_nullable
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Servers')
      AND name = 'ServerName';

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 0,
        @Actual = @IsNullable,
        @Message = 'ServerName should be NOT NULL';
END
GO

-- =====================================================
-- Test 6: IsActive should default to 1 (true)
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test IsActive should default to 1]
AS
BEGIN
    -- Arrange
    DECLARE @DefaultValue NVARCHAR(MAX);

    -- Act
    SELECT @DefaultValue = definition
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE c.object_id = OBJECT_ID('dbo.Servers')
      AND c.name = 'IsActive';

    -- Assert
    EXEC tSQLt.AssertLike
        @ExpectedPattern = '%1%',
        @Actual = @DefaultValue,
        @Message = 'IsActive should default to 1';
END
GO

-- =====================================================
-- Test 7: Required columns should exist
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test Required columns should exist]
AS
BEGIN
    -- Arrange
    DECLARE @ColumnCount INT;

    -- Act
    SELECT @ColumnCount = COUNT(*)
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Servers')
      AND name IN ('ServerID', 'ServerName', 'Environment', 'IsActive', 'CreatedDate', 'ModifiedDate');

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 6,
        @Actual = @ColumnCount,
        @Message = 'Servers table should have 6 required columns: ServerID, ServerName, Environment, IsActive, CreatedDate, ModifiedDate';
END
GO

-- =====================================================
-- Test 8: CreatedDate should default to GETUTCDATE()
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test CreatedDate should default to GETUTCDATE]
AS
BEGIN
    -- Arrange
    DECLARE @DefaultValue NVARCHAR(MAX);

    -- Act
    SELECT @DefaultValue = definition
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE c.object_id = OBJECT_ID('dbo.Servers')
      AND c.name = 'CreatedDate';

    -- Assert
    EXEC tSQLt.AssertLike
        @ExpectedPattern = '%getutcdate%',
        @Actual = @DefaultValue,
        @Message = 'CreatedDate should default to GETUTCDATE()';
END
GO

-- =====================================================
-- Test 9: Should be able to insert a valid server
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test Should insert valid server successfully]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';

    -- Act
    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES ('SQL-PROD-01', 'Production', 1);

    -- Assert
    DECLARE @ActualRowCount INT;
    SELECT @ActualRowCount = COUNT(*)
    FROM dbo.Servers
    WHERE ServerName = 'SQL-PROD-01';

    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @ActualRowCount,
        @Message = 'Should be able to insert a valid server';
END
GO

-- =====================================================
-- Test 10: Should prevent duplicate ServerName
-- =====================================================
CREATE OR ALTER PROCEDURE ServerTests.[test Should prevent duplicate ServerName]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.ApplyConstraint @TableName = 'dbo.Servers', @ConstraintName = 'UQ_Servers_ServerName';

    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES ('SQL-PROD-01', 'Production', 1);

    -- Act & Assert
    EXEC tSQLt.ExpectException
        @ExpectedMessage = '%duplicate%',
        @ExpectedSeverity = NULL,
        @ExpectedState = NULL,
        @Message = 'Should throw exception when inserting duplicate ServerName';

    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES ('SQL-PROD-01', 'Development', 1);
END
GO

-- =====================================================
-- Run All Tests
-- =====================================================
-- Execute this to run all Servers table tests:
-- EXEC tSQLt.Run 'ServerTests';
GO

PRINT '';
PRINT '========================================================';
PRINT 'Servers Table Tests Created (RED Phase)';
PRINT '========================================================';
PRINT 'Run tests with: EXEC tSQLt.Run ''ServerTests'';';
PRINT 'Expected: ALL TESTS SHOULD FAIL (table does not exist yet)';
PRINT 'Next: Create dbo.Servers table (GREEN phase)';
PRINT '========================================================';
GO
