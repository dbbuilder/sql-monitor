# Modular Feedback System - Complete Guide

**Deployed:** 2025-10-27
**Status:** ✅ Deployed to all 3 servers

## Executive Summary

The DBA monitoring system now includes a **modular, database-driven feedback system** that provides intelligent analysis and recommendations for every metric in the `DBA_DailyHealthOverview` report. Instead of hardcoding feedback text in stored procedures, all analysis rules are stored in database tables, making them easily customizable without code changes.

## What Was Deployed

### 1. New Tables

**FeedbackRule** - Stores analysis rules for metrics
```sql
SELECT TOP 5 * FROM DBATools.dbo.FeedbackRule
```

Columns:
- `FeedbackRuleID` - Primary key
- `ProcedureName` - Which SP uses this rule (e.g., 'DBA_DailyHealthOverview')
- `ResultSetNumber` - Which result set (1-12)
- `MetricName` - Field name (e.g., 'CpuSignalWaitPct', 'BlockingSessionCount')
- `RangeFrom` - Lower bound (NULL = no minimum)
- `RangeTo` - Upper bound (NULL = no maximum)
- `Severity` - INFO, ATTENTION, WARNING, CRITICAL
- `FeedbackText` - The analysis text to display
- `Recommendation` - Recommended action
- `SortOrder` - Display priority
- `IsActive` - Enable/disable rule

**FeedbackMetadata** - Stores result set descriptions
```sql
SELECT * FROM DBATools.dbo.FeedbackMetadata
```

Columns:
- `MetadataID` - Primary key
- `ProcedureName` - Which SP this describes
- `ResultSetNumber` - Which result set (1-12)
- `ResultSetName` - Friendly name
- `Description` - What this result set shows
- `InterpretationGuide` - How to read it

### 2. Helper Function

**fn_GetMetricFeedback** - Retrieves appropriate feedback for a metric value
```sql
-- Example: Get feedback for CPU signal wait of 35%
SELECT * FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 35)
```

Returns:
- `Severity` - INFO, ATTENTION, WARNING, or CRITICAL
- `FeedbackText` - Analysis of what the metric means
- `Recommendation` - What action to take

### 3. Enhanced DBA_DailyHealthOverview Procedure

The procedure now includes:
- **Inline feedback columns** for key metrics
- **Field guide result sets** explaining every field
- **Interpretation guidelines** for complex data
- **Actionable recommendations** based on thresholds

## Seeded Feedback Rules

### Result Set 1: Report Header

**DaysOfData Analysis:**
- 0 days → "First day of monitoring - limited historical data"
- 1-6 days → "Limited historical data (less than 1 week)"
- 7-13 days → "Good historical data (1-2 weeks). Trends are becoming meaningful."
- 14+ days → "Excellent historical data (2+ weeks). Trends are highly reliable."

### Result Set 2: Current System Health

**CpuSignalWaitPct Analysis:**
- 0-5% → INFO: "CPU signal wait is very low. CPU is not a bottleneck."
- 5-15% → INFO: "CPU signal wait is normal. Moderate CPU usage."
- 15-30% → ATTENTION: "CPU signal wait is elevated. CPU is becoming busy."
- 30-50% → WARNING: "CPU signal wait is high. CPU pressure detected."
- 50%+ → CRITICAL: "CPU signal wait is critical. Severe CPU bottleneck."

**BlockingSessionCount Analysis:**
- 0-5 → INFO: "Minimal blocking. Normal transactional activity."
- 6-15 → ATTENTION: "Moderate blocking. Some contention present."
- 16-30 → WARNING: "High blocking. Significant lock contention."
- 31+ → CRITICAL: "Critical blocking. Severe lock contention."

**DeadlockCountRecent Analysis:**
- 0 → INFO: "No deadlocks detected in last 10 minutes."
- 1-3 → ATTENTION: "Low deadlock count. Occasional deadlocks detected."
- 4-10 → WARNING: "Moderate deadlock count. Frequent deadlocks occurring."
- 11+ → CRITICAL: "High deadlock count. Severe deadlock storm."

