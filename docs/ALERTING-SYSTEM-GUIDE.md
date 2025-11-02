# Automated Alerting System - User Guide

**Feature**: Phase 3 - Feature #3
**Status**: Production Ready
**Version**: 1.0

---

## Overview

The Automated Alerting System provides intelligent, multi-level threshold monitoring with customizable alert rules, suppression windows, and notification capabilities. It automatically evaluates 11 alert rules every 5 minutes to detect performance issues, health degradation, query problems, and capacity constraints.

### Key Capabilities

- **Multi-Level Thresholds**: Low, Medium, High, Critical severity levels
- **Automatic Evaluation**: SQL Agent job runs every 5 minutes
- **11 Pre-Configured Rules**: CPU, Memory, Disk, Health Score, Query Performance, Blocking, Deadlocks, Indexes
- **Alert Suppression**: Maintenance windows and pattern-based exclusions
- **Notification Support**: Email and Webhook integration (requires configuration)
- **Grafana Dashboard**: Real-time alert visualization with 9 panels
- **Alert Lifecycle**: Raise → Acknowledge → Resolve workflow

---

## Quick Start

### View Active Alerts

```sql
-- Get summary of active alerts
EXEC dbo.usp_GetAlertSummary;

-- Get detailed active alerts
EXEC dbo.usp_GetActiveAlerts;

-- Get alerts for specific server
EXEC dbo.usp_GetActiveAlerts @ServerID = 1;
```

### Acknowledge an Alert

```sql
EXEC dbo.usp_AcknowledgeAlert
    @AlertID = 123,
    @AcknowledgedBy = 'DBA_Username';
```

### Create Custom Alert Rule

```sql
EXEC dbo.usp_CreateAlertRule
    @RuleName = 'High Query Wait Time',
    @MetricCategory = 'Query',
    @MetricName = 'AvgWaitTimeMs',
    @CriticalThreshold = 5000,
    @CriticalDurationSeconds = 300,
    @HighThreshold = 2000,
    @HighDurationSeconds = 600;
```

---

## Pre-Configured Alert Rules

### 1. High CPU Utilization

**Metric**: `CPU.Percent`
**Purpose**: Detect sustained high CPU usage indicating resource contention

**Thresholds**:
- **Medium**: >80% for 10 minutes
- **High**: >90% for 5 minutes
- **Critical**: >95% for 1 minute

**Common Causes**:
- Missing indexes causing table scans
- Poorly optimized queries
- Insufficient CPU resources for workload
- Parallel query execution storms

**Resolution**:
1. Identify top CPU-consuming queries: Query Store dashboard
2. Check for missing indexes: Query Performance Advisor
3. Review execution plans for inefficiencies
4. Consider query rewrite or adding covering indexes

---

### 2. Memory Pressure

**Metric**: `Memory.Available MB`
**Purpose**: Detect low available memory causing page life expectancy issues

**Thresholds**:
- **Medium**: <2 GB for 15 minutes
- **High**: <1 GB for 10 minutes
- **Critical**: <512 MB for 5 minutes

**Common Causes**:
- Memory-intensive queries
- Large data imports/exports
- Insufficient max server memory configuration
- Memory leaks in application code

**Resolution**:
1. Check Page Life Expectancy (PLE): Should be >300 seconds
2. Review top memory-consuming queries
3. Adjust max server memory if too low
4. Add physical memory if consistently pressured

---

### 3. Low Disk Space

**Metric**: `Disk.Free Percent`
**Purpose**: Prevent disk space exhaustion causing database unavailability

**Thresholds**:
- **Medium**: <20% free for 1 hour
- **High**: <10% free for 30 minutes
- **Critical**: <5% free for 10 minutes

**Common Causes**:
- Transaction log growth (full recovery without log backups)
- Data file growth (large inserts/bulk operations)
- TempDB growth (large sorts, hash joins)
- Backup files not being cleaned up

**Resolution**:
1. Identify largest files: Disk I/O dashboard
2. Shrink transaction logs after log backup
3. Implement log backup schedule if missing
4. Clean up old backup files
5. Add disk capacity if consistently low

---

### 4. Health Score Degradation

**Metric**: `HealthScore.OverallScore`
**Purpose**: Early warning of overall server health decline

