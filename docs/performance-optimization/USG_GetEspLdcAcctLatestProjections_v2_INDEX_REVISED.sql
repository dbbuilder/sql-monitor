/*
================================================================================
REVISED COVERING INDEX FOR USG_GetEspLdcAcctLatestProjections_v2
================================================================================

**CRITICAL UPDATE:** Existing index found that's close to what we need!

**Current Index:**
    IX_Projected_Usage_Channel_Version_ESP (USG_Meter_Channel_ID, Version, ESP_BE_ID)

**Problem:**
    - Missing Flow_Date (critical for date range filtering)
    - Missing INCLUDE clause with HE01-HE24 columns

**Solution:**
    - DROP existing IX_Projected_Usage_Channel_Version_ESP
    - CREATE enhanced version with Flow_Date + INCLUDE clause

**Table Stats:**
    - Rows: 409,235,729 (409 million)
    - Size: 167,927 MB (164 GB)
    - Estimated new index size: 40-60 GB
    - Estimated creation time: 2-3 hours

**Deployment:**
    - Run during off-peak hours (2 AM - 5 AM recommended)
    - Use ONLINE = ON to minimize blocking
    - Requires ~100 GB free disk space

**Created:** 2025-10-29 (Revised)
**Author:** SQL Monitor Team
**Status:** ✅ Ready for Deployment

================================================================================
*/

USE [PROD]  -- Change to your database name
GO

-- ============================================================================
-- STEP 1: Verify current index usage before dropping
-- ============================================================================

PRINT '=== Current Index Usage Stats ==='
SELECT
    OBJECT_NAME(ius.object_id) AS TableName,
    i.name AS IndexName,
    ius.user_seeks AS Seeks,
    ius.user_scans AS Scans,
    ius.user_lookups AS Lookups,
    ius.user_updates AS Updates,
    ius.last_user_seek AS LastSeek,
    ius.last_user_scan AS LastScan,
    CASE
        WHEN ius.user_seeks + ius.user_scans + ius.user_lookups > 0
        THEN '✅ Index is being used'
        ELSE '⚠️ Index has no reads'
    END AS Status
FROM sys.dm_db_index_usage_stats ius
JOIN sys.indexes i
    ON ius.object_id = i.object_id
    AND ius.index_id = i.index_id
WHERE ius.database_id = DB_ID()
  AND ius.object_id = OBJECT_ID('dbo.USG_Projected_Usage_Interval')
  AND i.name = 'IX_Projected_Usage_Channel_Version_ESP'
GO

-- ============================================================================
-- STEP 2: Check current index size
-- ============================================================================

PRINT ''
PRINT '=== Current Index Size ==='
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    ips.page_count,
    ips.page_count * 8 / 1024 AS IndexSizeMB,
    ips.avg_fragmentation_in_percent AS FragmentationPct,
    ips.record_count AS RecordCount
FROM sys.dm_db_index_physical_stats(
    DB_ID(),
    OBJECT_ID('dbo.USG_Projected_Usage_Interval'),
    NULL,
    NULL,
    'SAMPLED'
) ips
JOIN sys.indexes i
    ON ips.object_id = i.object_id
    AND ips.index_id = i.index_id
WHERE i.name = 'IX_Projected_Usage_Channel_Version_ESP'
GO

-- ============================================================================
-- STEP 3: Verify sufficient disk space
-- ============================================================================

PRINT ''
PRINT '=== Disk Space Check ==='
EXEC xp_fixeddrives
GO

PRINT ''
PRINT '⚠️  WARNING: You need at least 100 GB free space for this operation'
PRINT '⚠️  Estimated new index size: 40-60 GB'
PRINT '⚠️  Estimated creation time: 2-3 hours (409 million rows)'
PRINT ''
PRINT 'Press CTRL+C to cancel, or continue to proceed...'
WAITFOR DELAY '00:00:10'  -- 10 second pause
GO

-- ============================================================================
-- STEP 4: Drop existing index (prepare for enhanced version)
-- ============================================================================

PRINT ''
PRINT '=== Dropping Existing Index ==='
PRINT 'Dropping IX_Projected_Usage_Channel_Version_ESP...'

DROP INDEX IF EXISTS IX_Projected_Usage_Channel_Version_ESP
    ON dbo.USG_Projected_Usage_Interval
GO

PRINT '✅ Existing index dropped'
GO

-- ============================================================================
-- STEP 5: Create enhanced covering index (ONLINE mode)
-- ============================================================================

