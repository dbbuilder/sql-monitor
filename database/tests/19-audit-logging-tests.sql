-- =============================================
-- Phase 2.0 Feature 1: Comprehensive Audit Logging
-- Test Framework: tSQLt
-- SOC 2 Compliance: CC6.1, CC6.2, CC7.2, CC7.3, CC8.1
-- Created: 2025-10-26
-- =============================================

USE [MonitoringDB];
GO

-- =============================================
-- Create test class for audit logging tests
-- =============================================

EXEC tSQLt.NewTestClass 'AuditLogging_Tests';
GO

-- =============================================
-- Test 1: AuditLog table exists with required columns
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test AuditLog table exists with required columns]
AS
BEGIN
    -- Arrange: Expected columns
    DECLARE @ExpectedColumns TABLE (ColumnName NVARCHAR(128));
    INSERT INTO @ExpectedColumns VALUES
        ('AuditLogID'), ('EventTime'), ('EventType'), ('UserName'), ('ApplicationName'),
        ('HostName'), ('IPAddress'), ('DatabaseName'), ('SchemaName'), ('ObjectName'),
        ('ObjectType'), ('ActionType'), ('OldValue'), ('NewValue'), ('AffectedRows'),
        ('SqlText'), ('SessionID'), ('TransactionID'), ('ErrorNumber'), ('ErrorMessage'),
        ('Severity'), ('DataClassification'), ('ComplianceFlag'), ('RetentionDays');

    -- Act: Get actual columns
    DECLARE @ActualColumns TABLE (ColumnName NVARCHAR(128));
    INSERT INTO @ActualColumns
    SELECT COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'AuditLog';

    -- Assert: Check if table exists
    DECLARE @TableExists BIT = 0;
    IF EXISTS (SELECT 1 FROM @ActualColumns)
        SET @TableExists = 1;

    EXEC tSQLt.AssertEquals 1, @TableExists, 'AuditLog table does not exist';

    -- Assert: All expected columns exist
    DECLARE @MissingColumns NVARCHAR(MAX);
    SELECT @MissingColumns = STRING_AGG(e.ColumnName, ', ')
    FROM @ExpectedColumns e
    WHERE NOT EXISTS (SELECT 1 FROM @ActualColumns a WHERE a.ColumnName = e.ColumnName);

    IF @MissingColumns IS NOT NULL
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(500) = 'AuditLog table is missing columns: ' + @MissingColumns;
        EXEC tSQLt.Fail @ErrorMsg;
    END
END;
GO

-- =============================================
-- Test 2: AuditLog is partitioned by month
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test AuditLog is partitioned by month]
AS
BEGIN
    -- Assert: AuditLog uses partition scheme PS_MonitoringByMonth
    DECLARE @IsPartitioned BIT = 0;

    SELECT @IsPartitioned = 1
    FROM sys.indexes i
    INNER JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    WHERE t.name = 'AuditLog' AND ps.name = 'PS_MonitoringByMonth';

    IF @IsPartitioned = 0
    BEGIN
        EXEC tSQLt.Fail 'AuditLog table is not partitioned on PS_MonitoringByMonth';
    END
END;
GO

-- =============================================
-- Test 3: AuditLog has columnstore index for compression
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test AuditLog has columnstore index]
AS
BEGIN
    -- Assert: Clustered columnstore index exists
    DECLARE @HasColumnstore BIT = 0;

    SELECT @HasColumnstore = 1
    FROM sys.indexes i
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    WHERE t.name = 'AuditLog' AND i.type = 5; -- Type 5 = Clustered columnstore

    IF @HasColumnstore = 0
    BEGIN
        EXEC tSQLt.Fail 'AuditLog table does not have a clustered columnstore index';
    END
END;
GO

-- =============================================
-- Test 4: usp_LogAuditEvent stored procedure exists
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test usp_LogAuditEvent procedure exists]
AS
BEGIN
    -- Assert: Stored procedure exists
    DECLARE @ProcExists BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM INFORMATION_SCHEMA.ROUTINES
        WHERE ROUTINE_SCHEMA = 'dbo'
          AND ROUTINE_NAME = 'usp_LogAuditEvent'
          AND ROUTINE_TYPE = 'PROCEDURE'
    )
        SET @ProcExists = 1;

    EXEC tSQLt.AssertEquals 1, @ProcExists, 'usp_LogAuditEvent stored procedure does not exist';
