USE [DBATools]
GO

-- =============================================
-- Enhanced Monitoring Tables
-- Adds 20 components (excluding alerting infrastructure)
-- =============================================

-- =============================================
-- P0 CRITICAL PRIORITY
-- =============================================

-- P0.1: Query Performance Baseline
IF OBJECT_ID('dbo.PerfSnapshotQueryStats', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotQueryStats
    (
        PerfSnapshotQueryStatsID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        QueryHash                BINARY(8) NULL,
        QueryPlanHash            BINARY(8) NULL,
        DatabaseID               INT NULL,
        DatabaseName             SYSNAME NULL,
        ObjectID                 INT NULL,
        ObjectName               NVARCHAR(512) NULL,
        SqlText                  NVARCHAR(MAX) NULL,
        ExecutionCount           BIGINT NULL,
        TotalCpuMs               BIGINT NULL,
        AvgCpuMs                 DECIMAL(18,4) NULL,
        TotalLogicalReads        BIGINT NULL,
        AvgLogicalReads          DECIMAL(18,4) NULL,
        TotalPhysicalReads       BIGINT NULL,
        AvgPhysicalReads         DECIMAL(18,4) NULL,
        TotalElapsedMs           BIGINT NULL,
        AvgElapsedMs             DECIMAL(18,4) NULL,
        TotalWorkerTimeMs        BIGINT NULL,
        AvgWorkerTimeMs          DECIMAL(18,4) NULL,
        CreationTime             DATETIME2(3) NULL,
        LastExecutionTime        DATETIME2(3) NULL,
        PlanHandle               VARBINARY(64) NULL,
        CONSTRAINT FK_PerfSnapshotQueryStats_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotQueryStats_RunID
        ON dbo.PerfSnapshotQueryStats(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotQueryStats_QueryHash
        ON dbo.PerfSnapshotQueryStats(QueryHash) INCLUDE (PerfSnapshotRunID, AvgCpuMs, AvgLogicalReads)
END
GO

-- P0.2: I/O Performance Baseline
IF OBJECT_ID('dbo.PerfSnapshotIOStats', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotIOStats
    (
        PerfSnapshotIOStatsID    BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        DatabaseID               INT NOT NULL,
        DatabaseName             SYSNAME NOT NULL,
        FileID                   INT NOT NULL,
        FileType                 NVARCHAR(10) NULL, -- ROWS or LOG
        PhysicalName             NVARCHAR(520) NULL,
        NumReads                 BIGINT NULL,
        BytesRead                BIGINT NULL,
        IoStallReadMs            BIGINT NULL,
        NumWrites                BIGINT NULL,
        BytesWritten             BIGINT NULL,
        IoStallWriteMs           BIGINT NULL,
        IoStallMs                BIGINT NULL,
        SizeOnDiskMB             DECIMAL(18,2) NULL,
        AvgReadLatencyMs         DECIMAL(18,4) NULL,
        AvgWriteLatencyMs        DECIMAL(18,4) NULL,
        CONSTRAINT FK_PerfSnapshotIOStats_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotIOStats_RunID
        ON dbo.PerfSnapshotIOStats(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotIOStats_DatabaseID
        ON dbo.PerfSnapshotIOStats(DatabaseID, PerfSnapshotRunID)
END
GO

-- P0.3: Memory Utilization Baseline
IF OBJECT_ID('dbo.PerfSnapshotMemory', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotMemory
    (
        PerfSnapshotMemoryID     BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        PageLifeExpectancy       BIGINT NULL,          -- Seconds
        BufferCacheHitRatio      DECIMAL(9,4) NULL,    -- Percentage
        TotalServerMemoryMB      BIGINT NULL,
        TargetServerMemoryMB     BIGINT NULL,
        BufferPoolSizeMB         BIGINT NULL,
        FreeMemoryMB             BIGINT NULL,
        MemoryGrantsPending      INT NULL,
        MemoryGrantsOutstanding  INT NULL,
        StealCount               BIGINT NULL,          -- Memory stolen from buffer pool
        CONSTRAINT FK_PerfSnapshotMemory_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotMemory_RunID
        ON dbo.PerfSnapshotMemory(PerfSnapshotRunID)
END
GO

IF OBJECT_ID('dbo.PerfSnapshotMemoryClerks', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotMemoryClerks
    (
        PerfSnapshotMemoryClerkID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID         BIGINT NOT NULL,
        ClerkType                 NVARCHAR(120) NOT NULL,
        MemoryNodeId              INT NULL,
        SinglePagesMB             DECIMAL(18,2) NULL,
        MultiPagesMB              DECIMAL(18,2) NULL,
        TotalMemoryMB             DECIMAL(18,2) NULL,
        CONSTRAINT FK_PerfSnapshotMemoryClerks_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotMemoryClerks_RunID
        ON dbo.PerfSnapshotMemoryClerks(PerfSnapshotRunID)
END
GO

-- P0.4: Backup Validation
IF OBJECT_ID('dbo.PerfSnapshotBackupHistory', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotBackupHistory
    (
        PerfSnapshotBackupID     BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        DatabaseID               INT NOT NULL,
        DatabaseName             SYSNAME NOT NULL,
        RecoveryModel            NVARCHAR(60) NULL,
        LastFullBackupDate       DATETIME2(3) NULL,
        LastDiffBackupDate       DATETIME2(3) NULL,
        LastLogBackupDate        DATETIME2(3) NULL,
        HoursSinceFullBackup     INT NULL,
        HoursSinceDiffBackup     INT NULL,
        MinutesSinceLogBackup    INT NULL,
        BackupRiskLevel          VARCHAR(20) NULL,  -- 'OK', 'Warning', 'Critical'
        CONSTRAINT FK_PerfSnapshotBackupHistory_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotBackupHistory_RunID
        ON dbo.PerfSnapshotBackupHistory(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotBackupHistory_RiskLevel
        ON dbo.PerfSnapshotBackupHistory(BackupRiskLevel, PerfSnapshotRunID)
END
GO

-- =============================================
-- P1 HIGH PRIORITY
-- =============================================

-- P1.6: Index Usage Statistics
IF OBJECT_ID('dbo.PerfSnapshotIndexUsage', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotIndexUsage
    (
        PerfSnapshotIndexUsageID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        DatabaseID               INT NOT NULL,
        DatabaseName             SYSNAME NOT NULL,
        ObjectID                 INT NOT NULL,
        ObjectName               NVARCHAR(512) NULL,
        IndexID                  INT NOT NULL,
        IndexName                NVARCHAR(256) NULL,
        UserSeeks                BIGINT NULL,
        UserScans                BIGINT NULL,
        UserLookups              BIGINT NULL,
        UserUpdates              BIGINT NULL,
        LastSeek                 DATETIME2(3) NULL,
        LastScan                 DATETIME2(3) NULL,
        LastLookup               DATETIME2(3) NULL,
        LastUpdate               DATETIME2(3) NULL,
        CONSTRAINT FK_PerfSnapshotIndexUsage_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotIndexUsage_RunID
        ON dbo.PerfSnapshotIndexUsage(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotIndexUsage_Database
        ON dbo.PerfSnapshotIndexUsage(DatabaseID, ObjectID, IndexID)
END
GO

-- P1.7: Missing Index Recommendations
IF OBJECT_ID('dbo.PerfSnapshotMissingIndexes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotMissingIndexes
    (
        PerfSnapshotMissingIndexID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID          BIGINT NOT NULL,
        DatabaseID                 INT NOT NULL,
        DatabaseName               SYSNAME NOT NULL,
        ObjectID                   INT NOT NULL,
        ObjectName                 NVARCHAR(512) NULL,
        EqualityColumns            NVARCHAR(4000) NULL,
        InequalityColumns          NVARCHAR(4000) NULL,
        IncludedColumns            NVARCHAR(4000) NULL,
        UserSeeks                  BIGINT NULL,
        UserScans                  BIGINT NULL,
        AvgTotalUserCost           DECIMAL(18,4) NULL,
        AvgUserImpact              DECIMAL(18,4) NULL,
        LastUserSeek               DATETIME2(3) NULL,
        LastUserScan               DATETIME2(3) NULL,
        ImpactScore                DECIMAL(18,4) NULL, -- UserSeeks * AvgTotalUserCost
        CONSTRAINT FK_PerfSnapshotMissingIndexes_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotMissingIndexes_RunID
        ON dbo.PerfSnapshotMissingIndexes(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotMissingIndexes_Impact
        ON dbo.PerfSnapshotMissingIndexes(ImpactScore DESC) INCLUDE (DatabaseName, ObjectName)
END
GO

-- P1.8: Detailed Wait Statistics
IF OBJECT_ID('dbo.PerfSnapshotWaitStats', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotWaitStats
    (
        PerfSnapshotWaitStatsID  BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        WaitType                 NVARCHAR(120) NOT NULL,
        WaitingTasksCount        BIGINT NULL,
        WaitTimeMs               BIGINT NULL,
        SignalWaitTimeMs         BIGINT NULL,
        ResourceWaitTimeMs       BIGINT NULL,  -- Calculated: WaitTimeMs - SignalWaitTimeMs
        MaxWaitTimeMs            BIGINT NULL,
        AvgWaitTimeMs            DECIMAL(18,4) NULL,
        CONSTRAINT FK_PerfSnapshotWaitStats_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotWaitStats_RunID
        ON dbo.PerfSnapshotWaitStats(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotWaitStats_WaitType
        ON dbo.PerfSnapshotWaitStats(WaitType, PerfSnapshotRunID)
END
GO

-- P1.9: TempDB Contention Detection
IF OBJECT_ID('dbo.PerfSnapshotTempDBContention', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotTempDBContention
    (
        PerfSnapshotTempDBID     BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        WaitingTasksCount        INT NULL,
        PageResource             NVARCHAR(256) NULL,  -- e.g., "2:1:1" for PFS
        PageType                 NVARCHAR(20) NULL,   -- PFS, GAM, SGAM
        TotalWaitTimeMs          BIGINT NULL,
        MaxWaitTimeMs            BIGINT NULL,
        CONSTRAINT FK_PerfSnapshotTempDBContention_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotTempDBContention_RunID
        ON dbo.PerfSnapshotTempDBContention(PerfSnapshotRunID)
END
GO

-- P1.10: Query Execution Plan Capture
IF OBJECT_ID('dbo.PerfSnapshotQueryPlans', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotQueryPlans
    (
        PerfSnapshotQueryPlanID  BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        QueryHash                BINARY(8) NULL,
        QueryPlanHash            BINARY(8) NULL,
        DatabaseName             SYSNAME NULL,
        SqlText                  NVARCHAR(MAX) NULL,
        ExecutionCount           BIGINT NULL,
        AvgCpuMs                 DECIMAL(18,4) NULL,
        AvgLogicalReads          DECIMAL(18,4) NULL,
        AvgElapsedMs             DECIMAL(18,4) NULL,
        QueryPlanXML             XML NULL,
        CaptureReason            VARCHAR(50) NULL,  -- 'HighCPU', 'HighReads', 'LongRunning'
        CONSTRAINT FK_PerfSnapshotQueryPlans_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotQueryPlans_RunID
        ON dbo.PerfSnapshotQueryPlans(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotQueryPlans_QueryHash
        ON dbo.PerfSnapshotQueryPlans(QueryHash, PerfSnapshotRunID)
END
GO

-- =============================================
-- P2 MEDIUM PRIORITY
-- =============================================

-- P2.11: Server Configuration Baseline
IF OBJECT_ID('dbo.PerfSnapshotConfig', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotConfig
    (
        PerfSnapshotConfigID     BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        ConfigurationID          INT NOT NULL,
        ConfigName               NVARCHAR(256) NOT NULL,
        ConfigValue              SQL_VARIANT NULL,
        ConfigValueInUse         SQL_VARIANT NULL,
        ConfigMinimum            SQL_VARIANT NULL,
        ConfigMaximum            SQL_VARIANT NULL,
        IsAdvanced               BIT NULL,
        IsDynamic                BIT NULL,
        CONSTRAINT FK_PerfSnapshotConfig_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotConfig_RunID
        ON dbo.PerfSnapshotConfig(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotConfig_Name
        ON dbo.PerfSnapshotConfig(ConfigName, PerfSnapshotRunID)
END
GO

-- P2.12: VLF Count and Transaction Log Health (enhance existing PerfSnapshotDB)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.PerfSnapshotDB') AND name = 'VLFCount')
BEGIN
    ALTER TABLE dbo.PerfSnapshotDB ADD
        VLFCount                INT NULL,
        LogSizeUsedMB           DECIMAL(18,2) NULL,
        LogSpaceUsedPercent     DECIMAL(9,4) NULL,
        ActiveVLFCount          INT NULL
END
GO

-- P2.13: Enhanced Deadlock Analysis
IF OBJECT_ID('dbo.PerfSnapshotDeadlocks', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotDeadlocks
    (
        PerfSnapshotDeadlockID   BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        DeadlockTimestamp        DATETIME2(3) NULL,
        DeadlockXML              XML NULL,
        VictimSessionID          INT NULL,
        VictimDatabaseName       SYSNAME NULL,
        VictimObjectName         NVARCHAR(512) NULL,
        DeadlockGraphHash        VARBINARY(64) NULL,  -- For identifying recurring patterns
        CONSTRAINT FK_PerfSnapshotDeadlocks_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotDeadlocks_RunID
        ON dbo.PerfSnapshotDeadlocks(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotDeadlocks_Timestamp
        ON dbo.PerfSnapshotDeadlocks(DeadlockTimestamp DESC)
END
GO

-- P2.14: Scheduler Health Metrics
IF OBJECT_ID('dbo.PerfSnapshotSchedulers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotSchedulers
    (
        PerfSnapshotSchedulerID  BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        SchedulerID              INT NOT NULL,
        CpuID                    INT NULL,
        Status                   NVARCHAR(60) NULL,
        IsOnline                 BIT NULL,
        CurrentTasksCount        INT NULL,
        RunnableTasksCount       INT NULL,
        CurrentWorkersCount      INT NULL,
        ActiveWorkersCount       INT NULL,
        WorkQueueCount           INT NULL,
        PendingDiskIOCount       INT NULL,
        LoadFactor               INT NULL,
        YieldCount               BIGINT NULL,
        ContextSwitchCount       BIGINT NULL,
        CONSTRAINT FK_PerfSnapshotSchedulers_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotSchedulers_RunID
        ON dbo.PerfSnapshotSchedulers(PerfSnapshotRunID)
END
GO

-- P2.15: Performance Counter Metrics
IF OBJECT_ID('dbo.PerfSnapshotCounters', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotCounters
    (
        PerfSnapshotCounterID    BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        ObjectName               NVARCHAR(128) NOT NULL,
        CounterName              NVARCHAR(128) NOT NULL,
        InstanceName             NVARCHAR(128) NULL,
        CntrValue                BIGINT NULL,
        CntrType                 INT NULL,
        CONSTRAINT FK_PerfSnapshotCounters_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotCounters_RunID
        ON dbo.PerfSnapshotCounters(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotCounters_Name
        ON dbo.PerfSnapshotCounters(CounterName, PerfSnapshotRunID)
END
GO

-- P2.16: Autogrowth Event Tracking
IF OBJECT_ID('dbo.PerfSnapshotAutogrowthEvents', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotAutogrowthEvents
    (
        PerfSnapshotAutogrowthID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        DatabaseID               INT NOT NULL,
        DatabaseName             SYSNAME NOT NULL,
        FileID                   INT NOT NULL,
        FileName                 NVARCHAR(256) NULL,
        FileType                 NVARCHAR(10) NULL,  -- ROWS or LOG
        EventTimestamp           DATETIME2(3) NULL,
        DurationMs               BIGINT NULL,
        GrowthMB                 DECIMAL(18,2) NULL,
        EventsSinceLastSnapshot  INT NULL,
        CONSTRAINT FK_PerfSnapshotAutogrowthEvents_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotAutogrowthEvents_RunID
        ON dbo.PerfSnapshotAutogrowthEvents(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotAutogrowthEvents_Database
        ON dbo.PerfSnapshotAutogrowthEvents(DatabaseID, EventTimestamp DESC)
END
GO

-- P2.17: Database Property Change Tracking (enhance existing PerfSnapshotDB)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.PerfSnapshotDB') AND name = 'IsAutoClose')
BEGIN
    ALTER TABLE dbo.PerfSnapshotDB ADD
        IsAutoClose             BIT NULL,
        IsAutoShrink            BIT NULL,  -- Red flag if enabled
        IsAutoCreateStats       BIT NULL,
        IsAutoUpdateStats       BIT NULL,
        PageVerifyOption        NVARCHAR(60) NULL,
        SnapshotIsolationState  NVARCHAR(60) NULL,
        IsRCAllowed             BIT NULL  -- Read Committed Snapshot Isolation
END
GO

-- =============================================
-- P3 LOW PRIORITY
-- =============================================

-- P3.18: Latch Statistics
IF OBJECT_ID('dbo.PerfSnapshotLatchStats', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotLatchStats
    (
        PerfSnapshotLatchStatsID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        LatchClass               NVARCHAR(120) NOT NULL,
        WaitingRequestsCount     BIGINT NULL,
        WaitTimeMs               BIGINT NULL,
        MaxWaitTimeMs            BIGINT NULL,
        AvgWaitTimeMs            DECIMAL(18,4) NULL,
        CONSTRAINT FK_PerfSnapshotLatchStats_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotLatchStats_RunID
        ON dbo.PerfSnapshotLatchStats(PerfSnapshotRunID)
END
GO

-- P3.19: SQL Agent Job History
IF OBJECT_ID('dbo.PerfSnapshotJobHistory', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotJobHistory
    (
        PerfSnapshotJobID        BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        JobID                    UNIQUEIDENTIFIER NOT NULL,
        JobName                  SYSNAME NOT NULL,
        IsEnabled                BIT NULL,
        LastRunDate              DATETIME2(3) NULL,
        LastRunOutcome           INT NULL,  -- 0=Failed, 1=Succeeded
        LastRunDurationSeconds   INT NULL,
        FailureCountLast24Hours  INT NULL,
        CONSTRAINT FK_PerfSnapshotJobHistory_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotJobHistory_RunID
        ON dbo.PerfSnapshotJobHistory(PerfSnapshotRunID)

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotJobHistory_Outcome
        ON dbo.PerfSnapshotJobHistory(LastRunOutcome, PerfSnapshotRunID)
END
GO

-- P3.21: Spinlock Statistics
IF OBJECT_ID('dbo.PerfSnapshotSpinlockStats', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PerfSnapshotSpinlockStats
    (
        PerfSnapshotSpinlockID   BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PerfSnapshotRunID        BIGINT NOT NULL,
        SpinlockName             NVARCHAR(256) NOT NULL,
        Collisions               BIGINT NULL,
        Spins                    BIGINT NULL,
        SpinsPerCollision        BIGINT NULL,
        SleepTime                BIGINT NULL,
        Backoffs                 BIGINT NULL,
        CONSTRAINT FK_PerfSnapshotSpinlockStats_Run FOREIGN KEY (PerfSnapshotRunID)
            REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
    )

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotSpinlockStats_RunID
        ON dbo.PerfSnapshotSpinlockStats(PerfSnapshotRunID)
END
GO

PRINT 'Enhanced monitoring tables created successfully'
PRINT 'Total tables added: 17 new tables + 2 table enhancements'
GO
