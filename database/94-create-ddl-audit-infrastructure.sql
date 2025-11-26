-- =====================================================
-- DDL Audit Infrastructure for SQL Monitor
-- Phase 2.1: Schema Change Tracking with Cause/Effect Analysis
-- =====================================================
-- This script creates:
-- 1. DDLAuditEvents table for capturing all DDL changes
-- 2. DDLImpactAnalysis table for correlating DDL with performance
-- 3. Server-side DDL trigger template (to deploy on monitored servers)
-- 4. Procedures for DDL analysis and anomaly detection
-- 5. Cause/Effect correlation procedures
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- SECTION 1: DDL Audit Events Table
-- =====================================================
-- Captures all DDL events from monitored SQL Servers
-- This table receives data from DDL triggers on each monitored server

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'DDLAuditEvents' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.DDLAuditEvents (
        DDLEventID          BIGINT IDENTITY(1,1) NOT NULL,
        ServerID            INT NOT NULL,
        EventTime           DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),

        -- Event Classification
        EventType           VARCHAR(50) NOT NULL,           -- CREATE_TABLE, ALTER_INDEX, DROP_PROCEDURE, etc.
        EventCategory       VARCHAR(30) NOT NULL,           -- TABLE, INDEX, VIEW, PROCEDURE, FUNCTION, TRIGGER, SCHEMA, USER, ROLE

        -- Object Information
        DatabaseName        NVARCHAR(128) NOT NULL,
        SchemaName          NVARCHAR(128) NULL,
        ObjectName          NVARCHAR(128) NULL,
        ObjectType          VARCHAR(50) NULL,               -- Detailed object type

        -- User Attribution
        LoginName           NVARCHAR(128) NOT NULL,         -- SQL Server login
        UserName            NVARCHAR(128) NULL,             -- Database user (may differ from login)
        HostName            NVARCHAR(128) NULL,             -- Client machine
        ApplicationName     NVARCHAR(256) NULL,             -- Application making change
        IPAddress           VARCHAR(45) NULL,               -- Client IP (IPv4 or IPv6)

        -- Change Details
        SQLCommand          NVARCHAR(MAX) NOT NULL,         -- Full DDL statement
        CommandHash         VARBINARY(32) NULL,             -- SHA256 hash for deduplication

        -- Session Context
        SPID                INT NULL,                       -- Session ID
        TransactionID       BIGINT NULL,                    -- For grouping related changes
        NestLevel           INT NULL,                       -- Trigger nesting level

        -- Impact Tracking (populated by correlation analysis)
        ImpactSeverity      VARCHAR(20) NULL,               -- None, Low, Medium, High, Critical
        ImpactScore         INT NULL,                       -- 0-100 impact score
        RelatedAlertID      BIGINT NULL,                    -- Link to AlertHistory if triggered alert

        -- Metadata
        IsRollback          BIT NOT NULL DEFAULT 0,         -- Was this a rollback operation
        IsAutomated         BIT NOT NULL DEFAULT 0,         -- Automated (SQL Agent) vs Manual
        ReviewedBy          NVARCHAR(128) NULL,             -- Who reviewed (for compliance)
        ReviewedAt          DATETIME2(7) NULL,
        Notes               NVARCHAR(MAX) NULL,

        -- Partition Key
        PartitionKey        AS CAST(EventTime AS DATE) PERSISTED,

        CONSTRAINT PK_DDLAuditEvents PRIMARY KEY NONCLUSTERED (DDLEventID),
        CONSTRAINT FK_DDLAuditEvents_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
        CONSTRAINT CK_DDLAuditEvents_ImpactSeverity CHECK (ImpactSeverity IN ('None', 'Low', 'Medium', 'High', 'Critical'))
    );

    PRINT 'Created table: dbo.DDLAuditEvents';
END
ELSE
BEGIN
    PRINT 'Table dbo.DDLAuditEvents already exists';
END
GO

-- Clustered columnstore for compression and analytics
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'CCI_DDLAuditEvents' AND object_id = OBJECT_ID('dbo.DDLAuditEvents'))
BEGIN
    CREATE CLUSTERED COLUMNSTORE INDEX CCI_DDLAuditEvents ON dbo.DDLAuditEvents;
    PRINT 'Created clustered columnstore index on DDLAuditEvents';
END
GO

-- Performance indexes
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DDLAuditEvents_EventTime' AND object_id = OBJECT_ID('dbo.DDLAuditEvents'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_DDLAuditEvents_EventTime
    ON dbo.DDLAuditEvents (EventTime DESC)
    INCLUDE (ServerID, EventType, DatabaseName, ObjectName, LoginName);
    PRINT 'Created index: IX_DDLAuditEvents_EventTime';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DDLAuditEvents_LoginName' AND object_id = OBJECT_ID('dbo.DDLAuditEvents'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_DDLAuditEvents_LoginName
    ON dbo.DDLAuditEvents (LoginName, EventTime DESC)
    INCLUDE (ServerID, EventType, DatabaseName, ObjectName, ImpactSeverity);
    PRINT 'Created index: IX_DDLAuditEvents_LoginName';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DDLAuditEvents_ObjectName' AND object_id = OBJECT_ID('dbo.DDLAuditEvents'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_DDLAuditEvents_ObjectName
    ON dbo.DDLAuditEvents (DatabaseName, SchemaName, ObjectName, EventTime DESC)
    INCLUDE (EventType, LoginName, ImpactSeverity);
    PRINT 'Created index: IX_DDLAuditEvents_ObjectName';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DDLAuditEvents_ImpactSeverity' AND object_id = OBJECT_ID('dbo.DDLAuditEvents'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_DDLAuditEvents_ImpactSeverity
    ON dbo.DDLAuditEvents (ImpactSeverity, EventTime DESC)
    WHERE ImpactSeverity IS NOT NULL AND ImpactSeverity != 'None'
    INCLUDE (ServerID, EventType, DatabaseName, ObjectName, LoginName);
    PRINT 'Created filtered index: IX_DDLAuditEvents_ImpactSeverity';
