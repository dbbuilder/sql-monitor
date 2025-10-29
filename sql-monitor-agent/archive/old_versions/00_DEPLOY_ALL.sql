-- =============================================
-- SQL Server Monitoring System - Complete Deployment
-- =============================================
-- This script deploys all components in the correct order
--
-- Target Server: sqltest.schoolvision.net,14333
-- Connection: Server=sqltest.schoolvision.net,14333;Database=master;User Id=sv;Password=Gv51076!;TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30
--
-- Deployment Order:
--   01. Create DBATools database and baseline tables
--   02. Create logging procedure
--   03. Create original baseline collector
--   04. Create SQL Agent job (Linux compatible)
--   05. Create enhanced monitoring tables
--   06-09. Create modular collection procedures (P0-P3)
--   10. Create master orchestrator
--   11. Create purge procedure
--   12. Create diagnostic views
-- =============================================

SET NOCOUNT ON
GO

PRINT '======================================================='
PRINT 'SQL Server Monitoring System - Deployment Starting'
PRINT 'Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 121)
PRINT '======================================================='
GO

-- Step 1: Create DBATools and baseline tables
PRINT ''
PRINT 'Step 1/12: Creating DBATools database and baseline tables...'
:r 01_create_DBATools_and_tables.sql
GO

-- Step 2: Create logging procedure
PRINT ''
PRINT 'Step 2/12: Creating logging procedure...'
:r 02_create_DBA_LogEntry_Insert.sql
GO

-- Step 3: Create original baseline collector (will be replaced by enhanced version)
PRINT ''
PRINT 'Step 3/12: Creating baseline collector procedure...'
:r 03_create_DBA_CollectPerformanceSnapshot.sql
GO

-- Step 4: Create SQL Agent job
PRINT ''
PRINT 'Step 4/12: Creating SQL Agent job...'
:r 04_create_agent_job_linux.sql
GO

-- Step 5: Create enhanced monitoring tables
PRINT ''
PRINT 'Step 5/12: Creating enhanced monitoring tables...'
:r 05_create_enhanced_tables.sql
GO

-- Step 6: Create P0 modular collectors
PRINT ''
PRINT 'Step 6/12: Creating P0 (Critical) modular collectors...'
:r 06_create_modular_collectors_P0.sql
GO

-- Step 7: Create P1 modular collectors
PRINT ''
PRINT 'Step 7/12: Creating P1 (High) modular collectors...'
:r 07_create_modular_collectors_P1.sql
GO

-- Step 8: Create P2 modular collectors
PRINT ''
PRINT 'Step 8/12: Creating P2 (Medium) modular collectors...'
:r 08_create_modular_collectors_P2.sql
GO

-- Step 9: Create P3 modular collectors
PRINT ''
PRINT 'Step 9/12: Creating P3 (Low) modular collectors...'
:r 09_create_modular_collectors_P3.sql
GO

-- Step 10: Create master orchestrator (replaces baseline collector)
PRINT ''
PRINT 'Step 10/12: Creating master orchestrator procedure...'
:r 10_create_master_orchestrator.sql
GO

-- Step 11: Create purge procedure
PRINT ''
PRINT 'Step 11/12: Creating purge procedure...'
:r 11_create_purge_procedure.sql
GO

-- Step 12: Create diagnostic views
PRINT ''
PRINT 'Step 12/12: Creating diagnostic views...'
:r 12_create_diagnostic_views.sql
GO

PRINT ''
PRINT '======================================================='
PRINT 'Deployment Complete!'
PRINT 'Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 121)
PRINT '======================================================='
PRINT ''
PRINT 'Next Steps:'
PRINT '1. Test manual execution: EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1'
PRINT '2. Verify SQL Agent job is enabled: SELECT * FROM msdb.dbo.sysjobs WHERE name = ''DBA Collect Perf Snapshot'''
PRINT '3. Check first snapshot: SELECT TOP 1 * FROM DBATools.dbo.PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC'
PRINT '4. Review diagnostic views: SELECT * FROM DBATools.dbo.vw_LatestSnapshotSummary'
PRINT ''
GO
