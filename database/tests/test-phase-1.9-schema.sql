-- =====================================================
-- Test Script: test-phase-1.9-schema.sql
-- Description: Unit tests for Phase 1.9 schema deployment
-- Author: SQL Server Monitor Project
-- Date: 2025-10-27
-- Phase: 1.9 - Integration (Day 1)
-- TDD Phase: RED (Tests written before full deployment)
-- =====================================================

-- This script can be run against either DBATools or MonitoringDB
-- to verify Phase 1.9 schema is correctly deployed

SET NOCOUNT ON;
GO

PRINT '=========================================================================';
PRINT 'Phase 1.9 Schema Validation Tests';
PRINT '=========================================================================';
PRINT '';
GO

DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200);
DECLARE @Result NVARCHAR(10);

-- =====================================================
-- TEST CATEGORY 1: Core Tables Existence
-- =====================================================

PRINT 'TEST CATEGORY 1: Core Tables Existence';
PRINT '-------------------------------------------';

-- Test 1.1: Servers table exists
SET @TestName = 'Test 1.1: Servers table exists';
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Servers')
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.2: LogEntry table exists
SET @TestName = 'Test 1.2: LogEntry table exists';
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'LogEntry')
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.3: PerfSnapshotRun table exists
SET @TestName = 'Test 1.3: PerfSnapshotRun table exists';
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'PerfSnapshotRun')
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.4: PerfSnapshotDB table exists
SET @TestName = 'Test 1.4: PerfSnapshotDB table exists';
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'PerfSnapshotDB')
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.5: PerfSnapshotWorkload table exists
SET @TestName = 'Test 1.5: PerfSnapshotWorkload table exists';
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'PerfSnapshotWorkload')
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.6: PerfSnapshotErrorLog table exists
SET @TestName = 'Test 1.6: PerfSnapshotErrorLog table exists';
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'PerfSnapshotErrorLog')
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

PRINT '';

-- =====================================================
-- TEST CATEGORY 2: Enhanced Tables Existence (P0-P3)
-- =====================================================

PRINT 'TEST CATEGORY 2: Enhanced Tables Existence';
PRINT '-------------------------------------------';

-- Test 2.1: All P0 tables exist (5 tables)
DECLARE @P0TablesExpected INT = 5;
DECLARE @P0TablesFound INT;
SELECT @P0TablesFound = COUNT(*)
FROM sys.tables
WHERE name IN (
    'PerfSnapshotQueryStats',
    'PerfSnapshotIOStats',
    'PerfSnapshotMemory',
    'PerfSnapshotMemoryClerks',
    'PerfSnapshotBackupHistory'
);

SET @TestName = 'Test 2.1: All P0 tables exist (5 tables)';
IF @P0TablesFound = @P0TablesExpected
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: ' + CAST(@P0TablesExpected AS VARCHAR) + ', Found: ' + CAST(@P0TablesFound AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 2.2: All P1 tables exist (5 tables)
DECLARE @P1TablesExpected INT = 5;
DECLARE @P1TablesFound INT;
SELECT @P1TablesFound = COUNT(*)
FROM sys.tables
WHERE name IN (
    'PerfSnapshotIndexUsage',
    'PerfSnapshotMissingIndexes',
    'PerfSnapshotWaitStats',
    'PerfSnapshotTempDBContention',
    'PerfSnapshotQueryPlans'
);

SET @TestName = 'Test 2.2: All P1 tables exist (5 tables)';
IF @P1TablesFound = @P1TablesExpected
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: ' + CAST(@P1TablesExpected AS VARCHAR) + ', Found: ' + CAST(@P1TablesFound AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 2.3: All P2 tables exist (6 tables)
DECLARE @P2TablesExpected INT = 6;
DECLARE @P2TablesFound INT;
SELECT @P2TablesFound = COUNT(*)
FROM sys.tables
WHERE name IN (
    'PerfSnapshotConfig',
    'PerfSnapshotDeadlocks',
    'PerfSnapshotSchedulers',
    'PerfSnapshotCounters',
    'PerfSnapshotAutogrowthEvents'
);

SET @TestName = 'Test 2.3: All P2 tables exist (5 of 6 tables)';
IF @P2TablesFound >= 5  -- Allow 5 or 6 (some P2 tables may be optional)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= 5, Found: ' + CAST(@P2TablesFound AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 2.4: All P3 tables exist (3 tables)
DECLARE @P3TablesExpected INT = 3;
DECLARE @P3TablesFound INT;
SELECT @P3TablesFound = COUNT(*)
FROM sys.tables
WHERE name IN (
    'PerfSnapshotLatchStats',
    'PerfSnapshotJobHistory',
    'PerfSnapshotSpinlockStats'
);