END
GO

-- =====================================================
-- SECTION 2: DDL Impact Analysis Table
-- =====================================================
-- Links DDL events to performance metrics for cause/effect analysis

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'DDLImpactAnalysis' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.DDLImpactAnalysis (
        ImpactAnalysisID    BIGINT IDENTITY(1,1) NOT NULL,
        DDLEventID          BIGINT NOT NULL,
        ServerID            INT NOT NULL,
        AnalysisTime        DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),

        -- Time Windows
        BaselineStartTime   DATETIME2(7) NOT NULL,          -- Start of baseline period (before DDL)
        BaselineEndTime     DATETIME2(7) NOT NULL,          -- End of baseline (DDL event time)
        ImpactStartTime     DATETIME2(7) NOT NULL,          -- Start measuring impact (DDL event time)
        ImpactEndTime       DATETIME2(7) NOT NULL,          -- End of impact measurement window

        -- Baseline Metrics (before DDL)
        BaselineAvgCPU              DECIMAL(10,2) NULL,
        BaselineAvgMemory           DECIMAL(10,2) NULL,
        BaselineAvgDiskIO           DECIMAL(18,2) NULL,
        BaselineAvgBatchRequests    DECIMAL(18,2) NULL,
        BaselineAvgQueryDuration    DECIMAL(18,2) NULL,     -- ms
        BaselineErrorCount          INT NULL,
        BaselineBlockingCount       INT NULL,
        BaselineDeadlockCount       INT NULL,

        -- Post-DDL Metrics (after DDL)
        PostDDLAvgCPU               DECIMAL(10,2) NULL,
        PostDDLAvgMemory            DECIMAL(10,2) NULL,
        PostDDLAvgDiskIO            DECIMAL(18,2) NULL,
        PostDDLAvgBatchRequests     DECIMAL(18,2) NULL,
        PostDDLAvgQueryDuration     DECIMAL(18,2) NULL,
        PostDDLErrorCount           INT NULL,
        PostDDLBlockingCount        INT NULL,
        PostDDLDeadlockCount        INT NULL,

        -- Delta Calculations (positive = increase, negative = decrease)
        DeltaCPUPercent             DECIMAL(10,2) NULL,
        DeltaMemoryPercent          DECIMAL(10,2) NULL,
        DeltaDiskIOPercent          DECIMAL(10,2) NULL,
        DeltaBatchRequestsPercent   DECIMAL(10,2) NULL,
        DeltaQueryDurationPercent   DECIMAL(10,2) NULL,
        DeltaErrorCount             INT NULL,
        DeltaBlockingCount          INT NULL,
        DeltaDeadlockCount          INT NULL,

        -- Impact Assessment
        OverallImpactScore          INT NOT NULL DEFAULT 0,  -- 0-100
        ImpactCategory              VARCHAR(30) NOT NULL DEFAULT 'Unknown',
        ImpactSummary               NVARCHAR(MAX) NULL,      -- Human-readable summary
        RecommendedAction           NVARCHAR(MAX) NULL,      -- Suggested remediation

        -- Correlation Confidence
        ConfidenceLevel             VARCHAR(20) NOT NULL DEFAULT 'Low',  -- Low, Medium, High
        ConfidenceScore             INT NOT NULL DEFAULT 0,  -- 0-100
        ConfidenceNotes             NVARCHAR(MAX) NULL,

        -- Related Objects
        AffectedQueries             NVARCHAR(MAX) NULL,      -- JSON array of affected query hashes
        AffectedProcedures          NVARCHAR(MAX) NULL,      -- JSON array of affected procedures
        RelatedAlerts               NVARCHAR(MAX) NULL,      -- JSON array of related alert IDs

        CONSTRAINT PK_DDLImpactAnalysis PRIMARY KEY CLUSTERED (ImpactAnalysisID),
        CONSTRAINT FK_DDLImpactAnalysis_DDLEvent FOREIGN KEY (DDLEventID) REFERENCES dbo.DDLAuditEvents(DDLEventID),
        CONSTRAINT FK_DDLImpactAnalysis_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
        CONSTRAINT CK_DDLImpactAnalysis_ImpactCategory CHECK (ImpactCategory IN ('Unknown', 'Positive', 'Neutral', 'Negative', 'Critical')),
        CONSTRAINT CK_DDLImpactAnalysis_ConfidenceLevel CHECK (ConfidenceLevel IN ('Low', 'Medium', 'High'))
    );

    PRINT 'Created table: dbo.DDLImpactAnalysis';
END
GO

-- Index for querying impact by DDL event
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DDLImpactAnalysis_DDLEventID' AND object_id = OBJECT_ID('dbo.DDLImpactAnalysis'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_DDLImpactAnalysis_DDLEventID
    ON dbo.DDLImpactAnalysis (DDLEventID)
    INCLUDE (OverallImpactScore, ImpactCategory, ConfidenceLevel);
    PRINT 'Created index: IX_DDLImpactAnalysis_DDLEventID';
END
GO

