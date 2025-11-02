# Phase 3 - Feature #5: Predictive Analytics

**Version**: 1.0
**Date**: 2025-11-02
**Status**: Planning
**Budgeted Time**: 32 hours
**Estimated Actual**: 8-10 hours (based on 75-85% efficiency trend)

---

## Table of Contents

1. [Overview](#overview)
2. [Objectives](#objectives)
3. [Technical Approach](#technical-approach)
4. [Database Schema](#database-schema)
5. [Stored Procedures](#stored-procedures)
6. [Predictive Models](#predictive-models)
7. [Grafana Dashboards](#grafana-dashboards)
8. [Integration](#integration)
9. [Implementation Phases](#implementation-phases)
10. [Success Criteria](#success-criteria)

---

## Overview

**Predictive Analytics** provides forecasting and capacity planning by analyzing historical trends to predict future resource utilization, identify growth patterns, and warn before capacity limits are reached.

### Why Predictive Analytics?

**Problem**: Reactive monitoring waits for problems to occur before alerting.

**Solution**: Predictive analytics warns **before** problems occur by:
- Forecasting when resources will reach capacity
- Identifying growth trends (CPU, memory, disk, connections)
- Predicting when index fragmentation will require maintenance
- Estimating when database files will run out of space

### Example Use Cases

1. **Disk Space Forecasting**:
   - Current: 500 GB used of 1 TB
   - Growth rate: 10 GB/week
   - **Prediction**: Disk full in 50 weeks (~11 months)
   - **Alert**: Warn 30 days before capacity reached

2. **Memory Consumption Trend**:
   - Baseline: 60% memory utilization
   - Trend: +2% per week (potential memory leak)
   - **Prediction**: Memory exhaustion in 20 weeks
   - **Alert**: Investigate memory leak

3. **Connection Pool Growth**:
   - Current: 80 connections (max: 200)
   - Growth rate: +5 connections/week
   - **Prediction**: Connection pool exhausted in 24 weeks
   - **Alert**: Increase max connections or optimize

---

## Objectives

### Primary Goals

1. **Capacity Forecasting**: Predict when resources will reach capacity limits
2. **Trend Detection**: Identify growing/declining metrics over time
3. **Predictive Alerts**: Warn before capacity limits are reached
4. **Growth Rate Analysis**: Quantify resource growth (e.g., +10 GB/week)
5. **What-If Scenarios**: Project future state based on current trends

### Secondary Goals

6. **Seasonal Pattern Detection**: Identify weekly/monthly patterns
7. **Anomaly Prediction**: Forecast when anomalies are likely to occur
8. **Confidence Intervals**: Provide prediction confidence (best/worst case)

---

## Technical Approach

### Predictive Modeling Techniques

We'll implement **linear regression** and **moving averages** using T-SQL:

#### 1. Linear Regression (Least Squares Method)

Calculates best-fit line through historical data points:

```
y = mx + b

Where:
- y = predicted value
- m = slope (growth rate)
- x = time period
- b = y-intercept (starting value)

Formulas:
- m (slope) = (n*Σ(xy) - Σx*Σy) / (n*Σ(x²) - (Σx)²)
- b (intercept) = (Σy - m*Σx) / n
```

**Example**:
- Week 1: 100 GB
- Week 2: 110 GB
- Week 3: 120 GB
- Week 4: 130 GB

Slope (m) = 10 GB/week
Intercept (b) = 90 GB
Prediction for Week 10: y = 10*10 + 90 = **190 GB**

#### 2. Exponential Moving Average (EMA)

Weighted average that gives more importance to recent values:

```
EMA_today = α * Value_today + (1 - α) * EMA_yesterday

Where:
- α (alpha) = smoothing factor (0.2 = 20% weight on latest value)
```

**Use Case**: Smooth out noise in volatile metrics (e.g., CPU spikes).

#### 3. Time-to-Capacity Calculation

Predict when a resource will reach capacity:

```
DaysToCapacity = (Capacity - CurrentValue) / DailyGrowthRate

Where:
- Capacity = Maximum limit (e.g., disk size, max connections)
- CurrentValue = Latest metric value
- DailyGrowthRate = Linear regression slope
```

**Example**:
- Disk capacity: 1000 GB
- Current usage: 500 GB
- Growth rate: 2 GB/day
- **Days to capacity**: (1000 - 500) / 2 = **250 days**

---

## Database Schema

### New Tables

#### 1. `MetricTrends`

Stores calculated trends (slope, direction, confidence) for each metric.

```sql
CREATE TABLE dbo.MetricTrends (
    TrendID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
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

    -- Statistical measures
    SampleCount INT NOT NULL,
    StartValue DECIMAL(18,4) NULL,
    EndValue DECIMAL(18,4) NULL,
    AverageValue DECIMAL(18,4) NULL,
    StandardDeviation DECIMAL(18,4) NULL,

    -- Metadata
    CalculatedAt DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    INDEX IX_MetricTrends_Server_Category_Name NONCLUSTERED (ServerID, MetricCategory, MetricName, TrendPeriod, CalculationDate DESC)
);
```

#### 2. `CapacityForecasts`

Stores capacity predictions (when will resource be full).

```sql
CREATE TABLE dbo.CapacityForecasts (
    ForecastID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ServerID INT NOT NULL,
    ResourceType VARCHAR(50) NOT NULL,  -- 'Disk', 'Memory', 'Connections', etc.
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
    Confidence DECIMAL(10,2) NULL,        -- R² from trend analysis
    PredictionModel VARCHAR(50) NULL,     -- 'Linear', 'Exponential', etc.

    -- Metadata
    CalculatedAt DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    INDEX IX_CapacityForecasts_Server_Resource NONCLUSTERED (ServerID, ResourceType, ResourceName, ForecastDate DESC)
);
```

#### 3. `PredictiveAlerts`

Stores predictive alert configurations (warn before capacity reached).

```sql
CREATE TABLE dbo.PredictiveAlerts (
    PredictiveAlertID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AlertName NVARCHAR(255) NOT NULL,
    ResourceType VARCHAR(50) NOT NULL,
    WarningDaysThreshold INT NOT NULL,    -- Alert when N days to capacity
    CriticalDaysThreshold INT NOT NULL,
    IsEnabled BIT NOT NULL DEFAULT 1,

    -- Notification settings
    SendEmail BIT NOT NULL DEFAULT 1,
    EmailRecipients NVARCHAR(MAX) NULL,
    SendWebhook BIT NOT NULL DEFAULT 0,
    WebhookURL NVARCHAR(500) NULL,

    -- Metadata
    CreatedBy NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    CreatedDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    ModifiedBy NVARCHAR(128) NULL,
    ModifiedDate DATETIME2(7) NULL,

    CONSTRAINT UQ_PredictiveAlerts_Name UNIQUE (AlertName)
);
```

#### 4. `TrendCalculationHistory`

Audit trail of trend calculations.

```sql
CREATE TABLE dbo.TrendCalculationHistory (
    CalculationID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CalculationTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    TrendPeriod VARCHAR(20) NULL,
    ServersProcessed INT NOT NULL,
    MetricsProcessed INT NOT NULL,
    TrendsCalculated INT NOT NULL,
    ForecastsGenerated INT NOT NULL,
    DurationSeconds INT NOT NULL,
    Status VARCHAR(50) NOT NULL,
    ErrorMessage NVARCHAR(MAX) NULL
);
```

---

## Stored Procedures

### Trend Calculation

#### 1. `usp_CalculateTrend`

Calculates linear regression for a single metric over a time period.

**Input**:
- @ServerID
- @MetricCategory
- @MetricName
- @TrendPeriod ('7day', '14day', '30day', '90day')

**Output**: Inserts into `MetricTrends` table

**Algorithm**:
1. Retrieve metric values for period (e.g., last 30 days)
2. Calculate linear regression (slope, intercept, R²)
3. Determine trend direction (increasing/decreasing/stable)
4. Calculate growth rate (percent per day)
5. Insert results into MetricTrends

**Example**:
```sql
EXEC dbo.usp_CalculateTrend
    @ServerID = 1,
    @MetricCategory = 'Disk',
    @MetricName = 'UsedSpaceGB',
    @TrendPeriod = '30day';
```

#### 2. `usp_UpdateAllTrends`

Master procedure - calculates trends for all servers and metrics.

**Workflow**:
1. Iterate through all active servers
2. Get distinct metric categories
3. Calculate trends for each metric (7/14/30/90-day periods)
4. Log execution to TrendCalculationHistory

**Schedule**: Daily at 2:00 AM (via SQL Agent job)

#### 3. `usp_GenerateCapacityForecasts`

Generates capacity forecasts based on trends and resource limits.

**Input**:
- @ServerID (optional, NULL = all servers)
- @ResourceType (optional, NULL = all resources)

**Logic**:
1. Get latest trend for resource (slope)
2. Get current utilization
3. Get capacity limit (from configuration or system metadata)
4. Calculate days to warning/critical/full:
   - DaysToWarning = (WarningThreshold - CurrentUtilization) / DailyGrowthRate
   - DaysToCritical = (CriticalThreshold - CurrentUtilization) / DailyGrowthRate
   - DaysToFull = (100% - CurrentUtilization) / DailyGrowthRate
5. Insert forecast into CapacityForecasts

**Example**:
```sql
EXEC dbo.usp_GenerateCapacityForecasts
    @ServerID = 1,
    @ResourceType = 'Disk';
```

#### 4. `usp_EvaluatePredictiveAlerts`

Evaluates predictive alert rules and raises alerts if thresholds exceeded.

**Logic**:
1. Get active predictive alerts
2. Check capacity forecasts against thresholds
3. Raise alert if:
   - DaysToWarning <= WarningDaysThreshold
   - DaysToCritical <= CriticalDaysThreshold
4. Send notifications

**Example**:
```sql
EXEC dbo.usp_EvaluatePredictiveAlerts;
```

### Reporting Procedures

#### 5. `usp_GetTrendSummary`

Returns trend summary for all metrics on a server.

**Output**:
- MetricCategory
- MetricName
- TrendDirection
- DailyGrowthRate
- R² (confidence)

#### 6. `usp_GetCapacityProjection`

Projects future capacity utilization for a resource.

**Input**:
- @ServerID
- @ResourceType
- @DaysAhead (e.g., 30, 60, 90)

**Output**:
- Date
- ProjectedUtilization
- ConfidenceLow (worst case)
- ConfidenceHigh (best case)

---

## Predictive Models

### Model 1: Linear Regression (Primary)

**Use Case**: Metrics with steady growth/decline (disk space, memory)

**Advantages**:
- Simple, fast calculation
- Easy to interpret (e.g., "+10 GB/week")
- Reliable for short-term forecasts (30-90 days)

**Limitations**:
- Assumes constant growth rate
- Doesn't handle seasonal patterns
- Poor for volatile metrics (CPU spikes)

**Implementation**:
```sql
-- Linear regression formulas
DECLARE @n INT;              -- Sample count
DECLARE @SumX BIGINT;        -- Sum of X (days)
DECLARE @SumY DECIMAL(18,4); -- Sum of Y (metric values)
DECLARE @SumXY DECIMAL(18,4);
DECLARE @SumX2 BIGINT;

-- Calculate slope (m)
SET @Slope = (@n * @SumXY - @SumX * @SumY) / (@n * @SumX2 - @SumX * @SumX);

-- Calculate intercept (b)
SET @Intercept = (@SumY - @Slope * @SumX) / @n;

-- Calculate R² (goodness of fit)
-- R² = 1 - (SS_res / SS_tot)
```

### Model 2: Exponential Moving Average (Secondary)

**Use Case**: Smoothing volatile metrics before trend calculation

**Advantages**:
- Reduces noise
- Gives more weight to recent values
- Good for real-time predictions

**Limitations**:
- Requires continuous updates
- More complex to implement

**Implementation**:
```sql
-- EMA calculation
DECLARE @Alpha DECIMAL(5,4) = 0.2; -- Smoothing factor
DECLARE @EMA_Previous DECIMAL(18,4);
DECLARE @EMA_Current DECIMAL(18,4);

SET @EMA_Current = @Alpha * @CurrentValue + (1 - @Alpha) * @EMA_Previous;
```

---

## Grafana Dashboards

### Dashboard 12: Capacity Planning

**Panels**:

1. **Disk Space Forecast** (Time Series)
   - Current usage (solid line)
   - Projected usage (dashed line)
   - Warning threshold (orange line at 80%)
   - Critical threshold (red line at 90%)
   - Annotations: Predicted warning/critical dates

2. **Memory Trend** (Time Series)
   - Historical memory utilization
   - Trend line
   - Growth rate annotation

3. **Days to Capacity** (Table)
   - Resource name
   - Current utilization %
   - Daily growth rate
   - Days to warning
   - Days to critical
   - Days to full

4. **Growth Rates** (Bar Chart)
   - CPU: +X% per day
   - Memory: +X% per day
   - Disk: +X GB per day
   - Connections: +X per day

5. **Trend Confidence** (Gauge)
   - R² value (0-1)
   - Color: Green (>0.9), Yellow (0.7-0.9), Red (<0.7)

### Dashboard 13: Trend Analysis

**Panels**:

1. **Metric Trends** (Heat Map)
   - X-axis: Time
   - Y-axis: Metrics
   - Color: Growth rate (red = growing, blue = declining)

2. **Trending Up** (Table)
   - Metrics with positive slope
   - Growth rate
   - R²

3. **Trending Down** (Table)
   - Metrics with negative slope
   - Decline rate
   - R²

---

## Integration

### Feature #4: Baseline Comparison

- Use baseline data as input for trend calculation
- Compare trends to baseline growth rates
- Alert if growth rate exceeds baseline by 2x

### Feature #3: Automated Alerting

- Predictive alerts integrate with existing alert infrastructure
- Use same notification system (email/webhook)
- Alert history tracking

### Feature #1: Health Score

- Include capacity forecast in health score calculation
- Deduct points if days to capacity < 30

---

## Implementation Phases

### Phase 1: Database Foundation (2-3 hours)

1. Create tables (MetricTrends, CapacityForecasts, PredictiveAlerts, TrendCalculationHistory)
2. Create indexes
3. Insert default predictive alert configurations

**Deliverable**: `database/80-create-predictive-analytics-tables.sql`

### Phase 2: Trend Calculation (3-4 hours)

1. Implement `usp_CalculateTrend` (linear regression)
2. Implement `usp_UpdateAllTrends` (master procedure)
3. Test with real data

**Deliverable**: `database/81-create-trend-procedures.sql`

### Phase 3: Capacity Forecasting (2-3 hours)

1. Implement `usp_GenerateCapacityForecasts`
2. Implement `usp_EvaluatePredictiveAlerts`
3. Test forecasting accuracy

**Deliverable**: `database/82-create-forecasting-procedures.sql`

### Phase 4: SQL Agent Jobs (30 minutes)

1. Create daily trend calculation job (2:00 AM)
2. Create hourly forecast generation job
3. Create 15-minute predictive alert evaluation job

**Deliverable**: `database/83-create-predictive-sql-agent-jobs.sql`

### Phase 5: Grafana Dashboards (2-3 hours)

1. Create Dashboard 12: Capacity Planning
2. Create Dashboard 13: Trend Analysis
3. Test queries and visualization

**Deliverable**: `dashboards/grafana/dashboards/12-capacity-planning.json`, `13-trend-analysis.json`

### Phase 6: Documentation & Testing (2-3 hours)

1. Write user guide
2. Create integration tests
3. Validate predictions against historical data

**Deliverable**: `docs/PREDICTIVE-ANALYTICS-GUIDE.md`, `tests/test-predictive-analytics.sql`

---

## Success Criteria

### Functional Requirements

- ✅ Calculate linear regression for any metric
- ✅ Generate capacity forecasts for disk/memory/connections
- ✅ Predict when resources will reach capacity (within ±10% accuracy)
- ✅ Raise alerts 30 days before capacity reached
- ✅ Grafana dashboards with forecast visualization

### Performance Requirements

- Trend calculation: <30 seconds for all servers
- Forecast generation: <10 seconds per server
- Predictive alert evaluation: <5 seconds

### Accuracy Requirements

- Short-term (30 days): ±10% accuracy
- Medium-term (60 days): ±20% accuracy
- Long-term (90 days): ±30% accuracy

**Note**: Accuracy depends on metric stability (R² > 0.7 = reliable prediction)

---

## Risks and Mitigation

### Risk 1: Poor Prediction Accuracy for Volatile Metrics

**Mitigation**:
- Use EMA smoothing before trend calculation
- Require minimum R² threshold (0.7) for forecasts
- Provide confidence intervals (best/worst case)

### Risk 2: Linear Regression Doesn't Handle Seasonal Patterns

**Mitigation**:
- Use moving averages for seasonal metrics
- Compare 30-day vs 90-day trends to detect seasonality
- Future enhancement: Seasonal decomposition (Phase 4)

### Risk 3: Database Growth from Storing Trends/Forecasts

**Mitigation**:
- Store daily trends only (not hourly)
- Purge trends older than 365 days
- Estimated size: ~1 MB per server per year

---

## Cost-Benefit Analysis

### Development Cost

- Budgeted: 32 hours
- Estimated actual: 8-10 hours
- **Cost**: $800-$1,000 @ $100/hr

### Commercial Equivalent

- SolarWinds Database Performance Analyzer: Capacity planning addon (+$500/server/year)
- Datadog Forecasting: Included in APM ($31/host/month = $372/year)
- Redgate SQL Monitor: No capacity forecasting (would need separate tool)

### Value Delivered

- **Prevent outages**: Avoid disk full, memory exhaustion (1 outage = $10k-$50k loss)
- **Optimize spending**: Right-size resources before purchasing
- **Proactive planning**: Budget for hardware upgrades 3-6 months in advance

**ROI**: Break-even after preventing 1 capacity-related outage

---

## Next Steps

1. Review and approve plan
2. Begin Phase 1: Database foundation
3. Implement Phase 2-3: Trend calculation and forecasting
4. Test predictions against historical data
5. Deploy Grafana dashboards
6. Document and test

**Estimated Completion**: 8-10 hours (vs 32 budgeted = 69-75% efficiency)

---

**Document Version**: 1.0
**Status**: Awaiting Approval
**Next**: Begin implementation (Phase 1)