**MinutesSinceSnapshot Analysis:**
- 0-6 min → INFO: "Data is current. Collection is running normally."
- 7-15 min → ATTENTION: "Data is slightly stale. Possible collection delay."
- 16-60 min → WARNING: "Data is stale. Collection may have stopped."
- 61+ min → CRITICAL: "Data is very stale. Monitoring is not running."

### Result Set 4: Summary Statistics

**AvgCpuSignalWaitPct Analysis:**
- 0-10% → INFO: "Average CPU signal wait is low. CPU capacity is healthy."
- 10-20% → ATTENTION: "Average CPU signal wait is moderate. CPU utilization is increasing."
- 20%+ → WARNING: "Average CPU signal wait is high. CPU is consistently busy."

**TotalDeadlocks Analysis:**
- 0 → INFO: "No deadlocks in the reporting period. Excellent transaction management."
- 1-5 → ATTENTION: "Low deadlock count. Occasional deadlocks detected."
- 6-20 → WARNING: "Moderate deadlock count. Regular deadlocks occurring."
- 21+ → CRITICAL: "High deadlock count. Frequent deadlocking indicates design issues."

### Result Set 5: Slow Queries

**AvgElapsedMs Analysis:**
- 0-1000ms (< 1 sec) → INFO: "Query elapsed time is good. Acceptable performance."
- 1000-5000ms (1-5 sec) → ATTENTION: "Query elapsed time is slow. Consider optimization."
- 5000-30000ms (5-30 sec) → WARNING: "Query elapsed time is very slow. Needs optimization."
- 30000+ms (> 30 sec) → CRITICAL: "Query elapsed time is critical. Severe performance issue."

**ImpactScore Analysis:**
- 0-10,000 → INFO: "Low impact score. Query runs infrequently or is fast."
- 10,000-100,000 → ATTENTION: "Moderate impact score. Query has measurable impact."
- 100,000-1,000,000 → WARNING: "High impact score. Query significantly affects performance."
- 1,000,000+ → CRITICAL: "Critical impact score. Query is major performance bottleneck."

### Result Set 7: Missing Indexes

**ImpactScore Analysis:**
- 0-100,000 → INFO: "Low impact index. Marginal benefit expected."
- 100,000-1,000,000 → ATTENTION: "Moderate impact index. Noticeable benefit expected."
- 1,000,000-10,000,000 → WARNING: "High impact index. Significant performance gain expected."
- 10,000,000+ → CRITICAL: "Critical impact index. Major performance improvement expected."

**UserSeeks Analysis:**
- 0-100 → INFO: "Low seek count. Index is used infrequently."
- 100-10,000 → ATTENTION: "Moderate seek count. Regular index usage."
- 10,000+ → WARNING: "High seek count. Index would be heavily used."

### Result Set 9: Database Sizes

**TotalSizeMB Analysis:**
- 0-1,024 MB (< 1 GB) → INFO: "Small database. Size is not a concern."
- 1,024-10,240 MB (1-10 GB) → INFO: "Medium database. Normal size range."
- 10,240-102,400 MB (10-100 GB) → ATTENTION: "Large database. Monitor growth carefully."
- 102,400+ MB (> 100 GB) → WARNING: "Very large database. Requires active capacity management."

**LogReuseWaitDesc Analysis:**
- NOTHING → "Normal - Log space can be reused."
- CHECKPOINT → "Waiting for checkpoint. Run CHECKPOINT if log is growing."
- LOG_BACKUP → "CRITICAL: Full/Bulk recovery without log backups. Log will grow indefinitely!"
- ACTIVE_TRANSACTION → "Long-running transaction preventing log reuse."
- OLDEST_PAGE → "Normal for databases with activity."

## Example Usage

### Run Enhanced Report
```sql
EXEC DBA_DailyHealthOverview
    @TopSlowQueries = 20,
    @TopMissingIndexes = 20,
    @HoursBackForIssues = 48
```

### Sample Output (Result Set 2: Current Health)

