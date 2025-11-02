# Query Performance Advisor - User Guide

**Feature**: Phase 3 - Feature #2
**Status**: Production Ready
**Version**: 1.0

---

## Overview

The Query Performance Advisor automatically analyzes query execution patterns and generates actionable optimization recommendations. It identifies slow queries, missing indexes, plan regressions, and provides ready-to-run implementation scripts.

### Key Capabilities

- **Automatic Analysis**: Runs daily at 2:00 AM analyzing all active servers
- **Multiple Analysis Types**: Missing indexes, high logical reads, high CPU, plan regressions
- **Severity Classification**: Critical, High, Medium, Low
- **Estimated Improvements**: Percentage-based improvement predictions
- **Implementation Tracking**: Before/after performance comparison
- **Grafana Dashboard**: Real-time visualization of recommendations

---

## Quick Start

### View Recommendations

```sql
-- Get top 20 recommendations across all servers
EXEC dbo.usp_GetTopRecommendations @TopN = 20;

-- Get recommendations for a specific server
EXEC dbo.usp_GetTopRecommendations @ServerID = 1, @TopN = 10;

-- Include already-implemented recommendations
EXEC dbo.usp_GetTopRecommendations @IncludeImplemented = 1;
```

### Manual Analysis

```sql
-- Analyze query performance for a specific server
EXEC dbo.usp_AnalyzeQueryPerformance @ServerID = 1;

-- Detect plan regressions (50% threshold)
EXEC dbo.usp_DetectPlanRegressions
    @ServerID = 1,
    @RegressionThresholdPercent = 50.0;
```

### Implement a Recommendation

```sql
-- Mark recommendation as implemented
EXEC dbo.usp_MarkRecommendationImplemented
    @RecommendationID = 123,
    @ImplementedBy = 'DBA_Username';

-- View the implementation script
SELECT ImplementationScript
FROM dbo.QueryPerformanceRecommendations
WHERE RecommendationID = 123;
```

---

## Recommendation Types

### 1. Missing Index

**What it detects**: Queries that would benefit from additional indexes based on Query Store execution patterns and DMV missing index suggestions.

**Example Recommendation**:
```
Missing index on AdventureWorks.dbo.SalesOrderDetail
Expected improvement: 85%
Columns: ProductID, OrderQty
```

**Implementation Script**:
```sql
CREATE NONCLUSTERED INDEX IX_SalesOrderDetail_ProductID_OrderQty
ON AdventureWorks.dbo.SalesOrderDetail (ProductID, OrderQty)
INCLUDE (UnitPrice, LineTotal);
```

**When to Implement**:
- ✅ High impact (>70% improvement)
- ✅ Frequently executed query
- ✅ Low write overhead table
- ❌ Temporary data or staging tables
- ❌ Already have 10+ indexes on table

### 2. High Logical Reads

**What it detects**: Queries performing excessive logical reads (>10,000 per execution), indicating potential missing indexes or inefficient query design.

**Example Recommendation**:
```
High logical reads: 150,000 per execution
Consider adding indexes, rewriting query, or updating statistics
```

**Troubleshooting Steps**:
1. Review execution plan for table scans
2. Check for missing WHERE clause indexes
3. Look for implicit conversions
4. Update statistics: `UPDATE STATISTICS TableName WITH FULLSCAN;`
5. Consider query rewrite

### 3. High CPU Usage

**What it detects**: Queries consuming excessive CPU time (>500ms per execution), often due to sorts, aggregations, or scalar functions.

**Example Recommendation**:
```
High CPU usage: 2,500ms per execution
Review for expensive operations (sorts, aggregations, functions)
```

**Common Causes**:
- Sorts without supporting indexes
- Scalar functions in WHERE clause
- Implicit data type conversions
- Key lookups (add INCLUDE columns to indexes)
- Hash joins (add indexes to enable merge joins)

### 4. Plan Regression

**What it detects**: Execution plan changes that cause >50% performance degradation compared to the 7-14 day baseline.

**Example Recommendation**:
```
Plan regression detected: Duration increased by 250%
Old duration: 100ms, New duration: 350ms
Consider forcing old plan or updating statistics
```

**Resolution Options**:

**Option A: Force Old Plan** (temporary fix)
```sql
-- Find query_id and plan_id from Query Store
EXEC sp_query_store_force_plan
    @query_id = 12345,
    @plan_id = 67890;
```

**Option B: Update Statistics** (permanent fix)
```sql
UPDATE STATISTICS AdventureWorks.dbo.SalesOrderDetail
WITH FULLSCAN;
```

**Option C: Rebuild Indexes** (if fragmentation is high)
```sql
ALTER INDEX ALL ON AdventureWorks.dbo.SalesOrderDetail
REBUILD WITH (ONLINE = ON);
```

---

## Grafana Dashboard

### Dashboard Panels

1. **Open Recommendations** - Count of unimplemented recommendations
2. **Critical Recommendations** - Count of critical-severity recommendations
3. **Active Plan Regressions** - Count of unresolved plan regressions
4. **Avg Improvement Potential** - Average estimated improvement percentage
5. **Top 20 Recommendations** - Sorted by severity and improvement potential
6. **Recommendations by Type** - Time series chart showing recommendation trends
7. **Active Plan Regressions** - Table of unresolved plan regressions with details

### Accessing the Dashboard

1. Open Grafana: http://localhost:9001
2. Navigate to Dashboards → Query Performance Advisor
3. Time range defaults to last 7 days

---

## Best Practices

### When to Implement Recommendations

**High Priority (Implement ASAP)**:
- ✅ Critical severity with >80% improvement
- ✅ Frequently executed queries (>1000 executions/day)
- ✅ Plan regressions affecting production workload
- ✅ Low implementation risk (simple index creation)

