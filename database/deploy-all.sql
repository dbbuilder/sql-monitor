-- =====================================================
-- Master Deployment Script: deploy-all.sql
-- Description: Deploys complete MonitoringDB schema in correct order
-- Author: SQL Server Monitor Project
-- Date: 2025-11-26
-- Usage: sqlcmd -S SERVER -U USER -P PASSWORD -C -i deploy-all.sql
-- =====================================================
--
-- This script deploys all required database objects for SQL Server Monitor.
-- Scripts are executed in dependency order to ensure proper creation.
--
-- Total deployment time: ~5-10 minutes depending on server performance
-- =====================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT '';
PRINT '========================================================================';
PRINT '  SQL Server Monitor - Complete Database Deployment';
PRINT '========================================================================';
PRINT '  Started: ' + CONVERT(VARCHAR(23), GETUTCDATE(), 121) + ' UTC';
PRINT '========================================================================';
PRINT '';

DECLARE @StartTime DATETIME2 = GETUTCDATE();
DECLARE @StepStart DATETIME2;
DECLARE @StepNum INT = 0;

-- =====================================================
-- PHASE 1: Core Database Infrastructure
-- =====================================================

PRINT '========================================================================';
PRINT 'PHASE 1: Core Database Infrastructure';
PRINT '========================================================================';
PRINT '';

-- Step 1.1: Create Database
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT CONCAT('Step ', @StepNum, ': Creating database...');
:r 01-create-database.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 1.2: Create Partition Function and Scheme
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating partition infrastructure...');
:r 03-create-partitions.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 1.3: Create Core Tables
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating core tables...');
:r 02-create-tables.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 1.4: Create Core Stored Procedures
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating core stored procedures...');
:r 04-create-procedures.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- =====================================================
-- PHASE 2: Extended Collection Features
-- =====================================================

PRINT '';
PRINT '========================================================================';
PRINT 'PHASE 2: Extended Collection Features';
PRINT '========================================================================';
PRINT '';

-- Step 2.1: CPU Collection Procedures (Fixed version)
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT CONCAT('Step ', @StepNum, ': Creating CPU collection procedures...');
:r 05-create-cpu-collection-procedures-FIXED.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 2.2: Drilldown Tables
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating drilldown tables...');
:r 06-create-drilldown-tables.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 2.3: Drilldown Procedures
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating drilldown procedures...');
:r 07-create-drilldown-procedures.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 2.4: Master Collection Procedure
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating master collection procedure...');
:r 08-create-master-collection-procedure.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- =====================================================
-- PHASE 3: Extended Events & Advanced Analytics
-- =====================================================

PRINT '';
PRINT '========================================================================';
PRINT 'PHASE 3: Extended Events & Advanced Analytics';
PRINT '========================================================================';
PRINT '';

-- Step 3.1: Extended Events Tables
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT CONCAT('Step ', @StepNum, ': Creating extended events tables...');
:r 10-create-extended-events-tables.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 3.2: Extended Events Procedures
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating extended events procedures...');
:r 11-create-extended-events-procedures.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 3.3: Alerting System
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating alerting system...');
:r 12-create-alerting-system.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 3.4: Index Maintenance
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating index maintenance procedures...');
:r 13-create-index-maintenance.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 3.5: Schema Metadata Infrastructure
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating schema metadata infrastructure...');
:r 14-create-schema-metadata-infrastructure.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- =====================================================
-- PHASE 4: Query Analysis & Recommendations
-- =====================================================

PRINT '';
PRINT '========================================================================';
PRINT 'PHASE 4: Query Analysis & Recommendations';
PRINT '========================================================================';
PRINT '';

-- Step 4.1: Query Analysis Tables
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT CONCAT('Step ', @StepNum, ': Creating query analysis tables...');
:r 31-create-query-analysis-tables.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 4.2: Query Analysis Procedures
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating query analysis procedures...');
:r 32-create-query-analysis-procedures.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 4.3: Health Score System
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating health score system...');
:r 40-create-health-score-system.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 4.4: Query Advisor
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating query advisor...');
:r 42-create-query-advisor.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 4.5: Baseline Comparison
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating baseline comparison system...');
:r 50-create-baseline-comparison.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- =====================================================
-- PHASE 5: SOC 2 Compliance (Authentication & Audit)
-- =====================================================

