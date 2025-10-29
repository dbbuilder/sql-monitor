/*
================================================================================
PERFORMANCE COMPARISON TEST: v1 vs v2
================================================================================

**Purpose:** Compare original vs optimized procedure performance

**Expected Results:**
- v1 (original): 5+ minutes, 11M page reads
- v2 (optimized): <5 seconds, <500K page reads
- Improvement: 98% faster, 95% fewer disk reads

**Prerequisites:**
1. ✅ Covering index created (IX_USG_Projected_Usage_Interval_Covering)
2. ✅ v2 procedure deployed (USG_GetEspLdcAcctLatestProjections_v2)
3. ✅ Original procedure still exists (for comparison)

**Created:** 2025-10-29
**Author:** SQL Monitor Team
**Status:** ✅ Ready for Testing

================================================================================
*/

USE [PROD]  -- Change to your database name
GO

-- ============================================================================
-- TEST 1: Single Account Performance Test
-- ============================================================================

PRINT '========================================='
PRINT 'TEST 1: Single Account (ID: 203638)'
PRINT '========================================='
GO

DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id) VALUES (203638)

-- Clear cache for fair test (comment out in production)
-- DBCC DROPCLEANBUFFERS  -- Clears data cache
-- DBCC FREEPROCCACHE     -- Clears plan cache

PRINT ''
PRINT '--- ORIGINAL v1 (Current Production) ---'
SET STATISTICS TIME ON
SET STATISTICS IO ON

EXEC [dbo].[USG_GetEspLdcAcctLatestProjections]
    @espBeId = 484,
    @acctIdList = @acctIdList

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
GO

PRINT ''
PRINT '--- OPTIMIZED v2 (New Version) ---'

DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id) VALUES (203638)

SET STATISTICS TIME ON
SET STATISTICS IO ON

EXEC [dbo].[USG_GetEspLdcAcctLatestProjections_v2]
    @espBeId = 484,
    @acctIdList = @acctIdList,
    @debug = 1  -- Show debug info

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
GO

-- ============================================================================
-- TEST 2: Multiple Accounts Performance Test
-- ============================================================================

PRINT ''
PRINT '========================================='
PRINT 'TEST 2: Multiple Accounts (10 accounts)'
PRINT '========================================='
GO

-- Get 10 random accounts from your database
DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id)
SELECT TOP 10 USG_LDC_Account_ID
FROM USG_Ldc_Account
WHERE USG_LDC_Account_ID IS NOT NULL
ORDER BY USG_LDC_Account_ID

PRINT ''
PRINT '--- ORIGINAL v1 ---'
SET STATISTICS TIME ON
SET STATISTICS IO ON

EXEC [dbo].[USG_GetEspLdcAcctLatestProjections]
    @espBeId = 484,
    @acctIdList = @acctIdList

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
GO

PRINT ''
PRINT '--- OPTIMIZED v2 ---'

DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id)
SELECT TOP 10 USG_LDC_Account_ID
FROM USG_Ldc_Account
WHERE USG_LDC_Account_ID IS NOT NULL
ORDER BY USG_LDC_Account_ID

SET STATISTICS TIME ON
SET STATISTICS IO ON

EXEC [dbo].[USG_GetEspLdcAcctLatestProjections_v2]
    @espBeId = 484,
    @acctIdList = @acctIdList,
    @debug = 1

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
GO

-- ============================================================================
-- TEST 3: Result Set Comparison (Verify correctness)
-- ============================================================================

PRINT ''
PRINT '========================================='
PRINT 'TEST 3: Result Set Comparison'
PRINT '========================================='
GO

DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id) VALUES (203638)

-- Store v1 results in temp table
SELECT * INTO #v1Results
FROM (
    EXEC [dbo].[USG_GetEspLdcAcctLatestProjections]
        @espBeId = 484,
        @acctIdList = @acctIdList
) v1

-- Store v2 results in temp table
DECLARE @acctIdList2 IntIdTable
INSERT @acctIdList2 (Id) VALUES (203638)

SELECT * INTO #v2Results
FROM (
    EXEC [dbo].[USG_GetEspLdcAcctLatestProjections_v2]
        @espBeId = 484,
        @acctIdList = @acctIdList2
) v2