**Thresholds**:
- **Medium**: <75 for 15 minutes
- **High**: <60 for 10 minutes
- **Critical**: <40 for 5 minutes

**Common Causes**:
- Combination of multiple performance issues
- Resource exhaustion (CPU, memory, disk)
- Index fragmentation accumulation
- Query performance regressions

**Resolution**:
1. View Server Health Score dashboard
2. Identify which components are degraded
3. Check HealthScoreIssues table for specific problems
4. Address root causes per component recommendations

---

### 5. Critical Health Issues

**Metric**: `HealthScore.CriticalIssueCount`
**Purpose**: Alert on multiple critical performance problems

**Thresholds**:
- **Medium**: ≥1 critical issue for 10 minutes
- **High**: ≥3 critical issues for 5 minutes
- **Critical**: ≥5 critical issues for 3 minutes

**Common Causes**:
- Cascading performance failures
- Server overload
- Multiple subsystem failures

**Resolution**:
1. View Health Score Issues table
2. Prioritize by impact score
3. Address highest-impact issues first
4. Monitor health score recovery

---

### 6. High-Severity Query Recommendations

**Metric**: `QueryPerformance.CriticalRecommendations`
**Purpose**: Alert on accumulation of critical query optimization opportunities

**Thresholds**:
- **Medium**: ≥3 critical recommendations for 30 minutes
- **High**: ≥5 critical recommendations for 15 minutes
- **Critical**: ≥10 critical recommendations for 10 minutes

**Common Causes**:
- Application code changes introducing inefficient queries
- Data volume growth exposing query design issues
- Missing or outdated statistics
- Plan cache pollution

**Resolution**:
1. View Query Performance Advisor dashboard
2. Review top recommendations by improvement potential
3. Implement high-impact index recommendations
4. Update statistics on tables with stale data
5. Force plan recompilation for parameter sniffing issues

---

### 7. Active Plan Regressions

**Metric**: `QueryPerformance.UnresolvedRegressions`
**Purpose**: Detect execution plan changes causing performance degradation

**Thresholds**:
- **Medium**: ≥2 regressions for 30 minutes
- **High**: ≥5 regressions for 15 minutes
- **Critical**: ≥10 regressions for 10 minutes

**Common Causes**:
- Statistics updates changing cardinality estimates
- Parameter sniffing with skewed data distribution
- Index changes affecting plan selection
- SQL Server version upgrades

**Resolution Options**:
1. **Force Good Plan**: Use Query Store to force previous plan
2. **Update Statistics**: Refresh statistics with FULLSCAN
3. **Use Query Hints**: Add OPTIMIZE FOR hints for known distributions
4. **Rebuild Indexes**: If fragmentation is factor

---

### 8. Long-Running Blocking

**Metric**: `Blocking.MaxWaitDuration`
**Purpose**: Detect blocking chains causing user query delays

**Thresholds**:
- **Medium**: >30 seconds for 5 minutes
- **High**: >60 seconds for 3 minutes
- **Critical**: >120 seconds for 2 minutes

**Common Causes**:
- Long-running transactions holding locks
- Missing indexes causing lock escalation
- Application not committing transactions
- Deadlocks resolved as blocks

**Resolution**:
1. Identify blocking chain: Blocking Events dashboard
2. Review head blocker query
3. Kill blocking session if appropriate
4. Add indexes to reduce lock duration
5. Implement READ COMMITTED SNAPSHOT isolation

---

### 9. High Deadlock Frequency

**Metric**: `Deadlocks.DeadlocksPerHour`
**Purpose**: Alert on abnormal deadlock rate indicating design issues

**Thresholds**:
- **Medium**: ≥5 per hour
- **High**: ≥10 per hour
- **Critical**: ≥20 per hour

**Common Causes**:
- Multiple queries accessing tables in different orders
- Missing indexes causing scan locks
- Lock escalation from row/page to table locks
- Application retry logic amplifying deadlocks

**Resolution**:
1. Review deadlock graphs: Deadlock Events dashboard
2. Identify deadlock pattern (resource order)
3. Add indexes to reduce scan locks
4. Enforce consistent table access order in code
5. Use ROWLOCK hints to prevent escalation

---

