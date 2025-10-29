-- =============================================
-- DBCC Check System
-- Purpose: Run DBCC commands, capture output, catalog errors/warnings
-- =============================================

USE MonitoringDB;
GO

-- =============================================
-- Table: DBCCCheckResults
-- Stores DBCC command results with error/warning details
-- =============================================
IF OBJECT_ID('dbo.DBCCCheckResults', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DBCCCheckResults (
        CheckID INT IDENTITY(1,1) PRIMARY KEY,
        ServerID INT NOT NULL,
        DatabaseName NVARCHAR(128) NOT NULL,
        CheckType NVARCHAR(50) NOT NULL, -- CHECKDB, CHECKTABLE, CHECKCATALOG, CHECKALLOC
        ObjectName NVARCHAR(256) NULL, -- For CHECKTABLE
        CheckStartTime DATETIME2 NOT NULL,
        CheckEndTime DATETIME2 NULL,
        DurationSeconds INT NULL,
        Severity NVARCHAR(20) NOT NULL, -- CRITICAL, WARNING, INFO, SUCCESS
        MessageType NVARCHAR(50) NULL, -- ERROR, WARNING, INFORMATIONAL, REPAIR_SUGGESTION
        ErrorNumber INT NULL,
        RepairLevel NVARCHAR(50) NULL, -- REPAIR_ALLOW_DATA_LOSS, REPAIR_REBUILD, REPAIR_FAST
        MessageText NVARCHAR(MAX) NULL,
        RawOutput NVARCHAR(MAX) NULL,
        CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
        CONSTRAINT FK_DBCCCheckResults_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    );

    CREATE NONCLUSTERED INDEX IX_DBCCCheckResults_Server_Database
    ON dbo.DBCCCheckResults(ServerID, DatabaseName, CheckStartTime DESC);

    CREATE NONCLUSTERED INDEX IX_DBCCCheckResults_Severity
    ON dbo.DBCCCheckResults(Severity, CheckStartTime DESC)
    WHERE Severity IN ('CRITICAL', 'WARNING');

    PRINT 'Table DBCCCheckResults created successfully';
END
ELSE
BEGIN
    PRINT 'Table DBCCCheckResults already exists';
END
GO

-- =============================================
-- Table: DBCCCheckSchedule
-- Defines which DBCC checks to run and when
-- =============================================
IF OBJECT_ID('dbo.DBCCCheckSchedule', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DBCCCheckSchedule (
        ScheduleID INT IDENTITY(1,1) PRIMARY KEY,
        ServerID INT NOT NULL,
        DatabaseName NVARCHAR(128) NOT NULL, -- 'ALL' for all user databases
        CheckType NVARCHAR(50) NOT NULL, -- CHECKDB, CHECKCATALOG, CHECKALLOC
        FrequencyDays INT NOT NULL DEFAULT 7, -- Run every N days
        LastRunDate DATETIME2 NULL,
        NextRunDate DATETIME2 NULL,
        IsEnabled BIT NOT NULL DEFAULT 1,
        NotifyOnError BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
        CONSTRAINT FK_DBCCCheckSchedule_Server FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    );

    CREATE NONCLUSTERED INDEX IX_DBCCCheckSchedule_NextRun
    ON dbo.DBCCCheckSchedule(NextRunDate, IsEnabled)
    WHERE IsEnabled = 1;

    PRINT 'Table DBCCCheckSchedule created successfully';
END
ELSE
BEGIN
    PRINT 'Table DBCCCheckSchedule already exists';
END
GO

-- =============================================
-- Procedure: usp_RunDBCCCheck
-- Runs a single DBCC check and captures output
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_RunDBCCCheck
    @ServerID INT,
    @DatabaseName NVARCHAR(128),
    @CheckType NVARCHAR(50), -- CHECKDB, CHECKCATALOG, CHECKALLOC, CHECKTABLE
    @ObjectName NVARCHAR(256) = NULL, -- For CHECKTABLE
    @WithPhysicalOnly BIT = 0 -- Fast check (no row-level checks)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = GETUTCDATE();
    DECLARE @EndTime DATETIME2;
    DECLARE @DurationSeconds INT;
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ErrorCount INT = 0;
    DECLARE @WarningCount INT = 0;
    DECLARE @Severity NVARCHAR(20);
    DECLARE @MessageText NVARCHAR(MAX);

    -- Create temp table to capture DBCC output
    CREATE TABLE #DBCCOutput (
        ID INT IDENTITY(1,1),
        MessageText NVARCHAR(MAX)
    );

    BEGIN TRY
        -- Build DBCC command
        IF @CheckType = 'CHECKDB'
        BEGIN
            SET @SQL = 'DBCC CHECKDB([' + @DatabaseName + '])';
            IF @WithPhysicalOnly = 1
                SET @SQL = @SQL + ' WITH PHYSICAL_ONLY, NO_INFOMSGS';
            ELSE
                SET @SQL = @SQL + ' WITH NO_INFOMSGS';
        END
        ELSE IF @CheckType = 'CHECKCATALOG'
        BEGIN
            SET @SQL = 'DBCC CHECKCATALOG([' + @DatabaseName + ']) WITH NO_INFOMSGS';
        END
        ELSE IF @CheckType = 'CHECKALLOC'
        BEGIN
            SET @SQL = 'DBCC CHECKALLOC([' + @DatabaseName + ']) WITH NO_INFOMSGS';
        END
        ELSE IF @CheckType = 'CHECKTABLE' AND @ObjectName IS NOT NULL
        BEGIN
            SET @SQL = 'DBCC CHECKTABLE([' + @DatabaseName + '].[dbo].[' + @ObjectName + ']) WITH NO_INFOMSGS';
        END
        ELSE
        BEGIN
            THROW 50001, 'Invalid CheckType or missing ObjectName for CHECKTABLE', 1;
        END;

        -- Execute DBCC and capture output
        INSERT INTO #DBCCOutput (MessageText)
        EXEC sp_executesql @SQL;

        SET @EndTime = GETUTCDATE();
        SET @DurationSeconds = DATEDIFF(SECOND, @StartTime, @EndTime);

        -- Parse output for errors and warnings
        DECLARE @OutputCursor CURSOR;
        DECLARE @Line NVARCHAR(MAX);

        SET @OutputCursor = CURSOR FOR
        SELECT MessageText FROM #DBCCOutput ORDER BY ID;

        OPEN @OutputCursor;
        FETCH NEXT FROM @OutputCursor INTO @Line;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Check for errors (Msg xxxx patterns)
            IF @Line LIKE '%Msg %[0-9]%'
               OR @Line LIKE '%error%'
               OR @Line LIKE '%corruption%'
               OR @Line LIKE '%damaged%'
            BEGIN
                SET @ErrorCount = @ErrorCount + 1;

                INSERT INTO dbo.DBCCCheckResults (
                    ServerID,
                    DatabaseName,
                    CheckType,
                    ObjectName,
                    CheckStartTime,
                    CheckEndTime,
                    DurationSeconds,
                    Severity,
                    MessageType,
                    MessageText,
                    RawOutput
                )
                VALUES (
                    @ServerID,
                    @DatabaseName,
                    @CheckType,
                    @ObjectName,
                    @StartTime,
                    @EndTime,
                    @DurationSeconds,
                    'CRITICAL',
                    'ERROR',
                    @Line,
                    (SELECT STRING_AGG(MessageText, CHAR(13) + CHAR(10)) FROM #DBCCOutput)
                );
            END
            -- Check for warnings
            ELSE IF @Line LIKE '%warning%'
                    OR @Line LIKE '%REPAIR_%'
                    OR @Line LIKE '%allocation%'
                    OR @Line LIKE '%inconsisten%'
            BEGIN
                SET @WarningCount = @WarningCount + 1;

                DECLARE @RepairLevel NVARCHAR(50) = NULL;
                IF @Line LIKE '%REPAIR_ALLOW_DATA_LOSS%'
                    SET @RepairLevel = 'REPAIR_ALLOW_DATA_LOSS';
                ELSE IF @Line LIKE '%REPAIR_REBUILD%'
                    SET @RepairLevel = 'REPAIR_REBUILD';
                ELSE IF @Line LIKE '%REPAIR_FAST%'
                    SET @RepairLevel = 'REPAIR_FAST';

                INSERT INTO dbo.DBCCCheckResults (
                    ServerID,
                    DatabaseName,
                    CheckType,
                    ObjectName,
                    CheckStartTime,
                    CheckEndTime,
                    DurationSeconds,
                    Severity,
                    MessageType,
                    RepairLevel,
                    MessageText,
                    RawOutput
                )
                VALUES (
                    @ServerID,
                    @DatabaseName,
                    @CheckType,
                    @ObjectName,
                    @StartTime,
                    @EndTime,
                    @DurationSeconds,
                    'WARNING',
                    'WARNING',
                    @RepairLevel,
                    @Line,
                    (SELECT STRING_AGG(MessageText, CHAR(13) + CHAR(10)) FROM #DBCCOutput)
                );
            END

            FETCH NEXT FROM @OutputCursor INTO @Line;
        END

        CLOSE @OutputCursor;
        DEALLOCATE @OutputCursor;

        -- If no errors/warnings, log SUCCESS
        IF @ErrorCount = 0 AND @WarningCount = 0
        BEGIN
            INSERT INTO dbo.DBCCCheckResults (
                ServerID,
                DatabaseName,
                CheckType,
                ObjectName,
                CheckStartTime,
                CheckEndTime,
                DurationSeconds,
                Severity,
                MessageType,
                MessageText,
                RawOutput
            )
            VALUES (
                @ServerID,
                @DatabaseName,
                @CheckType,
                @ObjectName,
                @StartTime,
                @EndTime,
                @DurationSeconds,
                'SUCCESS',
                'INFORMATIONAL',
                'DBCC ' + @CheckType + ' completed with no errors or warnings',
                (SELECT STRING_AGG(MessageText, CHAR(13) + CHAR(10)) FROM #DBCCOutput)
            );
        END

    END TRY
    BEGIN CATCH
        SET @EndTime = GETUTCDATE();
        SET @DurationSeconds = DATEDIFF(SECOND, @StartTime, @EndTime);

        -- Log DBCC failure
        INSERT INTO dbo.DBCCCheckResults (
            ServerID,
            DatabaseName,
            CheckType,
            ObjectName,
            CheckStartTime,
            CheckEndTime,
            DurationSeconds,
            Severity,
            MessageType,
            ErrorNumber,
            MessageText
        )
        VALUES (
            @ServerID,
            @DatabaseName,
            @CheckType,
            @ObjectName,
            @StartTime,
            @EndTime,
            @DurationSeconds,
            'CRITICAL',
            'ERROR',
            ERROR_NUMBER(),
            'DBCC check failed: ' + ERROR_MESSAGE()
        );

        THROW;
    END CATCH

    DROP TABLE #DBCCOutput;
END
GO

-- =============================================
-- Procedure: usp_RunScheduledDBCCChecks
-- Runs all scheduled DBCC checks that are due
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_RunScheduledDBCCChecks
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ScheduleID INT;
    DECLARE @ServerID INT;
    DECLARE @DatabaseName NVARCHAR(128);
    DECLARE @CheckType NVARCHAR(50);
    DECLARE @CurrentDatabase NVARCHAR(128);

    -- Create temp table for databases to check
    CREATE TABLE #DatabasesToCheck (
        ScheduleID INT,
        ServerID INT,
        DatabaseName NVARCHAR(128),
        CheckType NVARCHAR(50)
    );

    -- Get all scheduled checks that are due
    INSERT INTO #DatabasesToCheck (ScheduleID, ServerID, DatabaseName, CheckType)
    SELECT
        ScheduleID,
        ServerID,
        DatabaseName,
        CheckType
    FROM dbo.DBCCCheckSchedule
    WHERE IsEnabled = 1
      AND (NextRunDate IS NULL OR NextRunDate <= GETUTCDATE());

    -- Process each scheduled check
    DECLARE check_cursor CURSOR FOR
    SELECT ScheduleID, ServerID, DatabaseName, CheckType
    FROM #DatabasesToCheck;

    OPEN check_cursor;
    FETCH NEXT FROM check_cursor INTO @ScheduleID, @ServerID, @DatabaseName, @CheckType;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- If DatabaseName is 'ALL', run check on all user databases
            IF @DatabaseName = 'ALL'
            BEGIN
                DECLARE db_cursor CURSOR FOR
                SELECT name
                FROM sys.databases
                WHERE database_id > 4 -- Exclude system databases
                  AND state = 0 -- ONLINE
                  AND name NOT IN ('ReportServer', 'ReportServerTempDB', 'MonitoringDB', 'DBATools');

                OPEN db_cursor;
                FETCH NEXT FROM db_cursor INTO @CurrentDatabase;

                WHILE @@FETCH_STATUS = 0
                BEGIN
                    EXEC dbo.usp_RunDBCCCheck
                        @ServerID = @ServerID,
                        @DatabaseName = @CurrentDatabase,
                        @CheckType = @CheckType,
                        @WithPhysicalOnly = 1; -- Fast check

                    FETCH NEXT FROM db_cursor INTO @CurrentDatabase;
                END

                CLOSE db_cursor;
                DEALLOCATE db_cursor;
            END
            ELSE
            BEGIN
                -- Run check on specific database
                EXEC dbo.usp_RunDBCCCheck
                    @ServerID = @ServerID,
                    @DatabaseName = @DatabaseName,
                    @CheckType = @CheckType,
                    @WithPhysicalOnly = 0; -- Full check
            END

            -- Update schedule
            UPDATE dbo.DBCCCheckSchedule
            SET LastRunDate = GETUTCDATE(),
                NextRunDate = DATEADD(DAY, FrequencyDays, GETUTCDATE())
            WHERE ScheduleID = @ScheduleID;

        END TRY
        BEGIN CATCH
            -- Log error but continue with next check
            INSERT INTO dbo.ErrorLog (
                ProcedureName,
                ErrorNumber,
                ErrorMessage,
                ErrorLine,
                ErrorSeverity,
                ErrorState,
                Parameters,
                ErrorTime
            )
            VALUES (
                'usp_RunScheduledDBCCChecks',
                ERROR_NUMBER(),
                ERROR_MESSAGE(),
                ERROR_LINE(),
                ERROR_SEVERITY(),
                ERROR_STATE(),
                CONCAT('ScheduleID=', @ScheduleID, ', Database=', @DatabaseName),
                GETUTCDATE()
            );
        END CATCH

        FETCH NEXT FROM check_cursor INTO @ScheduleID, @ServerID, @DatabaseName, @CheckType;
    END

    CLOSE check_cursor;
    DEALLOCATE check_cursor;

    DROP TABLE #DatabasesToCheck;
END
GO

-- =============================================
-- Procedure: usp_GetDBCCCheckSummary
-- Returns summary of DBCC check results
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetDBCCCheckSummary
    @ServerID INT = NULL,
    @DaysBack INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.ServerName,
        dcr.DatabaseName,
        dcr.CheckType,
        dcr.Severity,
        COUNT(*) AS IssueCount,
        MAX(dcr.CheckStartTime) AS LastCheckTime,
        MAX(dcr.DurationSeconds) AS MaxDurationSeconds,
        AVG(dcr.DurationSeconds) AS AvgDurationSeconds,
        STRING_AGG(CAST(dcr.MessageText AS NVARCHAR(MAX)), '; ') AS RecentMessages
    FROM dbo.DBCCCheckResults dcr
    INNER JOIN dbo.Servers s ON dcr.ServerID = s.ServerID
    WHERE (@ServerID IS NULL OR dcr.ServerID = @ServerID)
      AND dcr.CheckStartTime >= DATEADD(DAY, -@DaysBack, GETUTCDATE())
    GROUP BY
        s.ServerName,
        dcr.DatabaseName,
        dcr.CheckType,
        dcr.Severity
    ORDER BY
        CASE dcr.Severity
            WHEN 'CRITICAL' THEN 1
            WHEN 'WARNING' THEN 2
            WHEN 'INFO' THEN 3
            WHEN 'SUCCESS' THEN 4
        END,
        dcr.CheckStartTime DESC;
END
GO

-- =============================================
-- Initialize Default DBCC Check Schedules
-- =============================================

-- Get local server ID
DECLARE @LocalServerID INT = (SELECT TOP 1 ServerID FROM dbo.Servers WHERE ServerName = @@SERVERNAME);

IF @LocalServerID IS NOT NULL
BEGIN
    -- Weekly CHECKDB for all databases
    IF NOT EXISTS (SELECT 1 FROM dbo.DBCCCheckSchedule WHERE ServerID = @LocalServerID AND CheckType = 'CHECKDB')
    BEGIN
        INSERT INTO dbo.DBCCCheckSchedule (ServerID, DatabaseName, CheckType, FrequencyDays, NextRunDate)
        VALUES (@LocalServerID, 'ALL', 'CHECKDB', 7, GETUTCDATE());

        PRINT 'Default DBCC CHECKDB schedule created';
    END

    -- Weekly CHECKCATALOG for all databases
    IF NOT EXISTS (SELECT 1 FROM dbo.DBCCCheckSchedule WHERE ServerID = @LocalServerID AND CheckType = 'CHECKCATALOG')
    BEGIN
        INSERT INTO dbo.DBCCCheckSchedule (ServerID, DatabaseName, CheckType, FrequencyDays, NextRunDate)
        VALUES (@LocalServerID, 'ALL', 'CHECKCATALOG', 7, DATEADD(DAY, 1, GETUTCDATE()));

        PRINT 'Default DBCC CHECKCATALOG schedule created';
    END
END
GO

PRINT 'DBCC Check System created successfully';
PRINT 'Run EXEC dbo.usp_RunScheduledDBCCChecks to execute scheduled checks';
GO
