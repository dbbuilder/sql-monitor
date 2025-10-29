-- =====================================================
-- Script: 21-create-enhanced-tables.sql
-- Description: Phase 1.9 - Enhanced Monitoring Tables (P0-P3)
--              Creates all extended monitoring tables from sql-monitor-agent
-- Author: SQL Server Monitor Project
-- Date: 2025-10-27
-- Phase: 1.9 - Integration
-- Priority Levels:
--   P0: Critical (Query, IO, Memory, Backups)
--   P1: High (Indexes, Waits, TempDB, Query Plans)
--   P2: Medium (Config, VLF, Deadlocks, Schedulers, Counters, Autogrowth)
--   P3: Low (Latches, Jobs, Spinlocks)
-- =====================================================

PRINT 'Phase 1.9: Creating Enhanced Monitoring Tables (P0-P3)';
PRINT '=========================================================================';
GO

-- =====================================================
-- P0 CRITICAL PRIORITY
-- =====================================================

PRINT 'Creating P0 (Critical) tables...';
GO

-- P0.1: Query Performance Baseline
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotQueryStats') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotQueryStats (P0.1)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotQueryStats_RunID
        ON dbo.PerfSnapshotQueryStats(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotQueryStats_QueryHash
        ON dbo.PerfSnapshotQueryStats(QueryHash) INCLUDE (PerfSnapshotRunID, AvgCpuMs, AvgLogicalReads);

    PRINT '  ✓ dbo.PerfSnapshotQueryStats created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotQueryStats already exists';
END
GO

-- P0.2: I/O Performance Baseline
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotIOStats') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotIOStats (P0.2)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotIOStats_RunID
        ON dbo.PerfSnapshotIOStats(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotIOStats_DatabaseID
        ON dbo.PerfSnapshotIOStats(DatabaseID, PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotIOStats created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotIOStats already exists';
END
GO

-- P0.3: Memory Utilization Baseline
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotMemory') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotMemory (P0.3)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotMemory_RunID
        ON dbo.PerfSnapshotMemory(PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotMemory created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotMemory already exists';
END
GO

-- P0.3b: Memory Clerks Detail
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotMemoryClerks') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotMemoryClerks (P0.3b)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotMemoryClerks_RunID
        ON dbo.PerfSnapshotMemoryClerks(PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotMemoryClerks created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotMemoryClerks already exists';
END
GO

-- P0.4: Backup Validation
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotBackupHistory') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotBackupHistory (P0.4)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotBackupHistory_RunID
        ON dbo.PerfSnapshotBackupHistory(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotBackupHistory_RiskLevel
        ON dbo.PerfSnapshotBackupHistory(BackupRiskLevel, PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotBackupHistory created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotBackupHistory already exists';
END
GO

PRINT 'P0 (Critical) tables created ✓';
PRINT '';
GO

-- =====================================================
-- P1 HIGH PRIORITY
-- =====================================================

PRINT 'Creating P1 (High Priority) tables...';
GO

-- P1.6: Index Usage Statistics
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotIndexUsage') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotIndexUsage (P1.6)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotIndexUsage_RunID
        ON dbo.PerfSnapshotIndexUsage(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotIndexUsage_Database
        ON dbo.PerfSnapshotIndexUsage(DatabaseID, ObjectID, IndexID);

    PRINT '  ✓ dbo.PerfSnapshotIndexUsage created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotIndexUsage already exists';
END
GO

-- P1.7: Missing Index Recommendations
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotMissingIndexes') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotMissingIndexes (P1.7)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotMissingIndexes_RunID
        ON dbo.PerfSnapshotMissingIndexes(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotMissingIndexes_Impact
        ON dbo.PerfSnapshotMissingIndexes(ImpactScore DESC) INCLUDE (DatabaseName, ObjectName);

    PRINT '  ✓ dbo.PerfSnapshotMissingIndexes created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotMissingIndexes already exists';
END
GO

-- P1.8: Detailed Wait Statistics
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotWaitStats') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotWaitStats (P1.8)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotWaitStats_RunID
        ON dbo.PerfSnapshotWaitStats(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotWaitStats_WaitType
        ON dbo.PerfSnapshotWaitStats(WaitType, PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotWaitStats created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotWaitStats already exists';
END
GO

-- P1.9: TempDB Contention Detection
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotTempDBContention') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotTempDBContention (P1.9)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotTempDBContention_RunID
        ON dbo.PerfSnapshotTempDBContention(PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotTempDBContention created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotTempDBContention already exists';
END
GO

-- P1.10: Query Execution Plan Capture
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotQueryPlans') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotQueryPlans (P1.10)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotQueryPlans_RunID
        ON dbo.PerfSnapshotQueryPlans(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotQueryPlans_QueryHash
        ON dbo.PerfSnapshotQueryPlans(QueryHash, PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotQueryPlans created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotQueryPlans already exists';
END
GO

PRINT 'P1 (High Priority) tables created ✓';
PRINT '';
GO

-- =====================================================
-- P2 MEDIUM PRIORITY
-- =====================================================

PRINT 'Creating P2 (Medium Priority) tables...';
GO

-- P2.11: Server Configuration Baseline
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotConfig') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotConfig (P2.11)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotConfig_RunID
        ON dbo.PerfSnapshotConfig(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotConfig_Name
        ON dbo.PerfSnapshotConfig(ConfigName, PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotConfig created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotConfig already exists';
END
GO

-- P2.13: Enhanced Deadlock Analysis
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotDeadlocks') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotDeadlocks (P2.13)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotDeadlocks_RunID
        ON dbo.PerfSnapshotDeadlocks(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotDeadlocks_Timestamp
        ON dbo.PerfSnapshotDeadlocks(DeadlockTimestamp DESC);

    PRINT '  ✓ dbo.PerfSnapshotDeadlocks created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotDeadlocks already exists';
END
GO

-- P2.14: Scheduler Health Metrics
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotSchedulers') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotSchedulers (P2.14)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotSchedulers_RunID
        ON dbo.PerfSnapshotSchedulers(PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotSchedulers created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotSchedulers already exists';
END
GO

-- P2.15: Performance Counter Metrics
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotCounters') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotCounters (P2.15)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotCounters_RunID
        ON dbo.PerfSnapshotCounters(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotCounters_Name
        ON dbo.PerfSnapshotCounters(CounterName, PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotCounters created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotCounters already exists';
END
GO

-- P2.16: Autogrowth Event Tracking
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotAutogrowthEvents') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotAutogrowthEvents (P2.16)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotAutogrowthEvents_RunID
        ON dbo.PerfSnapshotAutogrowthEvents(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotAutogrowthEvents_Database
        ON dbo.PerfSnapshotAutogrowthEvents(DatabaseID, EventTimestamp DESC);

    PRINT '  ✓ dbo.PerfSnapshotAutogrowthEvents created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotAutogrowthEvents already exists';
END
GO

PRINT 'P2 (Medium Priority) tables created ✓';
PRINT '';
GO

-- =====================================================
-- P3 LOW PRIORITY
-- =====================================================

PRINT 'Creating P3 (Low Priority) tables...';
GO

-- P3.18: Latch Statistics
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotLatchStats') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotLatchStats (P3.18)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotLatchStats_RunID
        ON dbo.PerfSnapshotLatchStats(PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotLatchStats created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotLatchStats already exists';
END
GO

-- P3.19: SQL Agent Job History
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotJobHistory') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotJobHistory (P3.19)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotJobHistory_RunID
        ON dbo.PerfSnapshotJobHistory(PerfSnapshotRunID);

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotJobHistory_Outcome
        ON dbo.PerfSnapshotJobHistory(LastRunOutcome, PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotJobHistory created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotJobHistory already exists';
END
GO

-- P3.21: Spinlock Statistics
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerfSnapshotSpinlockStats') AND type = 'U')
BEGIN
    PRINT '  Creating dbo.PerfSnapshotSpinlockStats (P3.21)';

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
    );

    CREATE NONCLUSTERED INDEX IX_PerfSnapshotSpinlockStats_RunID
        ON dbo.PerfSnapshotSpinlockStats(PerfSnapshotRunID);

    PRINT '  ✓ dbo.PerfSnapshotSpinlockStats created';
END
ELSE
BEGIN
    PRINT '  ✓ dbo.PerfSnapshotSpinlockStats already exists';
END
GO

PRINT 'P3 (Low Priority) tables created ✓';
PRINT '';
GO

-- =====================================================
-- Summary
-- =====================================================

PRINT '=========================================================================';
PRINT 'Phase 1.9: Enhanced Monitoring Tables Created Successfully';
PRINT '=========================================================================';
PRINT '';
PRINT 'Created tables by priority:';
PRINT '  P0 (Critical):      5 tables  (Query, IO, Memory, MemoryClerks, Backups)';
PRINT '  P1 (High):          5 tables  (IndexUsage, MissingIndexes, WaitStats, TempDB, QueryPlans)';
PRINT '  P2 (Medium):        6 tables  (Config, Deadlocks, Schedulers, Counters, Autogrowth)';
PRINT '  P3 (Low):           3 tables  (LatchStats, JobHistory, SpinlockStats)';
PRINT '  TOTAL:             19 tables';
PRINT '';
PRINT 'Next: Run 22-create-feedback-system.sql for intelligent analysis';
PRINT '';
GO