-- =====================================================
-- SECTION 3: DDL Event Categories Reference
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'DDLEventCategories' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.DDLEventCategories (
        EventType           VARCHAR(50) NOT NULL PRIMARY KEY,
        EventCategory       VARCHAR(30) NOT NULL,
        RiskLevel           VARCHAR(20) NOT NULL,           -- Low, Medium, High, Critical
        RequiresReview      BIT NOT NULL DEFAULT 0,
        Description         NVARCHAR(500) NULL
    );

    -- Populate with common DDL event types
    INSERT INTO dbo.DDLEventCategories (EventType, EventCategory, RiskLevel, RequiresReview, Description) VALUES
    -- Table Operations
    ('CREATE_TABLE', 'TABLE', 'Medium', 0, 'New table created'),
    ('ALTER_TABLE', 'TABLE', 'High', 1, 'Table structure modified - may break dependencies'),
    ('DROP_TABLE', 'TABLE', 'Critical', 1, 'Table deleted - data loss risk'),
    ('RENAME', 'TABLE', 'High', 1, 'Object renamed - may break dependencies'),

    -- Index Operations
    ('CREATE_INDEX', 'INDEX', 'Medium', 0, 'Index created - may improve or degrade performance'),
    ('CREATE_NONCLUSTERED_INDEX', 'INDEX', 'Medium', 0, 'Nonclustered index created'),
    ('CREATE_CLUSTERED_INDEX', 'INDEX', 'High', 1, 'Clustered index created - table reorganization'),
    ('ALTER_INDEX', 'INDEX', 'Medium', 0, 'Index modified (rebuild, reorganize, disable)'),
    ('DROP_INDEX', 'INDEX', 'High', 1, 'Index removed - may impact query performance'),

    -- View Operations
    ('CREATE_VIEW', 'VIEW', 'Low', 0, 'View created'),
    ('ALTER_VIEW', 'VIEW', 'Medium', 0, 'View definition modified'),
    ('DROP_VIEW', 'VIEW', 'Medium', 1, 'View deleted'),

    -- Stored Procedure Operations
    ('CREATE_PROCEDURE', 'PROCEDURE', 'Low', 0, 'Procedure created'),
    ('ALTER_PROCEDURE', 'PROCEDURE', 'Medium', 0, 'Procedure modified'),
    ('DROP_PROCEDURE', 'PROCEDURE', 'Medium', 1, 'Procedure deleted'),

    -- Function Operations
    ('CREATE_FUNCTION', 'FUNCTION', 'Low', 0, 'Function created'),
    ('ALTER_FUNCTION', 'FUNCTION', 'Medium', 0, 'Function modified'),
    ('DROP_FUNCTION', 'FUNCTION', 'Medium', 1, 'Function deleted'),

    -- Trigger Operations
    ('CREATE_TRIGGER', 'TRIGGER', 'High', 1, 'Trigger created - impacts DML operations'),
    ('ALTER_TRIGGER', 'TRIGGER', 'High', 1, 'Trigger modified'),
    ('DROP_TRIGGER', 'TRIGGER', 'Medium', 1, 'Trigger removed'),
    ('ENABLE_TRIGGER', 'TRIGGER', 'Medium', 0, 'Trigger enabled'),
    ('DISABLE_TRIGGER', 'TRIGGER', 'Medium', 1, 'Trigger disabled'),

    -- Schema Operations
    ('CREATE_SCHEMA', 'SCHEMA', 'Low', 0, 'Schema created'),
    ('ALTER_SCHEMA', 'SCHEMA', 'Medium', 1, 'Schema modified'),
    ('DROP_SCHEMA', 'SCHEMA', 'High', 1, 'Schema deleted'),

    -- Security Operations
    ('CREATE_USER', 'USER', 'Medium', 1, 'Database user created'),
    ('ALTER_USER', 'USER', 'Medium', 1, 'User modified'),
    ('DROP_USER', 'USER', 'High', 1, 'User deleted'),
    ('CREATE_ROLE', 'ROLE', 'Medium', 1, 'Role created'),
    ('ALTER_ROLE', 'ROLE', 'Medium', 1, 'Role modified'),
    ('DROP_ROLE', 'ROLE', 'High', 1, 'Role deleted'),
    ('ADD_ROLE_MEMBER', 'ROLE', 'Medium', 1, 'User added to role'),
    ('DROP_ROLE_MEMBER', 'ROLE', 'Medium', 1, 'User removed from role'),
    ('GRANT', 'PERMISSION', 'Medium', 1, 'Permission granted'),
    ('DENY', 'PERMISSION', 'High', 1, 'Permission denied'),
    ('REVOKE', 'PERMISSION', 'Medium', 1, 'Permission revoked'),

    -- Statistics
    ('CREATE_STATISTICS', 'STATISTICS', 'Low', 0, 'Statistics created'),
    ('UPDATE_STATISTICS', 'STATISTICS', 'Low', 0, 'Statistics updated'),
    ('DROP_STATISTICS', 'STATISTICS', 'Medium', 0, 'Statistics dropped'),

    -- Other
    ('CREATE_TYPE', 'TYPE', 'Low', 0, 'User-defined type created'),
    ('DROP_TYPE', 'TYPE', 'Medium', 1, 'User-defined type dropped'),
    ('CREATE_SYNONYM', 'SYNONYM', 'Low', 0, 'Synonym created'),
    ('DROP_SYNONYM', 'SYNONYM', 'Low', 0, 'Synonym dropped'),
    ('CREATE_SEQUENCE', 'SEQUENCE', 'Low', 0, 'Sequence created'),
    ('ALTER_SEQUENCE', 'SEQUENCE', 'Low', 0, 'Sequence modified'),
    ('DROP_SEQUENCE', 'SEQUENCE', 'Medium', 1, 'Sequence dropped');

    PRINT 'Created and populated table: dbo.DDLEventCategories';
END
GO

-- =====================================================
-- SECTION 4: Procedure to Log DDL Events
-- =====================================================
-- Called by DDL triggers on monitored servers

