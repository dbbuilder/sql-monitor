-- =====================================================
-- Script: 97-create-adaptive-collection.sql
-- Description: Adaptive collection with exponential backoff
-- Author: SQL Server Monitor Project
-- Date: 2025-11-26
-- Purpose: Reduce monitoring overhead by dynamically adjusting
--          collection frequency based on event occurrence
-- =====================================================
--
-- BEHAVIOR:
--   - When events are detected: Speed up to minimum interval (15 min)
--   - When no events: Gradually back off by 15 min per hour without events
--   - Maximum interval: 2 hours (to ensure periodic checks)
--   - Minimum interval: 15 minutes (when events are occurring)
--
-- APPLIES TO:
--   - Deadlock collection
--   - Blocking event collection (can be extended)
--
-- =====================================================

USE MonitoringDB;
GO

PRINT '========================================';
PRINT 'Creating Adaptive Collection System';
PRINT '========================================';
PRINT '';

-- =====================================================
-- Table: AdaptiveCollectionState
-- Tracks collection intervals and last event times
-- =====================================================

IF OBJECT_ID('dbo.AdaptiveCollectionState', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdaptiveCollectionState (
        CollectionType VARCHAR(50) NOT NULL PRIMARY KEY,
        CurrentIntervalMinutes INT NOT NULL DEFAULT 15,
        MinIntervalMinutes INT NOT NULL DEFAULT 15,
        MaxIntervalMinutes INT NOT NULL DEFAULT 120,
        BackoffIncrementMinutes INT NOT NULL DEFAULT 15,
        LastCollectionTime DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        LastEventDetectedTime DATETIME2 NULL,
        EventsDetectedSinceBackoff INT NOT NULL DEFAULT 0,
        ConsecutiveEmptyCollections INT NOT NULL DEFAULT 0,
        TotalCollections BIGINT NOT NULL DEFAULT 0,
        TotalEventsDetected BIGINT NOT NULL DEFAULT 0,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );

    PRINT 'Created table: dbo.AdaptiveCollectionState';
END
ELSE
    PRINT 'Table already exists: dbo.AdaptiveCollectionState';
GO

-- =====================================================
-- Initialize default collection types
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM dbo.AdaptiveCollectionState WHERE CollectionType = 'Deadlock')
BEGIN
    INSERT INTO dbo.AdaptiveCollectionState (
        CollectionType, CurrentIntervalMinutes, MinIntervalMinutes,
        MaxIntervalMinutes, BackoffIncrementMinutes
    )
    VALUES ('Deadlock', 15, 15, 120, 15);

    PRINT 'Initialized adaptive state for: Deadlock';
END

IF NOT EXISTS (SELECT 1 FROM dbo.AdaptiveCollectionState WHERE CollectionType = 'Blocking')
BEGIN
    INSERT INTO dbo.AdaptiveCollectionState (
        CollectionType, CurrentIntervalMinutes, MinIntervalMinutes,
        MaxIntervalMinutes, BackoffIncrementMinutes
    )
    VALUES ('Blocking', 5, 5, 30, 5);

    PRINT 'Initialized adaptive state for: Blocking';
END

IF NOT EXISTS (SELECT 1 FROM dbo.AdaptiveCollectionState WHERE CollectionType = 'MissingIndexes')
BEGIN
    INSERT INTO dbo.AdaptiveCollectionState (
        CollectionType, CurrentIntervalMinutes, MinIntervalMinutes,
        MaxIntervalMinutes, BackoffIncrementMinutes
    )
    VALUES ('MissingIndexes', 30, 30, 240, 30);  -- 30 min to 4 hours

    PRINT 'Initialized adaptive state for: MissingIndexes';
END

IF NOT EXISTS (SELECT 1 FROM dbo.AdaptiveCollectionState WHERE CollectionType = 'UnusedIndexes')
BEGIN
    INSERT INTO dbo.AdaptiveCollectionState (
        CollectionType, CurrentIntervalMinutes, MinIntervalMinutes,
        MaxIntervalMinutes, BackoffIncrementMinutes
    )
    VALUES ('UnusedIndexes', 60, 60, 360, 60);  -- 1 hour to 6 hours

    PRINT 'Initialized adaptive state for: UnusedIndexes';
