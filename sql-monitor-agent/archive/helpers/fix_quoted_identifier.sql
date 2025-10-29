-- Drop and recreate procedure with correct settings
USE DBATools
GO

-- Drop existing procedure
IF OBJECT_ID('dbo.DBA_CollectPerformanceSnapshot', 'P') IS NOT NULL
    DROP PROCEDURE dbo.DBA_CollectPerformanceSnapshot
GO

-- Now re-create it by running the orchestrator file
-- This will be done via separate sqlcmd call
PRINT 'Procedure dropped. Ready for re-creation.'
GO