CREATE OR ALTER PROCEDURE dbo.usp_LogDDLEvent
    @ServerName         NVARCHAR(128),
    @EventType          VARCHAR(50),
    @DatabaseName       NVARCHAR(128),
    @SchemaName         NVARCHAR(128) = NULL,
    @ObjectName         NVARCHAR(128) = NULL,
    @ObjectType         VARCHAR(50) = NULL,
    @LoginName          NVARCHAR(128),
    @UserName           NVARCHAR(128) = NULL,
    @HostName           NVARCHAR(128) = NULL,
    @ApplicationName    NVARCHAR(256) = NULL,
    @IPAddress          VARCHAR(45) = NULL,
    @SQLCommand         NVARCHAR(MAX),
    @SPID               INT = NULL,
    @TransactionID      BIGINT = NULL,
    @NestLevel          INT = NULL,
    @IsAutomated        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerID INT;
    DECLARE @EventCategory VARCHAR(30);
    DECLARE @CommandHash VARBINARY(32);

    -- Get ServerID
    SELECT @ServerID = ServerID
    FROM dbo.Servers
    WHERE ServerName = @ServerName;

    IF @ServerID IS NULL
    BEGIN
        -- Auto-register server if not found
        INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
        VALUES (@ServerName, 'Unknown', 1);

        SET @ServerID = SCOPE_IDENTITY();
    END

    -- Get event category from reference table
    SELECT @EventCategory = ISNULL(EventCategory, 'OTHER')
    FROM dbo.DDLEventCategories
    WHERE EventType = @EventType;

    IF @EventCategory IS NULL
        SET @EventCategory = 'OTHER';

    -- Generate command hash for deduplication
    SET @CommandHash = HASHBYTES('SHA2_256', @SQLCommand);

    -- Insert DDL event
    INSERT INTO dbo.DDLAuditEvents (
        ServerID,
        EventType,
        EventCategory,
        DatabaseName,
        SchemaName,
        ObjectName,
        ObjectType,
        LoginName,
        UserName,
        HostName,
        ApplicationName,
        IPAddress,
        SQLCommand,
        CommandHash,
        SPID,
        TransactionID,
        NestLevel,
        IsAutomated
    )
    VALUES (
        @ServerID,
        @EventType,
        @EventCategory,
        @DatabaseName,
        @SchemaName,
        @ObjectName,
        @ObjectType,
        @LoginName,
        @UserName,
        @HostName,
        @ApplicationName,
        @IPAddress,
        @SQLCommand,
        @CommandHash,
        @SPID,
        @TransactionID,
        @NestLevel,
        @IsAutomated
    );

    RETURN 0;
END
GO

PRINT 'Created procedure: dbo.usp_LogDDLEvent';
GO

-- =====================================================
-- SECTION 5: Procedure to Analyze DDL Impact
-- =====================================================
-- Correlates DDL events with performance metrics

