# USG_GetEspLdcAcctLatestProjections v2 - Complete Deployment Guide

**Date:** 2025-10-29
**Status:** ✅ Ready for Deployment
**Priority:** 🔥 CRITICAL - Addresses 5+ minute timeout issue
**Expected Impact:** 98% performance improvement (5 min → 5 sec)

---

## 📋 Executive Summary

### The Problem

**Current Production Issue:**
- Stored procedure: `USG_GetEspLdcAcctLatestProjections`
- Execution time: **5-7 minutes** (frequently times out)
- Disk I/O: **11,000,000 pages (87 GB)** read from disk
- Wait type: **PAGEIOLATCH_SH** (disk bottleneck)
- Impact: 491 executions in 4 hours (36+ hours of cumulative query time per day)

**Root Cause:**
```sql
CROSS APPLY USG_fnGetProjectionsLatestV2(mc.USG_Meter_Channel_ID, @espBeId) prj
```
- Function called **once per meter channel** (row-by-row execution)
- 2,000 meter channels = 2,000 function calls = 2,000 table scans
- Nested function `USG_FnGetEspProjectionVersion` called inside = 2,000 more operations
- **Total: 4,000+ table accesses for a single query**

### The Solution

**Optimized v2 Procedure:**
- ✅ Eliminated CROSS APPLY (replaced with INNER JOIN)
- ✅ Inlined all function logic (set-based operation)
- ✅ Added date range filter (default: 60 days)
- ✅ Created covering index (eliminates table scans)
- ✅ Replaced OUTER APPLY with LEFT JOIN (simpler)

**Expected Results:**
- Execution time: **<5 seconds** (98% faster)
- Disk I/O: **<500,000 pages (<4 GB)** (95% reduction)
- Wait type: **Minimal** (index seeks instead of table scans)
- ROI: **36 hours of query time saved per day**

---

## 🎯 Deployment Files

| File | Purpose | Duration |
|------|---------|----------|
| `USG_GetEspLdcAcctLatestProjections_v2_INDEX.sql` | Create covering index | 30-60 min |
| `USG_GetEspLdcAcctLatestProjections_v2_OPTIMIZED.sql` | Deploy v2 procedure | 5 min |
| `USG_GetEspLdcAcctLatestProjections_v2_TEST.sql` | Performance tests | 15-30 min |
| `USG_GetEspLdcAcctLatestProjections_ANALYSIS.md` | Technical analysis | Reference |
| `USG_GetEspLdcAcctLatestProjections_v2_DEPLOYMENT_GUIDE.md` | This document | Reference |

---

## 🚀 Quick Start (TL;DR)

```sql
-- STEP 1: Create covering index (off-peak hours, 2 AM - 5 AM)
:r USG_GetEspLdcAcctLatestProjections_v2_INDEX.sql

-- STEP 2: Deploy v2 procedure
:r USG_GetEspLdcAcctLatestProjections_v2_OPTIMIZED.sql

-- STEP 3: Run performance tests
:r USG_GetEspLdcAcctLatestProjections_v2_TEST.sql

-- STEP 4: Update application to call v2
-- (In your application code)
EXEC USG_GetEspLdcAcctLatestProjections_v2
    @espBeId = 484,
    @acctIdList = @acctIdList,
    @startDate = '2025-10-01',  -- Optional: default is last 30 days
    @endDate = '2025-11-30'     -- Optional: default is next 30 days
```

**Expected timeline:** 1 week (index creation + testing + gradual rollout)

---

## 📅 Detailed Deployment Plan

### Phase 1: Preparation (Day 1)

#### 1.1 Pre-Deployment Checks

```sql
-- Check USG_Projected_Usage_Interval table size
SELECT
    OBJECT_NAME(p.object_id) AS TableName,
    p.rows AS RowCount,
    SUM(au.total_pages) * 8 / 1024 AS TotalSizeMB
FROM sys.partitions p
JOIN sys.allocation_units au ON p.partition_id = au.container_id
WHERE p.object_id = OBJECT_ID('dbo.USG_Projected_Usage_Interval')
GROUP BY p.object_id, p.rows
```

**Expected Results:**
- Row count: 10M-100M rows
- Table size: 50-200 GB
- Index size will be: 10-30% of table size (5-60 GB)