PRINT ''
PRINT '=== Creating Enhanced Covering Index ==='
PRINT 'This will take 2-3 hours for 409 million rows...'
PRINT 'Start time: ' + CONVERT(VARCHAR(20), GETDATE(), 120)
GO

CREATE NONCLUSTERED INDEX IX_Projected_Usage_Channel_Version_ESP_Enhanced
ON dbo.USG_Projected_Usage_Interval (
    -- Key columns (used in WHERE/JOIN/ORDER BY clauses)
    USG_Meter_Channel_ID,     -- JOIN condition
    [Version],                 -- JOIN condition (projection version)
    ESP_BE_ID,                 -- JOIN condition (business entity)
    Flow_Date                  -- ✅ NEW: Date range filter (CRITICAL for performance)
)
INCLUDE (
    -- Non-key columns (used in SELECT clause)
    Projection_Cycle,          -- Returned in SELECT
    Interval,                  -- Returned in SELECT
    -- Hourly energy values (HE01-HE24, HE2X) - 25 columns
    HE01, HE02, HE03, HE04, HE05, HE06,
    HE07, HE08, HE09, HE10, HE11, HE12,
    HE13, HE14, HE15, HE16, HE17, HE18,
    HE19, HE20, HE21, HE22, HE23, HE24,
    HE2X,
    -- F-values (not in current query, but keeping for compatibility)
    F01, F02, F03, F04, F05, F06,
    F07, F08, F09, F10, F11, F12,
    F13, F14, F15, F16, F17, F18,
    F19, F20, F21, F22, F23, F24,
    F2X,
    -- Other metadata columns
    Is_Filled,
    USG_Meter_Usage_Rank_Type_ID
)
WITH (
    ONLINE = ON,              -- Allow concurrent access (critical for production)
    FILLFACTOR = 90,          -- Leave 10% free space for future INSERTs
    SORT_IN_TEMPDB = ON,      -- Use tempdb for sort operations (faster, but needs tempdb space)
    MAXDOP = 4,               -- Use 4 CPU cores (adjust based on server load)
    DATA_COMPRESSION = PAGE   -- Compress index pages (save 40-60% space)
)
ON [PRIMARY]
GO

PRINT ''
PRINT '✅ Enhanced covering index created successfully'
PRINT 'End time: ' + CONVERT(VARCHAR(20), GETDATE(), 120)
GO

-- ============================================================================
-- STEP 6: Update statistics (ensure optimizer uses new index)
-- ============================================================================

PRINT ''
PRINT '=== Updating Statistics ==='
UPDATE STATISTICS dbo.USG_Projected_Usage_Interval
    IX_Projected_Usage_Channel_Version_ESP_Enhanced
WITH FULLSCAN
GO

PRINT '✅ Statistics updated'
GO

-- ============================================================================
-- STEP 7: Verify new index creation
-- ============================================================================

PRINT ''
PRINT '=== New Index Verification ==='
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    ips.page_count,
    ips.page_count * 8 / 1024 AS IndexSizeMB,
    ips.avg_fragmentation_in_percent AS FragmentationPct,
    ips.record_count AS RecordCount
FROM sys.dm_db_index_physical_stats(
    DB_ID(),
    OBJECT_ID('dbo.USG_Projected_Usage_Interval'),
    NULL,
    NULL,
    'SAMPLED'
) ips
JOIN sys.indexes i
    ON ips.object_id = i.object_id
    AND ips.index_id = i.index_id
WHERE i.name = 'IX_Projected_Usage_Channel_Version_ESP_Enhanced'
GO

-- ============================================================================
-- STEP 8: Verify all indexes on table
-- ============================================================================

PRINT ''
PRINT '=== All Indexes on Table ==='
EXEC sp_helpindex 'dbo.USG_Projected_Usage_Interval'
GO

/*
================================================================================
MONITORING QUERY (Run in separate window during index creation)
================================================================================
*/

-- Run this query in a separate SSMS window to track progress
/*
SELECT
    r.session_id,
    r.command,
    OBJECT_NAME(r.object_id) AS TableName,
    r.percent_complete,
    r.estimated_completion_time / 1000 / 60 AS EstimatedMinutesRemaining,
    r.total_elapsed_time / 1000 / 60 AS ElapsedMinutes,
    r.wait_type,
    r.wait_time,
    r.cpu_time,
    r.logical_reads,
    r.writes
FROM sys.dm_exec_requests r
WHERE r.command = 'CREATE INDEX'
  AND r.object_id = OBJECT_ID('dbo.USG_Projected_Usage_Interval')
GO
*/