### 10. High Index Fragmentation

**Metric**: `Index.AvgFragmentation`
**Purpose**: Alert on high fragmentation affecting query performance

**Thresholds**:
- **Medium**: >30% for 1 day
- **High**: >50% for 12 hours
- **Critical**: >70% for 6 hours

**Common Causes**:
- Heavy INSERT/UPDATE/DELETE activity
- Page splits from poor fill factor
- Inadequate index maintenance schedule
- Tables without clustered index

**Resolution**:
1. View Index Fragmentation dashboard
2. Identify fragmented indexes (>30%)
3. REORGANIZE for 30-50% fragmentation
4. REBUILD for >50% fragmentation
5. Adjust fill factor if frequent splits

---

### 11. High-Impact Missing Indexes

**Metric**: `Index.MissingIndexCount`
**Purpose**: Alert on accumulation of missing index recommendations

**Thresholds**:
- **Medium**: ≥10 recommendations for 1 day
- **High**: ≥20 recommendations for 12 hours
- **Critical**: ≥50 recommendations for 6 hours

**Common Causes**:
- New application features without index design
- Ad-hoc reporting queries
- Data volume growth revealing gaps
- Tables created without proper indexing

**Resolution**:
1. View Query Performance Advisor dashboard
2. Sort by estimated improvement percentage
3. Review CREATE INDEX scripts
4. Implement high-impact indexes (>70% improvement)
5. Test in lower environment first

---

## Grafana Dashboard

### Dashboard Panels

The Alert Monitoring dashboard provides comprehensive alert visualization:

1. **Critical Alerts** - Count of critical-severity active alerts (stat panel)
2. **High Alerts** - Count of high-severity active alerts (stat panel)
3. **Total Active Alerts** - All unresolved alerts (stat panel)
4. **Unacknowledged Alerts** - Alerts requiring attention (stat panel)
5. **Active Alerts** - Detailed table with severity, current value, threshold, duration
6. **Alert History by Severity** - Hourly time series showing alert trends
7. **Active Alerts by Category** - Pie chart of alert distribution
8. **Alert History** - Historical alerts with resolution times
9. **Alert Rules Configuration** - Current alert rule settings and statistics

### Accessing the Dashboard

1. Open Grafana: http://localhost:9001
2. Navigate to Dashboards → Alert Monitoring
3. Time range defaults to last 7 days

---

## Alert Lifecycle

### 1. Alert Raised

When metric exceeds threshold for specified duration:
- Alert created in `ActiveAlerts` table
- Severity determined by which threshold exceeded
- Notifications sent (if configured)
- Alert appears on Grafana dashboard

### 2. Alert Acknowledged

DBA reviews alert and acknowledges:
```sql
EXEC dbo.usp_AcknowledgeAlert
    @AlertID = 123,
    @AcknowledgedBy = 'john.doe';
```

- `IsAcknowledged` flag set to 1
- Acknowledged by/at fields populated
- Alert remains active until resolved

### 3. Alert Resolved

When metric returns below threshold:
- Alert automatically moved to `AlertHistory` table
- Duration calculated
- Alert removed from active alerts
- Historical trend data preserved

---

## Alert Suppression

### Maintenance Window Suppression

Suppress alerts during scheduled maintenance:

```sql
UPDATE dbo.AlertRules
SET SuppressStartTime = '02:00:00',
    SuppressEndTime = '04:00:00'
WHERE RuleName = 'High CPU Utilization';
```

### Pattern-Based Suppression

Suppress alerts for specific resources (e.g., test databases):

```sql
UPDATE dbo.AlertRules
SET SuppressPattern = '%_TEST%'
WHERE RuleName = 'Low Disk Space';
```

---

## Notification Configuration

### Email Notifications

**Requires**: SQL Server Database Mail configuration

```sql
-- Configure email for critical CPU alerts
UPDATE dbo.AlertRules
SET SendEmail = 1,
    EmailRecipients = 'dba-team@company.com;alerts@company.com'
WHERE RuleName = 'High CPU Utilization';
```

**Database Mail Setup**:
1. Configure Database Mail account: `sp_configure 'Database Mail XPs', 1;`
2. Create mail profile: `sysmail_add_profile_sp`
3. Add SMTP account: `sysmail_add_account_sp`
4. Test email: `sp_send_dbmail`

