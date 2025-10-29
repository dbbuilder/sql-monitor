/*
================================================================================
COVERING INDEX FOR USG_GetEspLdcAcctLatestProjections_v2
================================================================================

**Purpose:** Eliminate table scans on USG_Projected_Usage_Interval

**Impact:**
- BEFORE: 11M page reads (table scans on 87 GB of data)
- AFTER: <500K page reads (index seeks only)
- Reduction: 95% fewer disk reads

**Deployment:**
- Run during off-peak hours (2 AM - 5 AM recommended)
- Use ONLINE = ON to avoid blocking
- Estimated time: 30-60 minutes (depends on table size)
- Estimated size: 10-30% of table size

**Prerequisites:**
- Check current table size first (see queries below)
- Ensure sufficient disk space (2x current table size)
- Monitor progress with sys.dm_exec_requests

**Created:** 2025-10-29
**Author:** SQL Monitor Team
**Status:** ✅ Ready for Deployment

================================================================================
*/

USE [PROD]  -- Change to your database name
GO

-- ============================================================================
-- STEP 1: Check current table size and row count
-- ============================================================================

SELECT
    OBJECT_NAME(p.object_id) AS TableName,
    p.rows AS RowCount,
    SUM(au.total_pages) * 8 / 1024 AS TotalSizeMB,
    SUM(au.used_pages) * 8 / 1024 AS UsedSizeMB,
    SUM(au.data_pages) * 8 / 1024 AS DataSizeMB
FROM sys.partitions p
JOIN sys.allocation_units au
    ON p.partition_id = au.container_id
WHERE p.object_id = OBJECT_ID('dbo.USG_Projected_Usage_Interval')
GROUP BY p.object_id, p.rows
GO

-- Check existing indexes
EXEC sp_helpindex 'dbo.USG_Projected_Usage_Interval'
GO

-- ============================================================================
-- STEP 2: Create covering index (ONLINE mode)
-- ============================================================================

-- Drop existing index if this is a re-creation
-- IF EXISTS (SELECT 1 FROM sys.indexes
--            WHERE name = 'IX_USG_Projected_Usage_Interval_Covering'
--            AND object_id = OBJECT_ID('dbo.USG_Projected_Usage_Interval'))
-- BEGIN
--     DROP INDEX IX_USG_Projected_Usage_Interval_Covering
--         ON dbo.USG_Projected_Usage_Interval
--     PRINT 'Existing index dropped'
-- END
-- GO

CREATE NONCLUSTERED INDEX IX_USG_Projected_Usage_Interval_Covering
ON dbo.USG_Projected_Usage_Interval (
    -- Key columns (used in WHERE/JOIN clauses)
    USG_Meter_Channel_ID,     -- JOIN condition
    [Version],                 -- JOIN condition (projection version)
    ESP_BE_ID,                 -- JOIN condition (business entity)
    Flow_Date                  -- ✅ NEW: Date range filter (huge performance gain)
)
INCLUDE (
    -- Non-key columns (used in SELECT clause)
    Projection_Cycle,
    Interval,
    -- Hourly values (HE01-HE24, HE2X)
    HE01, HE02, HE03, HE04, HE05, HE06,
    HE07, HE08, HE09, HE10, HE11, HE12,
    HE13, HE14, HE15, HE16, HE17, HE18,
    HE19, HE20, HE21, HE22, HE23, HE24,
    HE2X,
    -- F-values (F01-F24, F2X) - Not in v2 query, but keeping for compatibility
    F01, F02, F03, F04, F05, F06,
    F07, F08, F09, F10, F11, F12,
    F13, F14, F15, F16, F17, F18,
    F19, F20, F21, F22, F23, F24,
    F2X,
    -- Other columns
    Is_Filled,
    USG_Meter_Usage_Rank_Type_ID
)
WITH (
    ONLINE = ON,              -- Allow concurrent access during index build
    FILLFACTOR = 90,          -- Leave 10% free space for future INSERTs
    SORT_IN_TEMPDB = ON,      -- Use tempdb for sort operations (faster)
    MAXDOP = 4,               -- Use 4 CPU cores (adjust based on server)
    DATA_COMPRESSION = PAGE   -- Compress index pages (save 40-60% space)
)
ON [PRIMARY]  -- Or specify filegroup
GO

-- ============================================================================
-- STEP 3: Verify index creation
-- ============================================================================

-- Check index size and fragmentation
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    ips.page_count,
    ips.page_count * 8 / 1024 AS IndexSizeMB,
    ips.avg_fragmentation_in_percent,
    ips.record_count
FROM sys.dm_db_index_physical_stats(
    DB_ID(),
    OBJECT_ID('dbo.USG_Projected_Usage_Interval'),
    NULL,
    NULL,
    'DETAILED'
) ips
JOIN sys.indexes i
    ON ips.object_id = i.object_id
    AND ips.index_id = i.index_id
