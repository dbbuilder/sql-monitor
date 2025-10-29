-- =====================================================================================
-- SQL Monitor Agent - Adjust Collection Schedule
-- Purpose: Modify SQL Agent job schedules to reduce collection frequency
-- =====================================================================================
--
-- Background:
--   The DBATools monitoring jobs collect performance data at regular intervals.
--   Default frequency is every 5 minutes for all collections.
--   If performance overhead becomes a concern, you can adjust schedules here.
--
-- Priority Levels:
--   P0 (Critical):  Core server health, wait stats, blocking - Keep at 5 minutes
--   P1 (Medium):    Query stats, index usage, memory - Can reduce to 15 minutes
--   P2 (Low):       Missing indexes, deadlocks, logs - Can reduce to 30 minutes
--   P3 (Archive):   Historical trends, capacity planning - Can reduce to 60 minutes
--
-- Usage:
--   1. Review current schedules (query at bottom)
--   2. Uncomment and run desired schedule changes
--   3. Verify changes with the verification query
--
-- Author: SQL Monitor Team
-- Date: 2025-10-29
-- =====================================================================================

USE msdb
GO

SET NOCOUNT ON
GO

PRINT ''
PRINT '=========================================='
PRINT 'DBATools Collection Schedule Adjustment'
PRINT '=========================================='
PRINT ''

-- =====================================================================================
-- Current Schedules (Before Changes)
-- =====================================================================================

PRINT 'CURRENT SCHEDULES (Before Changes):'
PRINT ''

SELECT
    s.name AS ScheduleName,
    j.name AS JobName,
    j.enabled AS JobEnabled,
    CASE s.freq_type
        WHEN 1 THEN 'Once'
        WHEN 4 THEN 'Daily'
        WHEN 8 THEN 'Weekly'
        WHEN 16 THEN 'Monthly'
        WHEN 32 THEN 'Monthly (relative)'
        WHEN 64 THEN 'When SQL Server Agent starts'
        WHEN 128 THEN 'When computer is idle'
    END AS FrequencyType,
    CASE s.freq_subday_type
        WHEN 1 THEN 'Once'
        WHEN 2 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' seconds'
        WHEN 4 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' minutes'
        WHEN 8 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' hours'
    END AS Frequency,
    s.freq_subday_interval AS IntervalValue
FROM msdb.dbo.sysschedules s
INNER JOIN msdb.dbo.sysjobschedules js ON s.schedule_id = js.schedule_id
INNER JOIN msdb.dbo.sysjobs j ON js.job_id = j.job_id
WHERE s.name LIKE 'DBA%'
   OR j.name LIKE 'DBA%'
ORDER BY s.name

PRINT ''
PRINT '=========================================='
PRINT 'Schedule Adjustment Options'
PRINT '=========================================='
PRINT ''

-- =====================================================================================
-- Option 1: Keep P0 at 5 minutes, reduce P1 to 15 minutes, P2 to 30 minutes
-- =====================================================================================

PRINT 'Option 1: Balanced Performance (Recommended)'
PRINT '  P0 (Critical): 5 minutes  - No change'
PRINT '  P1 (Medium):   15 minutes - Reduced frequency'
PRINT '  P2 (Low):      30 minutes - Reduced frequency'
PRINT ''

-- Uncomment to apply Option 1:

/*
-- Update P1 collections to run every 15 minutes
IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = 'DBATools_P1_Schedule')
BEGIN
    EXEC sp_update_schedule
        @name = 'DBATools_P1_Schedule',
        @freq_type = 4,  -- Daily
        @freq_interval = 1,
        @freq_subday_type = 4,  -- Minutes
        @freq_subday_interval = 15;  -- Every 15 minutes

    PRINT '  ✓ P1 schedule updated to 15 minutes'
END

-- Update P2 collections to run every 30 minutes
IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = 'DBATools_P2_Schedule')
BEGIN
    EXEC sp_update_schedule
        @name = 'DBATools_P2_Schedule',
        @freq_type = 4,  -- Daily
        @freq_interval = 1,
        @freq_subday_type = 4,  -- Minutes
        @freq_subday_interval = 30;  -- Every 30 minutes

    PRINT '  ✓ P2 schedule updated to 30 minutes'
END
*/

-- =====================================================================================
-- Option 2: Maximum Performance Reduction (Low-activity servers)
-- =====================================================================================

PRINT ''
PRINT 'Option 2: Maximum Performance Reduction (For low-activity servers)'
PRINT '  P0 (Critical): 15 minutes - Reduced frequency'
PRINT '  P1 (Medium):   30 minutes - Reduced frequency'
PRINT '  P2 (Low):      60 minutes - Reduced frequency'
PRINT ''

-- Uncomment to apply Option 2:

/*
-- Update P0 collections to run every 15 minutes
IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = 'DBATools_P0_Schedule')
BEGIN
    EXEC sp_update_schedule
        @name = 'DBATools_P0_Schedule',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 15;

    PRINT '  ✓ P0 schedule updated to 15 minutes'
END

-- Update P1 collections to run every 30 minutes
IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = 'DBATools_P1_Schedule')
BEGIN
    EXEC sp_update_schedule
        @name = 'DBATools_P1_Schedule',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 30;

    PRINT '  ✓ P1 schedule updated to 30 minutes'
END

-- Update P2 collections to run every 60 minutes
IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = 'DBATools_P2_Schedule')
BEGIN
    EXEC sp_update_schedule
        @name = 'DBATools_P2_Schedule',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 60;

    PRINT '  ✓ P2 schedule updated to 60 minutes'
END
*/

-- =====================================================================================
-- Option 3: Custom - Adjust individual job schedules
-- =====================================================================================

PRINT ''
PRINT 'Option 3: Custom (Adjust specific jobs as needed)'
PRINT ''

-- Example: Adjust a specific job
-- Uncomment and modify as needed:

/*
EXEC sp_update_schedule
    @name = 'YourScheduleName',
    @freq_type = 4,  -- Daily
    @freq_interval = 1,
    @freq_subday_type = 4,  -- Minutes
    @freq_subday_interval = 10;  -- Every 10 minutes
*/

-- =====================================================================================
-- Verification Query (Run after making changes)
-- =====================================================================================

PRINT ''
PRINT '=========================================='
PRINT 'VERIFICATION: Updated Schedules'
PRINT '=========================================='
PRINT ''

SELECT
    s.name AS ScheduleName,
    j.name AS JobName,
    j.enabled AS JobEnabled,
    CASE s.freq_subday_type
        WHEN 1 THEN 'Once'
        WHEN 2 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' seconds'
        WHEN 4 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' minutes'
        WHEN 8 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' hours'
    END AS CurrentFrequency,
    s.freq_subday_interval AS IntervalMinutes
FROM msdb.dbo.sysschedules s
INNER JOIN msdb.dbo.sysjobschedules js ON s.schedule_id = js.schedule_id
INNER JOIN msdb.dbo.sysjobs j ON js.job_id = j.job_id
WHERE s.name LIKE 'DBA%'
   OR j.name LIKE 'DBA%'
ORDER BY s.name

PRINT ''
PRINT '=========================================='
PRINT 'Schedule Adjustment Complete'
PRINT '=========================================='
PRINT ''
PRINT 'Notes:'
PRINT '  - Changes take effect immediately for future job executions'
PRINT '  - Monitor job history to verify new schedule is working'
PRINT '  - Use EXEC msdb.dbo.sp_help_jobhistory to view execution history'
PRINT ''

GO
