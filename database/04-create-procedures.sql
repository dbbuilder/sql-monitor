-- =====================================================
-- Script: 04-create-procedures.sql
-- Description: Creates stored procedures for MonitoringDB
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- TDD Phase: GREEN (Create procedures to pass tests)
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- Procedure: dbo.usp_GetServers
-- Description: Retrieves list of monitored SQL Server instances
-- Tests: database/tests/test_usp_GetServers.sql
-- Parameters:
--   @IsActive BIT = NULL (filter by active status, NULL = all)
--   @Environment NVARCHAR(50) = NULL (filter by environment, NULL = all)
-- =====================================================

CREATE OR ALTER PROCEDURE dbo.usp_GetServers
    @IsActive BIT = NULL,
    @Environment NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ServerID,
        ServerName,
        Environment,
        IsActive,
        CreatedDate,
        ModifiedDate
    FROM dbo.Servers
    WHERE (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Environment IS NULL OR Environment = @Environment)
    ORDER BY ServerName;
END
GO

PRINT 'Procedure [dbo].[usp_GetServers] created successfully.';
GO

-- =====================================================
-- Procedure: dbo.usp_InsertMetrics
-- Description: Inserts a single performance metric
-- Tests: database/tests/test_usp_InsertMetrics.sql
-- Parameters:
--   @ServerID INT (required, must exist in Servers table)
--   @CollectionTime DATETIME2 (required, when metric was collected)
--   @MetricCategory NVARCHAR(50) (required, e.g., CPU, Memory, IO)
--   @MetricName NVARCHAR(100) (required, specific metric name)
--   @MetricValue DECIMAL(18,4) (optional, NULL for non-numeric)
-- =====================================================

CREATE OR ALTER PROCEDURE dbo.usp_InsertMetrics
    @ServerID INT,
    @CollectionTime DATETIME2,
    @MetricCategory NVARCHAR(50),
    @MetricName NVARCHAR(100),
    @MetricValue DECIMAL(18,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate required parameters
    IF @ServerID IS NULL
        THROW 50001, 'Parameter @ServerID is required', 1;

    IF @CollectionTime IS NULL
        THROW 50002, 'Parameter @CollectionTime is required', 1;

    IF @MetricCategory IS NULL
        THROW 50003, 'Parameter @MetricCategory is required', 1;

    IF @MetricName IS NULL
        THROW 50004, 'Parameter @MetricName is required', 1;

    -- Insert metric
    INSERT INTO dbo.PerformanceMetrics (
        ServerID,
        CollectionTime,
        MetricCategory,
        MetricName,
        MetricValue
    )
    VALUES (
        @ServerID,
        @CollectionTime,
        @MetricCategory,
        @MetricName,
        @MetricValue
    );
END
GO

PRINT 'Procedure [dbo].[usp_InsertMetrics] created successfully.';
GO

-- =====================================================
-- Procedure: dbo.usp_GetMetrics
-- Description: Retrieves performance metrics with filtering
-- Tests: database/tests/test_usp_GetMetrics.sql
-- Parameters:
--   @ServerID INT (required, filter by server)
--   @StartTime DATETIME2 = NULL (optional, start of time range)
--   @EndTime DATETIME2 = NULL (optional, end of time range)
--   @MetricCategory NVARCHAR(50) = NULL (optional, filter by category)
--   @MetricName NVARCHAR(100) = NULL (optional, filter by metric name)
-- =====================================================

CREATE OR ALTER PROCEDURE dbo.usp_GetMetrics
    @ServerID INT,
    @StartTime DATETIME2 = NULL,
    @EndTime DATETIME2 = NULL,
    @MetricCategory NVARCHAR(50) = NULL,
    @MetricName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate required parameters
    IF @ServerID IS NULL
        THROW 50005, 'Parameter @ServerID is required', 1;

    -- Retrieve metrics with optional filters
    SELECT
        pm.MetricID,
        pm.ServerID,
        s.ServerName,
        pm.CollectionTime,
        pm.MetricCategory,
        pm.MetricName,
        pm.MetricValue
    FROM dbo.PerformanceMetrics pm
    INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
    WHERE pm.ServerID = @ServerID
      AND (@StartTime IS NULL OR pm.CollectionTime >= @StartTime)
      AND (@EndTime IS NULL OR pm.CollectionTime <= @EndTime)
      AND (@MetricCategory IS NULL OR pm.MetricCategory = @MetricCategory)
      AND (@MetricName IS NULL OR pm.MetricName = @MetricName)
    ORDER BY pm.CollectionTime DESC;
END
GO

PRINT 'Procedure [dbo].[usp_GetMetrics] created successfully.';
GO

-- =====================================================
-- Verification
-- =====================================================

PRINT '';
PRINT '========================================================';
PRINT 'Stored Procedures Created (GREEN Phase)';
PRINT '========================================================';
PRINT 'Created:';
PRINT '  - dbo.usp_GetServers (@IsActive, @Environment)';
PRINT '  - dbo.usp_InsertMetrics (@ServerID, @CollectionTime, @MetricCategory, @MetricName, @MetricValue)';
PRINT '  - dbo.usp_GetMetrics (@ServerID, @StartTime, @EndTime, @MetricCategory, @MetricName)';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Run tests to verify GREEN phase:';
PRINT '   EXEC tSQLt.Run ''usp_GetServersTests'';';
PRINT '   EXEC tSQLt.Run ''usp_InsertMetricsTests'';';
PRINT '   EXEC tSQLt.Run ''usp_GetMetricsTests'';';
PRINT '2. Expected: ALL TESTS SHOULD PASS';
PRINT '3. Update deploy-all.sql to include procedures';
PRINT '========================================================';
GO

-- Quick test query
PRINT '';
PRINT 'Quick verification (should return empty result set):';
EXEC dbo.usp_GetServers;
GO
