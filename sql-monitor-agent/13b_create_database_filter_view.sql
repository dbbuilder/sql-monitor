USE [DBATools]
GO

-- =============================================
-- Database Filter View
-- Centralizes database inclusion/exclusion logic
-- Configured via MonitoringConfig table
-- =============================================

-- Add filter configuration if not exists
IF NOT EXISTS (SELECT 1 FROM dbo.MonitoringConfig WHERE ConfigKey = 'DatabaseIncludeFilter')
BEGIN
    INSERT INTO dbo.MonitoringConfig (ConfigKey, ConfigValue, ConfigDescription, DataType, DefaultValue)
    VALUES
    ('DatabaseIncludeFilter', '*', 'Semicolon-separated list of database patterns to include (* = all)', 'STRING', '*'),
    ('DatabaseExcludeFilter', 'DBATools', 'Semicolon-separated list of database patterns to exclude', 'STRING', 'DBATools')

    PRINT 'Database filter configuration added'
END
GO

-- =============================================
-- Helper Function: Check if database matches pattern
-- =============================================
CREATE OR ALTER FUNCTION dbo.fn_DatabaseMatchesPattern
(
    @DatabaseName SYSNAME,
    @Pattern VARCHAR(500)
)
RETURNS BIT
AS
BEGIN
    DECLARE @Match BIT = 0

    -- Convert SQL wildcard to LIKE pattern
    -- * = % (match any characters)
    -- ? = _ (match single character)
    DECLARE @LikePattern VARCHAR(500) = REPLACE(REPLACE(@Pattern, '*', '%'), '?', '_')

    IF @DatabaseName LIKE @LikePattern
        SET @Match = 1

    RETURN @Match
END
GO

-- =============================================
-- Helper Function: Check if database should be monitored
-- =============================================
CREATE OR ALTER FUNCTION dbo.fn_ShouldMonitorDatabase
(
    @DatabaseName SYSNAME
)
RETURNS BIT
AS
BEGIN
    DECLARE @ShouldMonitor BIT = 0
    DECLARE @IncludeFilter VARCHAR(500)
    DECLARE @ExcludeFilter VARCHAR(500)

    -- Get filters from config
    SELECT @IncludeFilter = dbo.fn_GetConfigValue('DatabaseIncludeFilter')
    SELECT @ExcludeFilter = dbo.fn_GetConfigValue('DatabaseExcludeFilter')

    -- Default to include all if not configured
    IF @IncludeFilter IS NULL OR @IncludeFilter = ''
        SET @IncludeFilter = '*'

    -- Step 1: Check if database matches include filter
    DECLARE @Included BIT = 0
    DECLARE @Pattern VARCHAR(500)
    DECLARE @Pos INT

    -- Parse semicolon-separated include patterns
    WHILE LEN(@IncludeFilter) > 0
    BEGIN
        SET @Pos = CHARINDEX(';', @IncludeFilter)

        IF @Pos > 0
        BEGIN
            SET @Pattern = LTRIM(RTRIM(SUBSTRING(@IncludeFilter, 1, @Pos - 1)))
            SET @IncludeFilter = SUBSTRING(@IncludeFilter, @Pos + 1, LEN(@IncludeFilter))
        END
        ELSE
        BEGIN
            SET @Pattern = LTRIM(RTRIM(@IncludeFilter))
            SET @IncludeFilter = ''
        END

        IF dbo.fn_DatabaseMatchesPattern(@DatabaseName, @Pattern) = 1
        BEGIN
            SET @Included = 1
            BREAK
        END
    END

    -- Step 2: Check if database matches exclude filter (only if included)
    IF @Included = 1 AND @ExcludeFilter IS NOT NULL AND @ExcludeFilter <> ''
    BEGIN
        DECLARE @Excluded BIT = 0

        -- Parse semicolon-separated exclude patterns
        WHILE LEN(@ExcludeFilter) > 0
        BEGIN
            SET @Pos = CHARINDEX(';', @ExcludeFilter)

            IF @Pos > 0
            BEGIN
                SET @Pattern = LTRIM(RTRIM(SUBSTRING(@ExcludeFilter, 1, @Pos - 1)))
                SET @ExcludeFilter = SUBSTRING(@ExcludeFilter, @Pos + 1, LEN(@ExcludeFilter))
            END
            ELSE
            BEGIN
                SET @Pattern = LTRIM(RTRIM(@ExcludeFilter))
                SET @ExcludeFilter = ''
            END

            IF dbo.fn_DatabaseMatchesPattern(@DatabaseName, @Pattern) = 1
            BEGIN
                SET @Excluded = 1
                BREAK
            END
        END

        -- Include only if not excluded
        IF @Excluded = 0
            SET @ShouldMonitor = 1
    END
    ELSE IF @Included = 1
    BEGIN
        SET @ShouldMonitor = 1
    END

    RETURN @ShouldMonitor