END
GO

-- =====================================================
-- Procedure: usp_ShouldRunAdaptiveCollection
-- Returns 1 if collection should run, 0 if not yet time
-- =====================================================

IF OBJECT_ID('dbo.usp_ShouldRunAdaptiveCollection', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ShouldRunAdaptiveCollection;
GO

CREATE PROCEDURE dbo.usp_ShouldRunAdaptiveCollection
    @CollectionType VARCHAR(50),
    @ShouldRun BIT OUTPUT,
    @CurrentInterval INT OUTPUT,
    @MinutesSinceLastRun INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastCollectionTime DATETIME2;
    DECLARE @CurrentIntervalMinutes INT;

    SELECT
        @LastCollectionTime = LastCollectionTime,
        @CurrentIntervalMinutes = CurrentIntervalMinutes
    FROM dbo.AdaptiveCollectionState
    WHERE CollectionType = @CollectionType;

    IF @LastCollectionTime IS NULL
    BEGIN
        -- Collection type not found, initialize it
        SET @ShouldRun = 1;
        SET @CurrentInterval = 15;
        SET @MinutesSinceLastRun = 999;
        RETURN;
    END

    SET @MinutesSinceLastRun = DATEDIFF(MINUTE, @LastCollectionTime, GETUTCDATE());
    SET @CurrentInterval = @CurrentIntervalMinutes;

    IF @MinutesSinceLastRun >= @CurrentIntervalMinutes
        SET @ShouldRun = 1;
    ELSE
        SET @ShouldRun = 0;
END;
GO

PRINT 'Created procedure: dbo.usp_ShouldRunAdaptiveCollection';

-- =====================================================
-- Procedure: usp_UpdateAdaptiveCollectionState
-- Updates interval based on whether events were found
-- =====================================================

IF OBJECT_ID('dbo.usp_UpdateAdaptiveCollectionState', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_UpdateAdaptiveCollectionState;
GO

CREATE PROCEDURE dbo.usp_UpdateAdaptiveCollectionState
    @CollectionType VARCHAR(50),
    @EventsFound INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentInterval INT;
    DECLARE @MinInterval INT;
    DECLARE @MaxInterval INT;
    DECLARE @BackoffIncrement INT;
    DECLARE @ConsecutiveEmpty INT;
    DECLARE @NewInterval INT;
    DECLARE @LastEventTime DATETIME2;

    -- Get current state
    SELECT
        @CurrentInterval = CurrentIntervalMinutes,
        @MinInterval = MinIntervalMinutes,
        @MaxInterval = MaxIntervalMinutes,
        @BackoffIncrement = BackoffIncrementMinutes,
        @ConsecutiveEmpty = ConsecutiveEmptyCollections,
        @LastEventTime = LastEventDetectedTime
    FROM dbo.AdaptiveCollectionState
    WHERE CollectionType = @CollectionType;

    IF @CurrentInterval IS NULL
    BEGIN
        PRINT 'Collection type not found: ' + @CollectionType;
        RETURN;
    END

    IF @EventsFound > 0
    BEGIN
        -- Events detected: Reset to minimum interval
        SET @NewInterval = @MinInterval;
        SET @ConsecutiveEmpty = 0;
        SET @LastEventTime = GETUTCDATE();

        PRINT CONCAT('  Events detected (', @EventsFound, ') - resetting interval to ', @MinInterval, ' minutes');
    END
    ELSE
    BEGIN
        -- No events: Increase consecutive empty count and potentially back off
        SET @ConsecutiveEmpty = @ConsecutiveEmpty + 1;

        -- Back off every 4 consecutive empty collections (approximately 1 hour at 15-min intervals)
        -- Or adjust based on current interval
        DECLARE @CollectionsPerHour INT = CEILING(60.0 / @CurrentInterval);

        IF @ConsecutiveEmpty >= @CollectionsPerHour
        BEGIN
            -- Time to increase interval (exponential backoff)
            SET @NewInterval = @CurrentInterval + @BackoffIncrement;

            -- Cap at maximum
            IF @NewInterval > @MaxInterval
                SET @NewInterval = @MaxInterval;

            -- Reset consecutive counter after backing off
            SET @ConsecutiveEmpty = 0;

            IF @NewInterval > @CurrentInterval
                PRINT CONCAT('  No events for ~1 hour - backing off to ', @NewInterval, ' minute interval');
        END
        ELSE
        BEGIN
            -- Keep current interval
            SET @NewInterval = @CurrentInterval;
        END
    END

    -- Update state
    UPDATE dbo.AdaptiveCollectionState
    SET
        CurrentIntervalMinutes = @NewInterval,
        LastCollectionTime = GETUTCDATE(),
        LastEventDetectedTime = ISNULL(@LastEventTime, LastEventDetectedTime),
        EventsDetectedSinceBackoff = CASE WHEN @EventsFound > 0 THEN EventsDetectedSinceBackoff + @EventsFound ELSE 0 END,
        ConsecutiveEmptyCollections = @ConsecutiveEmpty,
        TotalCollections = TotalCollections + 1,
        TotalEventsDetected = TotalEventsDetected + @EventsFound,
        ModifiedDate = GETUTCDATE()
    WHERE CollectionType = @CollectionType;
END;
GO

PRINT 'Created procedure: dbo.usp_UpdateAdaptiveCollectionState';

-- =====================================================
-- Procedure: usp_CollectDeadlockEvents_Adaptive
-- Wrapper that uses adaptive scheduling
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectDeadlockEvents_Adaptive', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectDeadlockEvents_Adaptive;
GO

CREATE PROCEDURE dbo.usp_CollectDeadlockEvents_Adaptive
    @ServerID INT = NULL,
    @ForceRun BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ShouldRun BIT;
    DECLARE @CurrentInterval INT;
    DECLARE @MinutesSinceLastRun INT;
    DECLARE @EventsBefore BIGINT;
    DECLARE @EventsAfter BIGINT;
    DECLARE @EventsFound INT;

    -- Check if it's time to run
    EXEC dbo.usp_ShouldRunAdaptiveCollection
        @CollectionType = 'Deadlock',
        @ShouldRun = @ShouldRun OUTPUT,
        @CurrentInterval = @CurrentInterval OUTPUT,
        @MinutesSinceLastRun = @MinutesSinceLastRun OUTPUT;

    IF @ShouldRun = 0 AND @ForceRun = 0
    BEGIN
        PRINT CONCAT('Skipping deadlock collection - ', @MinutesSinceLastRun, ' minutes since last run, current interval is ', @CurrentInterval, ' minutes');
        RETURN;
    END

    PRINT CONCAT('Running adaptive deadlock collection (interval: ', @CurrentInterval, ' min, last run: ', @MinutesSinceLastRun, ' min ago)');

    -- Count events before collection
    SELECT @EventsBefore = COUNT(*) FROM dbo.DeadlockEvents;

    -- Run the actual collection
    BEGIN TRY
        -- Collect for all servers or specific server
        IF @ServerID IS NULL
        BEGIN
            DECLARE @CurrentServerID INT;
            DECLARE server_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT ServerID FROM dbo.Servers WHERE IsActive = 1;

            OPEN server_cursor;
            FETCH NEXT FROM server_cursor INTO @CurrentServerID;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                BEGIN TRY
                    EXEC dbo.usp_CollectDeadlockEvents @ServerID = @CurrentServerID;
                END TRY
                BEGIN CATCH
                    PRINT CONCAT('  Warning: Error collecting from ServerID ', @CurrentServerID, ': ', ERROR_MESSAGE());
                END CATCH;

                FETCH NEXT FROM server_cursor INTO @CurrentServerID;
            END

            CLOSE server_cursor;
            DEALLOCATE server_cursor;
        END
        ELSE
        BEGIN
            EXEC dbo.usp_CollectDeadlockEvents @ServerID = @ServerID;
        END
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Error in deadlock collection: ', ERROR_MESSAGE());
    END CATCH;

    -- Count events after collection
    SELECT @EventsAfter = COUNT(*) FROM dbo.DeadlockEvents;
    SET @EventsFound = @EventsAfter - @EventsBefore;

    -- Update adaptive state
    EXEC dbo.usp_UpdateAdaptiveCollectionState
        @CollectionType = 'Deadlock',
        @EventsFound = @EventsFound;

    IF @EventsFound > 0
        PRINT CONCAT('  Detected ', @EventsFound, ' new deadlock event(s)');
    ELSE
        PRINT '  No new deadlock events detected';
END;
GO

PRINT 'Created procedure: dbo.usp_CollectDeadlockEvents_Adaptive';

-- =====================================================
-- Procedure: usp_CollectBlockingEvents_Adaptive
-- Wrapper that uses adaptive scheduling for blocking
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectBlockingEvents_Adaptive', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectBlockingEvents_Adaptive;
GO

CREATE PROCEDURE dbo.usp_CollectBlockingEvents_Adaptive
    @ServerID INT = NULL,
    @ForceRun BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ShouldRun BIT;
    DECLARE @CurrentInterval INT;
    DECLARE @MinutesSinceLastRun INT;
    DECLARE @EventsBefore BIGINT;
    DECLARE @EventsAfter BIGINT;
    DECLARE @EventsFound INT;

    -- Check if it's time to run
    EXEC dbo.usp_ShouldRunAdaptiveCollection
        @CollectionType = 'Blocking',
        @ShouldRun = @ShouldRun OUTPUT,
        @CurrentInterval = @CurrentInterval OUTPUT,
        @MinutesSinceLastRun = @MinutesSinceLastRun OUTPUT;

    IF @ShouldRun = 0 AND @ForceRun = 0
    BEGIN
        PRINT CONCAT('Skipping blocking collection - ', @MinutesSinceLastRun, ' minutes since last run, current interval is ', @CurrentInterval, ' minutes');
        RETURN;
    END

    PRINT CONCAT('Running adaptive blocking collection (interval: ', @CurrentInterval, ' min, last run: ', @MinutesSinceLastRun, ' min ago)');

    -- Check for BlockingEvents table
    IF OBJECT_ID('dbo.BlockingEvents', 'U') IS NULL
    BEGIN
        PRINT '  BlockingEvents table not found - updating state only';
        EXEC dbo.usp_UpdateAdaptiveCollectionState @CollectionType = 'Blocking', @EventsFound = 0;
        RETURN;
    END

    -- Count events before collection
    SELECT @EventsBefore = COUNT(*) FROM dbo.BlockingEvents;

    -- Run the actual collection
    BEGIN TRY
        IF @ServerID IS NULL
        BEGIN
            DECLARE @CurrentServerID INT;
            DECLARE server_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT ServerID FROM dbo.Servers WHERE IsActive = 1;

            OPEN server_cursor;
            FETCH NEXT FROM server_cursor INTO @CurrentServerID;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                BEGIN TRY
                    EXEC dbo.usp_CollectBlockingEvents @ServerID = @CurrentServerID;
                END TRY
                BEGIN CATCH
                    PRINT CONCAT('  Warning: Error collecting from ServerID ', @CurrentServerID, ': ', ERROR_MESSAGE());
                END CATCH;

                FETCH NEXT FROM server_cursor INTO @CurrentServerID;
            END

            CLOSE server_cursor;
            DEALLOCATE server_cursor;
        END
        ELSE
        BEGIN
            EXEC dbo.usp_CollectBlockingEvents @ServerID = @ServerID;
        END
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Error in blocking collection: ', ERROR_MESSAGE());
    END CATCH;

    -- Count events after collection
    SELECT @EventsAfter = COUNT(*) FROM dbo.BlockingEvents;
    SET @EventsFound = @EventsAfter - @EventsBefore;

    -- Update adaptive state
    EXEC dbo.usp_UpdateAdaptiveCollectionState
        @CollectionType = 'Blocking',
        @EventsFound = @EventsFound;

    IF @EventsFound > 0
        PRINT CONCAT('  Detected ', @EventsFound, ' new blocking event(s)');
    ELSE
        PRINT '  No new blocking events detected';
END;
GO

PRINT 'Created procedure: dbo.usp_CollectBlockingEvents_Adaptive';

-- =====================================================
-- Procedure: usp_GetAdaptiveCollectionStatus
-- Returns current status of all adaptive collections
-- =====================================================

IF OBJECT_ID('dbo.usp_GetAdaptiveCollectionStatus', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetAdaptiveCollectionStatus;
GO

CREATE PROCEDURE dbo.usp_GetAdaptiveCollectionStatus
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        CollectionType,
        CurrentIntervalMinutes AS CurrentInterval,
        MinIntervalMinutes AS MinInterval,
        MaxIntervalMinutes AS MaxInterval,
        DATEDIFF(MINUTE, LastCollectionTime, GETUTCDATE()) AS MinutesSinceLastRun,
        CASE
            WHEN DATEDIFF(MINUTE, LastCollectionTime, GETUTCDATE()) >= CurrentIntervalMinutes
            THEN 'Ready to run'
            ELSE CONCAT('Next run in ', CurrentIntervalMinutes - DATEDIFF(MINUTE, LastCollectionTime, GETUTCDATE()), ' min')
        END AS Status,
        ConsecutiveEmptyCollections AS EmptyRuns,
        CASE
            WHEN LastEventDetectedTime IS NULL THEN 'Never'
            ELSE CONCAT(DATEDIFF(HOUR, LastEventDetectedTime, GETUTCDATE()), ' hours ago')
        END AS LastEventDetected,
        TotalCollections,
        TotalEventsDetected,
        CASE
            WHEN TotalCollections > 0
            THEN CAST(CAST(TotalEventsDetected AS FLOAT) / TotalCollections AS DECIMAL(10,2))
            ELSE 0
        END AS AvgEventsPerRun
    FROM dbo.AdaptiveCollectionState
    ORDER BY CollectionType;
END;
GO

PRINT 'Created procedure: dbo.usp_GetAdaptiveCollectionStatus';

-- =====================================================
-- Create SQL Agent Job for Adaptive Deadlock Collection
-- Runs every 5 minutes but actual collection is throttled
-- =====================================================

PRINT '';
PRINT 'Creating SQL Agent job for adaptive deadlock collection...';

-- Check if we can create jobs (SQL Agent must be running)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SQLMonitor_CollectDeadlocks_Adaptive')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'SQLMonitor_CollectDeadlocks_Adaptive';
    PRINT '  Deleted existing job: SQLMonitor_CollectDeadlocks_Adaptive';
END

BEGIN TRY
    DECLARE @JobID UNIQUEIDENTIFIER;

    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQLMonitor_CollectDeadlocks_Adaptive',
        @enabled = 1,
        @description = N'Adaptive deadlock collection with exponential backoff. Runs frequently but actual collection is throttled based on event occurrence.',
        @category_name = N'Database Maintenance',
        @owner_login_name = N'sv',
        @job_id = @JobID OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobID,
        @step_name = N'Collect Deadlocks (Adaptive)',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC dbo.usp_CollectDeadlockEvents_Adaptive;',
        @database_name = N'MonitoringDB',
        @on_success_action = 1,
        @on_fail_action = 2;

    -- Run every 5 minutes (the procedure handles actual throttling)
    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobID,
        @name = N'Every 5 minutes',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 5,
        @active_start_time = 0;

    EXEC msdb.dbo.sp_add_jobserver
        @job_id = @JobID,
        @server_name = N'(local)';

    PRINT '  Created job: SQLMonitor_CollectDeadlocks_Adaptive';
END TRY
BEGIN CATCH
    PRINT '  Note: Could not create SQL Agent job - ' + ERROR_MESSAGE();
    PRINT '  You can manually schedule: EXEC dbo.usp_CollectDeadlockEvents_Adaptive';
END CATCH;
GO

-- =====================================================
-- Create SQL Agent Job for Adaptive Blocking Collection
-- =====================================================

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SQLMonitor_CollectBlocking_Adaptive')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'SQLMonitor_CollectBlocking_Adaptive';
    PRINT '  Deleted existing job: SQLMonitor_CollectBlocking_Adaptive';
END

BEGIN TRY
    DECLARE @JobID2 UNIQUEIDENTIFIER;

    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQLMonitor_CollectBlocking_Adaptive',
        @enabled = 1,
        @description = N'Adaptive blocking collection with exponential backoff. Runs frequently but actual collection is throttled based on event occurrence.',
        @category_name = N'Database Maintenance',
        @owner_login_name = N'sv',
        @job_id = @JobID2 OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobID2,
        @step_name = N'Collect Blocking (Adaptive)',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC dbo.usp_CollectBlockingEvents_Adaptive;',
        @database_name = N'MonitoringDB',
        @on_success_action = 1,
        @on_fail_action = 2;

    -- Run every 1 minute (blocking is more time-sensitive)
    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobID2,
        @name = N'Every 1 minute',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 1,
        @active_start_time = 0;

    EXEC msdb.dbo.sp_add_jobserver
        @job_id = @JobID2,
        @server_name = N'(local)';

    PRINT '  Created job: SQLMonitor_CollectBlocking_Adaptive';
END TRY
BEGIN CATCH
    PRINT '  Note: Could not create SQL Agent job - ' + ERROR_MESSAGE();
    PRINT '  You can manually schedule: EXEC dbo.usp_CollectBlockingEvents_Adaptive';
END CATCH;
GO

PRINT '';
PRINT '========================================';
PRINT 'Adaptive Collection System Complete';
PRINT '========================================';
PRINT '';
PRINT 'Behavior:';
PRINT '  DEADLOCK collection:';
PRINT '    - When deadlocks detected: 15 min interval (minimum)';
PRINT '    - No deadlocks for ~1 hour: backs off by 15 min';
PRINT '    - Maximum interval: 2 hours';
PRINT '';
PRINT '  BLOCKING collection:';
PRINT '    - When blocking detected: 5 min interval (minimum)';
PRINT '    - No blocking for ~1 hour: backs off by 5 min';
PRINT '    - Maximum interval: 30 min';
PRINT '';
PRINT '  MISSING INDEXES collection:';
PRINT '    - When new recommendations: 30 min interval (minimum)';
PRINT '    - No new indexes for ~1 hour: backs off by 30 min';
PRINT '    - Maximum interval: 4 hours';
PRINT '';
PRINT '  UNUSED INDEXES collection:';
PRINT '    - When new unused indexes: 1 hour interval (minimum)';
PRINT '    - No new indexes for ~1 hour: backs off by 1 hour';
PRINT '    - Maximum interval: 6 hours';
PRINT '';
PRINT 'Check status: EXEC dbo.usp_GetAdaptiveCollectionStatus';
PRINT '';
GO

-- =====================================================
-- Procedure: usp_CollectMissingIndexes_Adaptive
-- Wrapper that uses adaptive scheduling for missing indexes
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectMissingIndexes_Adaptive', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectMissingIndexes_Adaptive;
GO

CREATE PROCEDURE dbo.usp_CollectMissingIndexes_Adaptive
    @ServerID INT = NULL,
    @ForceRun BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ShouldRun BIT;
    DECLARE @CurrentInterval INT;
    DECLARE @MinutesSinceLastRun INT;
    DECLARE @RecommendationsBefore BIGINT;
    DECLARE @RecommendationsAfter BIGINT;
    DECLARE @NewRecommendations INT;

    -- Check if it's time to run
    EXEC dbo.usp_ShouldRunAdaptiveCollection
        @CollectionType = 'MissingIndexes',
        @ShouldRun = @ShouldRun OUTPUT,
        @CurrentInterval = @CurrentInterval OUTPUT,
        @MinutesSinceLastRun = @MinutesSinceLastRun OUTPUT;

    IF @ShouldRun = 0 AND @ForceRun = 0
    BEGIN
        PRINT CONCAT('Skipping missing index collection - ', @MinutesSinceLastRun, ' minutes since last run, current interval is ', @CurrentInterval, ' minutes');
        RETURN;
    END

    PRINT CONCAT('Running adaptive missing index collection (interval: ', @CurrentInterval, ' min, last run: ', @MinutesSinceLastRun, ' min ago)');

    -- Check for MissingIndexes table
    IF OBJECT_ID('dbo.MissingIndexes', 'U') IS NULL
    BEGIN
        PRINT '  MissingIndexes table not found - updating state only';
        EXEC dbo.usp_UpdateAdaptiveCollectionState @CollectionType = 'MissingIndexes', @EventsFound = 0;
        RETURN;
    END

    -- Count recommendations before collection
    SELECT @RecommendationsBefore = COUNT(*) FROM dbo.MissingIndexes;

    -- Run the actual collection
    BEGIN TRY
        IF @ServerID IS NULL
        BEGIN
            DECLARE @CurrentServerID INT;
            DECLARE server_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT ServerID FROM dbo.Servers WHERE IsActive = 1;

            OPEN server_cursor;
            FETCH NEXT FROM server_cursor INTO @CurrentServerID;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                BEGIN TRY
                    EXEC dbo.usp_CollectMissingIndexes @ServerID = @CurrentServerID;
                END TRY
                BEGIN CATCH
                    PRINT CONCAT('  Warning: Error collecting from ServerID ', @CurrentServerID, ': ', ERROR_MESSAGE());
                END CATCH;

                FETCH NEXT FROM server_cursor INTO @CurrentServerID;
            END

            CLOSE server_cursor;
            DEALLOCATE server_cursor;
        END
        ELSE
        BEGIN
            EXEC dbo.usp_CollectMissingIndexes @ServerID = @ServerID;
        END
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Error in missing index collection: ', ERROR_MESSAGE());
    END CATCH;

    -- Count recommendations after collection
    SELECT @RecommendationsAfter = COUNT(*) FROM dbo.MissingIndexes;
    SET @NewRecommendations = @RecommendationsAfter - @RecommendationsBefore;

    -- Update adaptive state
    EXEC dbo.usp_UpdateAdaptiveCollectionState
        @CollectionType = 'MissingIndexes',
        @EventsFound = @NewRecommendations;

    IF @NewRecommendations > 0
        PRINT CONCAT('  Found ', @NewRecommendations, ' new missing index recommendation(s)');
    ELSE
        PRINT '  No new missing index recommendations';
END;
GO

PRINT 'Created procedure: dbo.usp_CollectMissingIndexes_Adaptive';

-- =====================================================
-- Procedure: usp_CollectUnusedIndexes_Adaptive
-- Wrapper that uses adaptive scheduling for unused indexes
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectUnusedIndexes_Adaptive', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectUnusedIndexes_Adaptive;
GO

CREATE PROCEDURE dbo.usp_CollectUnusedIndexes_Adaptive
    @ServerID INT = NULL,
    @ForceRun BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ShouldRun BIT;
    DECLARE @CurrentInterval INT;
    DECLARE @MinutesSinceLastRun INT;
    DECLARE @UnusedBefore BIGINT;
    DECLARE @UnusedAfter BIGINT;
    DECLARE @NewUnused INT;

    -- Check if it's time to run
    EXEC dbo.usp_ShouldRunAdaptiveCollection
        @CollectionType = 'UnusedIndexes',
        @ShouldRun = @ShouldRun OUTPUT,
        @CurrentInterval = @CurrentInterval OUTPUT,
        @MinutesSinceLastRun = @MinutesSinceLastRun OUTPUT;

    IF @ShouldRun = 0 AND @ForceRun = 0
    BEGIN
        PRINT CONCAT('Skipping unused index collection - ', @MinutesSinceLastRun, ' minutes since last run, current interval is ', @CurrentInterval, ' minutes');
        RETURN;
    END

    PRINT CONCAT('Running adaptive unused index collection (interval: ', @CurrentInterval, ' min, last run: ', @MinutesSinceLastRun, ' min ago)');

    -- Check for UnusedIndexes table
    IF OBJECT_ID('dbo.UnusedIndexes', 'U') IS NULL
    BEGIN
        PRINT '  UnusedIndexes table not found - updating state only';
        EXEC dbo.usp_UpdateAdaptiveCollectionState @CollectionType = 'UnusedIndexes', @EventsFound = 0;
        RETURN;
    END

    -- Count unused indexes before collection
    SELECT @UnusedBefore = COUNT(*) FROM dbo.UnusedIndexes;

    -- Run the actual collection
    BEGIN TRY
        IF @ServerID IS NULL
        BEGIN
            DECLARE @CurrentServerID INT;
            DECLARE server_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT ServerID FROM dbo.Servers WHERE IsActive = 1;

            OPEN server_cursor;
            FETCH NEXT FROM server_cursor INTO @CurrentServerID;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                BEGIN TRY
                    EXEC dbo.usp_CollectUnusedIndexes @ServerID = @CurrentServerID;
                END TRY
                BEGIN CATCH
                    PRINT CONCAT('  Warning: Error collecting from ServerID ', @CurrentServerID, ': ', ERROR_MESSAGE());
                END CATCH;

                FETCH NEXT FROM server_cursor INTO @CurrentServerID;
            END

            CLOSE server_cursor;
            DEALLOCATE server_cursor;
        END
        ELSE
        BEGIN
            EXEC dbo.usp_CollectUnusedIndexes @ServerID = @ServerID;
        END
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Error in unused index collection: ', ERROR_MESSAGE());
    END CATCH;

    -- Count unused indexes after collection
    SELECT @UnusedAfter = COUNT(*) FROM dbo.UnusedIndexes;
    SET @NewUnused = @UnusedAfter - @UnusedBefore;

    -- Update adaptive state
    EXEC dbo.usp_UpdateAdaptiveCollectionState
        @CollectionType = 'UnusedIndexes',
        @EventsFound = @NewUnused;

    IF @NewUnused > 0
        PRINT CONCAT('  Found ', @NewUnused, ' new unused index(es)');
    ELSE
        PRINT '  No new unused indexes detected';
END;
GO

PRINT 'Created procedure: dbo.usp_CollectUnusedIndexes_Adaptive';

-- =====================================================
-- Create SQL Agent Jobs for Index Analysis
-- =====================================================

PRINT '';
PRINT 'Creating SQL Agent jobs for adaptive index analysis...';

-- Missing Indexes Job
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SQLMonitor_CollectMissingIndexes_Adaptive')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'SQLMonitor_CollectMissingIndexes_Adaptive';
    PRINT '  Deleted existing job: SQLMonitor_CollectMissingIndexes_Adaptive';
END

BEGIN TRY
    DECLARE @JobID3 UNIQUEIDENTIFIER;

    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQLMonitor_CollectMissingIndexes_Adaptive',
        @enabled = 1,
        @description = N'Adaptive missing index collection. Backs off when no new recommendations found.',
        @category_name = N'Database Maintenance',
        @owner_login_name = N'sv',
        @job_id = @JobID3 OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobID3,
        @step_name = N'Collect Missing Indexes (Adaptive)',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC dbo.usp_CollectMissingIndexes_Adaptive;',
        @database_name = N'MonitoringDB',
        @on_success_action = 1,
        @on_fail_action = 2;

    -- Run every 15 minutes (procedure handles throttling)
    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobID3,
        @name = N'Every 15 minutes',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 15,
        @active_start_time = 0;

    EXEC msdb.dbo.sp_add_jobserver
        @job_id = @JobID3,
        @server_name = N'(local)';

    PRINT '  Created job: SQLMonitor_CollectMissingIndexes_Adaptive';
END TRY
BEGIN CATCH
    PRINT '  Note: Could not create SQL Agent job - ' + ERROR_MESSAGE();
END CATCH;
GO

-- Unused Indexes Job
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SQLMonitor_CollectUnusedIndexes_Adaptive')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'SQLMonitor_CollectUnusedIndexes_Adaptive';
    PRINT '  Deleted existing job: SQLMonitor_CollectUnusedIndexes_Adaptive';
END

BEGIN TRY
    DECLARE @JobID4 UNIQUEIDENTIFIER;

    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQLMonitor_CollectUnusedIndexes_Adaptive',
        @enabled = 1,
        @description = N'Adaptive unused index collection. Backs off when no new unused indexes found.',
        @category_name = N'Database Maintenance',
        @owner_login_name = N'sv',
        @job_id = @JobID4 OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobID4,
        @step_name = N'Collect Unused Indexes (Adaptive)',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC dbo.usp_CollectUnusedIndexes_Adaptive;',
        @database_name = N'MonitoringDB',
        @on_success_action = 1,
        @on_fail_action = 2;

    -- Run every 30 minutes (procedure handles throttling)
    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobID4,
        @name = N'Every 30 minutes',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 30,
        @active_start_time = 0;

    EXEC msdb.dbo.sp_add_jobserver
        @job_id = @JobID4,
        @server_name = N'(local)';

    PRINT '  Created job: SQLMonitor_CollectUnusedIndexes_Adaptive';
END TRY
BEGIN CATCH
    PRINT '  Note: Could not create SQL Agent job - ' + ERROR_MESSAGE();
END CATCH;
GO

PRINT '';
PRINT 'All adaptive collection jobs created successfully.';
PRINT '';