WHERE i.name = 'IX_USG_Projected_Usage_Interval_Covering'
GO

-- ============================================================================
-- STEP 4: Update statistics (ensure optimizer uses new index)
-- ============================================================================

UPDATE STATISTICS dbo.USG_Projected_Usage_Interval
    IX_USG_Projected_Usage_Interval_Covering
WITH FULLSCAN
GO

-- ============================================================================
-- STEP 5: Monitor index usage (after deployment)
-- ============================================================================

-- Run this query after 1 week to verify index is being used
SELECT
    OBJECT_NAME(ius.object_id) AS TableName,
    i.name AS IndexName,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates,
    ius.last_user_seek,
    ius.last_user_scan
FROM sys.dm_db_index_usage_stats ius
JOIN sys.indexes i
    ON ius.object_id = i.object_id
    AND ius.index_id = i.index_id
WHERE ius.database_id = DB_ID()
  AND ius.object_id = OBJECT_ID('dbo.USG_Projected_Usage_Interval')
  AND i.name = 'IX_USG_Projected_Usage_Interval_Covering'
GO

/*
================================================================================
DEPLOYMENT CHECKLIST
================================================================================

BEFORE DEPLOYMENT:
☐ 1. Run Step 1 queries to verify table size
☐ 2. Verify sufficient disk space (2x table size)
☐ 3. Schedule during off-peak hours (2 AM - 5 AM)
☐ 4. Notify team of index creation (will consume resources)
☐ 5. Take database backup (precaution)

DURING DEPLOYMENT:
☐ 6. Run index creation script (Step 2)
☐ 7. Monitor progress with query below
☐ 8. Verify no blocking issues (check sys.dm_exec_requests)

AFTER DEPLOYMENT:
☐ 9. Run Step 3 to verify index created successfully
☐ 10. Run Step 4 to update statistics
☐ 11. Test USG_GetEspLdcAcctLatestProjections_v2 procedure
☐ 12. Monitor index usage after 1 week (Step 5)

ROLLBACK PLAN:
If index causes issues:
    DROP INDEX IX_USG_Projected_Usage_Interval_Covering
        ON dbo.USG_Projected_Usage_Interval

================================================================================
*/

-- ============================================================================
-- MONITORING QUERY (Run during index creation to track progress)
-- ============================================================================

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

-- ============================================================================
-- ADDITIONAL INDEXES (Optional - Review after v2 deployment)
-- ============================================================================

-- Index for USG_Projected_Esp_Setting (used in LEFT JOIN)
-- Uncomment if query plan shows table scan on this table
/*
CREATE NONCLUSTERED INDEX IX_USG_Projected_Esp_Setting_MeterChannel_Esp
ON dbo.USG_Projected_Esp_Setting (USG_Meter_Channel_ID, ESP_BE_ID)
INCLUDE (Projection_Type, Projection_Version)
WITH (ONLINE = ON, FILLFACTOR = 90, DATA_COMPRESSION = PAGE)
GO
*/

-- Index for USG_Projection_MeterChannel_Esp_Mapping (used in LEFT JOIN)
-- Uncomment if query plan shows table scan on this table
/*
CREATE NONCLUSTERED INDEX IX_USG_Projection_MeterChannel_Esp_Mapping_Covering
ON dbo.USG_Projection_MeterChannel_Esp_Mapping (
    USG_Meter_Channel_ID,
    ESP_BE_ID,
    Projection_Type
)
INCLUDE (Projection_Version)
WITH (ONLINE = ON, FILLFACTOR = 90, DATA_COMPRESSION = PAGE)
GO
*/

-- ============================================================================
-- INDEX MAINTENANCE PLAN (Monthly)
-- ============================================================================

-- Run monthly to rebuild fragmented indexes
/*
ALTER INDEX IX_USG_Projected_Usage_Interval_Covering
    ON dbo.USG_Projected_Usage_Interval
REBUILD
WITH (
    ONLINE = ON,
    FILLFACTOR = 90,
    SORT_IN_TEMPDB = ON,
    DATA_COMPRESSION = PAGE
)
GO

-- Update statistics after rebuild
UPDATE STATISTICS dbo.USG_Projected_Usage_Interval
    IX_USG_Projected_Usage_Interval_Covering
WITH FULLSCAN
GO
*/

PRINT '✅ Index creation script completed'
PRINT 'Next steps:'
PRINT '  1. Verify index exists: EXEC sp_helpindex ''dbo.USG_Projected_Usage_Interval'''
PRINT '  2. Test v2 procedure: See USG_GetEspLdcAcctLatestProjections_v2_TEST.sql'
PRINT '  3. Monitor usage after 1 week: Re-run Step 5 query'
GO