-- Compare row counts
PRINT ''
PRINT 'Row count comparison:'
SELECT
    (SELECT COUNT(*) FROM #v1Results) AS v1_RowCount,
    (SELECT COUNT(*) FROM #v2Results) AS v2_RowCount,
    (SELECT COUNT(*) FROM #v1Results) - (SELECT COUNT(*) FROM #v2Results) AS Difference

-- Find rows in v1 but not in v2
PRINT ''
PRINT 'Rows in v1 but NOT in v2 (should be 0):'
SELECT COUNT(*) AS MissingFromV2
FROM #v1Results v1
WHERE NOT EXISTS (
    SELECT 1 FROM #v2Results v2
    WHERE v1.ldcAcctId = v2.ldcAcctId
      AND v1.USG_Meter_Channel_ID = v2.USG_Meter_Channel_ID
      AND v1.Interval = v2.Interval
)

-- Find rows in v2 but not in v1
PRINT ''
PRINT 'Rows in v2 but NOT in v1 (should be 0):'
SELECT COUNT(*) AS MissingFromV1
FROM #v2Results v2
WHERE NOT EXISTS (
    SELECT 1 FROM #v1Results v1
    WHERE v1.ldcAcctId = v2.ldcAcctId
      AND v1.USG_Meter_Channel_ID = v2.USG_Meter_Channel_ID
      AND v1.Interval = v2.Interval
)

-- Cleanup
DROP TABLE #v1Results
DROP TABLE #v2Results
GO

-- ============================================================================
-- TEST 4: Execution Plan Comparison
-- ============================================================================

PRINT ''
PRINT '========================================='
PRINT 'TEST 4: Execution Plan Comparison'
PRINT '========================================='
PRINT '(View in SSMS with "Include Actual Execution Plan" enabled)'
GO

DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id) VALUES (203638)

-- Enable execution plan
SET SHOWPLAN_ALL ON
GO

-- v1 plan
EXEC [dbo].[USG_GetEspLdcAcctLatestProjections]
    @espBeId = 484,
    @acctIdList = @acctIdList
GO

SET SHOWPLAN_ALL OFF
GO

-- v2 plan
SET SHOWPLAN_ALL ON
GO

DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id) VALUES (203638)

EXEC [dbo].[USG_GetEspLdcAcctLatestProjections_v2]
    @espBeId = 484,
    @acctIdList = @acctIdList
GO

SET SHOWPLAN_ALL OFF
GO

-- ============================================================================
-- TEST 5: Date Range Filter Test (v2 only)
-- ============================================================================

PRINT ''
PRINT '========================================='
PRINT 'TEST 5: Date Range Filter (v2 feature)'
PRINT '========================================='
GO

DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id) VALUES (203638)

PRINT ''
PRINT '--- Test 5a: Last 7 days only ---'
SET STATISTICS TIME ON
SET STATISTICS IO ON

EXEC [dbo].[USG_GetEspLdcAcctLatestProjections_v2]
    @espBeId = 484,
    @acctIdList = @acctIdList,
    @startDate = DATEADD(DAY, -7, GETDATE()),
    @endDate = GETDATE(),
    @debug = 1

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
GO

DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id) VALUES (203638)

PRINT ''
PRINT '--- Test 5b: Next 30 days only (future projections) ---'
SET STATISTICS TIME ON
SET STATISTICS IO ON

EXEC [dbo].[USG_GetEspLdcAcctLatestProjections_v2]
    @espBeId = 484,
    @acctIdList = @acctIdList,
    @startDate = GETDATE(),
    @endDate = DATEADD(DAY, 30, GETDATE()),
    @debug = 1

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
GO

-- ============================================================================
-- TEST 6: Stress Test (100 accounts)
-- ============================================================================

PRINT ''
PRINT '========================================='
PRINT 'TEST 6: Stress Test (100 accounts)'
PRINT '========================================='
PRINT 'WARNING: v1 may timeout (5+ minutes expected)'
PRINT 'Comment out v1 test if you want to skip it'
GO

-- Get 100 accounts
DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id)
SELECT TOP 100 USG_LDC_Account_ID
FROM USG_Ldc_Account
WHERE USG_LDC_Account_ID IS NOT NULL
ORDER BY USG_LDC_Account_ID

/*
-- UNCOMMENT TO TEST v1 (WARNING: MAY TAKE 5+ MINUTES)
PRINT ''
PRINT '--- ORIGINAL v1 (100 accounts) ---'
SET STATISTICS TIME ON
SET STATISTICS IO ON

EXEC [dbo].[USG_GetEspLdcAcctLatestProjections]
    @espBeId = 484,
    @acctIdList = @acctIdList

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
GO
*/