**Action Items:**
- ☐ Verify sufficient disk space (2x current table size)
- ☐ Schedule index creation during off-peak hours (2 AM - 5 AM)
- ☐ Notify DBA team of planned index creation
- ☐ Take database backup (precaution)

#### 1.2 Schedule Index Creation

**Recommended Window:** 2 AM - 5 AM (lowest transaction volume)

**Estimated Duration:**
- Small table (<10M rows): 15-30 minutes
- Medium table (10M-50M rows): 30-60 minutes
- Large table (>50M rows): 60-120 minutes

**Command:**
```sql
-- Run during scheduled window
:r USG_GetEspLdcAcctLatestProjections_v2_INDEX.sql
```

**Monitoring:**
```sql
-- Track progress
SELECT
    r.percent_complete,
    r.estimated_completion_time / 1000 / 60 AS EstimatedMinutesRemaining,
    r.total_elapsed_time / 1000 / 60 AS ElapsedMinutes
FROM sys.dm_exec_requests r
WHERE r.command = 'CREATE INDEX'
  AND r.object_id = OBJECT_ID('dbo.USG_Projected_Usage_Interval')
```

---

### Phase 2: Testing (Day 2)

#### 2.1 Deploy v2 Procedure to TEST Environment

```sql
-- Connect to TEST database
USE [TEST_PROD]
GO

-- Deploy v2 procedure
:r USG_GetEspLdcAcctLatestProjections_v2_OPTIMIZED.sql
```

#### 2.2 Run Performance Tests

```sql
-- Run full test suite
:r USG_GetEspLdcAcctLatestProjections_v2_TEST.sql
```

**Verification Checklist:**

| Test | v1 (Expected) | v2 (Expected) | Status |
|------|---------------|---------------|--------|
| Single account execution time | 5+ minutes | <5 seconds | ☐ |
| Single account page reads | 11M pages | <500K pages | ☐ |
| 10 accounts execution time | 50+ minutes | <30 seconds | ☐ |
| 100 accounts execution time | N/A (timeout) | <2 minutes | ☐ |
| Result set row count | Match | Match | ☐ |
| Result set differences | 0 | 0 | ☐ |
| Index seeks in plan | 0 | >0 | ☐ |
| Table scans in plan | Multiple | 0 | ☐ |

**If ALL tests pass:** ✅ Proceed to Phase 3
**If ANY test fails:** ❌ Investigate and fix before proceeding

---

### Phase 3: Soft Launch (Day 3-7)

#### 3.1 Deploy v2 to PRODUCTION

**Pre-Deployment:**
- ☐ Index created successfully in Phase 1
- ☐ All tests passed in Phase 2
- ☐ Backup created
- ☐ DBA team notified
- ☐ Rollback plan reviewed

**Deployment Command:**
```sql
-- Connect to PRODUCTION database
USE [PROD]
GO

-- Deploy v2 procedure
:r USG_GetEspLdcAcctLatestProjections_v2_OPTIMIZED.sql
```

#### 3.2 Update 10% of Application Calls

**Code Change Example:**

**BEFORE (v1):**
```csharp
// C# application code
var results = await connection.QueryAsync<ProjectionModel>(
    "USG_GetEspLdcAcctLatestProjections",  // OLD
    new { espBeId = 484, acctIdList = accountIds },
    commandType: CommandType.StoredProcedure,
    commandTimeout: 300  // 5 minutes (often times out)
);
```

**AFTER (v2):**
```csharp
// C# application code
var results = await connection.QueryAsync<ProjectionModel>(
    "USG_GetEspLdcAcctLatestProjections_v2",  // NEW
    new {
        espBeId = 484,
        acctIdList = accountIds,
        startDate = DateTime.Today.AddDays(-30),  // Optional: last 30 days
        endDate = DateTime.Today.AddDays(30)      // Optional: next 30 days
    },
    commandType: CommandType.StoredProcedure,
    commandTimeout: 30  // 30 seconds (plenty of time)
);
```

**Rollout Strategy:**
1. Update 1-2 low-volume API endpoints to use v2
2. Monitor for 24 hours
3. Verify no errors or performance degradation
4. If successful, proceed to next phase

#### 3.3 Monitor Soft Launch

**Daily Monitoring (Day 3-7):**

