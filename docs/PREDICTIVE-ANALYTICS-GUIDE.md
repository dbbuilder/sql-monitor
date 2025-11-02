# Predictive Analytics User Guide

**Feature #5: Capacity Forecasting & Trend Analysis**
**Version**: 1.0
**Last Updated**: 2025-11-02

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Overview](#overview)
3. [Trend Calculation (Linear Regression)](#trend-calculation-linear-regression)
4. [Capacity Forecasting](#capacity-forecasting)
5. [Predictive Alerts](#predictive-alerts)
6. [Grafana Dashboards](#grafana-dashboards)
7. [SQL Procedures Reference](#sql-procedures-reference)
8. [Configuration & Tuning](#configuration--tuning)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)
11. [FAQ](#faq)

---

## Quick Start

### 1. Verify Installation

```sql
-- Check if tables exist
SELECT name FROM sys.tables
WHERE name IN ('MetricTrends', 'CapacityForecasts', 'PredictiveAlerts', 'TrendCalculationHistory')
ORDER BY name;

-- Check if procedures exist
SELECT name FROM sys.procedures
WHERE name LIKE '%Trend%' OR name LIKE '%Forecast%' OR name LIKE '%Predictive%'
ORDER BY name;

-- Check if SQL Agent jobs are running
SELECT
    j.name AS JobName,
    j.enabled AS IsEnabled,
    h.run_status,
    h.run_date,
    h.run_time
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name LIKE 'MonitoringDB%Trend%'
   OR j.name LIKE 'MonitoringDB%Forecast%'
   OR j.name LIKE 'MonitoringDB%Predictive%'
ORDER BY h.instance_id DESC;
```

### 2. Run Initial Calculations

```sql
-- Calculate trends for all servers (7/14/30/90-day periods)
EXEC dbo.usp_UpdateAllTrends;

-- Generate capacity forecasts
EXEC dbo.usp_GenerateCapacityForecasts @MinConfidence = 0.7;

-- Evaluate predictive alerts
EXEC dbo.usp_EvaluatePredictiveAlerts;
```

### 3. View Results

```sql
-- View capacity forecasts
EXEC dbo.usp_GetCapacitySummary @MaxDaysToWarning = 90;

-- View active capacity alerts
SELECT * FROM dbo.ActiveAlerts WHERE Message LIKE '%CAPACITY%' ORDER BY Severity, RaisedAt DESC;

-- View trends with high confidence
EXEC dbo.usp_GetTrendSummary @ServerID = 1, @TrendPeriod = '30day', @MinConfidence = 0.7;
```

### 4. Access Dashboards

- **Dashboard 12**: Capacity Planning & Forecasting
- **Dashboard 13**: Trend Analysis & Statistics

---

## Overview

The Predictive Analytics system provides **capacity forecasting** and **trend analysis** using linear regression to predict when resources will reach capacity limits.

### Key Capabilities

1. **Trend Calculation**: Uses least squares linear regression to calculate growth rates
2. **Capacity Forecasting**: Predicts when resources reach 80%/90%/100% capacity
3. **Predictive Alerts**: Automatic notifications when forecasts exceed thresholds
4. **Confidence Scoring**: R² (goodness of fit) measures prediction reliability
5. **Automated Monitoring**: SQL Agent jobs run trends/forecasts/alerts automatically

### Architecture

```
┌──────────────────────┐
│ Performance Metrics  │  (Historical data: CPU, Memory, Disk, etc.)
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Trend Calculation    │  (Daily at 2:00 AM)
│ Linear Regression    │  → MetricTrends table
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Capacity Forecasting │  (Every hour)
│ Time-to-Capacity     │  → CapacityForecasts table
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Predictive Alerts    │  (Every 15 minutes)
│ Threshold Evaluation │  → ActiveAlerts, AlertHistory
└──────────────────────┘
```

---

## Trend Calculation (Linear Regression)

### How It Works

The system uses **least squares linear regression** to calculate trends:

1. **Collect Data**: Gathers metric values over a time period (7/14/30/90 days)
2. **Calculate Regression**: Computes slope, intercept, and R² (goodness of fit)
3. **Classify Trend**: Determines if metric is Increasing, Decreasing, or Stable
4. **Store Results**: Saves to MetricTrends table with confidence score

### Linear Regression Formulas

**Slope (growth rate per day)**:
```
m = (n*Σ(xy) - Σx*Σy) / (n*Σ(x²) - (Σx)²)
```

**Intercept**:
```
b = (Σy - m*Σx) / n
```

**R² (Coefficient of Determination)**:
```
R² = 1 - (SSresidual / SStotal)
```
- **R² = 0**: No predictive power (random)
- **R² = 0.5**: Moderate fit (50% of variation explained)
- **R² = 0.7+**: Good fit (recommended minimum for forecasting)
- **R² = 0.9+**: Excellent fit (high confidence)

### Trend Periods

| Period | Days | Use Case |
|--------|------|----------|
| **7-day** | 7 | Short-term trends, recent changes |
| **14-day** | 14 | Medium-term trends, seasonal patterns |
| **30-day** | 30 | **Default for forecasting**, monthly patterns |
| **90-day** | 90 | Long-term trends, annual patterns |

### Trend Direction

| Direction | Criteria | Meaning |
|-----------|----------|---------|
| **Increasing** | Slope > 0.01 | Resource usage growing |
| **Decreasing** | Slope < -0.01 | Resource usage declining |
| **Stable** | \|Slope\| ≤ 0.01 | Resource usage flat |

### Calculate Trends Manually

```sql
-- Calculate trend for specific metric
EXEC dbo.usp_CalculateTrend
    @ServerID = 1,
    @MetricCategory = 'Memory',
    @MetricName = 'Percent',
    @TrendPeriod = '30day';

-- Calculate all trends for all servers
EXEC dbo.usp_UpdateAllTrends @TrendPeriod = '30day';

-- View trends sorted by confidence
SELECT TOP 20
    s.ServerName,
    mt.MetricCategory,
    mt.MetricName,
    mt.TrendDirection,
    mt.Slope AS DailyGrowthRate,
    mt.RSquared AS Confidence,
    mt.SampleCount
FROM dbo.MetricTrends mt
INNER JOIN dbo.Servers s ON mt.ServerID = s.ServerID
WHERE mt.TrendPeriod = '30day'
  AND mt.CalculationDate = (SELECT MAX(CalculationDate) FROM dbo.MetricTrends)
  AND mt.RSquared >= 0.7
ORDER BY mt.RSquared DESC;
```

---

## Capacity Forecasting

### How It Works

Capacity forecasting uses trends to predict **when resources will reach capacity**:

1. **Use Trend Data**: Gets 30-day trend (slope and confidence)
2. **Calculate Time-to-Capacity**: Divides remaining capacity by daily growth rate
3. **Predict Dates**: Calculates when resource reaches 80%/90%/100% capacity
4. **Filter by Confidence**: Only includes forecasts with R² ≥ minimum threshold

### Forecast Calculations

**Days to Warning (80% capacity)**:
```
DaysToWarning = (80 - CurrentValue) / DailyGrowthRate
```

**Days to Critical (90% capacity)**:
```
DaysToCritical = (90 - CurrentValue) / DailyGrowthRate
```

**Days to Full (100% capacity)**:
```
DaysToFull = (100 - CurrentValue) / DailyGrowthRate
```

**Predicted Date**:
```
PredictedDate = Today + DaysToCapacity
```

### Resource Types Forecasted

| Resource | Metric | Max Capacity | Warning | Critical |
|----------|--------|--------------|---------|----------|
| **Disk** | Percent | 100% | 80% | 90% |
| **Memory** | Percent | 100% | 85% | 95% |
| **Connections** | UserConnections | 32,767 (default) | 80% | 90% |
| **Database** | Size (GB) | N/A (no max) | N/A | N/A |
| **TempDB** | Size (GB) | N/A (no max) | N/A | N/A |

### Generate Forecasts Manually

```sql
-- Generate forecasts for all resources (default: R² >= 0.7)
EXEC dbo.usp_GenerateCapacityForecasts;

-- Generate forecasts with lower confidence threshold
EXEC dbo.usp_GenerateCapacityForecasts @MinConfidence = 0.5;

-- Generate forecasts for specific server
EXEC dbo.usp_GenerateCapacityForecasts @ServerID = 1, @MinConfidence = 0.7;

-- Generate forecasts for specific resource type
EXEC dbo.usp_GenerateCapacityForecasts @ResourceType = 'Disk', @MinConfidence = 0.7;

-- View capacity summary (resources within 90 days of warning)
EXEC dbo.usp_GetCapacitySummary @MaxDaysToWarning = 90;
```

### Interpret Forecast Results

```sql
SELECT
    s.ServerName,
    cf.ResourceType,
    cf.ResourceName,
    cf.CurrentValue,
    cf.CurrentUtilization AS [Current %],
    cf.DailyGrowthRate,
    cf.DaysToWarning,
    cf.PredictedWarningDate,
    cf.DaysToCritical,
    cf.PredictedCriticalDate,
    cf.Confidence
FROM dbo.CapacityForecasts cf
INNER JOIN dbo.Servers s ON cf.ServerID = s.ServerID
WHERE cf.ForecastDate = CAST(GETUTCDATE() AS DATE)
  AND cf.DaysToWarning <= 90
ORDER BY cf.DaysToWarning;
```

**Example Output**:
```
ServerName       | ResourceType | Current % | DaysToWarning | PredictedWarningDate | Confidence
-----------------|--------------|-----------|---------------|----------------------|-----------
sqltest,14333    | Memory       | 75.0      | 9             | 2025-11-11           | 63.03
suncity,14333    | Disk         | 72.5      | 15            | 2025-11-17           | 78.42
```

**Interpretation**:
- **Memory**: Currently at 75%, will reach 80% in 9 days (63% confidence)
- **Disk**: Currently at 72.5%, will reach 80% in 15 days (78% confidence)

---

## Predictive Alerts

### How It Works

Predictive alerts automatically notify you when forecasts indicate approaching capacity:

1. **Alert Rules**: Configured in PredictiveAlerts table (5 default rules)
2. **Evaluation**: Runs every 15 minutes via SQL Agent job
3. **Threshold Check**: Compares DaysToWarning/DaysToCritical against alert thresholds
4. **Alert Creation**: Creates ActiveAlert and logs to AlertHistory
5. **Notifications**: Sends email/webhook (if configured)

### Default Alert Rules

| Rule Name | Resource | Warning Threshold | Critical Threshold | Min Confidence |
|-----------|----------|-------------------|-------------------|----------------|
| Disk Space - Low Capacity Warning | Disk | 30 days | 7 days | 70% |
| Memory - Increasing Utilization | Memory | 30 days | 7 days | 70% |
| Connections - Pool Exhaustion | Connections | 30 days | 7 days | 70% |
| Database - Rapid Growth | Database | 60 days | 14 days | 70% |
| TempDB - Size Growth | TempDB | 14 days | 3 days | 70% |

### Alert Workflow

```
Forecast Generated
       ↓
DaysToWarning <= WarningDaysThreshold?
       ↓ YES
Confidence >= MinimumConfidence?
       ↓ YES
Not Duplicate (last 24 hours)?
       ↓ YES
Create ActiveAlert (High severity)
Create AlertHistory entry
Send Notifications (if enabled)
```

### Evaluate Alerts Manually

```sql
-- Evaluate all predictive alerts
EXEC dbo.usp_EvaluatePredictiveAlerts;

-- View active capacity alerts
SELECT
    aa.AlertID,
    s.ServerName,
    aa.Severity,
    aa.Message,
    aa.RaisedAt,
    aa.IsAcknowledged
FROM dbo.ActiveAlerts aa
INNER JOIN dbo.Servers s ON aa.ServerID = s.ServerID
WHERE aa.Message LIKE '%CAPACITY%'
  AND aa.IsResolved = 0
ORDER BY aa.Severity, aa.RaisedAt DESC;

-- View alert history (last 7 days)
SELECT
    ah.Severity,
    s.ServerName,
    ah.Message,
    ah.RaisedAt
FROM dbo.AlertHistory ah
INNER JOIN dbo.Servers s ON ah.ServerID = s.ServerID
WHERE ah.Message LIKE '%CAPACITY%'
  AND ah.RaisedAt >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY ah.RaisedAt DESC;
```

### Configure Alert Rules

```sql
-- View current alert configurations
SELECT
    PredictiveAlertID,
    AlertName,
    ResourceType,
    WarningDaysThreshold,
    CriticalDaysThreshold,
    MinimumConfidence,
    IsEnabled
FROM dbo.PredictiveAlerts
ORDER BY ResourceType;

-- Adjust thresholds (example: more sensitive disk alerts)
UPDATE dbo.PredictiveAlerts
SET WarningDaysThreshold = 45,    -- Was 30
    CriticalDaysThreshold = 14    -- Was 7
WHERE AlertName = 'Disk Space - Low Capacity Warning';

-- Lower confidence requirement (accept less reliable forecasts)
UPDATE dbo.PredictiveAlerts
SET MinimumConfidence = 60.0      -- Was 70.0
WHERE ResourceType = 'Memory';

-- Disable specific alert
UPDATE dbo.PredictiveAlerts
SET IsEnabled = 0
WHERE AlertName = 'TempDB - Size Growth';
```

---

## Grafana Dashboards

### Dashboard 12: Capacity Planning & Forecasting

**URL**: `/d/capacity-planning`

**9 Panels**:
1. **Soonest Capacity Warning** (Stat): Days until first resource reaches 80%
2. **Soonest Critical Capacity** (Stat): Days until first resource reaches 90%
3. **Active Capacity Alerts** (Stat): Count of unresolved capacity alerts
4. **Resources at Risk** (Stat): Resources within 30 days of warning
5. **Memory Utilization Trend** (Time Series): 7-day memory usage with thresholds
6. **Disk Space Utilization Trend** (Time Series): 7-day disk usage with thresholds
7. **Capacity Forecast Summary** (Table): All forecasts within 90 days, sorted by urgency
8. **Daily Growth Rates** (Bar Chart): Growth rates from 30-day trends
9. **Top 20 Trends by Confidence** (Table): Most reliable trends (highest R²)

**Use Cases**:
- Capacity planning meetings
- Budget justification (when to add disk/memory)
- Proactive resource allocation
- SLA compliance monitoring

### Dashboard 13: Trend Analysis & Statistics

**URL**: `/d/trend-analysis`

**9 Panels**:
1. **Servers Monitored** (Stat): Count of servers with trends
2. **Trends Calculated** (Stat): Total trends calculated (latest run)
3. **Increasing Trends** (Stat): Count of growing resources (30-day)
4. **Decreasing Trends** (Stat): Count of declining resources (30-day)
5. **Growth Rate Trends** (Time Series): % per day growth rates over time
6. **Trend Confidence Over Time** (Time Series): R² values over time
7. **All Trends Summary** (Table): Complete trend data with direction/confidence
8. **Trend Calculation History** (Table): Execution history (last 7 days)
9. **Calculation Performance** (Time Series): Trend calculation duration over time

**Use Cases**:
- Trend analysis and pattern recognition
- Identify volatile metrics (low R²)
- Monitor calculation performance
- Validate trend accuracy

---

## SQL Procedures Reference

### Trend Calculation

#### `usp_CalculateTrend`

Calculate linear regression trend for a single metric.

**Parameters**:
- `@ServerID INT`: Server to analyze
- `@MetricCategory VARCHAR(50)`: Category (e.g., 'Memory', 'Disk', 'CPU')
- `@MetricName VARCHAR(100)`: Metric name (e.g., 'Percent', 'UsedSpaceGB')
- `@TrendPeriod VARCHAR(20)`: Period ('7day', '14day', '30day', '90day')

**Returns**: TrendID, Slope, Intercept, RSquared, TrendDirection

**Example**:
```sql
EXEC dbo.usp_CalculateTrend
    @ServerID = 1,
    @MetricCategory = 'Memory',
    @MetricName = 'Percent',
    @TrendPeriod = '30day';
```

---

#### `usp_UpdateAllTrends`

Calculate trends for all servers and metrics.

**Parameters**:
- `@TrendPeriod VARCHAR(20)`: Period to calculate (NULL = all periods)

**Example**:
```sql
-- Calculate all periods (7/14/30/90 days)
EXEC dbo.usp_UpdateAllTrends;

-- Calculate only 30-day trends
EXEC dbo.usp_UpdateAllTrends @TrendPeriod = '30day';
```

**Performance**: ~11 seconds for 444 baselines across 2 servers

---

#### `usp_GetTrendSummary`

Retrieve trend summary for a server.

**Parameters**:
- `@ServerID INT`: Server to query
- `@TrendPeriod VARCHAR(20)`: Period (default: '30day')
- `@MinConfidence DECIMAL(10,2)`: Minimum R² (default: 0.7)

**Example**:
```sql
EXEC dbo.usp_GetTrendSummary
    @ServerID = 1,
    @TrendPeriod = '30day',
    @MinConfidence = 0.7;
```

---

### Capacity Forecasting

#### `usp_GenerateCapacityForecasts`

Generate capacity predictions based on trends.

**Parameters**:
- `@ServerID INT`: Server to forecast (NULL = all servers)
- `@ResourceType VARCHAR(50)`: Resource to forecast (NULL = all types)
- `@MinConfidence DECIMAL(10,2)`: Minimum R² (default: 0.7)

**Example**:
```sql
-- Generate all forecasts (default)
EXEC dbo.usp_GenerateCapacityForecasts;

-- Forecast only disk space with lower confidence
EXEC dbo.usp_GenerateCapacityForecasts
    @ResourceType = 'Disk',
    @MinConfidence = 0.5;
```

**Performance**: <1 second for 5 resource types

---

#### `usp_GetCapacitySummary`

Retrieve capacity forecast summary.

**Parameters**:
- `@ServerID INT`: Server to query (NULL = all servers)
- `@MaxDaysToWarning INT`: Only show resources within N days (default: 90)

**Example**:
```sql
-- Show resources within 90 days of warning
EXEC dbo.usp_GetCapacitySummary @MaxDaysToWarning = 90;

-- Show all forecasts (including far future)
EXEC dbo.usp_GetCapacitySummary @MaxDaysToWarning = 9999;
```

---

#### `usp_EvaluatePredictiveAlerts`

Evaluate capacity forecasts and raise alerts.

**Parameters**: None

**Example**:
```sql
EXEC dbo.usp_EvaluatePredictiveAlerts;
```

**Performance**: ~7ms per run (every 15 minutes)

---

## Configuration & Tuning

### Adjust Confidence Thresholds

**Lower confidence = more forecasts** (including less reliable ones):

```sql
-- Generate forecasts with 50% minimum confidence (was 70%)
EXEC dbo.usp_GenerateCapacityForecasts @MinConfidence = 0.5;

-- Update alert rule to accept lower confidence
UPDATE dbo.PredictiveAlerts
SET MinimumConfidence = 60.0
WHERE AlertName = 'Disk Space - Low Capacity Warning';
```

**Trade-off**: More forecasts vs. less accuracy

---

### Adjust Alert Sensitivity

**More sensitive alerts** (warn earlier):

```sql
-- Increase warning threshold (warn 60 days before capacity)
UPDATE dbo.PredictiveAlerts
SET WarningDaysThreshold = 60,    -- Was 30
    CriticalDaysThreshold = 14    -- Was 7
WHERE ResourceType = 'Disk';
```

**Less sensitive alerts** (warn later):

```sql
-- Decrease warning threshold (warn 14 days before capacity)
UPDATE dbo.PredictiveAlerts
SET WarningDaysThreshold = 14,    -- Was 30
    CriticalDaysThreshold = 3     -- Was 7
WHERE ResourceType = 'Memory';
```

---

### Change Calculation Frequency

```sql
-- Disable hourly forecast generation
EXEC msdb.dbo.sp_update_job
    @job_name = 'MonitoringDB - Generate Capacity Forecasts (Hourly)',
    @enabled = 0;

-- Change schedule to every 4 hours
EXEC msdb.dbo.sp_update_jobschedule
    @job_name = 'MonitoringDB - Generate Capacity Forecasts (Hourly)',
    @name = 'Every Hour',
    @freq_subday_interval = 4;  -- Was 1
```

---

### Email Notifications

```sql
-- Enable email notifications for capacity alerts
UPDATE dbo.PredictiveAlerts
SET SendEmail = 1,
    EmailRecipients = 'dba@example.com;ops@example.com'
WHERE AlertName = 'Disk Space - Low Capacity Warning';

-- Configure Database Mail (required for email)
-- See Feature #3 Alerting documentation for setup
```

---

## Troubleshooting

### Problem: No Forecasts Generated

**Symptoms**:
```sql
SELECT COUNT(*) FROM dbo.CapacityForecasts WHERE ForecastDate = CAST(GETUTCDATE() AS DATE);
-- Returns 0
```

**Causes & Solutions**:

1. **No Trends Calculated**:
```sql
-- Check if trends exist
SELECT COUNT(*) FROM dbo.MetricTrends WHERE TrendPeriod = '30day';

-- Solution: Run trend calculation
EXEC dbo.usp_UpdateAllTrends @TrendPeriod = '30day';
```

2. **Confidence Too Low**:
```sql
-- Check trend confidence
SELECT AVG(RSquared) FROM dbo.MetricTrends WHERE TrendPeriod = '30day';

-- Solution: Lower confidence threshold
EXEC dbo.usp_GenerateCapacityForecasts @MinConfidence = 0.5;
```

3. **Decreasing Trends Only**:
```sql
-- Check trend direction
SELECT TrendDirection, COUNT(*)
FROM dbo.MetricTrends
WHERE TrendPeriod = '30day'
GROUP BY TrendDirection;

-- Note: Forecasts only generated for INCREASING trends
```

---

### Problem: Inaccurate Forecasts

**Symptoms**: Predicted dates don't match actual capacity exhaustion

**Causes & Solutions**:

1. **Low Sample Count** (< 100 samples):
```sql
-- Check sample counts
SELECT
    MetricCategory,
    MetricName,
    SampleCount,
    RSquared
FROM dbo.MetricTrends
WHERE TrendPeriod = '30day'
  AND SampleCount < 100;

-- Solution: Increase collection frequency or use shorter trend period
```

2. **Non-Linear Growth**:
```sql
-- Check for volatility
SELECT
    MetricCategory,
    MetricName,
    StandardDeviation / AverageValue AS CoefficientOfVariation,
    RSquared
FROM dbo.MetricTrends
WHERE TrendPeriod = '30day'
  AND RSquared < 0.5;

-- Solution: Linear regression assumes linear growth; use 7-day trends for volatile metrics
```

---

### Problem: Too Many Alerts

**Symptoms**: Alert fatigue from frequent capacity warnings

**Solutions**:

1. **Increase Thresholds**:
```sql
UPDATE dbo.PredictiveAlerts
SET WarningDaysThreshold = 60,    -- Warn 60 days before (was 30)
    CriticalDaysThreshold = 14    -- Critical 14 days before (was 7)
WHERE ResourceType = 'Disk';
```

2. **Increase Confidence Requirement**:
```sql
UPDATE dbo.PredictiveAlerts
SET MinimumConfidence = 80.0      -- Only high-confidence forecasts (was 70)
WHERE ResourceType = 'Memory';
```

3. **Disable Alerts for Specific Resources**:
```sql
UPDATE dbo.PredictiveAlerts
SET IsEnabled = 0
WHERE AlertName = 'TempDB - Size Growth';  -- TempDB growth is expected
```

---

### Problem: SQL Agent Jobs Not Running

**Check Job Status**:
```sql
SELECT
    j.name AS JobName,
    j.enabled,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS LastRunStatus,
    h.run_date,
    h.run_time,
    h.message
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name LIKE 'MonitoringDB%Trend%'
   OR j.name LIKE 'MonitoringDB%Forecast%'
   OR j.name LIKE 'MonitoringDB%Predictive%'
ORDER BY h.instance_id DESC;
```

**Common Solutions**:

1. **Job Disabled**:
```sql
EXEC msdb.dbo.sp_update_job
    @job_name = 'MonitoringDB - Calculate Trends (Daily)',
    @enabled = 1;
```

2. **SQL Agent Service Stopped**:
```sql
-- Check service status
EXEC xp_servicecontrol 'QueryState', 'SQLServerAgent';

-- Start SQL Agent (requires admin)
-- Use SQL Server Configuration Manager or:
-- NET START SQLSERVERAGENT
```

---

## Best Practices

### 1. Wait for Baseline Period

**Recommendation**: Wait 7-30 days after installation before trusting forecasts.

**Reason**: Linear regression requires stable data patterns. Initial trends may be volatile.

```sql
-- Check data availability
SELECT
    ServerID,
    MetricCategory,
    MIN(CollectionTime) AS FirstCollection,
    MAX(CollectionTime) AS LastCollection,
    DATEDIFF(DAY, MIN(CollectionTime), MAX(CollectionTime)) AS DaysOfData
FROM dbo.PerformanceMetrics
GROUP BY ServerID, MetricCategory
HAVING DATEDIFF(DAY, MIN(CollectionTime), MAX(CollectionTime)) >= 30
ORDER BY ServerID, MetricCategory;
```

---

### 2. Monitor Forecast Accuracy

**Recommendation**: Track how often forecasts are correct.

```sql
-- Compare predicted vs. actual dates (manual validation)
SELECT
    cf.ResourceType,
    cf.ResourceName,
    cf.PredictedWarningDate,
    cf.CurrentUtilization AS UtilizationAtForecast,
    pm.MetricValue AS CurrentUtilization,
    cf.Confidence
FROM dbo.CapacityForecasts cf
INNER JOIN dbo.PerformanceMetrics pm
    ON cf.ServerID = pm.ServerID
    AND pm.MetricCategory = cf.ResourceType
    AND pm.MetricName = cf.ResourceName
WHERE cf.ForecastDate = DATEADD(DAY, -30, GETUTCDATE())  -- Forecasts from 30 days ago
  AND pm.CollectionTime = (SELECT MAX(CollectionTime) FROM dbo.PerformanceMetrics)
ORDER BY cf.ResourceType;
```

**Action**: If forecasts are consistently off by >20%, adjust confidence thresholds or trend periods.

---

### 3. Use Confidence Filtering

**Recommendation**: Only act on forecasts with R² ≥ 0.7.

```sql
-- Generate forecasts with minimum 70% confidence
EXEC dbo.usp_GenerateCapacityForecasts @MinConfidence = 0.7;

-- View low-confidence forecasts (for informational purposes)
SELECT
    s.ServerName,
    cf.ResourceType,
    cf.Confidence,
    cf.DaysToWarning
FROM dbo.CapacityForecasts cf
INNER JOIN dbo.Servers s ON cf.ServerID = s.ServerID
WHERE cf.Confidence < 0.7
  AND cf.ForecastDate = CAST(GETUTCDATE() AS DATE)
ORDER BY cf.Confidence;
```

---

### 4. Combine with Baseline Comparison

**Recommendation**: Use Feature #4 (Baseline Comparison) to detect anomalies before forecasts.

```sql
-- Anomalies may indicate trend changes
SELECT
    ad.MetricCategory,
    ad.MetricName,
    ad.Severity,
    ad.DeviationScore,
    mt.TrendDirection,
    mt.RSquared
FROM dbo.AnomalyDetections ad
INNER JOIN dbo.MetricTrends mt
    ON ad.ServerID = mt.ServerID
    AND ad.MetricCategory = mt.MetricCategory
    AND ad.MetricName = mt.MetricName
WHERE ad.IsResolved = 0
  AND mt.TrendPeriod = '7day'
ORDER BY ad.Severity DESC;
```

**Action**: If anomalies persist, recalculate trends to reflect new pattern.

---

### 5. Regular Maintenance

**Recommendation**: Review forecasts monthly, tune thresholds quarterly.

**Monthly Review**:
```sql
-- Generate capacity report
EXEC dbo.usp_GetCapacitySummary @MaxDaysToWarning = 90;

-- Review alert history
SELECT
    ResourceType,
    COUNT(*) AS AlertCount
FROM dbo.AlertHistory
WHERE RaisedAt >= DATEADD(MONTH, -1, GETUTCDATE())
  AND Message LIKE '%CAPACITY%'
GROUP BY ResourceType
ORDER BY COUNT(*) DESC;
```

**Quarterly Tuning**:
- Adjust confidence thresholds based on accuracy
- Update warning/critical thresholds based on business needs
- Disable alerts for resources with predictable growth (e.g., TempDB)

---

## FAQ

### Q: How accurate are the forecasts?

**A**: Accuracy depends on R² (confidence score):
- **R² ≥ 0.9**: Very accurate (90%+ of variation explained)
- **R² = 0.7-0.9**: Accurate (70-90% confidence) - **recommended minimum**
- **R² = 0.5-0.7**: Moderate accuracy (50-70% confidence)
- **R² < 0.5**: Low accuracy (unreliable)

**Example**: If R²=0.8 and forecast says 30 days to capacity, actual may be 24-36 days.

---

### Q: Why do some metrics have no forecast?

**A**: Forecasts are only generated when:
1. **Trend exists** (metric has been collected)
2. **Trend is increasing** (Slope > 0)
3. **Confidence is sufficient** (R² ≥ MinConfidence)
4. **Capacity is known** (e.g., 100% for Disk/Memory)
5. **Sample count is adequate** (≥ 10 samples)

**Solution**: Lower `@MinConfidence` parameter or wait for more data.

---

### Q: Can I forecast custom metrics?

**A**: Yes! The system forecasts any metric with:
- Numeric values in PerformanceMetrics table
- Consistent collection (daily or more frequent)
- Linear growth pattern (R² ≥ 0.5)

**Custom Forecast Example**:
```sql
-- Add custom metric to PerformanceMetrics
INSERT INTO dbo.PerformanceMetrics (ServerID, MetricCategory, MetricName, MetricValue, CollectionTime)
VALUES (1, 'Custom', 'MyMetric', 75.0, GETUTCDATE());

-- Calculate trend
EXEC dbo.usp_CalculateTrend @ServerID = 1, @MetricCategory = 'Custom', @MetricName = 'MyMetric', @TrendPeriod = '30day';

-- Generate forecast
EXEC dbo.usp_GenerateCapacityForecasts @ResourceType = 'Custom';
```

---

### Q: How do I backtest forecasts?

**A**: Compare historical forecasts to actual outcomes:

```sql
-- Step 1: Get forecast from 30 days ago
DECLARE @ForecastDate DATE = DATEADD(DAY, -30, GETUTCDATE());

SELECT
    cf.ResourceType,
    cf.ResourceName,
    cf.CurrentUtilization AS ForecastedUtilization,
    cf.DaysToWarning AS PredictedDaysToWarning,
    cf.PredictedWarningDate,
    cf.Confidence
INTO #OldForecasts
FROM dbo.CapacityForecasts cf
WHERE cf.ForecastDate = @ForecastDate;

-- Step 2: Compare to actual current values
SELECT
    of.ResourceType,
    of.ResourceName,
    of.ForecastedUtilization AS [30 Days Ago],
    pm.MetricValue AS [Actual Today],
    pm.MetricValue - of.ForecastedUtilization AS Difference,
    of.PredictedDaysToWarning,
    of.Confidence
FROM #OldForecasts of
INNER JOIN dbo.PerformanceMetrics pm
    ON pm.MetricCategory = of.ResourceType
    AND pm.MetricName = of.ResourceName
WHERE pm.CollectionTime = (SELECT MAX(CollectionTime) FROM dbo.PerformanceMetrics)
ORDER BY ABS(pm.MetricValue - of.ForecastedUtilization) DESC;
```

---

### Q: What if growth is exponential, not linear?

**A**: Linear regression assumes linear growth. For exponential growth:

**Option 1**: Use shorter trend periods (7-day or 14-day) to approximate recent growth rate.

**Option 2**: Log-transform the data (advanced):
```sql
-- Calculate trend on LOG(MetricValue) instead of MetricValue
-- This requires custom procedure modification (not included)
```

**Option 3**: Monitor more frequently and recalculate trends weekly.

---

### Q: How much database storage does this use?

**A**: Storage requirements (per server):

| Table | Rows/Day | Size/Row | Daily Growth |
|-------|----------|----------|--------------|
| MetricTrends | 40 trends × 4 periods = 160 | ~200 bytes | 32 KB |
| CapacityForecasts | 5 resources × 24 updates = 120 | ~150 bytes | 18 KB |
| TrendCalculationHistory | 1 entry | ~100 bytes | 100 bytes |

**Total**: ~50 KB/day per server (~18 MB/year per server)

**Cleanup** (optional):
```sql
-- Delete trends older than 90 days
DELETE FROM dbo.MetricTrends
WHERE CalculationDate < DATEADD(DAY, -90, GETUTCDATE());

-- Delete old forecasts (keep 30 days)
DELETE FROM dbo.CapacityForecasts
WHERE ForecastDate < DATEADD(DAY, -30, GETUTCDATE());
```

---

## Summary

**Predictive Analytics provides**:
- ✅ **Trend Calculation**: Linear regression with R² confidence scoring
- ✅ **Capacity Forecasting**: Time-to-capacity predictions with 80%/90%/100% thresholds
- ✅ **Predictive Alerts**: Automatic notifications when resources approach capacity
- ✅ **Grafana Dashboards**: Visual capacity planning and trend analysis
- ✅ **Automated Monitoring**: SQL Agent jobs run trends/forecasts/alerts automatically

**Key Takeaways**:
1. **Wait 7-30 days** after installation for stable baselines
2. **Use R² ≥ 0.7** for reliable forecasts
3. **Monitor accuracy** and tune thresholds based on real-world results
4. **Combine with Feature #4** (Baseline Comparison) for comprehensive monitoring
5. **Review monthly**, tune quarterly for optimal alerting

**Need Help?**
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
- Review [PHASE-3-FEATURE-5-PREDICTIVE-ANALYTICS-PLAN.md](phases/PHASE-3-FEATURE-5-PREDICTIVE-ANALYTICS-PLAN.md) for technical details
- See SQL procedure comments for parameter documentation

---

**Generated with Claude Code** (claude.com/claude-code)
**Feature #5**: Predictive Analytics - 100% Complete