DECLARE @acctIdList IntIdTable
INSERT @acctIdList (Id)
SELECT TOP 100 USG_LDC_Account_ID
FROM USG_Ldc_Account
WHERE USG_LDC_Account_ID IS NOT NULL
ORDER BY USG_LDC_Account_ID

PRINT ''
PRINT '--- OPTIMIZED v2 (100 accounts) ---'
SET STATISTICS TIME ON
SET STATISTICS IO ON

EXEC [dbo].[USG_GetEspLdcAcctLatestProjections_v2]
    @espBeId = 484,
    @acctIdList = @acctIdList,
    @debug = 1

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
GO

-- ============================================================================
-- TEST 7: Index Usage Verification
-- ============================================================================

PRINT ''
PRINT '========================================='
PRINT 'TEST 7: Verify Covering Index is Used'
PRINT '========================================='
GO

-- Check index usage stats
SELECT
    OBJECT_NAME(ius.object_id) AS TableName,
    i.name AS IndexName,
    ius.user_seeks AS IndexSeeks,
    ius.user_scans AS IndexScans,
    ius.user_lookups AS IndexLookups,
    ius.last_user_seek AS LastSeek,
    CASE
        WHEN ius.user_seeks > 0 THEN '✅ Index is being used'
        ELSE '❌ Index NOT used (investigate)'
    END AS Status
FROM sys.dm_db_index_usage_stats ius
JOIN sys.indexes i
    ON ius.object_id = i.object_id
    AND ius.index_id = i.index_id
WHERE ius.database_id = DB_ID()
  AND ius.object_id = OBJECT_ID('dbo.USG_Projected_Usage_Interval')
  AND i.name = 'IX_USG_Projected_Usage_Interval_Covering'
GO

-- ============================================================================
-- TEST RESULTS SUMMARY
-- ============================================================================

PRINT ''
PRINT '========================================='
PRINT 'TEST RESULTS SUMMARY'
PRINT '========================================='
PRINT ''
PRINT 'Expected Results:'
PRINT '  v1 (original): 5+ minutes, 11M page reads, PAGEIOLATCH_SH waits'
PRINT '  v2 (optimized): <5 seconds, <500K page reads, minimal waits'
PRINT ''
PRINT 'Verification Checklist:'
PRINT '  ☐ v2 completes in <5 seconds'
PRINT '  ☐ v2 has <500K logical reads'
PRINT '  ☐ v1 and v2 return same row count'
PRINT '  ☐ No rows missing between v1 and v2'
PRINT '  ☐ Execution plan shows Index Seek on covering index'
PRINT '  ☐ No table scans in v2 execution plan'
PRINT '  ☐ Date range filter reduces page reads further'
PRINT ''
PRINT 'If all checks pass: ✅ Ready for production deployment'
PRINT 'If any checks fail: ❌ Investigate and fix before deployment'
GO

/*
================================================================================
PRODUCTION DEPLOYMENT PLAN
================================================================================

After successful testing:

PHASE 1: Soft Launch (Week 1)
☐ 1. Deploy v2 procedure to production (during off-peak hours)
☐ 2. Update 10% of application calls to use v2
☐ 3. Monitor performance metrics daily
☐ 4. Monitor error logs for any issues
☐ 5. Verify no increase in errors or timeouts

PHASE 2: Rollout (Week 2)
☐ 6. Update 50% of application calls to use v2
☐ 7. Continue monitoring performance
☐ 8. Compare v1 vs v2 execution times in production

PHASE 3: Full Deployment (Week 3)
☐ 9. Update 100% of application calls to use v2
☐ 10. Keep v1 procedure for 1 month (rollback safety)
☐ 11. After validation, drop v1 or rename v2 → v1

ROLLBACK PLAN:
If v2 has issues:
    1. Revert application to call v1
    2. Investigate execution plan differences
    3. Check for missing data in results
    4. Review index fragmentation

================================================================================
*/

PRINT '✅ Test script completed'
PRINT 'Next steps:'
PRINT '  1. Review test results above'
PRINT '  2. Compare execution times (v1 vs v2)'
PRINT '  3. Verify result sets match exactly'
PRINT '  4. If tests pass, proceed with production deployment'
GO
