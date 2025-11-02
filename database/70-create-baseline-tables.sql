-- =====================================================
-- Phase 3 - Feature #4: Historical Baseline Comparison
-- Database Tables for Baseline Aggregation and Anomaly Detection
-- =====================================================
-- File: 70-create-baseline-tables.sql
-- Purpose: Create tables for storing historical baselines and anomaly detection
-- Dependencies: 02-create-tables.sql (PerformanceMetrics)
-- =====================================================

USE MonitoringDB;
GO

SET QUOTED_IDENTIFIER ON;
GO

PRINT '======================================';
PRINT 'Creating Historical Baseline Tables';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Table 1: Metric Baselines
-- Stores aggregated baseline metrics at different time windows
-- =====================================================

IF OBJECT_ID('dbo.MetricBaselines', 'U') IS NOT NULL
    DROP TABLE dbo.MetricBaselines;
GO

CREATE TABLE dbo.MetricBaselines (
    BaselineID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    MetricCategory VARCHAR(50) NOT NULL,
    MetricName VARCHAR(100) NOT NULL,

    -- Time window for baseline
    BaselinePeriod VARCHAR(20) NOT NULL, -- '7day', '14day', '30day', '90day'
    BaselineDate DATE NOT NULL, -- Date baseline was calculated

    -- Statistical aggregations
    AvgValue DECIMAL(18,4) NOT NULL,
    MinValue DECIMAL(18,4) NOT NULL,
    MaxValue DECIMAL(18,4) NOT NULL,
    StdDevValue DECIMAL(18,4) NULL,
    MedianValue DECIMAL(18,4) NULL,
    P95Value DECIMAL(18,4) NULL, -- 95th percentile
    P99Value DECIMAL(18,4) NULL, -- 99th percentile

    -- Sample statistics
    SampleCount INT NOT NULL,
    SampleStartTime DATETIME2(7) NOT NULL,
    SampleEndTime DATETIME2(7) NOT NULL,

    -- Metadata
    CalculatedAt DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT PK_MetricBaselines PRIMARY KEY CLUSTERED (BaselineID),
    CONSTRAINT FK_MetricBaselines_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_MetricBaselines_Server_Date
ON dbo.MetricBaselines (ServerID, BaselinePeriod, BaselineDate DESC)
INCLUDE (MetricCategory, MetricName, AvgValue, StdDevValue);
GO

CREATE NONCLUSTERED INDEX IX_MetricBaselines_Metric
ON dbo.MetricBaselines (MetricCategory, MetricName, BaselinePeriod)
INCLUDE (ServerID, AvgValue, StdDevValue);
GO

PRINT '✅ Created: dbo.MetricBaselines';
PRINT '';

-- =====================================================
-- Table 2: Anomaly Detection Results
-- Stores detected anomalies based on baseline comparison
-- =====================================================

IF OBJECT_ID('dbo.AnomalyDetections', 'U') IS NOT NULL
    DROP TABLE dbo.AnomalyDetections;
GO

CREATE TABLE dbo.AnomalyDetections (
    AnomalyID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    MetricCategory VARCHAR(50) NOT NULL,
    MetricName VARCHAR(100) NOT NULL,

    -- Anomaly details
    DetectionTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    CurrentValue DECIMAL(18,4) NOT NULL,
    BaselineValue DECIMAL(18,4) NOT NULL,
    BaselineStdDev DECIMAL(18,4) NULL,
    DeviationScore DECIMAL(10,4) NOT NULL, -- How many standard deviations from baseline

    -- Severity based on deviation
    Severity VARCHAR(20) NOT NULL, -- 'Low', 'Medium', 'High', 'Critical'
    AnomalyType VARCHAR(50) NOT NULL, -- 'Spike', 'Drop', 'Trend', 'Outlier'

    -- Baseline reference
    BaselinePeriod VARCHAR(20) NOT NULL,
    BaselineID BIGINT NULL,

    -- Resolution
    IsResolved BIT NOT NULL DEFAULT 0,
    ResolvedAt DATETIME2(7) NULL,
    ResolutionNotes NVARCHAR(MAX) NULL,

    CONSTRAINT PK_AnomalyDetections PRIMARY KEY CLUSTERED (AnomalyID),
    CONSTRAINT FK_AnomalyDetections_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
    CONSTRAINT FK_AnomalyDetections_Baseline FOREIGN KEY (BaselineID) REFERENCES dbo.MetricBaselines(BaselineID)
);
GO

CREATE NONCLUSTERED INDEX IX_AnomalyDetections_Unresolved
ON dbo.AnomalyDetections (IsResolved, DetectionTime DESC)
INCLUDE (ServerID, Severity, AnomalyType);
GO

CREATE NONCLUSTERED INDEX IX_AnomalyDetections_Server
ON dbo.AnomalyDetections (ServerID, DetectionTime DESC)
WHERE IsResolved = 0;
GO

PRINT '✅ Created: dbo.AnomalyDetections';
PRINT '';

-- =====================================================
-- Table 3: Baseline Calculation History
-- Tracks baseline calculation runs for auditing
-- =====================================================

IF OBJECT_ID('dbo.BaselineCalculationHistory', 'U') IS NOT NULL
    DROP TABLE dbo.BaselineCalculationHistory;
GO

CREATE TABLE dbo.BaselineCalculationHistory (
    CalculationID BIGINT IDENTITY(1,1) NOT NULL,
    CalculationTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    BaselinePeriod VARCHAR(20) NOT NULL,

    -- Statistics
    ServersProcessed INT NOT NULL,
    MetricsProcessed INT NOT NULL,
    BaselinesCreated INT NOT NULL,
    AnomaliesDetected INT NOT NULL,

    -- Performance
    DurationSeconds INT NOT NULL,
    ErrorCount INT NOT NULL DEFAULT 0,
    ErrorMessage NVARCHAR(MAX) NULL,

    -- Status
    Status VARCHAR(20) NOT NULL, -- 'Success', 'Partial', 'Failed'

    CONSTRAINT PK_BaselineCalculationHistory PRIMARY KEY CLUSTERED (CalculationID)
);
GO

CREATE NONCLUSTERED INDEX IX_BaselineCalculationHistory_Time
ON dbo.BaselineCalculationHistory (CalculationTime DESC);
GO

PRINT '✅ Created: dbo.BaselineCalculationHistory';
PRINT '';

-- =====================================================
-- Table 4: Baseline Thresholds
-- Configurable thresholds for anomaly detection
-- =====================================================

IF OBJECT_ID('dbo.BaselineThresholds', 'U') IS NOT NULL
    DROP TABLE dbo.BaselineThresholds;
GO

CREATE TABLE dbo.BaselineThresholds (
    ThresholdID INT IDENTITY(1,1) NOT NULL,
    MetricCategory VARCHAR(50) NOT NULL,
    MetricName VARCHAR(100) NULL, -- NULL = applies to all metrics in category

    -- Anomaly detection thresholds (in standard deviations)
    LowSeverityThreshold DECIMAL(5,2) NOT NULL DEFAULT 2.0, -- 2 sigma
    MediumSeverityThreshold DECIMAL(5,2) NOT NULL DEFAULT 3.0, -- 3 sigma
    HighSeverityThreshold DECIMAL(5,2) NOT NULL DEFAULT 4.0, -- 4 sigma
    CriticalSeverityThreshold DECIMAL(5,2) NOT NULL DEFAULT 5.0, -- 5 sigma

    -- Anomaly type detection
    DetectSpikes BIT NOT NULL DEFAULT 1, -- Sudden increases
    DetectDrops BIT NOT NULL DEFAULT 1, -- Sudden decreases
    DetectTrends BIT NOT NULL DEFAULT 0, -- Gradual changes (requires multiple samples)

    -- Configuration
    IsEnabled BIT NOT NULL DEFAULT 1,
    MinSampleCount INT NOT NULL DEFAULT 100, -- Minimum samples required for baseline

    -- Metadata
    CreatedBy NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    CreatedDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    ModifiedBy NVARCHAR(128) NULL,
    ModifiedDate DATETIME2(7) NULL,

    CONSTRAINT PK_BaselineThresholds PRIMARY KEY CLUSTERED (ThresholdID)
);
GO

CREATE NONCLUSTERED INDEX IX_BaselineThresholds_Metric
ON dbo.BaselineThresholds (MetricCategory, MetricName)
WHERE IsEnabled = 1;
GO

PRINT '✅ Created: dbo.BaselineThresholds';
PRINT '';

-- =====================================================
-- Insert Default Baseline Thresholds
-- =====================================================

PRINT '======================================';
PRINT 'Inserting Default Baseline Thresholds';
PRINT '======================================';
PRINT '';

-- CPU thresholds (sensitive to spikes)
INSERT INTO dbo.BaselineThresholds (MetricCategory, MetricName, LowSeverityThreshold, MediumSeverityThreshold, HighSeverityThreshold, CriticalSeverityThreshold, DetectSpikes, DetectDrops)
VALUES ('CPU', 'Percent', 2.0, 3.0, 4.0, 5.0, 1, 0);

PRINT '✅ CPU baseline thresholds configured';

-- Memory thresholds (sensitive to drops)
INSERT INTO dbo.BaselineThresholds (MetricCategory, MetricName, LowSeverityThreshold, MediumSeverityThreshold, HighSeverityThreshold, CriticalSeverityThreshold, DetectSpikes, DetectDrops)
VALUES ('Memory', NULL, 2.0, 3.0, 4.0, 5.0, 0, 1);

PRINT '✅ Memory baseline thresholds configured';

-- Disk thresholds (sensitive to both spikes and drops)
INSERT INTO dbo.BaselineThresholds (MetricCategory, MetricName, LowSeverityThreshold, MediumSeverityThreshold, HighSeverityThreshold, CriticalSeverityThreshold, DetectSpikes, DetectDrops)
VALUES ('Disk', NULL, 2.5, 3.5, 4.5, 5.5, 1, 1);

PRINT '✅ Disk baseline thresholds configured';

-- Wait Stats thresholds (sensitive to spikes)
INSERT INTO dbo.BaselineThresholds (MetricCategory, MetricName, LowSeverityThreshold, MediumSeverityThreshold, HighSeverityThreshold, CriticalSeverityThreshold, DetectSpikes, DetectDrops)
VALUES ('Wait', NULL, 2.0, 3.0, 4.0, 5.0, 1, 0);

PRINT '✅ Wait Stats baseline thresholds configured';

-- Health Score thresholds (sensitive to drops)
INSERT INTO dbo.BaselineThresholds (MetricCategory, MetricName, LowSeverityThreshold, MediumSeverityThreshold, HighSeverityThreshold, CriticalSeverityThreshold, DetectSpikes, DetectDrops)
VALUES ('HealthScore', NULL, 2.0, 3.0, 4.0, 5.0, 0, 1);

PRINT '✅ Health Score baseline thresholds configured';

-- Query Performance thresholds (sensitive to spikes)
INSERT INTO dbo.BaselineThresholds (MetricCategory, MetricName, LowSeverityThreshold, MediumSeverityThreshold, HighSeverityThreshold, CriticalSeverityThreshold, DetectSpikes, DetectDrops)
VALUES ('QueryPerformance', NULL, 2.5, 3.5, 4.5, 5.5, 1, 0);

PRINT '✅ Query Performance baseline thresholds configured';

PRINT '';

-- =====================================================
-- Summary
-- =====================================================

PRINT '======================================';
PRINT 'Baseline Tables Created Successfully';
PRINT '======================================';
PRINT '';
PRINT 'Summary:';
PRINT '  ✅ Tables: MetricBaselines, AnomalyDetections, BaselineCalculationHistory, BaselineThresholds';
PRINT '  ✅ Indexes: 7 non-clustered indexes for optimal query performance';
PRINT '  ✅ Default thresholds: 6 metric categories configured';
PRINT '';
PRINT 'Baseline Periods Supported:';
PRINT '  - 7-day rolling baseline';
PRINT '  - 14-day rolling baseline';
PRINT '  - 30-day rolling baseline';
PRINT '  - 90-day rolling baseline';
PRINT '';
PRINT 'Anomaly Detection:';
PRINT '  - Spike detection (sudden increases)';
PRINT '  - Drop detection (sudden decreases)';
PRINT '  - Statistical deviation (2/3/4/5 sigma thresholds)';
PRINT '  - Severity classification (Low/Medium/High/Critical)';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Create baseline calculation procedures';
PRINT '2. Create anomaly detection procedures';
PRINT '3. Create SQL Agent job for daily baseline updates';
PRINT '4. Create Grafana dashboards with baseline overlays';
PRINT '======================================';
PRINT '';

GO
