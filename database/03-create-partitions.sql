-- =====================================================
-- Script: 03-create-partitions.sql
-- Description: Creates partition function and scheme for monthly partitioning
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- TDD: Required for PerformanceMetrics table tests to pass
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- Partition Function: Monthly boundaries
-- Description: Creates 13 partitions (12 months + overflow)
-- =====================================================

IF NOT EXISTS (SELECT * FROM sys.partition_functions WHERE name = 'PF_MonitoringByMonth')
BEGIN
    -- Create monthly boundaries for the next 12 months
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Boundaries NVARCHAR(MAX) = '';
    DECLARE @CurrentDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, GETUTCDATE()), 0); -- First day of current month
    DECLARE @i INT = 1;

    -- Generate 12 monthly boundaries
    WHILE @i <= 12
    BEGIN
        IF @i > 1
            SET @Boundaries = @Boundaries + ', ';

        SET @Boundaries = @Boundaries + '''' + CONVERT(VARCHAR(10), DATEADD(MONTH, @i, @CurrentDate), 120) + '''';
        SET @i = @i + 1;
    END

    SET @SQL = '
    CREATE PARTITION FUNCTION PF_MonitoringByMonth (DATETIME2)
    AS RANGE RIGHT FOR VALUES (' + @Boundaries + ')';

    EXEC sp_executesql @SQL;

    PRINT 'Partition function [PF_MonitoringByMonth] created with 12 monthly boundaries.';
END
ELSE
BEGIN
    PRINT 'Partition function [PF_MonitoringByMonth] already exists.';
END
GO

-- =====================================================
-- Partition Scheme: Map partitions to PRIMARY filegroup
-- =====================================================

IF NOT EXISTS (SELECT * FROM sys.partition_schemes WHERE name = 'PS_MonitoringByMonth')
BEGIN
    -- All partitions go to PRIMARY filegroup for simplicity
    -- In production, you might use separate filegroups
    CREATE PARTITION SCHEME PS_MonitoringByMonth
    AS PARTITION PF_MonitoringByMonth
    ALL TO ([PRIMARY]);

    PRINT 'Partition scheme [PS_MonitoringByMonth] created (all partitions on PRIMARY).';
END
ELSE
BEGIN
    PRINT 'Partition scheme [PS_MonitoringByMonth] already exists.';
END
GO

-- =====================================================
-- Verification Query
-- =====================================================

PRINT '';
PRINT '========================================================';
PRINT 'Partition Function and Scheme Created';
PRINT '========================================================';

-- Show partition boundaries
SELECT
    pf.name AS PartitionFunction,
    pf.fanout AS PartitionCount,
    prv.value AS BoundaryValue,
    prv.boundary_id AS BoundaryID
FROM sys.partition_functions pf
LEFT JOIN sys.partition_range_values prv ON pf.function_id = prv.function_id
WHERE pf.name = 'PF_MonitoringByMonth'
ORDER BY prv.boundary_id;

PRINT '';
PRINT 'Next: Create PerformanceMetrics table using this partition scheme';
PRINT '========================================================';
GO
