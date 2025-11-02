# Historical Baseline Comparison & Anomaly Detection Guide

**Version**: 1.0
**Last Updated**: 2025-11-02
**Feature**: Phase 3 - Feature #4

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Overview](#overview)
3. [Baseline Periods](#baseline-periods)
4. [Statistical Metrics](#statistical-metrics)
5. [Anomaly Detection](#anomaly-detection)
6. [Severity Levels](#severity-levels)
7. [Dashboard Usage](#dashboard-usage)
8. [Threshold Configuration](#threshold-configuration)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)
11. [FAQ](#faq)

---

## Quick Start

### View Active Anomalies

```sql
-- Get all active anomalies
EXEC dbo.usp_GetActiveAnomalies;
```

### Compare Current Metrics to Baseline

```sql
-- Compare current CPU usage to baselines
EXEC dbo.usp_GetBaselineComparison
    @ServerID = 1,
    @MetricCategory = 'CPU',
    @MetricName = 'Percent';
```

### Manual Baseline Calculation

```sql
-- Calculate all baselines (normally runs daily at 3:00 AM)
EXEC dbo.usp_UpdateAllBaselines;

-- Detect anomalies (normally runs every 15 minutes)
EXEC dbo.usp_DetectAnomalies @BaselinePeriod = '7day';
```

### View in Grafana

Navigate to: **Dashboard 11 - Baseline Comparison & Anomaly Detection**

- Server selection dropdown (top-left)
- Active anomaly count (top stats)
- CPU/Memory overlay charts (current vs 7/30-day baselines)
- Anomaly table with deviation scores

---

## Overview

The **Historical Baseline Comparison** feature provides:

1. **Automatic Baseline Calculation**: Daily calculation of statistical baselines for all metrics across 7/14/30/90-day rolling windows
2. **Anomaly Detection**: Automatic detection of deviations from normal behavior using statistical analysis (z-score)
3. **Trend Analysis**: Compare current performance to historical patterns
4. **Predictive Indicators**: Early warning of performance degradation before critical thresholds are breached

### How It Works

```
┌─────────────────────┐
│ Performance Metrics │  (Raw DMV data collected every 5 minutes)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Baseline Calculator │  (Runs daily at 3:00 AM)
│ - Aggregates 7/14/  │
│   30/90-day windows │
│ - Calculates Avg,   │
│   StdDev, P95, P99  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ MetricBaselines     │  (444 baselines per calculation)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Anomaly Detector    │  (Runs every 15 minutes)
│ - Compares recent   │
│   metrics to        │
│   baselines         │
│ - Calculates        │
│   z-score           │
│ - Classifies        │
│   severity          │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ AnomalyDetections   │  (Active anomalies table)
└─────────────────────┘
```

---

## Baseline Periods

Four rolling baseline windows are calculated daily:

| Period | Lookback | Use Case | Sample Size |
|--------|----------|----------|-------------|
| **7-day** | Last 7 days | Short-term trend analysis, recent changes | ~2,000 samples |
| **14-day** | Last 14 days | Medium-term patterns, weekly cycles | ~4,000 samples |
| **30-day** | Last 30 days | Monthly trends, seasonal patterns | ~8,600 samples |
| **90-day** | Last 90 days | Long-term baseline, year-over-year comparison | ~25,900 samples |

### When to Use Each Period

- **7-day**: Detect recent configuration changes, workload shifts
- **14-day**: Identify weekly patterns (e.g., Monday spike, Friday drop)
- **30-day**: Monthly billing cycles, month-end processing patterns
- **90-day**: Long-term capacity planning, performance degradation trends

---

## Statistical Metrics

Each baseline includes the following statistical aggregations:

### Core Metrics

| Metric | Description | Use Case |
|--------|-------------|----------|
| **AvgValue** | Mean value over period | Central tendency, "normal" performance |
| **MinValue** | Minimum value observed | Lower bound, best-case performance |
| **MaxValue** | Maximum value observed | Upper bound, worst-case performance |
| **StdDevValue** | Standard deviation | Variability, used for z-score calculation |

### Percentiles

| Metric | Description | Use Case |
|--------|-------------|----------|
| **MedianValue** (P50) | 50th percentile | Typical value (less affected by outliers than average) |
| **P95Value** | 95th percentile | "Worst 5%" performance threshold |
| **P99Value** | 99th percentile | Outlier detection threshold |

### Sample Statistics

| Metric | Description | Minimum Required |
|--------|-------------|------------------|
| **SampleCount** | Number of data points | 100 samples (prevents statistical noise) |
| **SampleStartTime** | Earliest data point | N/A |
| **SampleEndTime** | Latest data point | N/A |

---

## Anomaly Detection

### Z-Score Calculation

Anomalies are detected using **z-score** (standard deviations from mean):

```
Z-Score = (CurrentValue - BaselineAvg) / BaselineStdDev
```

**Example**:
- Baseline CPU Avg: 30%
- Baseline CPU StdDev: 10%
- Current CPU: 60%
- **Z-Score** = (60 - 30) / 10 = **3.0 sigma**

A z-score of 3.0 means the current value is 3 standard deviations above the baseline (99.7th percentile).

### Anomaly Types

| Type | Description | Example |
|------|-------------|---------|
| **Spike** | Sudden increase | CPU jumps from 30% to 80% |
| **Drop** | Sudden decrease | Memory drops from 80% to 20% |
| **Trend** | Gradual change (future) | CPU slowly increasing over 7 days |
| **Outlier** | Single extreme value | One-time CPU spike to 100% |

**Current Implementation**: Spike and Drop detection only (Trend and Outlier detection planned for Phase 3.5)

### Detection Workflow

```
1. Fetch recent metrics (last 5 minutes)
2. For each metric:
   a. Retrieve 7-day baseline (Avg, StdDev)
   b. Calculate z-score
   c. If z-score > threshold:
      - Classify severity (Low/Medium/High/Critical)
      - Determine anomaly type (Spike/Drop)
      - Insert into AnomalyDetections
3. Auto-resolve anomalies (current value within 2 sigma of baseline)
```

---

## Severity Levels

Anomaly severity is based on z-score thresholds configured in `BaselineThresholds` table:

| Severity | Default Threshold | Z-Score Range | Probability |
|----------|-------------------|---------------|-------------|
| **Low** | 2.0 sigma | 2.0 - 2.99 | 95.4th - 99.7th percentile |
| **Medium** | 3.0 sigma | 3.0 - 3.99 | 99.7th - 99.99th percentile |
| **High** | 4.0 sigma | 4.0 - 4.99 | 99.99th - 99.9999th percentile |
| **Critical** | 5.0 sigma | 5.0+ | >99.9999th percentile (extremely rare) |

### Threshold Configuration by Metric Category

| Category | Low | Medium | High | Critical | Detect Spikes | Detect Drops |
|----------|-----|--------|------|----------|---------------|--------------|
| CPU | 2.0σ | 3.0σ | 4.0σ | 5.0σ | ✅ Yes | ❌ No |
| Memory | 2.0σ | 3.0σ | 4.0σ | 5.0σ | ❌ No | ✅ Yes |
| Disk | 2.5σ | 3.5σ | 4.5σ | 5.5σ | ✅ Yes | ✅ Yes |
| Wait Stats | 2.0σ | 3.0σ | 4.0σ | 5.0σ | ✅ Yes | ❌ No |
| Health Score | 2.0σ | 3.0σ | 4.0σ | 5.0σ | ❌ No | ✅ Yes |
| Query Performance | 2.5σ | 3.5σ | 4.5σ | 5.5σ | ✅ Yes | ❌ No |

**Rationale**:
- **CPU, Wait Stats, Query Performance**: Spikes indicate performance problems
- **Memory, Health Score**: Drops indicate degradation
- **Disk**: Both spikes (high I/O) and drops (storage issues) are problematic

---

## Dashboard Usage

### Dashboard 11 - Baseline Comparison & Anomaly Detection

**URL**: `http://grafana:3000/d/baseline-comparison`

#### Top Stats (Row 1)

- **Active Anomalies**: Total unresolved anomalies (color: green = 0, yellow = 1-4, orange = 5-9, red = 10+)
- **Critical Anomalies**: Unresolved critical severity anomalies (color: green = 0, red = 1+)

#### CPU % - Current vs Baselines (Row 1, Right)

- **Blue line**: Current CPU% (raw DMV data, 5-minute resolution)
- **Orange line**: 7-day baseline (average)
- **Green line**: 30-day baseline (average)

**Interpretation**:
- Current line **above** baseline = Higher than normal (potential spike)
- Current line **below** baseline = Lower than normal (potential improvement or drop)
- **Diverging baselines** (7-day vs 30-day) = Recent trend change

#### Active Anomalies Table (Row 2, Left)

Columns:
- **ServerName**: Affected server
- **MetricCategory**: CPU, Memory, Disk, etc.
- **MetricName**: Specific metric (e.g., "Percent", "AvgReadLatencyMs")
- **DetectionTime**: When anomaly was detected
- **CurrentValue**: Actual metric value
- **BaselineValue**: Expected baseline average
- **DeviationScore**: Z-score (σ)
- **Severity**: Low/Medium/High/Critical (color-coded)
- **AnomalyType**: Spike or Drop

**Sorting**: Click column headers to sort (default: DeviationScore descending)

#### Memory % - Current vs Baselines (Row 2, Right)

Same as CPU chart, but for memory usage.

#### Anomaly Deviation Trend (Row 3, Right)

Time series showing deviation scores over time. Helps identify:
- **Recurring anomalies** (spikes at same time daily)
- **Escalating issues** (deviation increasing over days)
- **Resolved anomalies** (deviation returning to normal)

#### Recent Baseline Calculations (Row 4, Full Width)

Table showing all baselines calculated in last 7 days. Columns:
- **ServerName**, **MetricCategory**, **MetricName**, **BaselinePeriod**
- **BaselineDate**: Date of calculation
- **AvgValue**, **MinValue**, **MaxValue**, **StdDevValue**
- **MedianValue**, **P95Value**, **P99Value**
- **SampleCount**: Number of data points used

**Use Case**: Verify baselines are being calculated correctly, review statistical properties of metrics.

---

## Threshold Configuration

### View Current Thresholds

```sql
SELECT
    MetricCategory,
    MetricName,
    LowSeverityThreshold,
    MediumSeverityThreshold,
    HighSeverityThreshold,
    CriticalSeverityThreshold,
    DetectSpikes,
    DetectDrops,
    MinSampleCount
FROM dbo.BaselineThresholds
WHERE IsEnabled = 1
ORDER BY MetricCategory, MetricName;
```

### Custom Threshold for Specific Metric

```sql
-- Example: Make CPU spike detection more sensitive
INSERT INTO dbo.BaselineThresholds (
    MetricCategory,
    MetricName, -- NULL = applies to all metrics in category
    LowSeverityThreshold,
    MediumSeverityThreshold,
    HighSeverityThreshold,
    CriticalSeverityThreshold,
    DetectSpikes,
    DetectDrops,
    MinSampleCount
)
VALUES (
    'CPU',
    'Percent', -- Specific metric
    1.5,  -- Low severity at 1.5σ (less sensitive)
    2.5,  -- Medium at 2.5σ
    3.5,  -- High at 3.5σ
    4.5,  -- Critical at 4.5σ
    1,    -- Detect spikes
    0,    -- Don't detect drops
    150   -- Require 150 samples minimum
);
```

### Disable Anomaly Detection for Metric

```sql
UPDATE dbo.BaselineThresholds
SET IsEnabled = 0
WHERE MetricCategory = 'QueryPerformance'
  AND MetricName = 'ExecutionCount';
```

---

## Troubleshooting

### No Baselines Calculated

**Symptoms**: `SELECT COUNT(*) FROM dbo.MetricBaselines` returns 0.

**Diagnosis**:
```sql
-- Check if baseline job ran
SELECT TOP 5
    j.name,
    h.run_date,
    h.run_time,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS Status,
    h.message
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name = 'MonitoringDB - Update Baselines (Daily)'
ORDER BY h.instance_id DESC;
```

**Solutions**:
1. **Job not scheduled**: Run `72-create-baseline-sql-agent-job.sql` to create job
2. **Job disabled**: `EXEC msdb.dbo.sp_update_job @job_name = 'MonitoringDB - Update Baselines (Daily)', @enabled = 1;`
3. **Insufficient data**: Need 100+ samples per metric. Wait for metrics collection to run.
4. **Manual run**: `EXEC dbo.usp_UpdateAllBaselines;`

### No Anomalies Detected (But System Has Issues)

**Symptoms**: Active anomalies = 0, but you know performance is degraded.

**Diagnosis**:
```sql
-- Check anomaly detection job
SELECT TOP 5
    j.name,
    h.run_date,
    h.run_time,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
    END AS Status
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name = 'MonitoringDB - Detect Anomalies (15 min)'
ORDER BY h.instance_id DESC;

-- Check if baselines exist for problematic metric
EXEC dbo.usp_GetBaselineComparison
    @ServerID = 1,
    @MetricCategory = 'CPU',
    @MetricName = 'Percent';
```

**Solutions**:
1. **Thresholds too high**: Lower severity thresholds (e.g., 2.0σ → 1.5σ)
2. **Recent performance is the new normal**: Baselines adapt daily. If system degraded gradually, baselines follow the trend.
3. **Detection disabled**: Check `BaselineThresholds.IsEnabled = 1`
4. **Wrong baseline period**: Try comparing to 30-day or 90-day baseline instead of 7-day

### Too Many False Positive Anomalies

**Symptoms**: Hundreds of anomalies detected, most are normal workload variation.

**Diagnosis**:
```sql
-- Check anomaly distribution
SELECT
    Severity,
    COUNT(*) AS AnomalyCount
FROM dbo.AnomalyDetections
WHERE DetectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
GROUP BY Severity
ORDER BY Severity;
```

**Solutions**:
1. **Increase thresholds**: Raise Low/Medium thresholds (e.g., 2.0σ → 2.5σ)
2. **Increase MinSampleCount**: Require more samples for baseline calculation (reduces noise)
3. **Disable noisy metrics**: `UPDATE BaselineThresholds SET IsEnabled = 0 WHERE MetricCategory = 'Connections' AND MetricName = 'Active';`
4. **Use longer baseline period**: Switch from 7-day to 30-day baseline for more stable reference

### Baselines Not Updating

**Symptoms**: Baseline table shows old `CalculatedAt` timestamps.

**Diagnosis**:
```sql
-- Check last baseline calculation
SELECT TOP 1
    CalculationTime,
    BaselinePeriod,
    ServersProcessed,
    MetricsProcessed,
    BaselinesCreated,
    DurationSeconds,
    Status,
    ErrorMessage
FROM dbo.BaselineCalculationHistory
ORDER BY CalculationTime DESC;
```

**Solutions**:
1. **SQL Agent stopped**: Check `EXEC xp_servicecontrol 'QueryState', 'SQLServerAgent';`
2. **Job schedule changed**: Verify `SELECT * FROM msdb.dbo.sysschedules WHERE name = 'Daily at 3:00 AM';`
3. **Manual run**: `EXEC dbo.usp_UpdateAllBaselines;`

---

## Best Practices

### 1. Baseline Calculation Frequency

- **Daily calculation**: Adequate for most environments
- **Twice daily**: High-change environments (e.g., dev/test servers)
- **Weekly**: Stable production servers with minimal workload changes

**How to Change**:
```sql
-- Change to twice daily (3:00 AM and 3:00 PM)
EXEC msdb.dbo.sp_update_jobschedule
    @job_name = 'MonitoringDB - Update Baselines (Daily)',
    @name = 'Daily at 3:00 AM',
    @freq_subday_type = 8,       -- Hours
    @freq_subday_interval = 12,  -- Every 12 hours
    @active_start_time = 030000; -- Starting at 3:00 AM
```

### 2. Anomaly Detection Frequency

- **15 minutes**: Recommended for production
- **5 minutes**: High-sensitivity environments (real-time monitoring)
- **30 minutes**: Low-priority servers (reduce CPU overhead)

**How to Change**:
```sql
-- Change to every 5 minutes
EXEC msdb.dbo.sp_update_jobschedule
    @job_name = 'MonitoringDB - Detect Anomalies (15 min)',
    @name = 'Every 15 minutes',
    @freq_subday_interval = 5;
```

### 3. Threshold Tuning Process

1. **Start with defaults** (2/3/4/5 sigma)
2. **Monitor for 1 week** to collect anomaly data
3. **Review false positives**:
   ```sql
   SELECT
       MetricCategory,
       MetricName,
       COUNT(*) AS FalsePositives
   FROM dbo.AnomalyDetections
   WHERE Severity IN ('Low', 'Medium')
     AND DetectionTime >= DATEADD(DAY, -7, GETUTCDATE())
   GROUP BY MetricCategory, MetricName
   HAVING COUNT(*) > 50
   ORDER BY COUNT(*) DESC;
   ```
4. **Increase thresholds** for noisy metrics (or disable)
5. **Repeat weekly** until false positive rate < 5%

### 4. Baseline Period Selection

| Scenario | Recommended Period | Reason |
|----------|-------------------|--------|
| **Recent deployment** | 7-day | Captures new performance characteristics |
| **Stable workload** | 30-day | Smooths out weekly variations |
| **Seasonal business** | 90-day | Captures monthly/quarterly patterns |
| **Capacity planning** | 90-day | Long-term growth trends |

### 5. Integration with Alerting

Anomaly detection can trigger alerts automatically:

```sql
-- Create alert rule for high-severity anomalies
EXEC dbo.usp_CreateAlertRule
    @RuleName = 'High-Severity Anomaly Detected',
    @MetricCategory = 'Anomaly',
    @MetricName = 'HighSeverity',
    @HighThreshold = 1.0,  -- 1+ high-severity anomaly
    @HighDurationSeconds = 300, -- Sustained for 5 minutes
    @IsEnabled = 1;
```

### 6. Data Retention

- **PerformanceMetrics**: 90 days (partitioned, auto-cleanup)
- **MetricBaselines**: 365 days (small table, ~162k rows/year)
- **AnomalyDetections**: 180 days (audit trail)

**Cleanup Script**:
```sql
-- Clean up old anomalies (run monthly)
DELETE FROM dbo.AnomalyDetections
WHERE DetectionTime < DATEADD(DAY, -180, GETUTCDATE());
```

---

## FAQ

### Q1: What's the difference between baselines and thresholds?

**Baselines** are **historical averages** calculated from actual performance data. They represent "normal" behavior for each metric.

**Thresholds** are **deviation limits** that determine when current performance is considered abnormal. They are configured in standard deviations (sigma) from the baseline.

**Example**:
- **Baseline**: CPU averages 30% with 10% standard deviation (calculated from last 7 days)
- **Threshold**: Alert if CPU exceeds baseline by 3 standard deviations (3σ)
- **Trigger point**: CPU > 30% + (3 × 10%) = 60%

### Q2: How long until baselines are accurate?

- **Minimum**: 7 days of metrics collection (100+ samples per metric)
- **Recommended**: 30 days for stable baselines
- **Optimal**: 90 days for seasonal patterns

Baselines calculated after 7 days are functional but may have noise. Wait 30 days for production use.

### Q3: Can I manually mark an anomaly as resolved?

Yes:

```sql
UPDATE dbo.AnomalyDetections
SET IsResolved = 1,
    ResolvedAt = GETUTCDATE(),
    ResolutionNotes = 'Manual resolution - server maintenance completed'
WHERE AnomalyID = 12345;
```

### Q4: Why are anomalies auto-resolved?

`usp_DetectAnomalies` checks if previously detected anomalies have returned to normal (within 2σ of baseline). This prevents alerting on transient spikes.

**Example**:
- 9:00 AM: CPU spike to 80% (3σ above baseline) → Anomaly detected
- 9:15 AM: CPU returns to 35% (0.5σ above baseline) → Anomaly auto-resolved

### Q5: How do I test anomaly detection?

**Simulate CPU spike**:

```sql
-- Insert fake metric (high CPU)
INSERT INTO dbo.PerformanceMetrics (
    ServerID, CollectionTime, MetricCategory, MetricName, MetricValue
)
VALUES (
    1, -- Your server
    GETUTCDATE(),
    'CPU',
    'Percent',
    95.0 -- Abnormally high
);

-- Run anomaly detection
EXEC dbo.usp_DetectAnomalies @BaselinePeriod = '7day';

-- Check for anomaly
SELECT * FROM dbo.AnomalyDetections
WHERE ServerID = 1
  AND MetricCategory = 'CPU'
  AND DetectionTime >= DATEADD(MINUTE, -5, GETUTCDATE());
```

### Q6: What happens if baselines are deleted?

Anomaly detection fails gracefully:

```sql
-- Delete baselines (testing only!)
DELETE FROM dbo.MetricBaselines WHERE ServerID = 1;

-- Run anomaly detection
EXEC dbo.usp_DetectAnomalies @BaselinePeriod = '7day';
-- Result: 0 anomalies detected (no baseline to compare against)
```

**Recovery**: Run `EXEC dbo.usp_UpdateAllBaselines;` to recalculate.

### Q7: Can I compare to custom date ranges?

Not directly. Baselines use fixed windows (7/14/30/90 days). For custom comparisons:

```sql
-- Manual comparison: Current week vs same week last month
WITH CurrentWeek AS (
    SELECT AVG(MetricValue) AS AvgCPU
    FROM dbo.PerformanceMetrics
    WHERE ServerID = 1
      AND MetricCategory = 'CPU'
      AND MetricName = 'Percent'
      AND CollectionTime >= DATEADD(DAY, -7, GETUTCDATE())
),
LastMonthSameWeek AS (
    SELECT AVG(MetricValue) AS AvgCPU
    FROM dbo.PerformanceMetrics
    WHERE ServerID = 1
      AND MetricCategory = 'CPU'
      AND MetricName = 'Percent'
      AND CollectionTime BETWEEN DATEADD(DAY, -35, GETUTCDATE())
                              AND DATEADD(DAY, -28, GETUTCDATE())
)
SELECT
    c.AvgCPU AS CurrentWeekAvg,
    l.AvgCPU AS LastMonthAvg,
    ((c.AvgCPU - l.AvgCPU) / l.AvgCPU * 100) AS PercentChange
FROM CurrentWeek c, LastMonthSameWeek l;
```

---

## Summary

**Historical Baseline Comparison** provides:

✅ **Automatic baseline calculation** (444 baselines per day, 11-second runtime)
✅ **Statistical anomaly detection** (z-score based, 4 severity levels)
✅ **Grafana dashboards** (7 panels, overlay charts, deviation trends)
✅ **Configurable thresholds** (per metric category, spike/drop detection)
✅ **Integration with alerting** (Feature #3 integration)

**Next Steps**:

1. Wait 7 days for baselines to stabilize
2. Review anomalies in Grafana Dashboard 11
3. Tune thresholds based on false positive rate
4. Integrate with alerting system (Feature #3)

---

**For Questions/Issues**: Review [Troubleshooting](#troubleshooting) section or check `BaselineCalculationHistory` table for errors.
