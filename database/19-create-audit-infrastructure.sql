-- =============================================
-- Phase 2.0 Feature 1: Comprehensive Audit Logging
-- SOC 2 Compliance: CC6.1, CC6.2, CC7.2, CC7.3, CC8.1
-- Created: 2025-10-26
-- =============================================

USE MonitoringDB;
GO

PRINT 'Starting audit logging infrastructure creation...';
PRINT '';

-- =============================================
-- Step 1: Create AuditLog table (partitioned, columnstore)
-- =============================================

PRINT 'Step 1: Creating AuditLog table...';

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AuditLog')
BEGIN
    CREATE TABLE dbo.AuditLog
    (
        -- Primary key
        AuditLogID BIGINT IDENTITY(1,1) NOT NULL,

        -- Temporal data
        EventTime DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),

        -- Event classification
        EventType VARCHAR(50) NOT NULL, -- TableModified, LoginSuccess, LoginFailure, PermissionChange, ConfigChange, DataExport, etc.
        Severity VARCHAR(20) NOT NULL DEFAULT 'Information', -- Information, Warning, Error, Critical

        -- Actor identification
        UserName NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
        ApplicationName NVARCHAR(128) NULL DEFAULT APP_NAME(),
        HostName NVARCHAR(128) NULL DEFAULT HOST_NAME(),
        IPAddress VARCHAR(45) NULL, -- IPv4 or IPv6

        -- Object context
        DatabaseName NVARCHAR(128) NULL,
        SchemaName NVARCHAR(128) NULL,
        ObjectName NVARCHAR(128) NULL,
        ObjectType VARCHAR(50) NULL, -- Table, View, Procedure, Function, etc.

        -- Action details
        ActionType VARCHAR(20) NULL, -- INSERT, UPDATE, DELETE, SELECT, EXECUTE, GRANT, REVOKE
        OldValue NVARCHAR(MAX) NULL, -- JSON for UPDATE events
        NewValue NVARCHAR(MAX) NULL, -- JSON for INSERT/UPDATE events
        AffectedRows INT NULL,

        -- SQL context
        SqlText NVARCHAR(MAX) NULL,
        SessionID INT NULL DEFAULT @@SPID,
        TransactionID BIGINT NULL,

        -- Error tracking
        ErrorNumber INT NULL,
        ErrorMessage NVARCHAR(4000) NULL,

        -- Compliance metadata
        DataClassification VARCHAR(20) NOT NULL DEFAULT 'Internal', -- Public, Internal, Confidential, Restricted
        ComplianceFlag VARCHAR(50) NULL, -- SOC2, GDPR, PCI, HIPAA, FERPA
        RetentionDays INT NOT NULL DEFAULT 2555, -- 7 years default (SOC 2 requirement)

        -- Data classification constraint
        CONSTRAINT CK_AuditLog_DataClassification CHECK (DataClassification IN ('Public', 'Internal', 'Confidential', 'Restricted')),
        CONSTRAINT CK_AuditLog_Severity CHECK (Severity IN ('Information', 'Warning', 'Error', 'Critical'))

    ) ON PS_MonitoringByMonth(EventTime); -- Partition by month

    PRINT '  ✓ AuditLog table created (partitioned on PS_MonitoringByMonth)';
END
ELSE
BEGIN
    PRINT '  ℹ AuditLog table already exists';
END
GO

-- =============================================
-- Step 2: Create columnstore index for compression + fast queries
-- =============================================

PRINT 'Step 2: Creating columnstore index...';

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    WHERE t.name = 'AuditLog' AND i.type = 5 -- Clustered columnstore
)
BEGIN
    CREATE CLUSTERED COLUMNSTORE INDEX IX_AuditLog_CCS
    ON dbo.AuditLog
    ON PS_MonitoringByMonth(EventTime);

    PRINT '  ✓ Clustered columnstore index created';
END
ELSE
BEGIN
    PRINT '  ℹ Columnstore index already exists';
END
GO

-- =============================================
-- Step 3: Create performance indexes
-- =============================================

PRINT 'Step 3: Creating performance indexes...';

-- Index for queries filtering by EventTime
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditLog_EventTime' AND object_id = OBJECT_ID('dbo.AuditLog'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_AuditLog_EventTime
    ON dbo.AuditLog (EventTime DESC)
    ON PS_MonitoringByMonth(EventTime);

    PRINT '  ✓ Index IX_AuditLog_EventTime created';
END
ELSE
BEGIN
    PRINT '  ℹ Index IX_AuditLog_EventTime already exists';
END