CREATE OR ALTER PROCEDURE dbo.usp_AnalyzeDDLImpact
    @DDLEventID         BIGINT = NULL,              -- Analyze specific event, or NULL for recent unanalyzed
    @BaselineMinutes    INT = 60,                   -- Minutes before DDL for baseline
    @ImpactMinutes      INT = 60,                   -- Minutes after DDL to measure impact
    @MinConfidenceScore INT = 50                    -- Minimum confidence to record
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerID INT;
    DECLARE @EventTime DATETIME2(7);
    DECLARE @BaselineStart DATETIME2(7);
    DECLARE @BaselineEnd DATETIME2(7);
    DECLARE @ImpactStart DATETIME2(7);
    DECLARE @ImpactEnd DATETIME2(7);

    -- Baseline metrics
    DECLARE @BaselineCPU DECIMAL(10,2);
    DECLARE @BaselineMemory DECIMAL(10,2);
    DECLARE @BaselineDiskIO DECIMAL(18,2);
    DECLARE @BaselineBatchReq DECIMAL(18,2);
    DECLARE @BaselineQueryDur DECIMAL(18,2);
    DECLARE @BaselineErrors INT;
    DECLARE @BaselineBlocking INT;
    DECLARE @BaselineDeadlocks INT;

    -- Post-DDL metrics
    DECLARE @PostCPU DECIMAL(10,2);
    DECLARE @PostMemory DECIMAL(10,2);
    DECLARE @PostDiskIO DECIMAL(18,2);
    DECLARE @PostBatchReq DECIMAL(18,2);
    DECLARE @PostQueryDur DECIMAL(18,2);
    DECLARE @PostErrors INT;
    DECLARE @PostBlocking INT;
    DECLARE @PostDeadlocks INT;

    -- Impact calculations
    DECLARE @DeltaCPU DECIMAL(10,2);
    DECLARE @DeltaMemory DECIMAL(10,2);
    DECLARE @DeltaDiskIO DECIMAL(10,2);
    DECLARE @DeltaBatchReq DECIMAL(10,2);
    DECLARE @DeltaQueryDur DECIMAL(10,2);
    DECLARE @ImpactScore INT;
    DECLARE @ImpactCategory VARCHAR(30);
    DECLARE @ConfidenceScore INT;
    DECLARE @ConfidenceLevel VARCHAR(20);
    DECLARE @ImpactSummary NVARCHAR(MAX);

    -- Process specific event or get unanalyzed events
    DECLARE @EventsToProcess TABLE (DDLEventID BIGINT, ServerID INT, EventTime DATETIME2(7));

    IF @DDLEventID IS NOT NULL
    BEGIN
        INSERT INTO @EventsToProcess
        SELECT DDLEventID, ServerID, EventTime
        FROM dbo.DDLAuditEvents
        WHERE DDLEventID = @DDLEventID;
    END
    ELSE
    BEGIN
        -- Get recent DDL events without impact analysis (last 24 hours)
        INSERT INTO @EventsToProcess
        SELECT d.DDLEventID, d.ServerID, d.EventTime
        FROM dbo.DDLAuditEvents d
        LEFT JOIN dbo.DDLImpactAnalysis i ON d.DDLEventID = i.DDLEventID
        WHERE i.ImpactAnalysisID IS NULL
          AND d.EventTime >= DATEADD(HOUR, -24, SYSUTCDATETIME())
          AND d.EventTime <= DATEADD(MINUTE, -@ImpactMinutes, SYSUTCDATETIME());  -- Allow time for metrics
    END

    -- Process each event
    DECLARE event_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DDLEventID, ServerID, EventTime FROM @EventsToProcess;

    OPEN event_cursor;
    FETCH NEXT FROM event_cursor INTO @DDLEventID, @ServerID, @EventTime;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Calculate time windows
        SET @BaselineEnd = @EventTime;
        SET @BaselineStart = DATEADD(MINUTE, -@BaselineMinutes, @EventTime);
        SET @ImpactStart = @EventTime;
        SET @ImpactEnd = DATEADD(MINUTE, @ImpactMinutes, @EventTime);

        -- Get baseline metrics (before DDL)
        SELECT
            @BaselineCPU = AVG(CASE WHEN MetricName = 'CPU Utilization %' THEN MetricValue END),
            @BaselineMemory = AVG(CASE WHEN MetricName = 'Memory Utilization %' THEN MetricValue END),
            @BaselineDiskIO = AVG(CASE WHEN MetricName = 'Disk Read Bytes/sec' THEN MetricValue END) +
                              AVG(CASE WHEN MetricName = 'Disk Write Bytes/sec' THEN MetricValue END),
            @BaselineBatchReq = AVG(CASE WHEN MetricName = 'Batch Requests/sec' THEN MetricValue END)
        FROM dbo.PerformanceMetrics
        WHERE ServerID = @ServerID
          AND CollectionTime >= @BaselineStart
          AND CollectionTime < @BaselineEnd;

        -- Get baseline query duration from procedure stats
        SELECT @BaselineQueryDur = AVG(AvgDurationMs)
        FROM dbo.ProcedureStats
        WHERE ServerID = @ServerID
          AND CollectionTime >= @BaselineStart
          AND CollectionTime < @BaselineEnd;

        -- Get baseline error/blocking counts
        SELECT @BaselineErrors = COUNT(*)
        FROM dbo.AuditLog
        WHERE EventTime >= @BaselineStart
          AND EventTime < @BaselineEnd
          AND Severity IN ('Error', 'Critical');

        SELECT @BaselineBlocking = COUNT(*)
        FROM dbo.BlockingEvents
        WHERE ServerID = @ServerID
          AND EventTime >= @BaselineStart
          AND EventTime < @BaselineEnd;

        SELECT @BaselineDeadlocks = COUNT(*)
        FROM dbo.DeadlockEvents
        WHERE ServerID = @ServerID
          AND EventTime >= @BaselineStart
          AND EventTime < @BaselineEnd;

        -- Get post-DDL metrics
        SELECT
            @PostCPU = AVG(CASE WHEN MetricName = 'CPU Utilization %' THEN MetricValue END),
            @PostMemory = AVG(CASE WHEN MetricName = 'Memory Utilization %' THEN MetricValue END),
            @PostDiskIO = AVG(CASE WHEN MetricName = 'Disk Read Bytes/sec' THEN MetricValue END) +
                          AVG(CASE WHEN MetricName = 'Disk Write Bytes/sec' THEN MetricValue END),
            @PostBatchReq = AVG(CASE WHEN MetricName = 'Batch Requests/sec' THEN MetricValue END)
        FROM dbo.PerformanceMetrics
        WHERE ServerID = @ServerID
          AND CollectionTime >= @ImpactStart
          AND CollectionTime <= @ImpactEnd;

        SELECT @PostQueryDur = AVG(AvgDurationMs)
        FROM dbo.ProcedureStats
        WHERE ServerID = @ServerID
          AND CollectionTime >= @ImpactStart
          AND CollectionTime <= @ImpactEnd;

        SELECT @PostErrors = COUNT(*)
        FROM dbo.AuditLog
        WHERE EventTime >= @ImpactStart
          AND EventTime <= @ImpactEnd
          AND Severity IN ('Error', 'Critical');

        SELECT @PostBlocking = COUNT(*)
        FROM dbo.BlockingEvents
        WHERE ServerID = @ServerID
          AND EventTime >= @ImpactStart
          AND EventTime <= @ImpactEnd;

        SELECT @PostDeadlocks = COUNT(*)
        FROM dbo.DeadlockEvents
        WHERE ServerID = @ServerID
          AND EventTime >= @ImpactStart
          AND EventTime <= @ImpactEnd;

        -- Calculate deltas (percentage change)
        SET @DeltaCPU = CASE WHEN ISNULL(@BaselineCPU, 0) > 0
                             THEN ((@PostCPU - @BaselineCPU) / @BaselineCPU) * 100
                             ELSE 0 END;
        SET @DeltaMemory = CASE WHEN ISNULL(@BaselineMemory, 0) > 0
                                THEN ((@PostMemory - @BaselineMemory) / @BaselineMemory) * 100
                                ELSE 0 END;
        SET @DeltaDiskIO = CASE WHEN ISNULL(@BaselineDiskIO, 0) > 0
                                THEN ((@PostDiskIO - @BaselineDiskIO) / @BaselineDiskIO) * 100
                                ELSE 0 END;
        SET @DeltaBatchReq = CASE WHEN ISNULL(@BaselineBatchReq, 0) > 0
                                  THEN ((@PostBatchReq - @BaselineBatchReq) / @BaselineBatchReq) * 100
                                  ELSE 0 END;
        SET @DeltaQueryDur = CASE WHEN ISNULL(@BaselineQueryDur, 0) > 0
                                  THEN ((@PostQueryDur - @BaselineQueryDur) / @BaselineQueryDur) * 100
                                  ELSE 0 END;

        -- Calculate overall impact score (0-100)
        -- Higher scores = more negative impact
        SET @ImpactScore =
            CASE
                -- CPU increase is bad
                WHEN @DeltaCPU > 50 THEN 30
                WHEN @DeltaCPU > 20 THEN 20
                WHEN @DeltaCPU > 10 THEN 10
                ELSE 0
            END +
            CASE
                -- Query duration increase is bad
                WHEN @DeltaQueryDur > 100 THEN 40
                WHEN @DeltaQueryDur > 50 THEN 30
                WHEN @DeltaQueryDur > 20 THEN 15
                ELSE 0
            END +
            CASE
                -- New errors are bad
                WHEN (@PostErrors - ISNULL(@BaselineErrors, 0)) > 10 THEN 20
                WHEN (@PostErrors - ISNULL(@BaselineErrors, 0)) > 5 THEN 15
                WHEN (@PostErrors - ISNULL(@BaselineErrors, 0)) > 0 THEN 10
                ELSE 0
            END +
            CASE
                -- Blocking/deadlocks are very bad
                WHEN (@PostDeadlocks - ISNULL(@BaselineDeadlocks, 0)) > 0 THEN 15
                WHEN (@PostBlocking - ISNULL(@BaselineBlocking, 0)) > 5 THEN 10
                ELSE 0
            END;

        -- Determine impact category
        SET @ImpactCategory = CASE
            WHEN @ImpactScore >= 70 THEN 'Critical'
            WHEN @ImpactScore >= 40 THEN 'Negative'
            WHEN @ImpactScore >= 10 THEN 'Neutral'
            WHEN @ImpactScore < 0 THEN 'Positive'  -- Improvement
            ELSE 'Unknown'
        END;

        -- Calculate confidence score (based on data availability)
        SET @ConfidenceScore =
            CASE WHEN @BaselineCPU IS NOT NULL THEN 20 ELSE 0 END +
            CASE WHEN @PostCPU IS NOT NULL THEN 20 ELSE 0 END +
            CASE WHEN @BaselineQueryDur IS NOT NULL THEN 20 ELSE 0 END +
            CASE WHEN @PostQueryDur IS NOT NULL THEN 20 ELSE 0 END +
            CASE WHEN @BaselineMinutes >= 30 AND @ImpactMinutes >= 30 THEN 20 ELSE 10 END;

        SET @ConfidenceLevel = CASE
            WHEN @ConfidenceScore >= 80 THEN 'High'
            WHEN @ConfidenceScore >= 50 THEN 'Medium'
            ELSE 'Low'
        END;

        -- Generate impact summary
        SET @ImpactSummary =
            'CPU: ' + CAST(ISNULL(@DeltaCPU, 0) AS VARCHAR(10)) + '% change, ' +
            'Query Duration: ' + CAST(ISNULL(@DeltaQueryDur, 0) AS VARCHAR(10)) + '% change, ' +
            'Errors: ' + CAST(ISNULL(@PostErrors, 0) - ISNULL(@BaselineErrors, 0) AS VARCHAR(10)) + ' new, ' +
            'Blocking Events: ' + CAST(ISNULL(@PostBlocking, 0) - ISNULL(@BaselineBlocking, 0) AS VARCHAR(10)) + ' new';

        -- Only record if confidence meets threshold
        IF @ConfidenceScore >= @MinConfidenceScore
        BEGIN
            INSERT INTO dbo.DDLImpactAnalysis (
                DDLEventID, ServerID,
                BaselineStartTime, BaselineEndTime, ImpactStartTime, ImpactEndTime,
                BaselineAvgCPU, BaselineAvgMemory, BaselineAvgDiskIO, BaselineAvgBatchRequests, BaselineAvgQueryDuration,
                BaselineErrorCount, BaselineBlockingCount, BaselineDeadlockCount,
                PostDDLAvgCPU, PostDDLAvgMemory, PostDDLAvgDiskIO, PostDDLAvgBatchRequests, PostDDLAvgQueryDuration,
                PostDDLErrorCount, PostDDLBlockingCount, PostDDLDeadlockCount,
                DeltaCPUPercent, DeltaMemoryPercent, DeltaDiskIOPercent, DeltaBatchRequestsPercent, DeltaQueryDurationPercent,
                DeltaErrorCount, DeltaBlockingCount, DeltaDeadlockCount,
                OverallImpactScore, ImpactCategory, ImpactSummary,
                ConfidenceLevel, ConfidenceScore
            )
            VALUES (
                @DDLEventID, @ServerID,
                @BaselineStart, @BaselineEnd, @ImpactStart, @ImpactEnd,
                @BaselineCPU, @BaselineMemory, @BaselineDiskIO, @BaselineBatchReq, @BaselineQueryDur,
                @BaselineErrors, @BaselineBlocking, @BaselineDeadlocks,
                @PostCPU, @PostMemory, @PostDiskIO, @PostBatchReq, @PostQueryDur,
                @PostErrors, @PostBlocking, @PostDeadlocks,
                @DeltaCPU, @DeltaMemory, @DeltaDiskIO, @DeltaBatchReq, @DeltaQueryDur,
                @PostErrors - ISNULL(@BaselineErrors, 0),
                @PostBlocking - ISNULL(@BaselineBlocking, 0),
                @PostDeadlocks - ISNULL(@BaselineDeadlocks, 0),
                @ImpactScore, @ImpactCategory, @ImpactSummary,
                @ConfidenceLevel, @ConfidenceScore
            );

            -- Update the DDL event with impact severity
            UPDATE dbo.DDLAuditEvents
            SET ImpactSeverity = CASE
                    WHEN @ImpactScore >= 70 THEN 'Critical'
                    WHEN @ImpactScore >= 40 THEN 'High'
                    WHEN @ImpactScore >= 20 THEN 'Medium'
                    WHEN @ImpactScore >= 10 THEN 'Low'
                    ELSE 'None'
                END,
                ImpactScore = @ImpactScore
            WHERE DDLEventID = @DDLEventID;
        END

        FETCH NEXT FROM event_cursor INTO @DDLEventID, @ServerID, @EventTime;
    END

    CLOSE event_cursor;
    DEALLOCATE event_cursor;

    RETURN 0;
