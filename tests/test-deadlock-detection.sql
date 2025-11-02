-- =====================================================
-- Script: test-deadlock-detection.sql
-- Description: Test deadlock detection by creating an intentional deadlock
-- Author: SQL Server Monitor Project
-- Date: 2025-10-31
-- Purpose: Verify deadlock detection and collection works
-- =====================================================

USE MonitoringDB;
GO

PRINT '========================================';
PRINT 'Deadlock Detection Test';
PRINT '========================================';
PRINT '';

-- Create test table if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.TestTable1') AND type = 'U')
BEGIN
    CREATE TABLE dbo.TestTable1 (
        ID INT PRIMARY KEY,
        Value NVARCHAR(100)
    );

    INSERT INTO dbo.TestTable1 (ID, Value) VALUES (1, 'Row 1'), (2, 'Row 2');
    PRINT 'Created TestTable1';
END;

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.TestTable2') AND type = 'U')
BEGIN
    CREATE TABLE dbo.TestTable2 (
        ID INT PRIMARY KEY,
        Value NVARCHAR(100)
    );

    INSERT INTO dbo.TestTable2 (ID, Value) VALUES (1, 'Row 1'), (2, 'Row 2');
    PRINT 'Created TestTable2';
END;
GO

PRINT '';
PRINT 'To create a deadlock, you need to run TWO sessions simultaneously:';
PRINT '';
PRINT '========================================';
PRINT 'SESSION 1: (Run in one query window)';
PRINT '========================================';
PRINT '';
PRINT 'BEGIN TRANSACTION;';
PRINT '  UPDATE dbo.TestTable1 SET Value = ''Session 1 - Step 1'' WHERE ID = 1;';
PRINT '  PRINT ''Session 1: Updated TestTable1, waiting 10 seconds...'';';
PRINT '  WAITFOR DELAY ''00:00:10'';  -- Wait 10 seconds';
PRINT '  ';
PRINT '  PRINT ''Session 1: Now trying to update TestTable2...'';';
PRINT '  UPDATE dbo.TestTable2 SET Value = ''Session 1 - Step 2'' WHERE ID = 1;';
PRINT '  PRINT ''Session 1: SUCCESS - both tables updated'';';
PRINT 'COMMIT TRANSACTION;';
PRINT '';
PRINT '========================================';
PRINT 'SESSION 2: (Run in another query window IMMEDIATELY after Session 1)';
PRINT '========================================';
PRINT '';
PRINT 'BEGIN TRANSACTION;';
PRINT '  UPDATE dbo.TestTable2 SET Value = ''Session 2 - Step 1'' WHERE ID = 1;';
PRINT '  PRINT ''Session 2: Updated TestTable2, waiting 10 seconds...'';';
PRINT '  WAITFOR DELAY ''00:00:10'';  -- Wait 10 seconds';
PRINT '  ';
PRINT '  PRINT ''Session 2: Now trying to update TestTable1...'';';
PRINT '  UPDATE dbo.TestTable1 SET Value = ''Session 2 - Step 2'' WHERE ID = 1;';
PRINT '  PRINT ''Session 2: SUCCESS - both tables updated'';';
PRINT 'COMMIT TRANSACTION;';
PRINT '';
PRINT '========================================';
PRINT 'EXPECTED RESULT:';
PRINT '========================================';
PRINT 'One session will succeed, the other will be deadlock victim:';
PRINT '  Msg 1205, Level 13, State 51, Line X';
PRINT '  Transaction (Process ID XX) was deadlocked on lock resources';
PRINT '  with another process and has been chosen as the deadlock victim.';
PRINT '  Rerun the transaction.';
PRINT '';
PRINT 'After deadlock occurs, wait 1 minute, then check collection:';
PRINT '';
PRINT '  EXEC dbo.usp_CollectDeadlockEvents @ServerID = 1;';
PRINT '';
PRINT '  SELECT TOP 5 * ';
PRINT '  FROM dbo.DeadlockEvents ';
PRINT '  WHERE ServerID = 1 ';
PRINT '  ORDER BY EventTime DESC;';
PRINT '';
PRINT '========================================';
PRINT '';

-- Cleanup command
PRINT 'To cleanup test tables:';
PRINT '  DROP TABLE IF EXISTS dbo.TestTable1;';
PRINT '  DROP TABLE IF EXISTS dbo.TestTable2;';
PRINT '';