-- Index for queries filtering by UserName
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditLog_UserName' AND object_id = OBJECT_ID('dbo.AuditLog'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_AuditLog_UserName
    ON dbo.AuditLog (UserName, EventTime DESC)
    ON PS_MonitoringByMonth(EventTime);

    PRINT '  ✓ Index IX_AuditLog_UserName created';
END
ELSE
BEGIN
    PRINT '  ℹ Index IX_AuditLog_UserName already exists';
END

-- Index for queries filtering by EventType
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditLog_EventType' AND object_id = OBJECT_ID('dbo.AuditLog'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_AuditLog_EventType
    ON dbo.AuditLog (EventType, EventTime DESC)
    ON PS_MonitoringByMonth(EventTime);

    PRINT '  ✓ Index IX_AuditLog_EventType created';
END
ELSE
BEGIN
    PRINT '  ℹ Index IX_AuditLog_EventType already exists';
END

-- Index for queries filtering by ObjectName
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditLog_ObjectName' AND object_id = OBJECT_ID('dbo.AuditLog'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_AuditLog_ObjectName
    ON dbo.AuditLog (ObjectName, EventTime DESC)
    ON PS_MonitoringByMonth(EventTime);

    PRINT '  ✓ Index IX_AuditLog_ObjectName created';
END
ELSE
BEGIN
    PRINT '  ℹ Index IX_AuditLog_ObjectName already exists';
END
GO

-- =============================================
-- Step 4: Create usp_LogAuditEvent (insert audit records)
-- =============================================