END
GO

PRINT 'Created procedure: dbo.usp_AnalyzeDDLImpact';
GO

-- =====================================================
-- SECTION 6: Get DDL Audit Trail
-- =====================================================

CREATE OR ALTER PROCEDURE dbo.usp_GetDDLAuditTrail
    @ServerName         NVARCHAR(128) = NULL,
    @DatabaseName       NVARCHAR(128) = NULL,
    @LoginName          NVARCHAR(128) = NULL,
    @ObjectName         NVARCHAR(128) = NULL,
    @EventType          VARCHAR(50) = NULL,
    @EventCategory      VARCHAR(30) = NULL,
    @StartTime          DATETIME2(7) = NULL,
    @EndTime            DATETIME2(7) = NULL,
    @MinImpactScore     INT = NULL,
    @TopN               INT = 1000
AS
BEGIN
    SET NOCOUNT ON;

    IF @StartTime IS NULL SET @StartTime = DATEADD(DAY, -7, SYSUTCDATETIME());
    IF @EndTime IS NULL SET @EndTime = SYSUTCDATETIME();

    SELECT TOP (@TopN)
        d.DDLEventID,
        s.ServerName,
        d.EventTime,
        d.EventType,
        d.EventCategory,
        d.DatabaseName,
        d.SchemaName,
        d.ObjectName,
        d.ObjectType,
        d.LoginName,
        d.UserName,
        d.HostName,
        d.ApplicationName,
        d.SQLCommand,
        d.ImpactSeverity,
        d.ImpactScore,
        d.IsAutomated,
        d.ReviewedBy,
        d.ReviewedAt,
        c.RiskLevel,
        c.RequiresReview,
        i.OverallImpactScore AS AnalyzedImpactScore,
        i.ImpactCategory,
        i.ImpactSummary,
        i.ConfidenceLevel
    FROM dbo.DDLAuditEvents d
    INNER JOIN dbo.Servers s ON d.ServerID = s.ServerID
    LEFT JOIN dbo.DDLEventCategories c ON d.EventType = c.EventType
    LEFT JOIN dbo.DDLImpactAnalysis i ON d.DDLEventID = i.DDLEventID
    WHERE d.EventTime >= @StartTime
      AND d.EventTime <= @EndTime
      AND (@ServerName IS NULL OR s.ServerName = @ServerName)
      AND (@DatabaseName IS NULL OR d.DatabaseName = @DatabaseName)
      AND (@LoginName IS NULL OR d.LoginName = @LoginName)
      AND (@ObjectName IS NULL OR d.ObjectName LIKE '%' + @ObjectName + '%')
      AND (@EventType IS NULL OR d.EventType = @EventType)
      AND (@EventCategory IS NULL OR d.EventCategory = @EventCategory)
      AND (@MinImpactScore IS NULL OR d.ImpactScore >= @MinImpactScore)
    ORDER BY d.EventTime DESC;