PRINT '';
PRINT '========================================================================';
PRINT 'PHASE 5: SOC 2 Compliance (Authentication & Audit)';
PRINT '========================================================================';
PRINT '';

-- Step 5.1: Audit Infrastructure
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT CONCAT('Step ', @StepNum, ': Creating audit infrastructure...');
:r 19-create-audit-infrastructure.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 5.2: RBAC Infrastructure
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating RBAC infrastructure...');
:r 21-create-rbac-infrastructure.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 5.3: Authentication Procedures
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating authentication procedures...');
:r 23-authentication-procedures.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 5.4: MFA Schema
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating MFA schema...');
:r 26-mfa-schema.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 5.5: Session Management
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating session management schema...');
:r 27-session-management-schema.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- =====================================================
-- PHASE 6: DDL Audit & Performance Optimization
-- =====================================================

PRINT '';
PRINT '========================================================================';
PRINT 'PHASE 6: DDL Audit & Performance Optimization';
PRINT '========================================================================';
PRINT '';

-- Step 6.1: DDL Audit Infrastructure
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT CONCAT('Step ', @StepNum, ': Creating DDL audit infrastructure...');
:r 94-create-ddl-audit-infrastructure.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 6.2: Non-blocking Index Fragmentation Fix
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating non-blocking index fragmentation procedures...');
:r 96-fix-blocking-index-fragmentation.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- Step 6.3: Adaptive Collection System
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT '';
PRINT CONCAT('Step ', @StepNum, ': Creating adaptive collection system...');
:r 97-create-adaptive-collection.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- =====================================================
-- PHASE 7: SQL Agent Jobs (Optional - Run on Central Server)
-- =====================================================

PRINT '';
PRINT '========================================================================';
PRINT 'PHASE 7: SQL Agent Jobs';
PRINT '========================================================================';
PRINT '';

-- Step 7.1: Create SQL Agent Jobs
SET @StepNum = @StepNum + 1;
SET @StepStart = GETUTCDATE();
PRINT CONCAT('Step ', @StepNum, ': Creating SQL Agent jobs...');
:r 09-create-sql-agent-jobs-FIXED.sql
PRINT CONCAT('  Completed in ', DATEDIFF(SECOND, @StepStart, GETUTCDATE()), ' seconds');
GO

-- =====================================================
-- DEPLOYMENT COMPLETE - Summary
-- =====================================================

USE MonitoringDB;
GO

DECLARE @EndTime DATETIME2 = GETUTCDATE();

PRINT '';
PRINT '========================================================================';
PRINT '  DEPLOYMENT COMPLETE';
PRINT '========================================================================';
PRINT '';

-- Count created objects
PRINT 'Objects Created:';
PRINT '';

SELECT 'Tables' AS ObjectType, COUNT(*) AS [Count] FROM sys.tables WHERE is_ms_shipped = 0
UNION ALL
SELECT 'Stored Procedures', COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0
UNION ALL
SELECT 'Views', COUNT(*) FROM sys.views WHERE is_ms_shipped = 0
UNION ALL
SELECT 'Functions', COUNT(*) FROM sys.objects WHERE type IN ('FN', 'IF', 'TF') AND is_ms_shipped = 0
UNION ALL
SELECT 'Indexes', COUNT(*) FROM sys.indexes WHERE object_id IN (SELECT object_id FROM sys.tables WHERE is_ms_shipped = 0) AND index_id > 0
UNION ALL
SELECT 'Partition Functions', COUNT(*) FROM sys.partition_functions
UNION ALL
SELECT 'SQL Agent Jobs', COUNT(*) FROM msdb.dbo.sysjobs WHERE name LIKE 'SQLMonitor%';

PRINT '';
PRINT '========================================================================';
PRINT '  Duration: ' + CAST(DATEDIFF(SECOND, @StartTime, @EndTime) AS VARCHAR) + ' seconds';
PRINT '  Completed: ' + CONVERT(VARCHAR(23), @EndTime, 121) + ' UTC';
PRINT '========================================================================';
PRINT '';
PRINT 'Next Steps:';
PRINT '  1. Create application database user (monitor_api)';
PRINT '  2. Start the API and Grafana containers';
PRINT '  3. Register SQL Servers to monitor';
PRINT '  4. Configure alert rules in Grafana';
PRINT '';
PRINT 'Documentation: https://github.com/dbbuilder/sql-monitor/docs';
PRINT '========================================================================';
