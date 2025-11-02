-- =====================================================
-- Phase 3 - Feature #5: Predictive Analytics
-- Database Tables for Trend Analysis and Capacity Forecasting
-- =====================================================
-- File: 80-create-predictive-analytics-tables.sql
-- Purpose: Create tables for trend calculation and capacity forecasting
-- Dependencies: 02-create-tables.sql (Servers table)
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
GO

PRINT '======================================';
PRINT 'Creating Predictive Analytics Tables';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Table 1: MetricTrends
-- Stores calculated trends (linear regression results)
-- =====================================================

IF OBJECT_ID('dbo.MetricTrends', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.MetricTrends;
    PRINT '  Dropped existing dbo.MetricTrends table';
END;
GO

CREATE TABLE dbo.MetricTrends (
    TrendID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    MetricCategory VARCHAR(50) NOT NULL,
    MetricName VARCHAR(100) NOT NULL,
    TrendPeriod VARCHAR(20) NOT NULL, -- '7day', '14day', '30day', '90day'
    CalculationDate DATE NOT NULL,

    -- Linear regression results
    Slope DECIMAL(18,6) NULL,           -- Growth rate per day
    Intercept DECIMAL(18,6) NULL,       -- Y-intercept
    RSquared DECIMAL(10,4) NULL,        -- R² (goodness of fit: 0-1)

    -- Trend characteristics
    TrendDirection VARCHAR(20) NULL,    -- 'Increasing', 'Decreasing', 'Stable'
    GrowthPercentPerDay DECIMAL(10,4) NULL,
    GrowthAbsolutePerDay DECIMAL(18,6) NULL,

    -- Statistical measures
    SampleCount INT NOT NULL,
    StartValue DECIMAL(18,4) NULL,
    EndValue DECIMAL(18,4) NULL,
    AverageValue DECIMAL(18,4) NULL,
    StandardDeviation DECIMAL(18,4) NULL,
    MinValue DECIMAL(18,4) NULL,
    MaxValue DECIMAL(18,4) NULL,

    -- Metadata
    CalculatedAt DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT PK_MetricTrends PRIMARY KEY CLUSTERED (TrendID),
    CONSTRAINT FK_MetricTrends_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_MetricTrends_Server_Category_Name
ON dbo.MetricTrends (ServerID, MetricCategory, MetricName, TrendPeriod, CalculationDate DESC)
INCLUDE (Slope, TrendDirection, RSquared);
GO

CREATE NONCLUSTERED INDEX IX_MetricTrends_Date
ON dbo.MetricTrends (CalculationDate DESC)
INCLUDE (ServerID, MetricCategory, MetricName, Slope);
GO

PRINT '✅ Created: dbo.MetricTrends';
PRINT '';

-- =====================================================
-- Table 2: CapacityForecasts
-- Stores capacity predictions (when will resource be full)
-- =====================================================

IF OBJECT_ID('dbo.CapacityForecasts', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.CapacityForecasts;
    PRINT '  Dropped existing dbo.CapacityForecasts table';
END;
GO

CREATE TABLE dbo.CapacityForecasts (
    ForecastID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    ResourceType VARCHAR(50) NOT NULL,  -- 'Disk', 'Memory', 'Connections', 'TempDB', 'Database'
    ResourceName VARCHAR(200) NULL,     -- Disk drive letter, database name, etc.
    ForecastDate DATE NOT NULL,

    -- Current state
    CurrentValue DECIMAL(18,4) NOT NULL,
    CurrentUtilization DECIMAL(10,2) NULL, -- Percentage used

    -- Capacity limits
    MaxCapacity DECIMAL(18,4) NULL,
    WarningThreshold DECIMAL(10,2) NULL,  -- Default: 80%
    CriticalThreshold DECIMAL(10,2) NULL, -- Default: 90%

    -- Predictions
    DailyGrowthRate DECIMAL(18,6) NOT NULL,
    PredictedWarningDate DATE NULL,       -- When 80% capacity reached
    PredictedCriticalDate DATE NULL,      -- When 90% capacity reached
    PredictedFullDate DATE NULL,          -- When 100% capacity reached
    DaysToWarning INT NULL,
    DaysToCritical INT NULL,
    DaysToFull INT NULL,

    -- Prediction confidence
    Confidence DECIMAL(10,2) NULL,        -- R² from trend analysis (0-100%)
    PredictionModel VARCHAR(50) NULL,     -- 'Linear', 'Exponential', 'Moving Average'

    -- Metadata
    TrendID BIGINT NULL,                  -- Reference to MetricTrends
    CalculatedAt DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT PK_CapacityForecasts PRIMARY KEY CLUSTERED (ForecastID),
    CONSTRAINT FK_CapacityForecasts_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
    CONSTRAINT FK_CapacityForecasts_Trend FOREIGN KEY (TrendID) REFERENCES dbo.MetricTrends(TrendID)
);
GO

CREATE NONCLUSTERED INDEX IX_CapacityForecasts_Server_Resource
ON dbo.CapacityForecasts (ServerID, ResourceType, ResourceName, ForecastDate DESC)
INCLUDE (DaysToWarning, DaysToCritical, DaysToFull);
GO

CREATE NONCLUSTERED INDEX IX_CapacityForecasts_DaysToWarning
ON dbo.CapacityForecasts (DaysToWarning ASC)
WHERE DaysToWarning IS NOT NULL AND DaysToWarning <= 90
INCLUDE (ServerID, ResourceType, ResourceName, CurrentUtilization);
GO

PRINT '✅ Created: dbo.CapacityForecasts';
PRINT '';

-- =====================================================
-- Table 3: PredictiveAlerts
-- Alert configurations for capacity warnings
-- =====================================================

IF OBJECT_ID('dbo.PredictiveAlerts', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.PredictiveAlerts;
    PRINT '  Dropped existing dbo.PredictiveAlerts table';
END;
GO

CREATE TABLE dbo.PredictiveAlerts (
    PredictiveAlertID INT IDENTITY(1,1) NOT NULL,
    AlertName NVARCHAR(255) NOT NULL,
    ResourceType VARCHAR(50) NOT NULL,
    ResourcePattern NVARCHAR(200) NULL,   -- Wildcard pattern (e.g., 'C:%', 'prod_%')

    -- Alert thresholds
    WarningDaysThreshold INT NOT NULL,    -- Alert when N days to capacity
    CriticalDaysThreshold INT NOT NULL,

    -- Minimum confidence required
    MinimumConfidence DECIMAL(10,2) NOT NULL DEFAULT 70.0, -- R² >= 0.70

    -- Suppression
    SuppressPattern NVARCHAR(500) NULL,   -- Regex to suppress (e.g., 'test%')
    SuppressStartTime TIME(7) NULL,
    SuppressEndTime TIME(7) NULL,

    -- Notification settings
    IsEnabled BIT NOT NULL DEFAULT 1,
    SendEmail BIT NOT NULL DEFAULT 1,
    EmailRecipients NVARCHAR(MAX) NULL,
    SendWebhook BIT NOT NULL DEFAULT 0,
    WebhookURL NVARCHAR(500) NULL,

    -- Metadata
    CreatedBy NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    CreatedDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    ModifiedBy NVARCHAR(128) NULL,
    ModifiedDate DATETIME2(7) NULL,

    CONSTRAINT PK_PredictiveAlerts PRIMARY KEY CLUSTERED (PredictiveAlertID),
    CONSTRAINT UQ_PredictiveAlerts_Name UNIQUE (AlertName),
    CONSTRAINT CK_PredictiveAlerts_DaysThreshold CHECK (CriticalDaysThreshold <= WarningDaysThreshold)
);
GO

CREATE NONCLUSTERED INDEX IX_PredictiveAlerts_Enabled
ON dbo.PredictiveAlerts (IsEnabled, ResourceType)
INCLUDE (WarningDaysThreshold, CriticalDaysThreshold, MinimumConfidence);
GO

PRINT '✅ Created: dbo.PredictiveAlerts';
PRINT '';

-- =====================================================
-- Table 4: TrendCalculationHistory
-- Audit trail of trend calculations
-- =====================================================

IF OBJECT_ID('dbo.TrendCalculationHistory', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.TrendCalculationHistory;
    PRINT '  Dropped existing dbo.TrendCalculationHistory table';
END;
GO

CREATE TABLE dbo.TrendCalculationHistory (
    CalculationID BIGINT IDENTITY(1,1) NOT NULL,
    CalculationTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    CalculationType VARCHAR(50) NOT NULL, -- 'Trends', 'Forecasts', 'Alerts'
    TrendPeriod VARCHAR(20) NULL,
    ServersProcessed INT NOT NULL,
    MetricsProcessed INT NOT NULL,
    TrendsCalculated INT NOT NULL,
    ForecastsGenerated INT NOT NULL,
    AlertsRaised INT NOT NULL,
    DurationSeconds INT NOT NULL,
    Status VARCHAR(50) NOT NULL,
    ErrorMessage NVARCHAR(MAX) NULL,

    CONSTRAINT PK_TrendCalculationHistory PRIMARY KEY CLUSTERED (CalculationID)
);
GO

CREATE NONCLUSTERED INDEX IX_TrendCalculationHistory_Time
ON dbo.TrendCalculationHistory (CalculationTime DESC)
INCLUDE (CalculationType, Status, DurationSeconds);
GO

PRINT '✅ Created: dbo.TrendCalculationHistory';
PRINT '';

-- =====================================================
-- Insert Default Predictive Alerts
-- =====================================================

PRINT '======================================';
PRINT 'Inserting Default Predictive Alerts';
PRINT '======================================';
PRINT '';

-- Alert 1: Disk Space - Warning
INSERT INTO dbo.PredictiveAlerts (
    AlertName,
    ResourceType,
    WarningDaysThreshold,
    CriticalDaysThreshold,
    MinimumConfidence,
    IsEnabled,
    SendEmail,
    SendWebhook
)
VALUES (
    'Disk Space - Low Capacity Warning',
    'Disk',
    30,  -- Warn 30 days before reaching 80%
    7,   -- Critical 7 days before reaching 90%
    70.0,
    1,
    1,
    0
);
PRINT '  ✅ Created: Disk Space - Low Capacity Warning';

-- Alert 2: Memory - Warning
INSERT INTO dbo.PredictiveAlerts (
    AlertName,
    ResourceType,
    WarningDaysThreshold,
    CriticalDaysThreshold,
    MinimumConfidence,
    IsEnabled,
    SendEmail,
    SendWebhook
)
VALUES (
    'Memory - Increasing Utilization',
    'Memory',
    30,  -- Warn 30 days before exhaustion
    7,   -- Critical 7 days before exhaustion
    70.0,
    1,
    1,
    0
);
PRINT '  ✅ Created: Memory - Increasing Utilization';

-- Alert 3: Connections - Warning
INSERT INTO dbo.PredictiveAlerts (
    AlertName,
    ResourceType,
    WarningDaysThreshold,
    CriticalDaysThreshold,
    MinimumConfidence,
    IsEnabled,
    SendEmail,
    SendWebhook
)
VALUES (
    'Connections - Pool Exhaustion',
    'Connections',
    30,  -- Warn 30 days before max connections
    7,   -- Critical 7 days before max connections
    70.0,
    1,
    1,
    0
);
PRINT '  ✅ Created: Connections - Pool Exhaustion';

-- Alert 4: Database Size - Warning
INSERT INTO dbo.PredictiveAlerts (
    AlertName,
    ResourceType,
    WarningDaysThreshold,
    CriticalDaysThreshold,
    MinimumConfidence,
    IsEnabled,
    SendEmail,
    SendWebhook
)
VALUES (
    'Database - Rapid Growth',
    'Database',
    60,  -- Warn 60 days before database size limits
    14,  -- Critical 14 days before limits
    70.0,
    1,
    1,
    0
);
PRINT '  ✅ Created: Database - Rapid Growth';

-- Alert 5: TempDB - Warning
INSERT INTO dbo.PredictiveAlerts (
    AlertName,
    ResourceType,
    WarningDaysThreshold,
    CriticalDaysThreshold,
    MinimumConfidence,
    IsEnabled,
    SendEmail,
    SendWebhook
)
VALUES (
    'TempDB - Size Growth',
    'TempDB',
    14,  -- Warn 14 days before TempDB issues
    3,   -- Critical 3 days before issues
    70.0,
    1,
    1,
    0
);
PRINT '  ✅ Created: TempDB - Size Growth';

PRINT '';

-- =====================================================
-- Summary and Verification
-- =====================================================

PRINT '======================================';
PRINT 'Predictive Analytics Tables Created';
PRINT '======================================';
PRINT '';

PRINT 'Tables Created:';
SELECT
    name AS TableName,
    create_date AS CreatedDate
FROM sys.tables
WHERE name IN ('MetricTrends', 'CapacityForecasts', 'PredictiveAlerts', 'TrendCalculationHistory')
ORDER BY name;

PRINT '';
PRINT 'Indexes Created:';
SELECT
    t.name AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType
FROM sys.indexes i
INNER JOIN sys.tables t ON i.object_id = t.object_id
WHERE t.name IN ('MetricTrends', 'CapacityForecasts', 'PredictiveAlerts', 'TrendCalculationHistory')
  AND i.name IS NOT NULL
ORDER BY t.name, i.name;

PRINT '';
PRINT 'Default Predictive Alerts:';
SELECT
    PredictiveAlertID,
    AlertName,
    ResourceType,
    WarningDaysThreshold,
    CriticalDaysThreshold,
    CASE IsEnabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS Status
FROM dbo.PredictiveAlerts
ORDER BY PredictiveAlertID;

PRINT '';
PRINT '✅ Predictive Analytics Database Foundation Complete';
PRINT '';
PRINT 'Next Steps:';
PRINT '  1. Create trend calculation procedures (81-create-trend-procedures.sql)';
PRINT '  2. Create capacity forecasting procedures (82-create-forecasting-procedures.sql)';
PRINT '  3. Create SQL Agent jobs for automation';
PRINT '======================================';

GO