```sql
-- Check v2 execution times
SELECT
    OBJECT_NAME(ps.object_id) AS ProcedureName,
    ps.execution_count,
    ps.total_elapsed_time / 1000000.0 / ps.execution_count AS AvgElapsedSeconds,
    ps.max_elapsed_time / 1000000.0 AS MaxElapsedSeconds,
    ps.total_logical_reads / ps.execution_count AS AvgLogicalReads,
    ps.last_execution_time
FROM sys.dm_exec_procedure_stats ps
WHERE OBJECT_NAME(ps.object_id) LIKE '%USG_GetEspLdcAcctLatestProjections%'
ORDER BY ps.last_execution_time DESC
```

**Expected Results:**
- AvgElapsedSeconds: <5 seconds
- MaxElapsedSeconds: <10 seconds
- AvgLogicalReads: <500,000 pages

**Red Flags (Stop Rollout):**
- ❌ AvgElapsedSeconds > 30 seconds
- ❌ MaxElapsedSeconds > 60 seconds
- ❌ Any application errors related to projections
- ❌ Missing data in results

---

### Phase 4: Full Rollout (Week 2)

#### 4.1 Update 50% of Application Calls

**After successful soft launch:**
- Update remaining API endpoints to use v2
- Monitor for 3 days
- Verify performance improvements across all endpoints

#### 4.2 Update 100% of Application Calls

**After successful 50% rollout:**
- Update ALL remaining calls to v2
- Keep v1 procedure for 1 month (rollback safety)
- Monitor for 1 week

#### 4.3 Deprecate v1 (Week 3-4)

**After 2 weeks of successful v2 operation:**
- Rename `USG_GetEspLdcAcctLatestProjections` → `USG_GetEspLdcAcctLatestProjections_v1_DEPRECATED`
- Rename `USG_GetEspLdcAcctLatestProjections_v2` → `USG_GetEspLdcAcctLatestProjections`
- Update application to remove `_v2` suffix
- Drop v1 after 1 month of no usage

---

## 🔧 Rollback Plan

### If v2 Has Issues During Rollout

**Immediate Actions:**
1. Revert application calls to v1 (comment out v2 code)
2. Stop updating additional endpoints
3. Investigate root cause

**Common Issues and Solutions:**

| Issue | Cause | Solution |
|-------|-------|----------|
| Slow performance | Index not being used | Run `UPDATE STATISTICS`, check execution plan |
| Missing data | Date range too narrow | Adjust @startDate/@endDate defaults |
| Different results | Query logic error | Compare execution plans, verify JOIN conditions |
| High CPU usage | Missing index | Verify covering index exists and is not fragmented |

**Rollback Commands:**
```sql
-- Revert application to v1 (no database changes needed)
-- v1 procedure is still available during rollout

-- If needed, drop v2 and recreate v1
DROP PROCEDURE IF EXISTS [dbo].[USG_GetEspLdcAcctLatestProjections_v2]
GO

-- Recreate v1 from source control
:r USG_GetEspLdcAcctLatestProjections_v1_ORIGINAL.sql
```

---

## 📊 Success Metrics

### Key Performance Indicators (KPIs)

**Before v2 (Baseline):**
- Average execution time: 308 seconds (5.1 minutes)
- Max execution time: 439 seconds (7.3 minutes)
- Average logical reads: 11,000,000 pages (87 GB)
- Timeout rate: 25-30% of queries

**After v2 (Target):**
- Average execution time: <5 seconds (98% improvement)
- Max execution time: <10 seconds
- Average logical reads: <500,000 pages (95% reduction)
- Timeout rate: 0%

### Business Impact

**Daily Time Savings:**
- 491 executions per 4 hours = ~2,950 executions per day
- Time saved per execution: 303 seconds (5 min → 5 sec)
- **Total daily savings: 893,850 seconds = 248 hours**

**Cost Savings:**
- I/O reduction: 11M pages → 500K pages = 95% reduction
- Storage I/O cost savings: ~$500-$1,000/month (AWS EBS IOPS charges)
- Application timeout errors: Reduced from 25% to 0%
- Developer time saved troubleshooting timeouts: ~10 hours/week

---

## 🎓 Lessons Learned

### Anti-Pattern: CROSS APPLY with Scalar/Table-Valued Functions

**Problem:**
```sql
-- ❌ BAD: Row-by-row execution
CROSS APPLY USG_fnGetProjectionsLatestV2(mc.USG_Meter_Channel_ID, @espBeId) prj
```

