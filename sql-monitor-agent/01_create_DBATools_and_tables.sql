IF DB_ID('DBATools') IS NULL
BEGIN
    CREATE DATABASE [DBATools]
END
GO

USE [DBATools]
GO

IF OBJECT_ID('dbo.LogEntry', 'U') IS NULL
BEGIN
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
    )
END
GO

IF OBJECT_ID('dbo.PerfSnapshotRun', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotRun
    (
        PerfSnapshotRunID       BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        SnapshotUTC             DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        ServerName              SYSNAME      NOT NULL,
        SqlVersion              NVARCHAR(200) NOT NULL,
        CpuSignalWaitPct        DECIMAL(9,4) NULL,
        TopWaitType             NVARCHAR(120) NULL,
        TopWaitMsPerSec         DECIMAL(18,4) NULL,
        SessionsCount           INT          NULL,
        RequestsCount           INT          NULL,
        BlockingSessionCount    INT          NULL,
        DeadlockCountRecent     INT          NULL,
        MemoryGrantWarningCount INT          NULL
    )
END
GO

IF OBJECT_ID('dbo.PerfSnapshotDB', 'U') IS NULL
BEGIN
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
        CONSTRAINT FK_PerfSnapshotDB_Run
            FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )
END
GO

-- Add VLFCount column if it doesn't exist (for existing databases)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.PerfSnapshotDB') AND name = 'VLFCount')
BEGIN
    ALTER TABLE dbo.PerfSnapshotDB ADD VLFCount INT NULL
    PRINT 'Added VLFCount column to PerfSnapshotDB'
END
GO

IF OBJECT_ID('dbo.PerfSnapshotWorkload', 'U') IS NULL
BEGIN
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
    )
END
GO

IF OBJECT_ID('dbo.PerfSnapshotErrorLog', 'U') IS NULL
BEGIN
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
    )
END
GO