END;
GO

-- =============================================
-- Test 5: usp_LogAuditEvent inserts audit record
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test usp_LogAuditEvent inserts audit record]
AS
BEGIN
    -- Arrange: Fake AuditLog table
    EXEC tSQLt.FakeTable 'dbo', 'AuditLog';

    -- Act: Call usp_LogAuditEvent
    DECLARE @ReturnValue INT;
    EXEC @ReturnValue = dbo.usp_LogAuditEvent
        @EventType = 'TableModified',
        @UserName = 'TestUser',
        @DatabaseName = 'MonitoringDB',
        @ObjectName = 'Servers',
        @ActionType = 'INSERT',
        @AffectedRows = 1,
        @DataClassification = 'Internal',
        @ComplianceFlag = 'SOC2';

    -- Assert: Return value is 0 (success)
    EXEC tSQLt.AssertEquals 0, @ReturnValue, 'usp_LogAuditEvent did not return success (0)';

    -- Assert: Audit record inserted
    DECLARE @RowCount INT;
    SELECT @RowCount = COUNT(*) FROM dbo.AuditLog
    WHERE EventType = 'TableModified' AND UserName = 'TestUser';

    EXEC tSQLt.AssertEquals 1, @RowCount, 'usp_LogAuditEvent did not insert audit record';
END;
GO

-- =============================================
-- Test 6: usp_LogAuditEvent handles errors gracefully
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test usp_LogAuditEvent handles errors gracefully]
AS
BEGIN
    -- Arrange: Fake AuditLog table with constraint to force error
    EXEC tSQLt.FakeTable 'dbo', 'AuditLog';

    -- Create constraint that will fail
    ALTER TABLE dbo.AuditLog ADD CONSTRAINT CK_Test_ForceError CHECK (EventType != 'InvalidEvent');

    -- Act: Call usp_LogAuditEvent with invalid data
    DECLARE @ReturnValue INT;
    EXEC @ReturnValue = dbo.usp_LogAuditEvent
        @EventType = 'InvalidEvent',
        @UserName = 'TestUser';

    -- Assert: Return value is 1 (failure) - procedure should not throw exception
    EXEC tSQLt.AssertEquals 1, @ReturnValue, 'usp_LogAuditEvent should return 1 on error';

    -- Assert: Error was logged to AuditLog (self-audit)
    DECLARE @ErrorLogCount INT;
    SELECT @ErrorLogCount = COUNT(*) FROM dbo.AuditLog
    WHERE EventType = 'AuditLogFailure';

    EXEC tSQLt.AssertGreaterThan 0, @ErrorLogCount, 'usp_LogAuditEvent did not log its own error';
END;
GO

-- =============================================
-- Test 7: Audit trigger exists on Servers table
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test Servers table has audit trigger]
AS
BEGIN
    -- Assert: Trigger trg_Audit_Servers_IUD exists
    DECLARE @TriggerExists BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM sys.triggers t
        INNER JOIN sys.tables tbl ON t.parent_id = tbl.object_id
        WHERE tbl.name = 'Servers'
          AND t.name = 'trg_Audit_Servers_IUD'
    )
        SET @TriggerExists = 1;

    EXEC tSQLt.AssertEquals 1, @TriggerExists, 'Audit trigger trg_Audit_Servers_IUD does not exist on Servers table';
END;
GO

-- =============================================
-- Test 8: Servers audit trigger logs INSERT events
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test Servers audit trigger logs INSERT events]
AS
BEGIN
    -- Arrange: Fake tables
    EXEC tSQLt.FakeTable 'dbo', 'Servers';
    EXEC tSQLt.FakeTable 'dbo', 'AuditLog';
    EXEC tSQLt.ApplyTrigger 'dbo', 'Servers', 'trg_Audit_Servers_IUD';

    -- Act: Insert into Servers
    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES ('TestServer', 'Test', 1);

    -- Assert: Audit record created
    DECLARE @AuditCount INT;
    SELECT @AuditCount = COUNT(*) FROM dbo.AuditLog
    WHERE ObjectName = 'Servers' AND ActionType = 'INSERT';

    EXEC tSQLt.AssertEquals 1, @AuditCount, 'Audit trigger did not log INSERT event';
END;
GO

