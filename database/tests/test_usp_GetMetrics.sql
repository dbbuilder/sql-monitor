-- =====================================================
-- Test Suite: usp_GetMetrics Stored Procedure Tests
-- Description: TDD tests for dbo.usp_GetMetrics
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- TDD Phase: RED (Write tests FIRST, expect failures)
-- =====================================================

USE MonitoringDB;
GO

-- Create test class for usp_GetMetrics tests
EXEC tSQLt.NewTestClass 'usp_GetMetricsTests';
GO

-- =====================================================
-- Test 1: Stored procedure should exist
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetMetricsTests.[test usp_GetMetrics should exist]
AS
BEGIN
    -- Arrange & Act & Assert
    EXEC tSQLt.AssertObjectExists @ObjectName = 'dbo.usp_GetMetrics';
END
GO

-- =====================================================
-- Test 2: Should return metrics for a specific server
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetMetricsTests.[test Should return metrics for specific server]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1), (2, 'SQL-TEST-02', 'Test', 1);

    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    VALUES
        (1, '2025-10-25 10:00:00', 'CPU', 'Percent', 45.5),
        (1, '2025-10-25 10:00:00', 'Memory', 'UsedMB', 8192.0),
        (2, '2025-10-25 10:00:00', 'CPU', 'Percent', 30.0);

    -- Act
    DECLARE @Actual TABLE (
        MetricID BIGINT,
        ServerID INT,
        CollectionTime DATETIME2,
        MetricCategory NVARCHAR(50),
        MetricName NVARCHAR(100),
        MetricValue DECIMAL(18,4)
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetMetrics @ServerID = 1;

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM @Actual WHERE ServerID = 1;

    EXEC tSQLt.AssertEquals
        @Expected = 2,
        @Actual = @ActualCount,
        @Message = 'Should return 2 metrics for ServerID = 1';
END
GO

-- =====================================================
-- Test 3: Should filter by time range
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetMetricsTests.[test Should filter by time range]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    VALUES
        (1, '2025-10-25 09:00:00', 'CPU', 'Percent', 40.0),
        (1, '2025-10-25 10:00:00', 'CPU', 'Percent', 45.5),
        (1, '2025-10-25 11:00:00', 'CPU', 'Percent', 50.0);

    -- Act
    DECLARE @Actual TABLE (
        MetricID BIGINT,
        ServerID INT,
        CollectionTime DATETIME2,
        MetricCategory NVARCHAR(50),
        MetricName NVARCHAR(100),
        MetricValue DECIMAL(18,4)
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetMetrics
        @ServerID = 1,
        @StartTime = '2025-10-25 09:30:00',
        @EndTime = '2025-10-25 10:30:00';

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM @Actual;

    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @ActualCount,
        @Message = 'Should return only 1 metric within time range';
END
GO

-- =====================================================
-- Test 4: Should filter by MetricCategory
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetMetricsTests.[test Should filter by MetricCategory]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    VALUES
        (1, '2025-10-25 10:00:00', 'CPU', 'Percent', 45.5),
        (1, '2025-10-25 10:00:00', 'Memory', 'UsedMB', 8192.0),
        (1, '2025-10-25 10:00:00', 'CPU', 'Idle', 54.5);

    -- Act
    DECLARE @Actual TABLE (
        MetricID BIGINT,
        ServerID INT,
        CollectionTime DATETIME2,
        MetricCategory NVARCHAR(50),
        MetricName NVARCHAR(100),
        MetricValue DECIMAL(18,4)
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetMetrics
        @ServerID = 1,
        @MetricCategory = 'CPU';

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM @Actual WHERE MetricCategory = 'CPU';

    EXEC tSQLt.AssertEquals
        @Expected = 2,
        @Actual = @ActualCount,
        @Message = 'Should return only CPU metrics when @MetricCategory = CPU';
END
GO

-- =====================================================
-- Test 5: Should order by CollectionTime DESC
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetMetricsTests.[test Should order by CollectionTime DESC]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    VALUES
        (1, '2025-10-25 09:00:00', 'CPU', 'Percent', 40.0),
        (1, '2025-10-25 11:00:00', 'CPU', 'Percent', 50.0),
        (1, '2025-10-25 10:00:00', 'CPU', 'Percent', 45.5);

    -- Act
    DECLARE @Actual TABLE (
        MetricID BIGINT,
        ServerID INT,
        CollectionTime DATETIME2,
        MetricCategory NVARCHAR(50),
        MetricName NVARCHAR(100),
        MetricValue DECIMAL(18,4),
        RowNum INT IDENTITY(1,1)
    );

    INSERT INTO @Actual (MetricID, ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    EXEC dbo.usp_GetMetrics @ServerID = 1;

    -- Assert
    DECLARE @FirstTime DATETIME2;
    SELECT @FirstTime = CollectionTime FROM @Actual WHERE RowNum = 1;

    EXEC tSQLt.AssertEquals
        @Expected = '2025-10-25 11:00:00',
        @Actual = @FirstTime,
        @Message = 'First row should have most recent CollectionTime (DESC order)';
END
GO

-- =====================================================
-- Test 6: Should include ServerName in results
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetMetricsTests.[test Should include ServerName in results]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    VALUES (1, '2025-10-25 10:00:00', 'CPU', 'Percent', 45.5);

    -- Act
    DECLARE @Actual TABLE (
        MetricID BIGINT,
        ServerID INT,
        ServerName NVARCHAR(256),
        CollectionTime DATETIME2,
        MetricCategory NVARCHAR(50),
        MetricName NVARCHAR(100),
        MetricValue DECIMAL(18,4)
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetMetrics @ServerID = 1;

    -- Assert
    DECLARE @ActualServerName NVARCHAR(256);
    SELECT @ActualServerName = ServerName FROM @Actual;

    EXEC tSQLt.AssertEqualsString
        @Expected = 'SQL-TEST-01',
        @Actual = @ActualServerName,
        @Message = 'Should return ServerName joined from Servers table';
END
GO

-- =====================================================
-- Test 7: Should handle empty result set
-- =====================================================
CREATE OR ALTER PROCEDURE usp_GetMetricsTests.[test Should return empty result when no metrics]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    -- Act
    DECLARE @Actual TABLE (
        MetricID BIGINT,
        ServerID INT,
        CollectionTime DATETIME2,
        MetricCategory NVARCHAR(50),
        MetricName NVARCHAR(100),
        MetricValue DECIMAL(18,4)
    );

    INSERT INTO @Actual
    EXEC dbo.usp_GetMetrics @ServerID = 1;

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM @Actual;

    EXEC tSQLt.AssertEquals
        @Expected = 0,
        @Actual = @ActualCount,
        @Message = 'Should return empty result set when no metrics exist';
END
GO

-- =====================================================
-- Run All Tests
-- =====================================================
-- Execute this to run all usp_GetMetrics tests:
-- EXEC tSQLt.Run 'usp_GetMetricsTests';
GO

PRINT '';
PRINT '========================================================';
PRINT 'usp_GetMetrics Tests Created (RED Phase)';
PRINT '========================================================';
PRINT 'Run tests with: EXEC tSQLt.Run ''usp_GetMetricsTests'';';
PRINT 'Expected: ALL TESTS SHOULD FAIL (procedure does not exist yet)';
PRINT 'Next: Create dbo.usp_GetMetrics (GREEN phase)';
PRINT '========================================================';
GO