### Webhook Notifications

**Requires**: CLR assembly or external integration service

```sql
-- Configure webhook for critical alerts
UPDATE dbo.AlertRules
SET SendWebhook = 1,
    WebhookURL = 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
WHERE Severity IN ('Critical', 'High');
```

**Integration Options**:
- Slack incoming webhooks
- Microsoft Teams connectors
- PagerDuty integration
- Custom REST API endpoints

---

## Custom Alert Rules

### Example: Database Growth Rate

```sql
EXEC dbo.usp_CreateAlertRule
    @RuleName = 'Rapid Database Growth',
    @ServerID = NULL,  -- Apply to all servers
    @MetricCategory = 'Database',
    @MetricName = 'GrowthRateMBPerDay',
    @CriticalThreshold = 1000,  -- >1GB/day
    @CriticalDurationSeconds = 3600,
    @HighThreshold = 500,  -- >500MB/day
    @HighDurationSeconds = 7200,
    @MediumThreshold = 250,  -- >250MB/day
    @MediumDurationSeconds = 14400,
    @SendEmail = 1,
    @EmailRecipients = 'capacity-planning@company.com';
```

### Example: Backup Age

```sql
EXEC dbo.usp_CreateAlertRule
    @RuleName = 'Stale Full Backup',
    @MetricCategory = 'Backup',
    @MetricName = 'HoursSinceLastFull',
    @CriticalThreshold = 48,  -- >2 days
    @CriticalDurationSeconds = 3600,
    @HighThreshold = 36,  -- >1.5 days
    @HighDurationSeconds = 7200,
    @MediumThreshold = 26,  -- >26 hours
    @MediumDurationSeconds = 14400;
```

---

## Best Practices

### Alert Rule Design

**High Priority (Immediate Response)**:
- ✅ Critical severity with immediate business impact
- ✅ Short duration thresholds (1-5 minutes)
- ✅ Resource exhaustion (CPU >95%, Memory <512MB, Disk <5%)
- ✅ Service availability (blocking >2 min, health score <40)

**Medium Priority (Proactive Response)**:
- ⚠️ High severity with potential escalation
- ⚠️ Moderate duration thresholds (10-30 minutes)
- ⚠️ Performance degradation (health score <60, plan regressions)
- ⚠️ Capacity warnings (disk <20%, high fragmentation)

**Low Priority (Scheduled Review)**:
- 📋 Medium/Low severity
- 📋 Long duration thresholds (hours/days)
- 📋 Optimization opportunities (missing indexes, recommendations)
- 📋 Trend monitoring (growth rates, usage patterns)

### Threshold Tuning

**Avoid Alert Fatigue**:
1. **Baseline First**: Monitor metrics for 1-2 weeks before setting thresholds
2. **Start Conservative**: Begin with higher thresholds, lower as needed
3. **Use Duration**: Require sustained threshold violations (not spikes)
4. **Review Weekly**: Adjust thresholds based on false positive rate
5. **Target <5%**: Aim for <5% false positive rate

**Effective Thresholds**:
```sql
-- GOOD: Sustained high CPU
CriticalThreshold = 95,
CriticalDurationSeconds = 300  -- 5 minutes

-- BAD: Any CPU spike
CriticalThreshold = 80,
CriticalDurationSeconds = 60  -- 1 minute (too sensitive)
```

### Alert Response

**Incident Response Workflow**:
1. **Acknowledge**: Mark alert as acknowledged
2. **Assess**: Review current value vs threshold
3. **Investigate**: Use linked dashboards to identify root cause
4. **Mitigate**: Apply temporary fix if needed
5. **Resolve**: Implement permanent solution
6. **Document**: Add notes to AlertHistory for future reference

---

## Troubleshooting

### No Alerts Being Generated

**Possible Causes**:
1. All metrics within thresholds (healthy system)
2. SQL Agent job not running
3. Alert evaluation failing silently
4. Metric collection not working

