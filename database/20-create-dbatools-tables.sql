-- =====================================================
-- Script: 20-create-dbatools-tables.sql
-- Description: Phase 1.9 - sql-monitor-agent Integration
--              Creates all DBATools tables in MonitoringDB
--              with multi-server support (ServerID column)
-- Author: SQL Server Monitor Project
-- Date: 2025-10-27
-- Phase: 1.9 - Integration
-- TDD Phase: GREEN (Create schema to pass tests)
-- =====================================================

-- This script can be run in either:
--   1. DBATools (single-server mode, backwards compatible)
--   2. MonitoringDB (multi-server mode, enterprise)

-- Note: Database selection should already be done before running this script
-- Example: USE MonitoringDB; or USE DBATools;

PRINT 'Phase 1.9: Creating DBATools-compatible tables with multi-server support';
PRINT '=========================================================================';
GO

-- =====================================================
-- PREREQUISITE: Servers Table (if not exists)
-- =====================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Servers') AND type = 'U')
BEGIN
    PRINT 'Creating dbo.Servers table (multi-server inventory)';

    CREATE TABLE dbo.Servers
    (
        ServerID        INT             IDENTITY(1,1)   NOT NULL,
        ServerName      NVARCHAR(256)                   NOT NULL,
        Environment     NVARCHAR(50)                    NULL,        -- Production, Development, Staging, Test
        IsActive        BIT                             NOT NULL DEFAULT 1,
        CreatedDate     DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),
        ModifiedDate    DATETIME2                       NULL,

        CONSTRAINT PK_Servers PRIMARY KEY CLUSTERED (ServerID),
        CONSTRAINT UQ_Servers_ServerName UNIQUE (ServerName)
    );

    CREATE NONCLUSTERED INDEX IX_Servers_IsActive
    ON dbo.Servers(IsActive)
    INCLUDE (ServerName, Environment);

    PRINT '  ✓ dbo.Servers created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.Servers already exists';
END
GO

-- =====================================================
-- CORE TABLES (from sql-monitor-agent)
-- =====================================================

-- -----------------------------------------------------
-- Table: dbo.LogEntry
-- Purpose: Diagnostic logging for collection procedures
-- -----------------------------------------------------

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.LogEntry') AND type = 'U')
BEGIN
    PRINT 'Creating dbo.LogEntry (diagnostic logging)';

    CREATE TABLE dbo.LogEntry
    (
        LogEntryID          INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        DateTime_Occurred   DATETIME2(3)      NOT NULL DEFAULT SYSUTCDATETIME(),
        ProcedureName       SYSNAME           NULL,
        ProcedureSection    VARCHAR(200)      NULL,
        ErrDescription      VARCHAR(2000)     NULL,
        ErrNumber           BIGINT            NULL,
        ErrSeverity         INT               NULL,
        ErrState            INT               NULL,
        ErrLine             INT               NULL,
        ErrProcedure        SYSNAME           NULL,
        IsError             BIT               NOT NULL DEFAULT(0),
        AdditionalInfo      VARCHAR(4000)     NULL,
        EnteredDate         DATETIME2(3)      NOT NULL DEFAULT SYSUTCDATETIME()
    );

    CREATE NONCLUSTERED INDEX IX_LogEntry_DateTime
    ON dbo.LogEntry(DateTime_Occurred DESC)
    INCLUDE (ProcedureName, IsError);

    PRINT '  ✓ dbo.LogEntry created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.LogEntry already exists';
END
GO

-- -----------------------------------------------------
-- Table: dbo.PerfSnapshotRun
-- Purpose: Server-level performance snapshot (main metrics)
-- Phase 1.9: Added ServerID for multi-server support
-- -----------------------------------------------------

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotRun') AND type = 'U')
BEGIN
    PRINT 'Creating dbo.PerfSnapshotRun (server-level metrics)';

    CREATE TABLE dbo.PerfSnapshotRun
    (
        PerfSnapshotRunID       BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        SnapshotUTC             DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        ServerID                INT          NULL,  -- NEW: Phase 1.9 multi-server support (NULL = local server)
        ServerName              SYSNAME      NOT NULL,
        SqlVersion              NVARCHAR(200) NOT NULL,
        CpuSignalWaitPct        DECIMAL(9,4) NULL,
        TopWaitType             NVARCHAR(120) NULL,
        TopWaitMsPerSec         DECIMAL(18,4) NULL,
        SessionsCount           INT          NULL,
        RequestsCount           INT          NULL,
        BlockingSessionCount    INT          NULL,
        DeadlockCountRecent     INT          NULL,
        MemoryGrantWarningCount INT          NULL,

        CONSTRAINT FK_PerfSnapshotRun_Servers FOREIGN KEY (ServerID)
            REFERENCES dbo.Servers(ServerID)
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotRun_ServerID_Time
    ON dbo.PerfSnapshotRun(ServerID, SnapshotUTC DESC)
    INCLUDE (CpuSignalWaitPct, SessionsCount, BlockingSessionCount);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotRun_Time
    ON dbo.PerfSnapshotRun(SnapshotUTC DESC);

    PRINT '  ✓ dbo.PerfSnapshotRun created with ServerID support';
END
ELSE
BEGIN
    -- Add ServerID column if table exists but column doesn't
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.PerfSnapshotRun') AND name = 'ServerID')
    BEGIN
        PRINT '  → Adding ServerID column to existing PerfSnapshotRun';
        ALTER TABLE dbo.PerfSnapshotRun ADD ServerID INT NULL;

        ALTER TABLE dbo.PerfSnapshotRun ADD CONSTRAINT FK_PerfSnapshotRun_Servers
            FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID);

        CREATE NONCLUSTERED INDEX IX_PerfSnapshotRun_ServerID_Time
        ON dbo.PerfSnapshotRun(ServerID, SnapshotUTC DESC)
        INCLUDE (CpuSignalWaitPct, SessionsCount, BlockingSessionCount);

        PRINT '  ✓ ServerID column added to PerfSnapshotRun';
    END
    ELSE
    BEGIN
        PRINT '  ✓ dbo.PerfSnapshotRun already exists with ServerID';
    END