-- =============================================
-- Test 9: Servers audit trigger logs UPDATE events
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test Servers audit trigger logs UPDATE events]
AS
BEGIN
    -- Arrange: Fake tables
    EXEC tSQLt.FakeTable 'dbo', 'Servers';
    EXEC tSQLt.FakeTable 'dbo', 'AuditLog';
    EXEC tSQLt.ApplyTrigger 'dbo', 'Servers', 'trg_Audit_Servers_IUD';

    -- Insert test data
    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'TestServer', 'Test', 1);

    -- Clear audit log from INSERT
    DELETE FROM dbo.AuditLog;

    -- Act: Update server
    UPDATE dbo.Servers
    SET IsActive = 0
    WHERE ServerID = 1;

    -- Assert: Audit record created with UPDATE action
    DECLARE @AuditCount INT;
    SELECT @AuditCount = COUNT(*) FROM dbo.AuditLog
    WHERE ObjectName = 'Servers' AND ActionType = 'UPDATE';

    EXEC tSQLt.AssertEquals 1, @AuditCount, 'Audit trigger did not log UPDATE event';
END;
GO

-- =============================================
-- Test 10: Servers audit trigger logs DELETE events
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test Servers audit trigger logs DELETE events]
AS
BEGIN
    -- Arrange: Fake tables
    EXEC tSQLt.FakeTable 'dbo', 'Servers';
    EXEC tSQLt.FakeTable 'dbo', 'AuditLog';
    EXEC tSQLt.ApplyTrigger 'dbo', 'Servers', 'trg_Audit_Servers_IUD';

    -- Insert test data
    INSERT INTO dbo.Servers (ServerID, ServerName, Environment, IsActive)
    VALUES (1, 'TestServer', 'Test', 1);

    -- Clear audit log from INSERT
    DELETE FROM dbo.AuditLog;

    -- Act: Delete server
    DELETE FROM dbo.Servers WHERE ServerID = 1;

    -- Assert: Audit record created with DELETE action
    DECLARE @AuditCount INT;
    SELECT @AuditCount = COUNT(*) FROM dbo.AuditLog
    WHERE ObjectName = 'Servers' AND ActionType = 'DELETE';

    EXEC tSQLt.AssertEquals 1, @AuditCount, 'Audit trigger did not log DELETE event';
END;
GO

-- =============================================
-- Test 11: Audit trigger exists on AlertRules table
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test AlertRules table has audit trigger]
AS
BEGIN
    -- Assert: Trigger trg_Audit_AlertRules_IUD exists
    DECLARE @TriggerExists BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM sys.triggers t
        INNER JOIN sys.tables tbl ON t.parent_id = tbl.object_id
        WHERE tbl.name = 'AlertRules'
          AND t.name = 'trg_Audit_AlertRules_IUD'
    )
        SET @TriggerExists = 1;

    EXEC tSQLt.AssertEquals 1, @TriggerExists, 'Audit trigger trg_Audit_AlertRules_IUD does not exist on AlertRules table';
END;
GO

-- =============================================
-- Test 12: usp_GetAuditTrail stored procedure exists
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test usp_GetAuditTrail procedure exists]
AS
BEGIN
    -- Assert: Stored procedure exists
    DECLARE @ProcExists BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM INFORMATION_SCHEMA.ROUTINES
        WHERE ROUTINE_SCHEMA = 'dbo'
          AND ROUTINE_NAME = 'usp_GetAuditTrail'
          AND ROUTINE_TYPE = 'PROCEDURE'
    )
        SET @ProcExists = 1;

    EXEC tSQLt.AssertEquals 1, @ProcExists, 'usp_GetAuditTrail stored procedure does not exist';
END;
GO

