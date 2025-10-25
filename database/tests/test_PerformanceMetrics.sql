-- =====================================================
-- Test Suite: PerformanceMetrics Table Tests
-- Description: TDD tests for partitioned dbo.PerformanceMetrics table
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- TDD Phase: RED (Write tests FIRST, expect failures)
-- =====================================================

USE MonitoringDB;
GO

-- Create test class for PerformanceMetrics table tests
EXEC tSQLt.NewTestClass 'PerformanceMetricsTests';
GO

-- =====================================================
-- Test 1: PerformanceMetrics table should exist
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test PerformanceMetrics table should exist]
AS
BEGIN
    -- Arrange & Act & Assert
    EXEC tSQLt.AssertObjectExists @ObjectName = 'dbo.PerformanceMetrics';
END
GO

-- =====================================================
-- Test 2: PerformanceMetrics should have composite primary key
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test Should have primary key on CollectionTime and MetricID]
AS
BEGIN
    -- Arrange
    DECLARE @PKColumnCount INT;

    -- Act
    SELECT @PKColumnCount = COUNT(*)
    FROM sys.index_columns ic
    INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    WHERE i.object_id = OBJECT_ID('dbo.PerformanceMetrics')
      AND i.is_primary_key = 1;

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 2,
        @Actual = @PKColumnCount,
        @Message = 'Primary key should include 2 columns (CollectionTime, MetricID)';
END
GO

-- =====================================================
-- Test 3: MetricID should be IDENTITY column
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test MetricID should be IDENTITY column]
AS
BEGIN
    -- Arrange
    DECLARE @IsIdentity BIT;

    -- Act
    SELECT @IsIdentity = is_identity
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics')
      AND name = 'MetricID';

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @IsIdentity,
        @Message = 'MetricID should be an IDENTITY column';
END
GO

-- =====================================================
-- Test 4: Should have foreign key to Servers table
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test Should have foreign key to Servers table]
AS
BEGIN
    -- Arrange
    DECLARE @FKExists BIT = 0;

    -- Act
    IF EXISTS (
        SELECT 1
        FROM sys.foreign_keys fk
        INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN sys.columns c ON fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id
        WHERE fk.parent_object_id = OBJECT_ID('dbo.PerformanceMetrics')
          AND fk.referenced_object_id = OBJECT_ID('dbo.Servers')
          AND c.name = 'ServerID'
    )
    SET @FKExists = 1;

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @FKExists,
        @Message = 'PerformanceMetrics should have FK to Servers on ServerID';
END
GO

-- =====================================================
-- Test 5: Required columns should exist
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test Required columns should exist]
AS
BEGIN
    -- Arrange
    DECLARE @ColumnCount INT;

    -- Act
    SELECT @ColumnCount = COUNT(*)
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics')
      AND name IN ('MetricID', 'ServerID', 'CollectionTime', 'MetricCategory', 'MetricName', 'MetricValue');

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 6,
        @Actual = @ColumnCount,
        @Message = 'PerformanceMetrics should have 6 required columns';
END
GO

-- =====================================================
-- Test 6: CollectionTime should be DATETIME2 NOT NULL
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test CollectionTime should be DATETIME2 NOT NULL]
AS
BEGIN
    -- Arrange
    DECLARE @DataType NVARCHAR(128);
    DECLARE @IsNullable BIT;

    -- Act
    SELECT
        @DataType = TYPE_NAME(user_type_id),
        @IsNullable = is_nullable
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics')
      AND name = 'CollectionTime';

    -- Assert
    EXEC tSQLt.AssertEqualsString
        @Expected = 'datetime2',
        @Actual = @DataType,
        @Message = 'CollectionTime should be DATETIME2';

    EXEC tSQLt.AssertEquals
        @Expected = 0,
        @Actual = @IsNullable,
        @Message = 'CollectionTime should be NOT NULL';
END
GO

-- =====================================================
-- Test 7: MetricValue should be DECIMAL(18,4) and nullable
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test MetricValue should be DECIMAL with precision 18 and scale 4]
AS
BEGIN
    -- Arrange
    DECLARE @DataType NVARCHAR(128);
    DECLARE @Precision INT;
    DECLARE @Scale INT;

    -- Act
    SELECT
        @DataType = TYPE_NAME(user_type_id),
        @Precision = precision,
        @Scale = scale
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics')
      AND name = 'MetricValue';

    -- Assert
    EXEC tSQLt.AssertEqualsString
        @Expected = 'decimal',
        @Actual = @DataType,
        @Message = 'MetricValue should be DECIMAL';

    EXEC tSQLt.AssertEquals
        @Expected = 18,
        @Actual = @Precision,
        @Message = 'MetricValue precision should be 18';

    EXEC tSQLt.AssertEquals
        @Expected = 4,
        @Actual = @Scale,
        @Message = 'MetricValue scale should be 4';
END
GO

-- =====================================================
-- Test 8: Should be partitioned by CollectionTime
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test Table should be partitioned]
AS
BEGIN
    -- Arrange
    DECLARE @IsPartitioned BIT = 0;

    -- Act
    SELECT @IsPartitioned = 1
    FROM sys.tables t
    INNER JOIN sys.indexes i ON t.object_id = i.object_id
    INNER JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
    WHERE t.name = 'PerformanceMetrics'
      AND i.index_id IN (0, 1); -- Heap or clustered index

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @IsPartitioned,
        @Message = 'PerformanceMetrics should be partitioned';
END
GO

-- =====================================================
-- Test 9: Should have columnstore index
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test Should have columnstore index]
AS
BEGIN
    -- Arrange
    DECLARE @HasColumnstore BIT = 0;

    -- Act
    IF EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics')
          AND type_desc IN ('CLUSTERED COLUMNSTORE', 'NONCLUSTERED COLUMNSTORE')
    )
    SET @HasColumnstore = 1;

    -- Assert
    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @HasColumnstore,
        @Message = 'PerformanceMetrics should have a columnstore index';
END
GO

-- =====================================================
-- Test 10: Should insert valid performance metric
-- =====================================================
CREATE OR ALTER PROCEDURE PerformanceMetricsTests.[test Should insert valid metric successfully]
AS
BEGIN
    -- Arrange
    EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';
    EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';

    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'SQL-TEST-01', 'Test', 1);

    -- Act
    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    VALUES (1, '2025-10-25 10:00:00', 'CPU', 'Percent', 45.5);

    -- Assert
    DECLARE @ActualRowCount INT;
    SELECT @ActualRowCount = COUNT(*)
    FROM dbo.PerformanceMetrics
    WHERE ServerID = 1 AND MetricCategory = 'CPU';

    EXEC tSQLt.AssertEquals
        @Expected = 1,
        @Actual = @ActualRowCount,
        @Message = 'Should be able to insert a valid performance metric';
END
GO

-- =====================================================
-- Run All Tests
-- =====================================================
-- Execute this to run all PerformanceMetrics table tests:
-- EXEC tSQLt.Run 'PerformanceMetricsTests';
GO

PRINT '';
PRINT '========================================================';
PRINT 'PerformanceMetrics Table Tests Created (RED Phase)';
PRINT '========================================================';
PRINT 'Run tests with: EXEC tSQLt.Run ''PerformanceMetricsTests'';';
PRINT 'Expected: ALL TESTS SHOULD FAIL (table does not exist yet)';
PRINT 'Next: Create partitioned PerformanceMetrics table (GREEN phase)';
PRINT '========================================================';
GO