**Resolution**:
```sql
-- Check SQL Agent job status
SELECT name, enabled, last_run_date, last_run_time
FROM msdb.dbo.sysjobs
WHERE name = 'SQLTEST: SQL Monitor - Alert Evaluation';

-- Check recent metric collection
SELECT ServerID, COUNT(*) AS MetricCount, MAX(CollectionTime) AS LastCollection
FROM dbo.PerformanceMetrics
WHERE CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY ServerID;

-- Manually run alert evaluation
EXEC dbo.usp_EvaluateAlertRules;
```

### Alerts Not Resolving

**Possible Causes**:
1. Metric still exceeds threshold
2. Alert evaluation not running
3. Alert manually locked (IsResolved=0 override)

**Resolution**:
```sql
-- Check current metric values
SELECT
    ar.RuleName,
    ar.CriticalThreshold,
    AVG(pm.MetricValue) AS CurrentValue
FROM dbo.AlertRules ar
INNER JOIN dbo.ActiveAlerts aa ON ar.RuleID = aa.RuleID
INNER JOIN dbo.PerformanceMetrics pm ON aa.ServerID = pm.ServerID
WHERE aa.IsResolved = 0
  AND pm.MetricCategory = ar.MetricCategory
  AND pm.MetricName = ar.MetricName
  AND pm.CollectionTime >= DATEADD(MINUTE, -10, GETUTCDATE())
GROUP BY ar.RuleName, ar.CriticalThreshold;

-- Manually resolve if appropriate
UPDATE dbo.ActiveAlerts
SET IsResolved = 1,
    ResolvedAt = GETUTCDATE()
WHERE AlertID = 123;
```

### Too Many False Positives

**Symptoms**:
- Alerts fire during normal operation
- Alerts fire and resolve within minutes
- Alert fatigue (DBAs ignore alerts)

**Resolution**:
```sql
-- Increase duration threshold
UPDATE dbo.AlertRules
SET CriticalDurationSeconds = 600  -- 10 minutes instead of 5
WHERE RuleName = 'High CPU Utilization';

-- Increase threshold value
UPDATE dbo.AlertRules
SET CriticalThreshold = 98  -- 98% instead of 95%
WHERE RuleName = 'High CPU Utilization';

-- Add suppression window
UPDATE dbo.AlertRules
SET SuppressStartTime = '02:00:00',
    SuppressEndTime = '04:00:00'
WHERE RuleName = 'High CPU Utilization';
```

---

## Performance Impact

### Alert Evaluation Job

- **Runtime**: ~5-10 seconds for 11 rules across 3 servers
- **CPU**: <1% during evaluation
- **I/O**: Minimal (reads recent metrics only)
- **Frequency**: Every 5 minutes (288 times/day)

### Storage Growth

- **Active Alerts**: Typically 0-10 per server (100 bytes each)
- **Alert History**: ~10-50/day per server (~5 KB/day)
- **Notification Log**: ~20-100/day per server (~2 KB/day)
- **Total**: ~7 KB/day, ~200 KB/month, ~2.4 MB/year per server

---

## FAQ

**Q: How often are alert rules evaluated?**
A: Every 5 minutes via SQL Agent job "SQLTEST: SQL Monitor - Alert Evaluation"

**Q: Can I create alerts for specific databases?**
A: Yes, use SuppressPattern to include/exclude databases, or create custom rules with CustomMetricQuery targeting specific databases

**Q: What happens if Database Mail isn't configured?**
A: Email notifications will be logged as "Pending" in AlertNotifications table but won't be sent. System continues to function.

**Q: Can I disable an alert rule without deleting it?**
A: Yes: `UPDATE dbo.AlertRules SET IsEnabled = 0 WHERE RuleName = '...';`

**Q: How do I get notified in Slack?**
A: Configure webhook notification with Slack incoming webhook URL in AlertRules.WebhookURL column

**Q: Can alerts trigger on custom metrics?**
A: Yes, use CustomMetricQuery column to define T-SQL query returning single numeric value

---

## Support and Enhancement Requests

For issues or enhancement requests, review:
- Database logs: `SELECT * FROM AuditLog WHERE Action LIKE '%Alert%'`
- SQL Agent job history: `sp_help_jobhistory @job_name = 'SQLTEST: SQL Monitor - Alert Evaluation'`
- GitHub issues: https://github.com/dbbuilder/sql-monitor/issues

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02
**Status**: Production Ready
