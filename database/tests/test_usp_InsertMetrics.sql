-- =====================================================
-- Test Suite: usp_InsertMetrics Stored Procedure Tests
-- Description: TDD tests for dbo.usp_InsertMetrics
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- TDD Phase: RED (Write tests FIRST, expect failures)
-- =====================================================

USE MonitoringDB;
GO

-- Create test class for usp_InsertMetrics tests
EXEC tSQLt.NewTestClass 'usp_InsertMetricsTests';
GO

-- =====================================================
-- Test 1: Stored procedure should exist
-- =====================================================
CREATE OR ALTER PROCEDURE usp_InsertMetricsTests.[test usp_InsertMetrics should exist]
AS
BEGIN
    -- Arrange & Act & Assert
    EXEC tSQLt.AssertObjectExists @ObjectName = 'dbo.usp_InsertMetrics';
END
GO

-- =====================================================
-- Test 2: Should insert a single metric successfully
-- =====================================================
CREATE OR ALTER PROCEDURE usp_InsertMetricsTests.[test Should insert single metric]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    -- Act
    EXEC dbo.usp_InsertMetrics
        @ServerID = 1,
        @CollectionTime = '2025-10-25 10:00:00',
        @MetricCategory = 'CPU',
        @MetricName = 'Percent',
        @MetricValue = 45.5;

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*)
    FROM dbo.PerformanceMetrics
    WHERE ServerID = 1
      AND MetricCategory = 'CPU'
      AND MetricName = 'Percent';

    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @ActualCount,
        @Message = 'Should insert exactly 1 metric';
END
GO

-- =====================================================
-- Test 3: Should validate ServerID exists
-- =====================================================
CREATE OR ALTER PROCEDURE usp_InsertMetricsTests.[test Should fail when ServerID does not exist]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';
    EXEC tSQLt.ApplyConstraint @TableName = 'dbo.PerformanceMetrics', @ConstraintName = 'FK_PerformanceMetrics_Servers';

    -- Act & Assert
    EXEC tSQLt.ExpectException
        @ExpectedMessage = '%foreign key%',
        @ExpectedSeverity = NULL,
        @ExpectedState = NULL,
        @Message = 'Should throw FK violation when ServerID does not exist';

    EXEC dbo.usp_InsertMetrics
        @ServerID = 999,
        @CollectionTime = '2025-10-25 10:00:00',
        @MetricCategory = 'CPU',
        @MetricName = 'Percent',
        @MetricValue = 45.5;
END
GO

-- =====================================================
-- Test 4: Should handle NULL MetricValue
-- =====================================================
CREATE OR ALTER PROCEDURE usp_InsertMetricsTests.[test Should allow NULL MetricValue]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    -- Act
    EXEC dbo.usp_InsertMetrics
        @ServerID = 1,
        @CollectionTime = '2025-10-25 10:00:00',
        @MetricCategory = 'Status',
        @MetricName = 'DatabaseState',
        @MetricValue = NULL;

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*)
    FROM dbo.PerformanceMetrics
    WHERE ServerID = 1
      AND MetricValue IS NULL;

    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @ActualCount,
        @Message = 'Should allow NULL MetricValue for non-numeric metrics';
END
GO

-- =====================================================
-- Test 5: Should require CollectionTime
-- =====================================================
CREATE OR ALTER PROCEDURE usp_InsertMetricsTests.[test Should fail when CollectionTime is NULL]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';
    EXEC tSQLt.ApplyConstraint @TableName = 'dbo.PerformanceMetrics', @NullCheckOnly = 1;

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    -- Act & Assert
    EXEC tSQLt.ExpectException
        @ExpectedMessage = '%null%',
        @ExpectedSeverity = NULL,
        @ExpectedState = NULL,
        @Message = 'Should throw error when CollectionTime is NULL';

    EXEC dbo.usp_InsertMetrics
        @ServerID = 1,
        @CollectionTime = NULL,
        @MetricCategory = 'CPU',
        @MetricName = 'Percent',
        @MetricValue = 45.5;
END
GO

-- =====================================================
-- Test 6: Should require MetricCategory
-- =====================================================
CREATE OR ALTER PROCEDURE usp_InsertMetricsTests.[test Should fail when MetricCategory is NULL]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';
    EXEC tSQLt.ApplyConstraint @TableName = 'dbo.PerformanceMetrics', @NullCheckOnly = 1;

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    -- Act & Assert
    EXEC tSQLt.ExpectException
        @ExpectedMessage = '%null%',
        @ExpectedSeverity = NULL,
        @ExpectedState = NULL,
        @Message = 'Should throw error when MetricCategory is NULL';

    EXEC dbo.usp_InsertMetrics
        @ServerID = 1,
        @CollectionTime = '2025-10-25 10:00:00',
        @MetricCategory = NULL,
        @MetricName = 'Percent',
        @MetricValue = 45.5;
END
GO

-- =====================================================
-- Test 7: Should insert multiple metrics in batch
-- =====================================================
CREATE OR ALTER PROCEDURE usp_InsertMetricsTests.[test Should insert multiple metrics]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    -- Act
    EXEC dbo.usp_InsertMetrics
        @ServerID = 1,
        @CollectionTime = '2025-10-25 10:00:00',
        @MetricCategory = 'CPU',
        @MetricName = 'Percent',
        @MetricValue = 45.5;

    EXEC dbo.usp_InsertMetrics
        @ServerID = 1,
        @CollectionTime = '2025-10-25 10:00:00',
        @MetricCategory = 'Memory',
        @MetricName = 'UsedMB',
        @MetricValue = 8192.0;

    -- Assert
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*)
    FROM dbo.PerformanceMetrics
    WHERE ServerID = 1;

    EXEC tSQLt.AssertEquals
        @Expected = 2,
        @Actual = @ActualCount,
        @Message = 'Should insert 2 metrics successfully';
END
GO

-- =====================================================
-- Run All Tests
-- =====================================================
-- Execute this to run all usp_InsertMetrics tests:
-- EXEC tSQLt.Run 'usp_InsertMetricsTests';
GO

PRINT '';
PRINT '========================================================';
PRINT 'usp_InsertMetrics Tests Created (RED Phase)';
PRINT '========================================================';
PRINT 'Run tests with: EXEC tSQLt.Run ''usp_InsertMetricsTests'';';
PRINT 'Expected: ALL TESTS SHOULD FAIL (procedure does not exist yet)';
PRINT 'Next: Create dbo.usp_InsertMetrics (GREEN phase)';
PRINT '========================================================';
GO
