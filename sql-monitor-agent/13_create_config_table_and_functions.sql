USE [DBATools]
GO

-- =============================================
-- Configuration Table and Timezone Support
-- Enables centralized configuration management
-- =============================================

-- Create configuration table
IF OBJECT_ID('dbo.MonitoringConfig', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MonitoringConfig
    (
        ConfigID                INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        ConfigKey               VARCHAR(100) NOT NULL UNIQUE,
        ConfigValue             NVARCHAR(500) NULL,
        ConfigDescription       NVARCHAR(1000) NULL,
        DataType                VARCHAR(50) NULL, -- 'STRING', 'INT', 'BIT', 'DECIMAL', 'DATETIME'
        DefaultValue            NVARCHAR(500) NULL,
        IsActive                BIT NOT NULL DEFAULT 1,
        LastModified            DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        ModifiedBy              SYSNAME NULL DEFAULT SUSER_SNAME()
    )

    CREATE NONCLUSTERED INDEX IX_MonitoringConfig_Key_Active
        ON dbo.MonitoringConfig(ConfigKey, IsActive)
END
GO

-- Populate default configuration values
IF NOT EXISTS (SELECT 1 FROM dbo.MonitoringConfig WHERE ConfigKey = 'ReportingTimeZone')
BEGIN
    INSERT INTO dbo.MonitoringConfig (ConfigKey, ConfigValue, ConfigDescription, DataType, DefaultValue)
    VALUES
    ('ReportingTimeZone', 'Eastern Standard Time', 'Time zone for all reporting views (data stored in UTC)', 'STRING', 'Eastern Standard Time'),
    ('RetentionDays', '30', 'Number of days to retain snapshot data before purging', 'INT', '30'),
    ('CollectionIntervalMinutes', '5', 'Frequency of snapshot collection in minutes', 'INT', '5'),
    ('EnableP0Collection', '1', 'Enable P0 (Critical) data collection', 'BIT', '1'),
    ('EnableP1Collection', '1', 'Enable P1 (High) data collection', 'BIT', '1'),
    ('EnableP2Collection', '1', 'Enable P2 (Medium) data collection', 'BIT', '1'),
    ('EnableP3Collection', '0', 'Enable P3 (Low) data collection', 'BIT', '0'),
    ('QueryStatsTopN', '100', 'Number of top queries to capture per snapshot', 'INT', '100'),
    ('QueryPlansTopN', '30', 'Number of query plans to capture per snapshot', 'INT', '30'),
    ('MissingIndexTopN', '100', 'Number of missing index recommendations to capture', 'INT', '100'),
    ('WaitStatsTopN', '100', 'Number of wait types to capture per snapshot', 'INT', '100'),
    ('BackupWarningHours', '24', 'Hours since last full backup before WARNING status', 'INT', '24'),
    ('BackupCriticalHours', '48', 'Hours since last full backup before CRITICAL status', 'INT', '48'),
    ('LogBackupWarningMinutes', '60', 'Minutes since last log backup before WARNING (FULL recovery only)', 'INT', '60'),
    ('PageLifeExpectancyWarning', '500', 'Page Life Expectancy threshold for WARNING (seconds)', 'INT', '500'),
    ('PageLifeExpectancyCritical', '300', 'Page Life Expectancy threshold for CRITICAL (seconds)', 'INT', '300'),
    ('BufferCacheHitRatioWarning', '95', 'Buffer Cache Hit Ratio threshold for WARNING (percent)', 'DECIMAL', '95'),
    ('BufferCacheHitRatioCritical', '90', 'Buffer Cache Hit Ratio threshold for CRITICAL (percent)', 'DECIMAL', '90'),
    ('IOLatencyWarningMs', '15', 'I/O latency threshold for WARNING (milliseconds)', 'INT', '15'),
    ('IOLatencyCriticalMs', '25', 'I/O latency threshold for CRITICAL (milliseconds)', 'INT', '25'),
    ('VLFCountWarning', '1000', 'VLF count threshold for WARNING', 'INT', '1000'),
    ('VLFCountCritical', '10000', 'VLF count threshold for CRITICAL', 'INT', '10000'),
    ('BlockingSessionsWarning', '5', 'Number of blocking sessions for WARNING', 'INT', '5'),
    ('BlockingSessionsCritical', '10', 'Number of blocking sessions for CRITICAL', 'INT', '10'),
    ('RunnableTasksWarning', '2', 'Runnable tasks per scheduler for WARNING (CPU pressure)', 'INT', '2'),
    ('RunnableTasksCritical', '5', 'Runnable tasks per scheduler for CRITICAL (CPU pressure)', 'INT', '5'),
    ('LogSpaceUsedWarning', '80', 'Log space used percentage for WARNING', 'INT', '80'),
    ('LogSpaceUsedCritical', '90', 'Log space used percentage for CRITICAL', 'INT', '90')

    PRINT 'Default configuration values inserted'
END
GO

-- =============================================
-- Configuration Helper Functions
-- =============================================

-- Function to get config value as string
CREATE OR ALTER FUNCTION dbo.fn_GetConfigValue
(
    @ConfigKey VARCHAR(100)
)
RETURNS NVARCHAR(500)
AS
BEGIN
    DECLARE @Value NVARCHAR(500)

    SELECT @Value = ConfigValue
    FROM dbo.MonitoringConfig
    WHERE ConfigKey = @ConfigKey
      AND IsActive = 1

    -- Return default if not found
    IF @Value IS NULL
    BEGIN
        SELECT @Value = DefaultValue
        FROM dbo.MonitoringConfig
        WHERE ConfigKey = @ConfigKey
    END

    RETURN @Value
END
GO

-- Function to get config value as integer
CREATE OR ALTER FUNCTION dbo.fn_GetConfigInt
(
    @ConfigKey VARCHAR(100)
)
RETURNS INT
AS
BEGIN
    DECLARE @Value INT

    SELECT @Value = TRY_CAST(ConfigValue AS INT)
    FROM dbo.MonitoringConfig
    WHERE ConfigKey = @ConfigKey
      AND IsActive = 1

    -- Return default if not found or invalid
    IF @Value IS NULL
    BEGIN
        SELECT @Value = TRY_CAST(DefaultValue AS INT)
        FROM dbo.MonitoringConfig
        WHERE ConfigKey = @ConfigKey
    END

    RETURN ISNULL(@Value, 0)
END
GO

-- Function to get config value as bit
CREATE OR ALTER FUNCTION dbo.fn_GetConfigBit
(
    @ConfigKey VARCHAR(100)
)
RETURNS BIT
AS
BEGIN
    DECLARE @Value BIT

    SELECT @Value = TRY_CAST(ConfigValue AS BIT)
    FROM dbo.MonitoringConfig
    WHERE ConfigKey = @ConfigKey
      AND IsActive = 1

    -- Return default if not found or invalid
    IF @Value IS NULL
    BEGIN
        SELECT @Value = TRY_CAST(DefaultValue AS BIT)
        FROM dbo.MonitoringConfig
        WHERE ConfigKey = @ConfigKey
    END

    RETURN ISNULL(@Value, 0)
END
GO

-- =============================================
-- Timezone Conversion Functions
-- =============================================

-- Convert UTC to configured reporting timezone
-- Note: Functions cannot contain TRY/CATCH blocks
CREATE OR ALTER FUNCTION dbo.fn_ConvertToReportingTime
(
    @UTCDateTime DATETIME2(3)
)
RETURNS DATETIME2(3)
AS
BEGIN
    DECLARE @TimeZone NVARCHAR(500)
    DECLARE @LocalTime DATETIME2(3)

    -- Get configured timezone
    SELECT @TimeZone = dbo.fn_GetConfigValue('ReportingTimeZone')

    -- Default to Eastern Standard Time if not configured
    IF @TimeZone IS NULL OR @TimeZone = ''
        SET @TimeZone = 'Eastern Standard Time'

    -- Convert UTC to local time
    -- Note: AT TIME ZONE requires SQL Server 2016+
    -- Returns DATETIMEOFFSET, cast to DATETIME2
    SET @LocalTime = CAST(@UTCDateTime AT TIME ZONE 'UTC' AT TIME ZONE @TimeZone AS DATETIME2(3))

    RETURN @LocalTime
END
GO

-- Convert reporting time to UTC
-- Note: Functions cannot contain TRY/CATCH blocks
CREATE OR ALTER FUNCTION dbo.fn_ConvertToUTC
(
    @LocalDateTime DATETIME2(3)
)
RETURNS DATETIME2(3)
AS
BEGIN
    DECLARE @TimeZone NVARCHAR(500)
    DECLARE @UTCTime DATETIME2(3)

    -- Get configured timezone
    SELECT @TimeZone = dbo.fn_GetConfigValue('ReportingTimeZone')

    -- Default to Eastern Standard Time if not configured
    IF @TimeZone IS NULL OR @TimeZone = ''
        SET @TimeZone = 'Eastern Standard Time'

    -- Convert local time to UTC
    -- Returns DATETIMEOFFSET, cast to DATETIME2
    SET @UTCTime = CAST(@LocalDateTime AT TIME ZONE @TimeZone AT TIME ZONE 'UTC' AS DATETIME2(3))

    RETURN @UTCTime
END
GO

-- Note: Reporting views moved to 09_create_reporting_views.sql
-- (Must be created after collector tables exist)

-- =============================================
-- Configuration Management Procedures
-- =============================================

-- Update a configuration value
CREATE OR ALTER PROCEDURE dbo.DBA_UpdateConfig
    @ConfigKey VARCHAR(100),
    @ConfigValue NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON

    UPDATE dbo.MonitoringConfig
    SET ConfigValue = @ConfigValue,
        LastModified = SYSUTCDATETIME(),
        ModifiedBy = SUSER_SNAME()
    WHERE ConfigKey = @ConfigKey

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Configuration key "%s" not found', 16, 1, @ConfigKey)
        RETURN -1
    END

    PRINT 'Configuration updated: ' + @ConfigKey + ' = ' + @ConfigValue
    RETURN 0
END
GO

-- View all configuration
CREATE OR ALTER PROCEDURE dbo.DBA_ViewConfig
    @ConfigKey VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON

    IF @ConfigKey IS NULL
    BEGIN
        -- Show all config
        SELECT
            ConfigKey,
            ConfigValue,
            DefaultValue,
            DataType,
            ConfigDescription,
            IsActive,
            LastModified,
            ModifiedBy
        FROM dbo.MonitoringConfig
        ORDER BY ConfigKey
    END
    ELSE
    BEGIN
        -- Show specific config
        SELECT
            ConfigKey,
            ConfigValue,
            DefaultValue,
            DataType,
            ConfigDescription,
            IsActive,
            LastModified,
            ModifiedBy
        FROM dbo.MonitoringConfig
        WHERE ConfigKey = @ConfigKey
    END
END
GO

-- Reset configuration to defaults
CREATE OR ALTER PROCEDURE dbo.DBA_ResetConfig
    @ConfigKey VARCHAR(100) = NULL,
    @ResetAll BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    IF @ResetAll = 1
    BEGIN
        UPDATE dbo.MonitoringConfig
        SET ConfigValue = DefaultValue,
            LastModified = SYSUTCDATETIME(),
            ModifiedBy = SUSER_SNAME()

        PRINT 'All configuration values reset to defaults'
    END
    ELSE IF @ConfigKey IS NOT NULL
    BEGIN
        UPDATE dbo.MonitoringConfig
        SET ConfigValue = DefaultValue,
            LastModified = SYSUTCDATETIME(),
            ModifiedBy = SUSER_SNAME()
        WHERE ConfigKey = @ConfigKey

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('Configuration key "%s" not found', 16, 1, @ConfigKey)
            RETURN -1
        END

        PRINT 'Configuration reset to default: ' + @ConfigKey
    END
    ELSE
    BEGIN
        RAISERROR('Must specify @ConfigKey or @ResetAll = 1', 16, 1)
        RETURN -1
    END

    RETURN 0
END
GO

PRINT 'Configuration table and timezone support created successfully'
PRINT ''
PRINT 'Available configuration:'
EXEC dbo.DBA_ViewConfig
PRINT ''
PRINT 'Usage Examples:'
PRINT '  -- View all config:     EXEC DBA_ViewConfig'
PRINT '  -- View specific:       EXEC DBA_ViewConfig ''ReportingTimeZone'''
PRINT '  -- Update config:       EXEC DBA_UpdateConfig ''RetentionDays'', ''60'''
PRINT '  -- Reset to default:    EXEC DBA_ResetConfig ''RetentionDays'''
PRINT '  -- Reset all:           EXEC DBA_ResetConfig @ResetAll = 1'
PRINT ''
PRINT 'Timezone Conversion:'
PRINT '  -- All *_ET views show times in Eastern timezone'
PRINT '  -- Data is stored in UTC in the database'
PRINT '  -- Change timezone:     EXEC DBA_UpdateConfig ''ReportingTimeZone'', ''Pacific Standard Time'''
GO