END
GO

-- -----------------------------------------------------
-- Table: dbo.PerfSnapshotDB
-- Purpose: Database-level statistics
-- Phase 1.9: Added ServerID via FK to PerfSnapshotRun
-- -----------------------------------------------------

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotDB') AND type = 'U')
BEGIN
    PRINT 'Creating dbo.PerfSnapshotDB (database-level stats)';

    CREATE TABLE dbo.PerfSnapshotDB
    (
        PerfSnapshotDBID    BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID   BIGINT               NOT NULL,
        DatabaseID          INT                  NOT NULL,
        DatabaseName        SYSNAME              NOT NULL,
        StateDesc           NVARCHAR(60)         NOT NULL,
        RecoveryModelDesc   NVARCHAR(60)         NOT NULL,
        IsReadOnly          BIT                  NOT NULL,
        TotalDataMB         DECIMAL(18,2)        NULL,
        TotalLogMB          DECIMAL(18,2)        NULL,
        LogReuseWaitDesc    NVARCHAR(120)        NULL,
        FileCount           INT                  NULL,
        CompatLevel         INT                  NULL,
        VLFCount            INT                  NULL,
        LogSizeUsedMB       DECIMAL(18,2)        NULL,
        LogSpaceUsedPercent DECIMAL(9,4)         NULL,
        ActiveVLFCount      INT                  NULL,
        IsAutoClose         BIT                  NULL,
        IsAutoShrink        BIT                  NULL,
        IsAutoCreateStats   BIT                  NULL,
        IsAutoUpdateStats   BIT                  NULL,
        PageVerifyOption    NVARCHAR(60)         NULL,
        SnapshotIsolationState NVARCHAR(60)      NULL,
        IsRCAllowed         BIT                  NULL,

        CONSTRAINT FK_PerfSnapshotDB_Run
            FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotDB_RunID
    ON dbo.PerfSnapshotDB(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotDB_DatabaseID
    ON dbo.PerfSnapshotDB(DatabaseID, PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotDB created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotDB already exists';
END
GO

-- -----------------------------------------------------
-- Table: dbo.PerfSnapshotWorkload
-- Purpose: Active workload (sessions, requests)
-- Phase 1.9: Inherits ServerID from PerfSnapshotRun FK
-- -----------------------------------------------------

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotWorkload') AND type = 'U')
BEGIN
    PRINT 'Creating dbo.PerfSnapshotWorkload (active workload)';

    CREATE TABLE dbo.PerfSnapshotWorkload
    (
        PerfSnapshotWorkloadID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID      BIGINT               NOT NULL,
        SessionID              INT                  NULL,
        LoginName              NVARCHAR(256)        NULL,
        HostName               NVARCHAR(256)        NULL,
        DatabaseName           SYSNAME              NULL,
        Status                 NVARCHAR(60)         NULL,
        Command                NVARCHAR(60)         NULL,
        WaitType               NVARCHAR(120)        NULL,
        WaitTimeMs             BIGINT               NULL,
        BlockingSessionID      INT                  NULL,
        CpuTimeMs              BIGINT               NULL,
        TotalElapsedMs         BIGINT               NULL,
        LogicalReads           BIGINT               NULL,
        Writes                 BIGINT               NULL,
        StatementText          NVARCHAR(MAX)        NULL,
        OBJECT_NAME_Resolved   NVARCHAR(512)        NULL,

        CONSTRAINT FK_PerfSnapshotWorkload_Run
            FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotWorkload_RunID
    ON dbo.PerfSnapshotWorkload(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotWorkload_Blocking
    ON dbo.PerfSnapshotWorkload(BlockingSessionID)
    WHERE BlockingSessionID IS NOT NULL;

    PRINT '  ✓ dbo.PerfSnapshotWorkload created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotWorkload already exists';
END
GO

-- -----------------------------------------------------
-- Table: dbo.PerfSnapshotErrorLog
-- Purpose: SQL Server error log entries
-- Phase 1.9: Inherits ServerID from PerfSnapshotRun FK
-- -----------------------------------------------------

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotErrorLog') AND type = 'U')
BEGIN
    PRINT 'Creating dbo.PerfSnapshotErrorLog (error log entries)';

    CREATE TABLE dbo.PerfSnapshotErrorLog
    (
        PerfSnapshotErrorLogID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID      BIGINT               NOT NULL,
        LogDateUTC             DATETIME2(3)         NULL,
        ProcessInfo            NVARCHAR(50)         NULL,
        LogText                NVARCHAR(4000)       NULL,

        CONSTRAINT FK_PerfSnapshotErrorLog_Run
            FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotErrorLog_RunID
    ON dbo.PerfSnapshotErrorLog(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotErrorLog_LogDate
    ON dbo.PerfSnapshotErrorLog(LogDateUTC DESC);

    PRINT '  ✓ dbo.PerfSnapshotErrorLog created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotErrorLog already exists';
END
GO

PRINT '';
PRINT '=========================================================================';
PRINT 'Phase 1.9: Core tables created successfully';
PRINT '=========================================================================';
PRINT '';
PRINT 'Next: Run 21-create-enhanced-tables.sql for P0-P3 enhanced monitoring';
PRINT '';
GO