```
Section                 | CURRENT SYSTEM HEALTH
PerfSnapshotRunID       | 66
SnapshotUTC             | 2025-10-27 23:25:00.460
ServerName              | SVWeb\CLUBTRACK
CpuSignalWaitPct        | 1.12
BlockingSessionCount    | 56
DeadlockCountRecent     | 0
HealthStatus            | WARNING - High Blocking
MinutesSinceSnapshot    | 1
CpuAnalysis             | CPU signal wait is very low (< 5%). CPU is not a bottleneck.
CpuRecommendation       | CPU is healthy. If experiencing performance issues, investigate disk I/O, memory, or query optimization.
BlockingAnalysis        | Critical blocking (> 30 sessions). Severe lock contention.
BlockingRecommendation  | IMMEDIATE ACTION: Execute "EXEC sp_who2" to identify blocking head. Review blocking queries and consider killing long-running transactions if necessary.
DeadlockAnalysis        | No deadlocks detected in last 10 minutes.
DeadlockRecommendation  | Deadlock monitoring is active. No action needed.
```

### Field Guide Result Sets

Each main result set is followed by a "FIELD GUIDE" that explains:
- What each field means
- How to interpret the values
- What thresholds matter
- What actions to take

Example (Result Set 2a: Current Health - Field Guide):
```
FieldName             | CpuSignalWaitPct
FieldDescription      | Percentage of time SQL Server is waiting for CPU (signal waits)
Interpretation        | Higher = CPU pressure. 0-10% = healthy, 10-20% = moderate, 20-40% = elevated, 40%+ = critical.
```

## Customizing Feedback Rules

### Add New Rule
```sql
INSERT INTO DBATools.dbo.FeedbackRule
(
    ProcedureName,
    ResultSetNumber,
    MetricName,
    RangeFrom,
    RangeTo,
    Severity,
    FeedbackText,
    Recommendation,
    SortOrder
)
VALUES
(
    'DBA_DailyHealthOverview',  -- Procedure name
    2,                           -- Result set number
    'CpuSignalWaitPct',         -- Metric name
    70,                          -- From 70%
    NULL,                        -- To infinity
    'CRITICAL',                  -- Severity
    'Extreme CPU pressure (> 70%). System may be unresponsive.',
    'EMERGENCY: Consider killing expensive queries or restarting SQL Server if system is hung.',
    6                            -- Sort order
)
```

### Modify Existing Rule
```sql
UPDATE DBATools.dbo.FeedbackRule
SET FeedbackText = 'Your custom analysis text here',
    Recommendation = 'Your custom recommendation here'
WHERE FeedbackRuleID = 15
```

### Disable Rule
```sql
UPDATE DBATools.dbo.FeedbackRule
SET IsActive = 0
WHERE FeedbackRuleID = 20
```

### View All Rules for a Metric
```sql
SELECT
    ResultSetNumber,
    MetricName,
    RangeFrom,
    RangeTo,
    Severity,
    FeedbackText,
    Recommendation
FROM DBATools.dbo.FeedbackRule
WHERE ProcedureName = 'DBA_DailyHealthOverview'
  AND MetricName = 'CpuSignalWaitPct'
  AND IsActive = 1
ORDER BY RangeFrom
```

## Benefits

### 1. **No Code Changes Required**
- Modify feedback messages without redeploying stored procedures
- Add new rules dynamically
- Disable rules temporarily without code changes

### 2. **Consistent Analysis**
- Same thresholds applied across all servers
- Version-controlled feedback rules
- Easy to audit and review

### 3. **Easy Customization**
- Different thresholds for different environments (dev vs. prod)
- Organization-specific guidance
- Localization support (change text to different languages)

### 4. **Scalable**
- Add new procedures that use the same feedback system
- Reuse feedback rules across multiple procedures
- Build custom reporting tools using the same rules

## Advanced Usage

### Test Feedback for Different Values
```sql
-- Test CPU feedback at different levels
SELECT
    5 AS CpuValue,
    Severity,
    FeedbackText
FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 5)

UNION ALL

SELECT
    25,
    Severity,
    FeedbackText
FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 25)

UNION ALL

SELECT
    55,
    Severity,
    FeedbackText
FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 55)
```

