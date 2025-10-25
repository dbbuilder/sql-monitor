-- =====================================================
-- Test Suite: usp_GetServers Stored Procedure Tests
-- Description: TDD tests for dbo.usp_GetServers
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- TDD Phase: RED (Write tests FIRST, expect failures)
-- =====================================================

USE MonitoringDB;
GO

-- Create test class for usp_GetServers tests
EXEC tSQLt.NewTestClass 'usp_GetServersTests';
GO

-- =====================================================
-- Test 1: Stored procedure should exist
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetServersTests.[test usp_GetServers should exist]
AS
BEGIN
    -- Arrange & Act & Assert
    EXEC tSQLt.AssertObjectExists @ObjectName = 'dbo.usp_GetServers';
END
GO

-- =====================================================
-- Test 2: Should return all active servers when no filter
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetServersTests.[test Should return all active servers]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES
        (1, 'SQL-PROD-01', 'Production', 1),
        (2, 'SQL-PROD-02', 'Production', 1),
        (3, 'SQL-DEV-01', 'Development', 1),
        (4, 'SQL-TEST-01', 'Test', 0); -- Inactive

    -- Act
    DECLARE @Actual TABLE (
        ServerID INT,
        ServerName NVARCHAR(256),
        Environment NVARCHAR(50),
        IsActive BIT
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetServers;

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM @Actual WHERE IsActive = 1;

    EXEC tSQLt.AssertEquals
        @Expected = 3,
        @Actual = @ActualCount,
        @Message = 'Should return 3 active servers';
END
GO

-- =====================================================
-- Test 3: Should filter by IsActive parameter
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetServersTests.[test Should filter by IsActive parameter]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES
        (1, 'SQL-PROD-01', 'Production', 1),
        (2, 'SQL-TEST-01', 'Test', 0);

    -- Act
    DECLARE @Actual TABLE (
        ServerID INT,
        ServerName NVARCHAR(256),
        Environment NVARCHAR(50),
        IsActive BIT
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetServers @IsActive = 0;

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM @Actual;

    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @ActualCount,
        @Message = 'Should return only inactive servers when @IsActive = 0';
END
GO

-- =====================================================
-- Test 4: Should return servers ordered by ServerName
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetServersTests.[test Should return servers ordered by ServerName]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES
        (1, 'SQL-PROD-03', 'Production', 1),
        (2, 'SQL-PROD-01', 'Production', 1),
        (3, 'SQL-PROD-02', 'Production', 1);

    -- Act
    DECLARE @Actual TABLE (
        ServerID INT,
        ServerName NVARCHAR(256),
        Environment NVARCHAR(50),
        IsActive BIT,
        RowNum INT IDENTITY(1,1)
    );

    INSERT INTO @Actual (ServerID, ServerName, Environment, IsActive)
    EXEC dbo.usp_GetServers;

    -- Assert
    DECLARE @FirstServerName NVARCHAR(256);
    SELECT @FirstServerName = ServerName FROM @Actual WHERE RowNum = 1;

    EXEC tSQLt.AssertEqualsString
        @Expected = 'SQL-PROD-01',
        @Actual = @FirstServerName,
        @Message = 'First server should be SQL-PROD-01 (alphabetically first)';
END
GO

-- =====================================================
-- Test 5: Should return all columns needed for API
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetServersTests.[test Should return all required columns]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive, CreatedDate)
    VALUES (1, 'SQL-PROD-01', 'Production', 1, '2025-10-25');

    -- Act
    DECLARE @Actual TABLE (
        ServerID INT,
        ServerName NVARCHAR(256),
        Environment NVARCHAR(50),
        IsActive BIT,
        CreatedDate DATETIME2,
        ModifiedDate DATETIME2
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetServers;

    -- Assert
    DECLARE @HasAllColumns BIT = 0;

    IF EXISTS (
        SELECT 1 FROM @Actual
        WHERE ServerID IS NOT NULL
          AND ServerName IS NOT NULL
          AND IsActive IS NOT NULL
          AND CreatedDate IS NOT NULL
    )
    SET @HasAllColumns = 1;

    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @HasAllColumns,
        @Message = 'Should return ServerID, ServerName, Environment, IsActive, CreatedDate, ModifiedDate';
END
GO

-- =====================================================
-- Test 6: Should handle empty table gracefully
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetServersTests.[test Should return empty result set when no servers]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';

    -- Act
    DECLARE @Actual TABLE (
        ServerID INT,
        ServerName NVARCHAR(256),
        Environment NVARCHAR(50),
        IsActive BIT
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetServers;

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM @Actual;

    EXEC tSQLt.AssertEquals
        @Expected = 0,
        @Actual = @ActualCount,
        @Message = 'Should return empty result set when no servers exist';
END
GO

-- =====================================================
-- Test 7: Should filter by Environment parameter
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetServersTests.[test Should filter by Environment parameter]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES
        (1, 'SQL-PROD-01', 'Production', 1),
        (2, 'SQL-PROD-02', 'Production', 1),
        (3, 'SQL-DEV-01', 'Development', 1);

    -- Act
    DECLARE @Actual TABLE (
        ServerID INT,
        ServerName NVARCHAR(256),
        Environment NVARCHAR(50),
        IsActive BIT
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetServers @Environment = 'Production';

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM @Actual;

    EXEC tSQLt.AssertEquals
        @Expected = 2,
        @Actual = @ActualCount,
        @Message = 'Should return only Production servers when @Environment = Production';
END
GO

-- =====================================================
-- Run All Tests
-- =====================================================
-- Execute this to run all usp_GetServers tests:
-- EXEC tSQLt.Run 'usp_GetServersTests';
GO

PRINT '';
PRINT '========================================================';
PRINT 'usp_GetServers Tests Created (RED Phase)';
PRINT '========================================================';
PRINT 'Run tests with: EXEC tSQLt.Run ''usp_GetServersTests'';';
PRINT 'Expected: ALL TESTS SHOULD FAIL (procedure does not exist yet)';
PRINT 'Next: Create dbo.usp_GetServers (GREEN phase)';
PRINT '========================================================';
GO