END
GO

-- =============================================
-- View: Filtered Database List
-- Returns only databases that should be monitored
-- =============================================
CREATE OR ALTER VIEW dbo.vw_MonitoredDatabases
AS
SELECT
    d.database_id,
    d.name AS database_name,
    d.state_desc,
    d.recovery_model_desc,
    d.compatibility_level,
    d.is_read_only
FROM sys.databases d
WHERE d.state_desc = 'ONLINE'  -- Only ONLINE databases
  AND d.database_id > 4        -- Exclude system databases (master, tempdb, model, msdb)
  AND dbo.fn_ShouldMonitorDatabase(d.name) = 1  -- Apply include/exclude filters
GO

-- =============================================
-- Test/Demo Procedure
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_TestDatabaseFilters
AS
BEGIN
    SET NOCOUNT ON

    PRINT '=== Current Database Filter Configuration ==='
    PRINT ''

    SELECT
        ConfigKey,
        ConfigValue,
        ConfigDescription
    FROM dbo.MonitoringConfig
    WHERE ConfigKey IN ('DatabaseIncludeFilter', 'DatabaseExcludeFilter')

    PRINT ''
    PRINT '=== All Databases ==='
    PRINT ''

    SELECT
        database_id,
        name,
        state_desc,
        CASE WHEN dbo.fn_ShouldMonitorDatabase(name) = 1 THEN 'YES' ELSE 'NO' END AS WillMonitor
    FROM sys.databases
    WHERE database_id > 4
    ORDER BY name

    PRINT ''
    PRINT '=== Databases That Will Be Monitored ==='
    PRINT ''

    SELECT
        database_id,
        database_name,
        state_desc,
        recovery_model_desc
    FROM dbo.vw_MonitoredDatabases
    ORDER BY database_name
END
GO

PRINT ''
PRINT 'Database filter view created successfully'
PRINT ''
PRINT 'Default Configuration:'
PRINT '  Include: * (all databases)'
PRINT '  Exclude: DBATools (monitoring database itself)'
PRINT ''
PRINT 'Pattern Syntax:'
PRINT '  *       = Match any characters (e.g., "Prod*" matches "ProdDB", "Production")'
PRINT '  ?       = Match single character (e.g., "DB?" matches "DB1", "DB2")'
PRINT '  Exact   = Exact match (e.g., "MyDatabase")'
PRINT ''
PRINT 'Examples:'
PRINT '  -- Monitor only production databases:'
PRINT '      EXEC DBA_UpdateConfig ''DatabaseIncludeFilter'', ''Prod*;Production*'''
PRINT ''
PRINT '  -- Monitor all except test and DBATools:'
PRINT '      EXEC DBA_UpdateConfig ''DatabaseIncludeFilter'', ''*'''
PRINT '      EXEC DBA_UpdateConfig ''DatabaseExcludeFilter'', ''Test*;DBATools'''
PRINT ''
PRINT '  -- Monitor only specific databases:'
PRINT '      EXEC DBA_UpdateConfig ''DatabaseIncludeFilter'', ''MyDB1;MyDB2;MyDB3'''
PRINT '      EXEC DBA_UpdateConfig ''DatabaseExcludeFilter'', '''''
PRINT ''
PRINT 'Usage:'
PRINT '  -- Test filters:'
PRINT '      EXEC DBA_TestDatabaseFilters'
PRINT ''
PRINT '  -- Use in queries:'
PRINT '      SELECT * FROM vw_MonitoredDatabases'
PRINT ''
GO

-- Show current filtered database list
EXEC dbo.DBA_TestDatabaseFilters
GO