-- =============================================
-- Test 13: usp_GetAuditTrail filters by date range
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test usp_GetAuditTrail filters by date range]
AS
BEGIN
    -- Arrange: Fake AuditLog with test data
    EXEC tSQLt.FakeTable 'dbo', 'AuditLog';

    INSERT INTO dbo.AuditLog (EventTime, EventType, UserName, DataClassification)
    VALUES
        ('2025-10-01 10:00:00', 'TableModified', 'User1', 'Internal'),
        ('2025-10-15 10:00:00', 'TableModified', 'User2', 'Internal'),
        ('2025-10-25 10:00:00', 'TableModified', 'User3', 'Internal');

    -- Act: Call usp_GetAuditTrail for Oct 10-20
    CREATE TABLE #Results (
        AuditLogID BIGINT,
        EventTime DATETIME2,
        EventType VARCHAR(50),
        Severity VARCHAR(20),
        UserName NVARCHAR(128),
        ApplicationName NVARCHAR(128),
        HostName NVARCHAR(128),
        IPAddress VARCHAR(45),
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        ObjectName NVARCHAR(128),
        ObjectType VARCHAR(50),
        ActionType VARCHAR(20),
        OldValue NVARCHAR(MAX),
        NewValue NVARCHAR(MAX),
        AffectedRows INT,
        SqlText NVARCHAR(MAX),
        ErrorNumber INT,
        ErrorMessage NVARCHAR(4000),
        DataClassification VARCHAR(20),
        ComplianceFlag VARCHAR(50)
    );

    INSERT INTO #Results
    EXEC dbo.usp_GetAuditTrail
        @StartTime = '2025-10-10',
        @EndTime = '2025-10-20';

    -- Assert: Only User2 returned (within date range)
    DECLARE @ResultCount INT;
    SELECT @ResultCount = COUNT(*) FROM #Results WHERE UserName = 'User2';

    EXEC tSQLt.AssertEquals 1, @ResultCount, 'usp_GetAuditTrail did not filter by date range correctly';

    -- Assert: User1 and User3 NOT returned (outside date range)
    DECLARE @OutsideCount INT;
    SELECT @OutsideCount = COUNT(*) FROM #Results WHERE UserName IN ('User1', 'User3');

    EXEC tSQLt.AssertEquals 0, @OutsideCount, 'usp_GetAuditTrail returned records outside date range';

    DROP TABLE #Results;
END;
GO

-- =============================================
-- Test 14: usp_GetAuditTrail filters by EventType
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test usp_GetAuditTrail filters by EventType]
AS
BEGIN
    -- Arrange: Fake AuditLog with test data
    EXEC tSQLt.FakeTable 'dbo', 'AuditLog';

    INSERT INTO dbo.AuditLog (EventTime, EventType, UserName, DataClassification)
    VALUES
        ('2025-10-25 10:00:00', 'TableModified', 'User1', 'Internal'),
        ('2025-10-25 11:00:00', 'ConfigChange', 'User2', 'Internal'),
        ('2025-10-25 12:00:00', 'TableModified', 'User3', 'Internal');

    -- Act: Call usp_GetAuditTrail for ConfigChange only
    CREATE TABLE #Results (
        AuditLogID BIGINT,
        EventTime DATETIME2,
        EventType VARCHAR(50),
        Severity VARCHAR(20),
        UserName NVARCHAR(128),
        ApplicationName NVARCHAR(128),
        HostName NVARCHAR(128),
        IPAddress VARCHAR(45),
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        ObjectName NVARCHAR(128),
        ObjectType VARCHAR(50),
        ActionType VARCHAR(20),
        OldValue NVARCHAR(MAX),
        NewValue NVARCHAR(MAX),
        AffectedRows INT,
        SqlText NVARCHAR(MAX),
        ErrorNumber INT,
        ErrorMessage NVARCHAR(4000),
        DataClassification VARCHAR(20),
        ComplianceFlag VARCHAR(50)
    );

    INSERT INTO #Results
    EXEC dbo.usp_GetAuditTrail
        @StartTime = '2025-10-25 00:00:00',
        @EventType = 'ConfigChange';

    -- Assert: Only User2 returned (ConfigChange event)
    DECLARE @ResultCount INT;
    SELECT @ResultCount = COUNT(*) FROM #Results;

    EXEC tSQLt.AssertEquals 1, @ResultCount, 'usp_GetAuditTrail did not filter by EventType correctly';

    -- Assert: Correct user returned
    DECLARE @UserName NVARCHAR(128);
    SELECT @UserName = UserName FROM #Results;

    EXEC tSQLt.AssertEqualsString 'User2', @UserName, 'usp_GetAuditTrail returned wrong user for EventType filter';

    DROP TABLE #Results;
END;
GO