END
GO

PRINT 'Created procedure: dbo.usp_GetDDLAuditTrail';
GO

-- =====================================================
-- SECTION 7: Get DDL Activity by User
-- =====================================================

CREATE OR ALTER PROCEDURE dbo.usp_GetDDLActivityByUser
    @StartTime          DATETIME2(7) = NULL,
    @EndTime            DATETIME2(7) = NULL,
    @MinEvents          INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @StartTime IS NULL SET @StartTime = DATEADD(DAY, -30, SYSUTCDATETIME());
    IF @EndTime IS NULL SET @EndTime = SYSUTCDATETIME();

    SELECT
        d.LoginName,
        COUNT(*) AS TotalDDLEvents,
        COUNT(DISTINCT d.ServerID) AS ServersAffected,
        COUNT(DISTINCT d.DatabaseName) AS DatabasesAffected,
        COUNT(DISTINCT d.ObjectName) AS ObjectsAffected,
        MIN(d.EventTime) AS FirstActivity,
        MAX(d.EventTime) AS LastActivity,
        SUM(CASE WHEN d.EventCategory = 'TABLE' THEN 1 ELSE 0 END) AS TableChanges,
        SUM(CASE WHEN d.EventCategory = 'INDEX' THEN 1 ELSE 0 END) AS IndexChanges,
        SUM(CASE WHEN d.EventCategory = 'PROCEDURE' THEN 1 ELSE 0 END) AS ProcedureChanges,
        SUM(CASE WHEN d.EventCategory IN ('USER', 'ROLE', 'PERMISSION') THEN 1 ELSE 0 END) AS SecurityChanges,
        SUM(CASE WHEN d.ImpactSeverity IN ('High', 'Critical') THEN 1 ELSE 0 END) AS HighImpactChanges,
        AVG(ISNULL(d.ImpactScore, 0)) AS AvgImpactScore,
        COUNT(DISTINCT d.HostName) AS UniqueHosts,
        COUNT(DISTINCT d.ApplicationName) AS UniqueApplications
    FROM dbo.DDLAuditEvents d
    WHERE d.EventTime >= @StartTime
      AND d.EventTime <= @EndTime
    GROUP BY d.LoginName
    HAVING COUNT(*) >= @MinEvents
    ORDER BY TotalDDLEvents DESC;
END
GO

PRINT 'Created procedure: dbo.usp_GetDDLActivityByUser';
GO

-- =====================================================
-- SECTION 8: Detect DDL Anomalies
-- =====================================================