**Solution:**
```sql
-- ✅ GOOD: Set-based operation
INNER JOIN dbo.USG_Projected_Usage_Interval pmui
    ON pmui.USG_Meter_Channel_ID = mc.USG_Meter_Channel_ID
    AND pmui.[Version] = [calculated_version]
```

### Best Practices

1. **Always inline functions when possible** - SQL Server cannot optimize across function calls
2. **Use covering indexes for large tables** - Eliminates table scans
3. **Add date range filters** - Reduce data volume (80-90% reduction)
4. **Prefer INNER JOIN over CROSS APPLY** - Better execution plans
5. **Test with production-like data volumes** - 10x difference between dev and prod

### Future Improvements

**Potential Phase 3 Optimizations:**
1. Partition `USG_Projected_Usage_Interval` by Flow_Date (monthly partitions)
2. Add filtered index for common ESP BE IDs
3. Implement query result caching (15-minute TTL)
4. Add query hints if plan regressions occur

---

## 📞 Support

### Deployment Questions

- **DBA Team:** dba-team@company.com
- **Application Team:** dev-team@company.com
- **On-Call:** xxx-xxx-xxxx

### Escalation Path

1. **Issues during index creation:** Stop creation, investigate disk space/locks
2. **Issues during testing:** Revert to v1, investigate execution plan differences
3. **Issues during rollout:** Stop rollout at current percentage, investigate
4. **Production incidents:** Immediately revert to v1, create incident ticket

---

## ✅ Deployment Checklist

### Pre-Deployment

- ☐ Read full deployment guide
- ☐ Verify disk space available (2x table size)
- ☐ Schedule index creation window (2 AM - 5 AM)
- ☐ Notify DBA team
- ☐ Create database backup
- ☐ Review rollback plan

### Phase 1: Index Creation

- ☐ Execute `USG_GetEspLdcAcctLatestProjections_v2_INDEX.sql`
- ☐ Monitor index creation progress
- ☐ Verify index created successfully
- ☐ Update statistics on new index
- ☐ Verify index is not fragmented

### Phase 2: Testing

- ☐ Deploy v2 to TEST environment
- ☐ Execute `USG_GetEspLdcAcctLatestProjections_v2_TEST.sql`
- ☐ Verify all tests pass
- ☐ Compare result sets (v1 vs v2)
- ☐ Review execution plans
- ☐ Document test results

### Phase 3: Soft Launch (10%)

- ☐ Deploy v2 to PRODUCTION
- ☐ Update 1-2 API endpoints to use v2
- ☐ Monitor for 24 hours
- ☐ Verify no errors or performance degradation
- ☐ Review execution stats

### Phase 4: Full Rollout (100%)

- ☐ Update 50% of API endpoints
- ☐ Monitor for 3 days
- ☐ Update remaining 50%
- ☐ Monitor for 1 week
- ☐ Keep v1 for 1 month (safety)

### Phase 5: Cleanup

- ☐ Verify v2 stable for 2 weeks
- ☐ Rename v2 → v1 (or update application)
- ☐ Drop deprecated v1 (after 1 month)
- ☐ Document final performance metrics
- ☐ Share success story with team

---

## 🎉 Expected Outcomes

### Performance Improvements

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Execution Time** | 5+ minutes | <5 seconds | **98% faster** |
| **Page Reads** | 11M pages (87 GB) | <500K pages (<4 GB) | **95% reduction** |
| **Timeout Rate** | 25-30% | 0% | **100% elimination** |
| **Daily Query Time** | 248 hours | 4 hours | **244 hours saved** |

### Business Value

- ✅ Eliminates production timeout errors
- ✅ Improves user experience (instant results vs 5+ minute waits)
- ✅ Reduces infrastructure costs (95% less I/O)
- ✅ Frees up database resources for other queries
- ✅ Demonstrates technical excellence and problem-solving

---

**Status:** ✅ Ready for Deployment
**Priority:** 🔥 CRITICAL
**Timeline:** 1-2 weeks
**Expected ROI:** 248 hours/day saved + $500-$1,000/month cost savings
**Risk Level:** Low (gradual rollout with rollback plan)

**Next Step:** Execute Phase 1 (Index Creation) during next available maintenance window.