**Medium Priority (Implement in maintenance window)**:
- ⚠️ High severity with >50% improvement
- ⚠️ Moderate execution frequency (100-1000/day)
- ⚠️ Requires query rewrite or schema changes

**Low Priority (Evaluate and monitor)**:
- 📋 Medium/Low severity
- 📋 Infrequent queries (<100/day)
- 📋 Marginal improvement (<30%)
- 📋 High implementation complexity

### Testing Recommendations

**Before implementing in production**:

1. **Capture Baseline Metrics**:
   ```sql
   -- Record current performance
   SELECT
       AvgDurationMs,
       AvgCPUTimeMs,
       AvgLogicalReads
   FROM QueryPerformanceRecommendations
   WHERE RecommendationID = 123;
   ```

2. **Test in Lower Environment**:
   - Apply recommendation to DEV/TEST first
   - Run representative workload
   - Verify performance improvement

3. **Monitor After Implementation**:
   - After-metrics captured automatically after 24 hours
   - Review `QueryOptimizationHistory` table
   - Compare actual vs. estimated improvement

4. **Rollback Plan**:
   - For indexes: Keep DROP INDEX script ready
   - For plans: Can unforce with `sp_query_store_unforce_plan`
   - For queries: Maintain version control

---

## Automated Analysis Schedule

### SQL Agent Job: "Analyze Query Performance - All Servers"

**Schedule**: Daily at 2:00 AM

**Steps**:
1. **Analyze Query Performance** - Runs `usp_AnalyzeQueryPerformance` for all active servers
2. **Detect Plan Regressions** - Runs `usp_DetectPlanRegressions` for all active servers

**Manual Execution**:
```sql
EXEC msdb.dbo.sp_start_job
    @job_name = 'Analyze Query Performance - All Servers';
```

**View Job History**:
```sql
EXEC msdb.dbo.sp_help_jobhistory
    @job_name = 'Analyze Query Performance - All Servers';
```

---

## Database Tables

### QueryPerformanceRecommendations

Stores optimization recommendations with severity, estimated improvement, and implementation scripts.

**Key Columns**:
- `RecommendationType` - MissingIndex, HighLogicalReads, HighCPU, PlanRegression
- `RecommendationSeverity` - Critical, High, Medium, Low
- `EstimatedImprovementPercent` - Predicted performance improvement
- `ImplementationScript` - Ready-to-run SQL script
- `IsImplemented` - Tracks implementation status

### QueryPlanRegressions

Tracks execution plan changes that degrade performance.

**Key Columns**:
- `OldAvgDurationMs` / `NewAvgDurationMs` - Before/after performance
- `DurationIncreasePct` - Percentage degradation
- `IsResolved` - Resolution status

### QueryOptimizationHistory

Tracks before/after performance for implemented recommendations.

**Key Columns**:
- `BeforeAvgDurationMs` / `AfterAvgDurationMs` - Actual performance
- `ActualDurationImprovementPct` - Actual improvement achieved
- `AccuracyScore` - How close was our estimate?

---

## Troubleshooting

### No Recommendations Generated

**Possible Causes**:
1. **Insufficient Data**: Query Store data not collected yet (requires 24h of runtime stats)
2. **All Queries Performing Well**: No queries meet thresholds (>100ms, >10k reads, >500ms CPU)
3. **Duplicate Detection**: Recommendations already exist within last 7 days

**Resolution**:
```sql
-- Check Query Store data availability
SELECT COUNT(*) FROM QueryStoreRuntimeStats
WHERE CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE());

-- Check for existing recommendations
SELECT * FROM QueryPerformanceRecommendations
WHERE DetectionTime >= DATEADD(DAY, -7, GETUTCDATE());
```

### False Positives

**Missing Index Recommendations for Temporary Data**:
- Review table usage patterns
- Exclude staging/ETL tables from analysis
- Mark recommendation as implemented without action

**Plan Regressions Due to Data Changes**:
- Some plan changes are legitimate (data volume increased)
- Verify data distribution hasn't changed
- Update statistics rather than forcing old plan

---

## Performance Impact

### Analysis Job

- **Runtime**: ~2-5 minutes for 3 servers
- **CPU**: <5% during analysis
- **I/O**: Minimal (reads Query Store and DMVs only)
- **Frequency**: Once daily (off-hours)

### Storage Growth

- **Recommendations**: ~50-100/day across 3 servers
- **Plan Regressions**: ~5-10/week
- **Storage**: ~50 KB/day, ~1.5 MB/month, ~18 MB/year

---

## FAQ

**Q: How often should I review recommendations?**
A: Weekly for proactive optimization, daily if performance issues exist.

**Q: Can I adjust severity thresholds?**
A: Yes, modify the CASE statements in `usp_AnalyzeQueryPerformance` stored procedure.

**Q: What if estimated improvement is inaccurate?**
A: Estimates improve over time. Check `QueryOptimizationHistory` for accuracy trending.

**Q: Should I implement all Critical recommendations?**
A: Prioritize by frequency and business impact, not just severity. Test in lower environments first.

**Q: How do I exclude specific queries from analysis?**
A: Add WHERE clause exclusions in stored procedures (e.g., exclude by database name or query pattern).

---

## Support and Enhancement Requests

For issues or enhancement requests, review:
- Database logs: `SELECT * FROM AuditLog WHERE Action LIKE '%Query%'`
- SQL Agent job history: `sp_help_jobhistory`
- GitHub issues: https://github.com/dbbuilder/sql-monitor/issues

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02
**Status**: Production Ready