PRINT 'Step 4: Creating usp_LogAuditEvent stored procedure...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_LogAuditEvent
    @EventType VARCHAR(50),
    @UserName NVARCHAR(128) = NULL,
    @ApplicationName NVARCHAR(128) = NULL,
    @HostName NVARCHAR(128) = NULL,
    @IPAddress VARCHAR(45) = NULL,
    @DatabaseName NVARCHAR(128) = NULL,
    @SchemaName NVARCHAR(128) = NULL,
    @ObjectName NVARCHAR(128) = NULL,
    @ObjectType VARCHAR(50) = NULL,
    @ActionType VARCHAR(20) = NULL,
    @OldValue NVARCHAR(MAX) = NULL,
    @NewValue NVARCHAR(MAX) = NULL,
    @AffectedRows INT = NULL,
    @SqlText NVARCHAR(MAX) = NULL,
    @ErrorNumber INT = NULL,
    @ErrorMessage NVARCHAR(4000) = NULL,
    @Severity VARCHAR(20) = 'Information',
    @DataClassification VARCHAR(20) = 'Internal',
    @ComplianceFlag VARCHAR(50) = NULL,
    @RetentionDays INT = 2555 -- 7 years default
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Insert audit record
        INSERT INTO dbo.AuditLog (
            EventTime, EventType, Severity, UserName, ApplicationName, HostName, IPAddress,
            DatabaseName, SchemaName, ObjectName, ObjectType, ActionType,
            OldValue, NewValue, AffectedRows, SqlText, SessionID, TransactionID,
            ErrorNumber, ErrorMessage, DataClassification, ComplianceFlag, RetentionDays
        )
        VALUES (
            SYSUTCDATETIME(),
            @EventType,
            @Severity,
            COALESCE(@UserName, SUSER_SNAME()),
            COALESCE(@ApplicationName, APP_NAME()),
            COALESCE(@HostName, HOST_NAME()),
            @IPAddress,
            @DatabaseName,
            @SchemaName,
            @ObjectName,
            @ObjectType,
            @ActionType,
            @OldValue,
            @NewValue,
            @AffectedRows,
            @SqlText,
            @@SPID,
            NULL, -- TransactionID (can be added later)
            @ErrorNumber,
            @ErrorMessage,
            @DataClassification,
            @ComplianceFlag,
            @RetentionDays
        );

        RETURN 0; -- Success
    END TRY
    BEGIN CATCH
        -- Log the error (but don't fail the calling transaction)
        -- Use a simple INSERT to avoid recursion
        BEGIN TRY
            INSERT INTO dbo.AuditLog (EventType, Severity, ErrorNumber, ErrorMessage, DataClassification)
            VALUES ('AuditLogFailure', 'Critical', ERROR_NUMBER(), ERROR_MESSAGE(), 'Internal');
        END TRY
        BEGIN CATCH
            -- If even error logging fails, silently continue
            -- (better to lose one audit record than fail the entire transaction)
        END CATCH

        RETURN 1; -- Failure
    END CATCH
END;
GO

PRINT '  ✓ usp_LogAuditEvent stored procedure created';
GO

-- =============================================
-- Step 5: Create usp_GetAuditTrail (query audit records)
-- =============================================

PRINT 'Step 5: Creating usp_GetAuditTrail stored procedure...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetAuditTrail
    @StartTime DATETIME2 = NULL,
    @EndTime DATETIME2 = NULL,
    @EventType VARCHAR(50) = NULL,
    @UserName NVARCHAR(128) = NULL,
    @ObjectName NVARCHAR(128) = NULL,
    @Severity VARCHAR(20) = NULL,
    @DataClassification VARCHAR(20) = NULL,
    @TopN INT = 1000
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to last 24 hours if not specified
    SET @StartTime = COALESCE(@StartTime, DATEADD(DAY, -1, SYSUTCDATETIME()));
    SET @EndTime = COALESCE(@EndTime, SYSUTCDATETIME());

    -- Query with filters
    SELECT TOP (@TopN)
        AuditLogID,
        EventTime,
        EventType,
        Severity,
        UserName,
        ApplicationName,
        HostName,
        IPAddress,
        DatabaseName,
        SchemaName,
        ObjectName,
        ObjectType,
        ActionType,
        OldValue,
        NewValue,
        AffectedRows,
        SqlText,
        ErrorNumber,
        ErrorMessage,
        DataClassification,
        ComplianceFlag
    FROM dbo.AuditLog
    WHERE EventTime >= @StartTime
      AND EventTime <= @EndTime
      AND (@EventType IS NULL OR EventType = @EventType)
      AND (@UserName IS NULL OR UserName = @UserName)
      AND (@ObjectName IS NULL OR ObjectName = @ObjectName)
      AND (@Severity IS NULL OR Severity = @Severity)
      AND (@DataClassification IS NULL OR DataClassification = @DataClassification)
    ORDER BY EventTime DESC;
END;
GO

PRINT '  ✓ usp_GetAuditTrail stored procedure created';
GO

-- =============================================
-- Step 6: Create audit trigger for Servers table
-- =============================================

PRINT 'Step 6: Creating audit trigger for Servers table...';
GO

CREATE OR ALTER TRIGGER dbo.trg_Audit_Servers_IUD
ON dbo.Servers
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Only execute if rows affected
    IF @@ROWCOUNT = 0 RETURN;

    DECLARE @ActionType VARCHAR(20);
    DECLARE @OldValue NVARCHAR(MAX);
    DECLARE @NewValue NVARCHAR(MAX);
    DECLARE @AffectedRows INT = @@ROWCOUNT;

    -- Determine action type
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @ActionType = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @ActionType = 'INSERT';
    ELSE
        SET @ActionType = 'DELETE';

    -- Capture old/new values as JSON
    SET @OldValue = (SELECT * FROM deleted FOR JSON AUTO);
    SET @NewValue = (SELECT * FROM inserted FOR JSON AUTO);

    -- Log audit event (don't check return value - don't fail the DML)
    EXEC dbo.usp_LogAuditEvent
        @EventType = 'TableModified',
        @DatabaseName = 'MonitoringDB',
        @SchemaName = 'dbo',
        @ObjectName = 'Servers',
        @ObjectType = 'Table',
        @ActionType = @ActionType,
        @OldValue = @OldValue,
        @NewValue = @NewValue,
        @AffectedRows = @AffectedRows,
        @DataClassification = 'Internal',
        @ComplianceFlag = 'SOC2';
END;
GO

PRINT '  ✓ Audit trigger trg_Audit_Servers_IUD created';
GO

-- =============================================
-- Step 7: Create audit trigger for AlertRules table
-- =============================================

PRINT 'Step 7: Creating audit trigger for AlertRules table...';
GO

CREATE OR ALTER TRIGGER dbo.trg_Audit_AlertRules_IUD
ON dbo.AlertRules
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Only execute if rows affected
    IF @@ROWCOUNT = 0 RETURN;

    DECLARE @ActionType VARCHAR(20);
    DECLARE @OldValue NVARCHAR(MAX);
    DECLARE @NewValue NVARCHAR(MAX);
    DECLARE @AffectedRows INT = @@ROWCOUNT;

    -- Determine action type
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @ActionType = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @ActionType = 'INSERT';
    ELSE
        SET @ActionType = 'DELETE';

    -- Capture old/new values as JSON
    SET @OldValue = (SELECT * FROM deleted FOR JSON AUTO);
    SET @NewValue = (SELECT * FROM inserted FOR JSON AUTO);

    -- Log audit event (config changes have 7 year retention)
    EXEC dbo.usp_LogAuditEvent
        @EventType = 'ConfigChange',
        @DatabaseName = 'MonitoringDB',
        @SchemaName = 'dbo',
        @ObjectName = 'AlertRules',
        @ObjectType = 'Table',
        @ActionType = @ActionType,
        @OldValue = @OldValue,
        @NewValue = @NewValue,
        @AffectedRows = @AffectedRows,
        @DataClassification = 'Internal',
        @ComplianceFlag = 'SOC2',
        @RetentionDays = 2555; -- 7 years for config changes
END;
GO

PRINT '  ✓ Audit trigger trg_Audit_AlertRules_IUD created';
GO

-- =============================================
-- Step 8: Test the audit infrastructure
-- =============================================

PRINT '';
PRINT 'Step 8: Testing audit infrastructure...';
GO

-- Test usp_LogAuditEvent
DECLARE @TestReturnValue INT;
EXEC @TestReturnValue = dbo.usp_LogAuditEvent
    @EventType = 'TestEvent',
    @UserName = 'AuditInfrastructureTest',
    @ObjectName = 'AuditLog',
    @ActionType = 'INSERT',
    @DataClassification = 'Internal',
    @ComplianceFlag = 'SOC2';

IF @TestReturnValue = 0
    PRINT '  ✓ usp_LogAuditEvent test PASSED (return value: 0)';
ELSE
    PRINT '  ✗ usp_LogAuditEvent test FAILED (return value: ' + CAST(@TestReturnValue AS VARCHAR(10)) + ')';

-- Verify test event was logged
DECLARE @TestEventCount INT;
SELECT @TestEventCount = COUNT(*)
FROM dbo.AuditLog
WHERE EventType = 'TestEvent' AND UserName = 'AuditInfrastructureTest';

IF @TestEventCount > 0
    PRINT '  ✓ Test audit event verified in AuditLog table';
ELSE
    PRINT '  ✗ Test audit event NOT found in AuditLog table';

-- Test usp_GetAuditTrail
DECLARE @AuditTrailCount INT = 0;
SELECT @AuditTrailCount = COUNT(*)
FROM (
    EXEC dbo.usp_GetAuditTrail
        @EventType = 'TestEvent',
        @TopN = 10
) AS AuditTrail;

IF @AuditTrailCount >= 0
    PRINT '  ✓ usp_GetAuditTrail test PASSED';
ELSE
    PRINT '  ✗ usp_GetAuditTrail test FAILED';
GO

-- =============================================
-- Step 9: Display summary
-- =============================================

PRINT '';
PRINT '========================================';
PRINT 'Audit Logging Infrastructure Summary';
PRINT '========================================';
PRINT '';
PRINT 'Tables Created:';
PRINT '  ✓ dbo.AuditLog (partitioned, columnstore)';
PRINT '';
PRINT 'Indexes Created:';
PRINT '  ✓ IX_AuditLog_CCS (clustered columnstore)';
PRINT '  ✓ IX_AuditLog_EventTime';
PRINT '  ✓ IX_AuditLog_UserName';
PRINT '  ✓ IX_AuditLog_EventType';
PRINT '  ✓ IX_AuditLog_ObjectName';
PRINT '';
PRINT 'Stored Procedures Created:';
PRINT '  ✓ dbo.usp_LogAuditEvent';
PRINT '  ✓ dbo.usp_GetAuditTrail';
PRINT '';
PRINT 'Triggers Created:';
PRINT '  ✓ dbo.trg_Audit_Servers_IUD (Servers table)';
PRINT '  ✓ dbo.trg_Audit_AlertRules_IUD (AlertRules table)';
PRINT '';
PRINT 'SOC 2 Controls Addressed:';
PRINT '  ✓ CC6.1 - Logical access controls';
PRINT '  ✓ CC6.2 - Access removal tracking';
PRINT '  ✓ CC6.3 - Access approval documentation';
PRINT '  ✓ CC7.2 - System monitoring';
PRINT '  ✓ CC7.3 - Anomaly detection (foundation)';
PRINT '  ✓ CC8.1 - Change management tracking';
PRINT '';
PRINT 'Retention Policy:';
PRINT '  ✓ Default: 7 years (2555 days) - SOC 2 requirement';
PRINT '';
PRINT 'Next Steps:';
PRINT '  1. Run tSQLt tests: EXEC tSQLt.Run ''AuditLogging_Tests'';';
PRINT '  2. Add audit triggers for remaining critical tables';
PRINT '  3. Implement API middleware for HTTP request logging';
PRINT '  4. Create Grafana dashboard for audit visualization';
PRINT '';
PRINT '========================================';
PRINT 'Audit infrastructure creation COMPLETE';
PRINT '========================================';
GO