-- =============================================
-- Test 15: AuditLog DataClassification has CHECK constraint
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test AuditLog DataClassification has CHECK constraint]
AS
BEGIN
    -- Assert: DataClassification column has CHECK constraint
    DECLARE @HasConstraint BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu
        INNER JOIN INFORMATION_SCHEMA.CHECK_CONSTRAINTS cc ON ccu.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
        WHERE ccu.TABLE_NAME = 'AuditLog' AND ccu.COLUMN_NAME = 'DataClassification'
    )
        SET @HasConstraint = 1;

    EXEC tSQLt.AssertEquals 1, @HasConstraint, 'AuditLog.DataClassification does not have CHECK constraint';
END;
GO

-- =============================================
-- Test 16: AuditLog Severity has CHECK constraint
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test AuditLog Severity has CHECK constraint]
AS
BEGIN
    -- Assert: Severity column has CHECK constraint
    DECLARE @HasConstraint BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu
        INNER JOIN INFORMATION_SCHEMA.CHECK_CONSTRAINTS cc ON ccu.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
        WHERE ccu.TABLE_NAME = 'AuditLog' AND ccu.COLUMN_NAME = 'Severity'
    )
        SET @HasConstraint = 1;

    EXEC tSQLt.AssertEquals 1, @HasConstraint, 'AuditLog.Severity does not have CHECK constraint';
END;
GO

-- =============================================
-- Test 17: High-security events have 7-year retention by default
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test high-security events have 7 year retention]
AS
BEGIN
    -- Arrange: Fake AuditLog
    EXEC tSQLt.FakeTable 'dbo', 'AuditLog';

    -- Act: Insert high-security event via usp_LogAuditEvent
    EXEC dbo.usp_LogAuditEvent
        @EventType = 'PermissionChange',
        @UserName = 'TestUser',
        @DataClassification = 'Restricted';

    -- Assert: Retention is 7 years (2555 days)
    DECLARE @RetentionDays INT;
    SELECT @RetentionDays = RetentionDays FROM dbo.AuditLog
    WHERE EventType = 'PermissionChange';

    EXEC tSQLt.AssertEquals 2555, @RetentionDays, 'High-security events should have 7 year retention (2555 days)';
END;
GO

-- =============================================
-- Test 18: AuditLog has required indexes for performance
-- =============================================

CREATE PROCEDURE AuditLogging_Tests.[test AuditLog has required indexes]
AS
BEGIN
    -- Assert: Index on EventTime exists
    DECLARE @HasEventTimeIndex BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.tables t ON i.object_id = t.object_id
        WHERE t.name = 'AuditLog'
          AND i.name = 'IX_AuditLog_EventTime'
    )
        SET @HasEventTimeIndex = 1;

    EXEC tSQLt.AssertEquals 1, @HasEventTimeIndex, 'AuditLog is missing index IX_AuditLog_EventTime';

    -- Assert: Index on UserName exists
    DECLARE @HasUserNameIndex BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.tables t ON i.object_id = t.object_id
        WHERE t.name = 'AuditLog'
          AND i.name = 'IX_AuditLog_UserName'
    )
        SET @HasUserNameIndex = 1;

    EXEC tSQLt.AssertEquals 1, @HasUserNameIndex, 'AuditLog is missing index IX_AuditLog_UserName';

    -- Assert: Index on EventType exists
    DECLARE @HasEventTypeIndex BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.tables t ON i.object_id = t.object_id
        WHERE t.name = 'AuditLog'
          AND i.name = 'IX_AuditLog_EventType'
    )
        SET @HasEventTypeIndex = 1;

    EXEC tSQLt.AssertEquals 1, @HasEventTypeIndex, 'AuditLog is missing index IX_AuditLog_EventType';
END;
GO

-- =============================================
-- Summary: Print test class info
-- =============================================

PRINT 'AuditLogging_Tests test class created successfully';
PRINT 'Total tests: 18';
PRINT '';
PRINT 'Test categories:';
PRINT '  - Schema validation: 6 tests (table structure, partitioning, indexes)';
PRINT '  - Stored procedures: 6 tests (usp_LogAuditEvent, usp_GetAuditTrail)';
PRINT '  - Audit triggers: 5 tests (Servers, AlertRules)';
PRINT '  - Data integrity: 1 test (CHECK constraints)';
PRINT '';
PRINT 'Run all tests: EXEC tSQLt.Run ''AuditLogging_Tests'';';
PRINT 'Run specific test: EXEC tSQLt.Run ''AuditLogging_Tests'', ''[test AuditLog table exists with required columns]'';';
GO