/*
================================================================================
POST-DEPLOYMENT MONITORING (Run after 1 week)
================================================================================
*/

-- Check if new index is being used
/*
SELECT
    OBJECT_NAME(ius.object_id) AS TableName,
    i.name AS IndexName,
    ius.user_seeks AS Seeks,
    ius.user_scans AS Scans,
    ius.user_lookups AS Lookups,
    ius.user_updates AS Updates,
    ius.last_user_seek AS LastSeek,
    CASE
        WHEN ius.user_seeks > 1000 THEN '✅ Excellent usage'
        WHEN ius.user_seeks > 100 THEN '✅ Good usage'
        WHEN ius.user_seeks > 0 THEN '⚠️ Low usage'
        ELSE '❌ Not being used'
    END AS Status
FROM sys.dm_db_index_usage_stats ius
JOIN sys.indexes i
    ON ius.object_id = i.object_id
    AND ius.index_id = i.index_id
WHERE ius.database_id = DB_ID()
  AND ius.object_id = OBJECT_ID('dbo.USG_Projected_Usage_Interval')
  AND i.name = 'IX_Projected_Usage_Channel_Version_ESP_Enhanced'
GO
*/

/*
================================================================================
ROLLBACK PLAN (If new index causes issues)
================================================================================
*/

-- If new index causes problems, drop it and recreate original
/*
-- Drop enhanced index
DROP INDEX IF EXISTS IX_Projected_Usage_Channel_Version_ESP_Enhanced
    ON dbo.USG_Projected_Usage_Interval
GO

-- Recreate original index (without Flow_Date and INCLUDE)
CREATE NONCLUSTERED INDEX IX_Projected_Usage_Channel_Version_ESP
ON dbo.USG_Projected_Usage_Interval (
    USG_Meter_Channel_ID,
    [Version],
    ESP_BE_ID
)
WITH (ONLINE = ON, FILLFACTOR = 90)
GO
*/

/*
================================================================================
INDEX MAINTENANCE PLAN (Monthly)
================================================================================
*/

-- Run monthly to rebuild fragmented indexes
/*
-- Check fragmentation
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent AS FragmentationPct,
    CASE
        WHEN ips.avg_fragmentation_in_percent > 30 THEN '❌ REBUILD needed'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN '⚠️ REORGANIZE recommended'
        ELSE '✅ OK'
    END AS Action
FROM sys.dm_db_index_physical_stats(
    DB_ID(),
    OBJECT_ID('dbo.USG_Projected_Usage_Interval'),
    NULL,
    NULL,
    'SAMPLED'
) ips
JOIN sys.indexes i
    ON ips.object_id = i.object_id
    AND ips.index_id = i.index_id
WHERE i.name = 'IX_Projected_Usage_Channel_Version_ESP_Enhanced'
GO

-- If fragmentation > 30%, rebuild index
ALTER INDEX IX_Projected_Usage_Channel_Version_ESP_Enhanced
    ON dbo.USG_Projected_Usage_Interval
REBUILD
WITH (
    ONLINE = ON,
    FILLFACTOR = 90,
    SORT_IN_TEMPDB = ON,
    DATA_COMPRESSION = PAGE,
    MAXDOP = 4
)
GO

-- Update statistics after rebuild
UPDATE STATISTICS dbo.USG_Projected_Usage_Interval
    IX_Projected_Usage_Channel_Version_ESP_Enhanced
WITH FULLSCAN
GO
*/

PRINT ''
PRINT '========================================='
PRINT '✅ INDEX CREATION COMPLETED'
PRINT '========================================='
PRINT ''
PRINT 'Next Steps:'
PRINT '  1. Verify index exists: EXEC sp_helpindex ''dbo.USG_Projected_Usage_Interval'''
PRINT '  2. Deploy v2 procedure: Run USG_GetEspLdcAcctLatestProjections_v2_OPTIMIZED.sql'
PRINT '  3. Run performance tests: Run USG_GetEspLdcAcctLatestProjections_v2_TEST.sql'
PRINT '  4. Monitor index usage after 1 week'
PRINT ''
PRINT 'Index Details:'
PRINT '  Name: IX_Projected_Usage_Channel_Version_ESP_Enhanced'
PRINT '  Table: USG_Projected_Usage_Interval'
PRINT '  Rows: 409,235,729'
PRINT '  Key Columns: USG_Meter_Channel_ID, Version, ESP_BE_ID, Flow_Date'
PRINT '  INCLUDE: 50+ columns (HE01-HE24, F01-F24, etc.)'
PRINT ''
GO