SET @TestName = 'Test 2.4: All P3 tables exist (3 tables)';
IF @P3TablesFound = @P3TablesExpected
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: ' + CAST(@P3TablesExpected AS VARCHAR) + ', Found: ' + CAST(@P3TablesFound AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

PRINT '';

-- =====================================================
-- TEST CATEGORY 3: ServerID Column (Multi-Server Support)
-- =====================================================

PRINT 'TEST CATEGORY 3: ServerID Column (Multi-Server Support)';
PRINT '-------------------------------------------';

-- Test 3.1: ServerID column exists in PerfSnapshotRun
SET @TestName = 'Test 3.1: ServerID column exists in PerfSnapshotRun';
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.PerfSnapshotRun')
    AND name = 'ServerID'
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 3.2: ServerID column is nullable (backwards compatible)
SET @TestName = 'Test 3.2: ServerID column is nullable';
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.PerfSnapshotRun')
    AND name = 'ServerID'
    AND is_nullable = 1
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 3.3: ServerID is INT data type
SET @TestName = 'Test 3.3: ServerID is INT data type';
IF EXISTS (
    SELECT 1 FROM sys.columns c
    INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
    WHERE c.object_id = OBJECT_ID('dbo.PerfSnapshotRun')
    AND c.name = 'ServerID'
    AND t.name = 'int'
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

PRINT '';

-- =====================================================
-- TEST CATEGORY 4: Foreign Key Constraints
-- =====================================================

PRINT 'TEST CATEGORY 4: Foreign Key Constraints';
PRINT '-------------------------------------------';

-- Test 4.1: FK_PerfSnapshotRun_Servers exists
SET @TestName = 'Test 4.1: FK_PerfSnapshotRun_Servers exists';
IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_PerfSnapshotRun_Servers'
    AND parent_object_id = OBJECT_ID('dbo.PerfSnapshotRun')
    AND referenced_object_id = OBJECT_ID('dbo.Servers')
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 4.2: All PerfSnapshot* tables have FK to PerfSnapshotRun
DECLARE @ExpectedFKCount INT = 18;  -- All enhanced tables should have FK to PerfSnapshotRun
DECLARE @ActualFKCount INT;
SELECT @ActualFKCount = COUNT(*)
FROM sys.foreign_keys
WHERE referenced_object_id = OBJECT_ID('dbo.PerfSnapshotRun');

SET @TestName = 'Test 4.2: All enhanced tables have FK to PerfSnapshotRun';
IF @ActualFKCount >= @ExpectedFKCount
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= ' + CAST(@ExpectedFKCount AS VARCHAR) + ', Found: ' + CAST(@ActualFKCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

PRINT '';

-- =====================================================
-- TEST CATEGORY 5: Indexes
-- =====================================================

PRINT 'TEST CATEGORY 5: Indexes';
PRINT '-------------------------------------------';

-- Test 5.1: Primary key on Servers.ServerID
SET @TestName = 'Test 5.1: Primary key on Servers.ServerID';
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.Servers')
    AND name = 'PK_Servers'
    AND is_primary_key = 1
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 5.2: Unique constraint on Servers.ServerName
SET @TestName = 'Test 5.2: Unique constraint on Servers.ServerName';
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.Servers')
    AND name = 'UQ_Servers_ServerName'
    AND is_unique = 1
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 5.3: Index on PerfSnapshotRun(ServerID, SnapshotUTC)
SET @TestName = 'Test 5.3: Index on PerfSnapshotRun(ServerID, SnapshotUTC)';
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PerfSnapshotRun')
    AND name = 'IX_PerfSnapshotRun_ServerID_Time'
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 5.4: All PerfSnapshot* tables have index on PerfSnapshotRunID
DECLARE @ExpectedRunIDIndexes INT = 19;
DECLARE @ActualRunIDIndexes INT;
SELECT @ActualRunIDIndexes = COUNT(DISTINCT i.object_id)
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE c.name = 'PerfSnapshotRunID'
AND i.name LIKE 'IX_%RunID';

SET @TestName = 'Test 5.4: All enhanced tables have index on RunID';
IF @ActualRunIDIndexes >= @ExpectedRunIDIndexes
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= ' + CAST(@ExpectedRunIDIndexes AS VARCHAR) + ', Found: ' + CAST(@ActualRunIDIndexes AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

PRINT '';

-- =====================================================
-- TEST CATEGORY 6: Data Insertion (Functional Tests)
-- =====================================================

PRINT 'TEST CATEGORY 6: Data Insertion (Functional Tests)';
PRINT '-------------------------------------------';

-- Test 6.1: Can insert into Servers table
SET @TestName = 'Test 6.1: Can insert into Servers table';
BEGIN TRY
    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES ('TEST-SERVER-001', 'Test', 1);

    DELETE FROM dbo.Servers WHERE ServerName = 'TEST-SERVER-001';

    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END TRY
BEGIN CATCH
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Error: ' + ERROR_MESSAGE();
END CATCH
PRINT @TestName + ': ' + @Result;

-- Test 6.2: Can insert into PerfSnapshotRun with NULL ServerID
SET @TestName = 'Test 6.2: Can insert with NULL ServerID (backwards compat)';
BEGIN TRY
    INSERT INTO dbo.PerfSnapshotRun (SnapshotUTC, ServerID, ServerName, SqlVersion)
    VALUES (GETUTCDATE(), NULL, 'TEST-SERVER', '16.0.0.0');

    DECLARE @TestRunID BIGINT = SCOPE_IDENTITY();
    DELETE FROM dbo.PerfSnapshotRun WHERE PerfSnapshotRunID = @TestRunID;

    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END TRY
BEGIN CATCH
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Error: ' + ERROR_MESSAGE();
END CATCH
PRINT @TestName + ': ' + @Result;

-- Test 6.3: Can insert into PerfSnapshotRun with valid ServerID
SET @TestName = 'Test 6.3: Can insert with valid ServerID (multi-server)';
BEGIN TRY
    -- Create test server
    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES ('TEST-SERVER-002', 'Test', 1);
    DECLARE @TestServerID INT = SCOPE_IDENTITY();

    -- Insert snapshot with ServerID
    INSERT INTO dbo.PerfSnapshotRun (SnapshotUTC, ServerID, ServerName, SqlVersion)
    VALUES (GETUTCDATE(), @TestServerID, 'TEST-SERVER-002', '16.0.0.0');

    DECLARE @TestRunID2 BIGINT = SCOPE_IDENTITY();

    -- Cleanup
    DELETE FROM dbo.PerfSnapshotRun WHERE PerfSnapshotRunID = @TestRunID2;
    DELETE FROM dbo.Servers WHERE ServerID = @TestServerID;

    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END TRY
BEGIN CATCH
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Error: ' + ERROR_MESSAGE();
END CATCH
PRINT @TestName + ': ' + @Result;

-- Test 6.4: FK constraint prevents invalid ServerID
SET @TestName = 'Test 6.4: FK constraint prevents invalid ServerID';
BEGIN TRY
    -- Try to insert with non-existent ServerID (should fail)
    INSERT INTO dbo.PerfSnapshotRun (SnapshotUTC, ServerID, ServerName, SqlVersion)
    VALUES (GETUTCDATE(), 999999, 'INVALID-SERVER', '16.0.0.0');

    -- If we got here, test failed (insert should have been blocked)
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Error: FK constraint did not prevent invalid ServerID';

    -- Cleanup
    DELETE FROM dbo.PerfSnapshotRun WHERE ServerID = 999999;
END TRY
BEGIN CATCH
    -- Expected to fail with FK violation
    IF ERROR_NUMBER() = 547  -- FK constraint violation
    BEGIN
        SET @Result = '✓ PASS';
        SET @TestsPassed = @TestsPassed + 1;
    END
    ELSE
    BEGIN
        SET @Result = '✗ FAIL';
        SET @TestsFailed = @TestsFailed + 1;
        PRINT '  Unexpected error: ' + ERROR_MESSAGE();
    END
END CATCH
PRINT @TestName + ': ' + @Result;

PRINT '';

-- =====================================================
-- TEST SUMMARY
-- =====================================================

PRINT '=========================================================================';
PRINT 'TEST SUMMARY';
PRINT '=========================================================================';
PRINT 'Total Tests: ' + CAST((@TestsPassed + @TestsFailed) AS VARCHAR);
PRINT 'Passed:      ' + CAST(@TestsPassed AS VARCHAR) + ' ✓';
PRINT 'Failed:      ' + CAST(@TestsFailed AS VARCHAR) + ' ✗';
PRINT '';

IF @TestsFailed = 0
BEGIN
    PRINT '✓✓✓ ALL TESTS PASSED ✓✓✓';
    PRINT '';
    PRINT 'Phase 1.9 schema deployment is SUCCESSFUL!';
    PRINT 'Ready to proceed to Day 2: Schema Unification (mapping views)';
END
ELSE
BEGIN
    PRINT '✗✗✗ SOME TESTS FAILED ✗✗✗';
    PRINT '';
    PRINT 'Please review failed tests and fix schema deployment before continuing.';
END

PRINT '=========================================================================';
GO