CREATE OR ALTER PROCEDURE dbo.usp_DetectDDLAnomalies
    @LookbackDays       INT = 7,
    @BaselineDays       INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LookbackStart DATETIME2(7) = DATEADD(DAY, -@LookbackDays, SYSUTCDATETIME());
    DECLARE @BaselineStart DATETIME2(7) = DATEADD(DAY, -@BaselineDays - @LookbackDays, SYSUTCDATETIME());
    DECLARE @BaselineEnd DATETIME2(7) = @LookbackStart;

    -- Anomaly detection results
    SELECT
        LoginName,
        AnomalyType,
        Severity,
        Details,
        RecentCount,
        BaselineAvg,
        DeviationPercent
    FROM (
        -- Anomaly 1: Unusual volume of DDL events per user
        SELECT
            d.LoginName,
            'HIGH_DDL_VOLUME' AS AnomalyType,
            CASE
                WHEN recentCount > baselineAvg * 5 THEN 'Critical'
                WHEN recentCount > baselineAvg * 3 THEN 'High'
                WHEN recentCount > baselineAvg * 2 THEN 'Medium'
                ELSE 'Low'
            END AS Severity,
            'User performed ' + CAST(recentCount AS VARCHAR) + ' DDL operations vs baseline avg of ' +
                CAST(CAST(baselineAvg AS INT) AS VARCHAR) AS Details,
            recentCount AS RecentCount,
            baselineAvg AS BaselineAvg,
            CASE WHEN baselineAvg > 0 THEN ((recentCount - baselineAvg) / baselineAvg) * 100 ELSE 100 END AS DeviationPercent
        FROM (
            SELECT
                LoginName,
                (SELECT COUNT(*) FROM dbo.DDLAuditEvents
                 WHERE LoginName = d.LoginName AND EventTime >= @LookbackStart) AS recentCount,
                (SELECT COUNT(*) * 1.0 / NULLIF(@BaselineDays, 0) * @LookbackDays
                 FROM dbo.DDLAuditEvents
                 WHERE LoginName = d.LoginName
                   AND EventTime >= @BaselineStart AND EventTime < @BaselineEnd) AS baselineAvg
            FROM dbo.DDLAuditEvents d
            WHERE d.EventTime >= @LookbackStart
            GROUP BY d.LoginName
        ) userStats
        WHERE recentCount > baselineAvg * 2 OR (baselineAvg = 0 AND recentCount > 10)

        UNION ALL

        -- Anomaly 2: High-impact DDL events
        SELECT
            d.LoginName,
            'HIGH_IMPACT_DDL' AS AnomalyType,
            'High' AS Severity,
            'DDL event with impact score ' + CAST(d.ImpactScore AS VARCHAR) + ': ' + d.EventType + ' on ' + d.ObjectName AS Details,
            1 AS RecentCount,
            0 AS BaselineAvg,
            100 AS DeviationPercent
        FROM dbo.DDLAuditEvents d
        WHERE d.EventTime >= @LookbackStart
          AND d.ImpactScore >= 50

        UNION ALL

        -- Anomaly 3: DDL from unusual host/application
        SELECT
            d.LoginName,
            'UNUSUAL_SOURCE' AS AnomalyType,
            'Medium' AS Severity,
            'DDL from new source: ' + ISNULL(d.HostName, 'Unknown') + '/' + ISNULL(d.ApplicationName, 'Unknown') AS Details,
            1 AS RecentCount,
            0 AS BaselineAvg,
            100 AS DeviationPercent
        FROM dbo.DDLAuditEvents d
        WHERE d.EventTime >= @LookbackStart
          AND NOT EXISTS (
              SELECT 1 FROM dbo.DDLAuditEvents b
              WHERE b.LoginName = d.LoginName
                AND b.HostName = d.HostName
                AND b.ApplicationName = d.ApplicationName
                AND b.EventTime >= @BaselineStart
                AND b.EventTime < @BaselineEnd
          )

        UNION ALL

        -- Anomaly 4: After-hours DDL activity
        SELECT
            d.LoginName,
            'AFTER_HOURS_DDL' AS AnomalyType,
            'Medium' AS Severity,
            'DDL performed at ' + FORMAT(d.EventTime, 'HH:mm') + ' UTC: ' + d.EventType + ' on ' + ISNULL(d.ObjectName, 'N/A') AS Details,
            1 AS RecentCount,
            0 AS BaselineAvg,
            100 AS DeviationPercent
        FROM dbo.DDLAuditEvents d
        WHERE d.EventTime >= @LookbackStart
          AND (DATEPART(HOUR, d.EventTime) < 6 OR DATEPART(HOUR, d.EventTime) > 22)  -- Outside 6 AM - 10 PM
          AND d.IsAutomated = 0  -- Not automated/scheduled

        UNION ALL

        -- Anomaly 5: Rapid-fire DDL (many changes in short time)
        SELECT
            d.LoginName,
            'RAPID_FIRE_DDL' AS AnomalyType,
            'High' AS Severity,
            'Made ' + CAST(COUNT(*) AS VARCHAR) + ' DDL changes within 5 minutes on database ' + d.DatabaseName AS Details,
            COUNT(*) AS RecentCount,
            5 AS BaselineAvg,
            ((COUNT(*) - 5.0) / 5.0) * 100 AS DeviationPercent
        FROM dbo.DDLAuditEvents d
        WHERE d.EventTime >= @LookbackStart
        GROUP BY d.LoginName, d.DatabaseName, DATEADD(MINUTE, DATEDIFF(MINUTE, 0, d.EventTime) / 5 * 5, 0)
        HAVING COUNT(*) > 10

    ) anomalies
    ORDER BY
        CASE Severity
            WHEN 'Critical' THEN 1
            WHEN 'High' THEN 2
            WHEN 'Medium' THEN 3
            ELSE 4
        END,
        DeviationPercent DESC;
END
GO

PRINT 'Created procedure: dbo.usp_DetectDDLAnomalies';
GO

-- =====================================================
-- SECTION 9: SQL Agent Job for DDL Impact Analysis
-- =====================================================

-- Create job to run impact analysis every 15 minutes
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SQL Monitor - DDL Impact Analysis')
BEGIN
    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQL Monitor - DDL Impact Analysis',
        @enabled = 1,
        @description = N'Analyzes DDL events and correlates them with performance metrics to detect impact',
        @category_name = N'Database Maintenance',
        @owner_login_name = N'sa';

    EXEC msdb.dbo.sp_add_jobstep
        @job_name = N'SQL Monitor - DDL Impact Analysis',
        @step_name = N'Analyze DDL Impact',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC dbo.usp_AnalyzeDDLImpact @BaselineMinutes = 60, @ImpactMinutes = 60, @MinConfidenceScore = 50;',
        @database_name = N'MonitoringDB',
        @on_success_action = 1,
        @on_fail_action = 2;

    EXEC msdb.dbo.sp_add_jobschedule
        @job_name = N'SQL Monitor - DDL Impact Analysis',
        @name = N'Every 15 minutes',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 15,
        @active_start_time = 0;

    EXEC msdb.dbo.sp_add_jobserver
        @job_name = N'SQL Monitor - DDL Impact Analysis',
        @server_name = N'(local)';

    PRINT 'Created SQL Agent job: SQL Monitor - DDL Impact Analysis';
END
GO

PRINT 'DDL Audit Infrastructure created successfully!';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Deploy DDL trigger on each monitored server (see 95-deploy-ddl-trigger-template.sql)';
PRINT '2. Create Grafana dashboard for DDL audit visualization';
PRINT '3. Configure alerting rules for high-impact DDL events';
GO