### Export Rules for Backup
```sql
SELECT *
FROM DBATools.dbo.FeedbackRule
WHERE ProcedureName = 'DBA_DailyHealthOverview'
ORDER BY ResultSetNumber, MetricName, SortOrder
-- Export to CSV or XML for backup
```

### Create Environment-Specific Rules
```sql
-- Add more aggressive thresholds for production
INSERT INTO DBATools.dbo.FeedbackRule (...)
SELECT
    ProcedureName,
    ResultSetNumber,
    MetricName,
    RangeFrom * 0.7,  -- 30% lower thresholds for prod
    RangeTo * 0.7,
    'CRITICAL',       -- Higher severity
    FeedbackText + ' [PRODUCTION ENVIRONMENT]',
    Recommendation,
    SortOrder
FROM DBATools.dbo.FeedbackRule
WHERE Severity IN ('WARNING', 'ATTENTION')
```

## Troubleshooting

### Feedback Not Appearing
```sql
-- Check if rule exists and is active
SELECT *
FROM DBATools.dbo.FeedbackRule
WHERE MetricName = 'CpuSignalWaitPct'
  AND IsActive = 1
  AND 35 >= ISNULL(RangeFrom, -999999)
  AND 35 <= ISNULL(RangeTo, 999999)
```

### Multiple Rules Match
The function returns **TOP 1** ordered by `SortOrder`. Lower SortOrder wins.

```sql
-- Check for conflicting rules
SELECT *
FROM DBATools.dbo.FeedbackRule
WHERE MetricName = 'BlockingSessionCount'
  AND IsActive = 1
  AND 25 >= ISNULL(RangeFrom, -999999)
  AND 25 <= ISNULL(RangeTo, 999999)
ORDER BY SortOrder
```

### Performance Impact
The feedback queries use indexed lookups and should have minimal impact (<50ms per result set).

```sql
-- Check feedback query performance
SET STATISTICS TIME ON
SET STATISTICS IO ON

SELECT * FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 35)

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
```

## Files Deployed

| File | Description | Status |
|------|-------------|--------|
| `13_create_feedback_system.sql` | Creates tables, function, and seeds data | ✅ All servers |
| `14_enhance_daily_overview_with_feedback.sql` | Enhanced procedure with feedback | ✅ All servers |

## Statistics

- **Tables Created:** 2 (FeedbackRule, FeedbackMetadata)
- **Function Created:** 1 (fn_GetMetricFeedback)
- **Metadata Records:** 12 (one per result set)
- **Feedback Rules Seeded:** 47
  - Report Header: 4 rules
  - Current Health: 17 rules
  - Summary Statistics: 7 rules
  - Slow Queries: 8 rules
  - Missing Indexes: 7 rules
  - Database Sizes: 4 rules

## Quick Reference

### Add Rule
```sql
INSERT INTO DBATools.dbo.FeedbackRule (ProcedureName, ResultSetNumber, MetricName, RangeFrom, RangeTo, Severity, FeedbackText, Recommendation, SortOrder)
VALUES ('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 50, NULL, 'CRITICAL', 'Analysis text', 'Recommendation text', 10)
```

### Update Rule
```sql
UPDATE DBATools.dbo.FeedbackRule SET FeedbackText = 'New text' WHERE FeedbackRuleID = 15
```

### Disable Rule
```sql
UPDATE DBATools.dbo.FeedbackRule SET IsActive = 0 WHERE FeedbackRuleID = 20
```

### Test Feedback
```sql
SELECT * FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 45)
```

### Run Enhanced Report
```sql
EXEC DBA_DailyHealthOverview @TopSlowQueries = 20, @TopMissingIndexes = 20
```

---

**Next Steps:**
1. Run `EXEC DBA_DailyHealthOverview` to see feedback in action
2. Review default thresholds and adjust for your environment
3. Add custom rules for organization-specific scenarios
4. Export FeedbackRule table for version control/backup
