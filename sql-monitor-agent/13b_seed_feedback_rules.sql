-- =============================================
-- File: 13b_seed_feedback_rules.sql
-- Purpose: Seed/reseed feedback rules (idempotent)
-- Created: 2025-10-27
-- =============================================
-- This script is IDEMPOTENT - safe to run multiple times
-- It will clear all existing rules and reseed with current version
-- =============================================

USE DBATools
GO

PRINT 'Reseeding Feedback Rules...'
GO

-- =============================================
-- STEP 1: Clear ONLY system-seeded data (ID < 1 billion)
-- User-created rules (ID >= 1 billion) are preserved
-- =============================================
PRINT 'Clearing system-seeded feedback rules (ID < 1,000,000,000)...'

DELETE FROM dbo.FeedbackMetadata WHERE MetadataID < 1000000000
DELETE FROM dbo.FeedbackRule WHERE FeedbackRuleID < 1000000000

DECLARE @DeletedMetadata INT = @@ROWCOUNT
DECLARE @DeletedRules INT

SELECT @DeletedRules = COUNT(*) FROM dbo.FeedbackRule WHERE FeedbackRuleID < 1000000000

PRINT 'System-seeded data cleared:'
PRINT '  - Metadata records deleted: ' + CAST(@DeletedMetadata AS VARCHAR(10))
PRINT '  - Rules deleted: ' + CAST(@DeletedRules AS VARCHAR(10))
PRINT '  - User-created data (ID >= 1B) preserved'
GO

-- =============================================
-- STEP 2: Seed Result Set Metadata (IDs 1-99)
-- =============================================
PRINT 'Seeding FeedbackMetadata with explicit IDs (1-12)...'
GO

SET IDENTITY_INSERT dbo.FeedbackMetadata ON

INSERT INTO dbo.FeedbackMetadata (MetadataID, ProcedureName, ResultSetNumber, ResultSetName, Description, InterpretationGuide, IsSystemMetadata)
VALUES
    (1, 'DBA_DailyHealthOverview', 1, 'Report Header',
     'Report metadata and data collection status',
     'Check DataStatus field first - if not "DATA CURRENT", investigate collection jobs immediately.', 1),

    (2, 'DBA_DailyHealthOverview', 2, 'Current System Health',
     'Latest snapshot with health assessment',
     'HealthStatus indicates overall system state. CRITICAL or WARNING require immediate attention. Check specific metrics to identify the cause.', 1),

    (3, 'DBA_DailyHealthOverview', 3, 'Issues Found',
     'All problem periods detected in the time window',
     'Each row represents a 5-minute snapshot where issues were detected. Look for patterns - are issues constant or intermittent?', 1),

    (4, 'DBA_DailyHealthOverview', 4, 'Summary Statistics',
     'Statistical overview of the time period',
     'Use averages to understand typical load, maximums to find peak periods. Compare today vs. historical trends.', 1),

    (5, 'DBA_DailyHealthOverview', 5, 'Top Slowest Queries',
     'Worst performing queries by elapsed time',
     'ImpactScore = ExecutionCount × AvgElapsedMs. High scores indicate queries to optimize. Review execution plans.', 1),

    (6, 'DBA_DailyHealthOverview', 6, 'Top CPU Queries',
     'Most CPU-intensive queries',
     'High CPU queries may indicate missing indexes, poor query plans, or algorithmic issues. Compare CPU time to elapsed time.', 1),

    (7, 'DBA_DailyHealthOverview', 7, 'Top Missing Indexes',
     'Index recommendations with CREATE statements',
     'ImpactScore indicates potential benefit. ALWAYS test in non-production first. Monitor index usage after creation.', 1),

    (8, 'DBA_DailyHealthOverview', 8, 'Top Wait Types',
     'Wait statistics breakdown',
     'Wait types reveal bottlenecks: PAGEIOLATCH = disk I/O, LCK_M = locking, CXPACKET = parallelism. Focus on top 3-5 wait types.', 1),

    (9, 'DBA_DailyHealthOverview', 9, 'Database Sizes',
     'Current size of all databases',
     'Monitor LogReuseWaitDesc - anything other than NOTHING may indicate log growth issues. Track size changes over time.', 1),

    (10, 'DBA_DailyHealthOverview', 10, 'Recent Errors',
     'Collection errors from the time window',
     'Any errors indicate problems with the monitoring system itself. Investigate and resolve to ensure data accuracy.', 1),

    (11, 'DBA_DailyHealthOverview', 11, 'Collection Job Status',
     'Verify automated collection is working',
     'If LastRunStatus != Succeeded or job is disabled, monitoring data will be incomplete. Fix immediately.', 1),

    (12, 'DBA_DailyHealthOverview', 12, 'Action Items',
     'Prioritized list of recommended actions',
     'Start with CRITICAL, then HIGH priority items. MEDIUM items should be reviewed weekly. INFO means no action needed.', 1)

SET IDENTITY_INSERT dbo.FeedbackMetadata OFF

PRINT 'FeedbackMetadata seeded: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' records (IDs 1-12)'
GO

-- =============================================
-- STEP 3: Seed Feedback Rules
-- =============================================

-- Result Set 1: Report Header (IDs 100-109)
PRINT 'Seeding FeedbackRule - Report Header (IDs 100-103)...'
GO

SET IDENTITY_INSERT dbo.FeedbackRule ON

INSERT INTO dbo.FeedbackRule (FeedbackRuleID, ProcedureName, ResultSetNumber, MetricName, RangeFrom, RangeTo, Severity, FeedbackText, Recommendation, SortOrder, IsSystemRule)
VALUES
    (100, 'DBA_DailyHealthOverview', 1, 'DaysOfData', 0, 0, 'INFO',
     'First day of monitoring - limited historical data available.',
     'Run this report daily to build trend history. Consider comparing snapshots hour-to-hour instead of day-to-day.', 1, 1),

    (101, 'DBA_DailyHealthOverview', 1, 'DaysOfData', 1, 6, 'INFO',
     'Limited historical data (less than 1 week). Trends may not be representative.',
     'Continue collecting for at least 7 days before making major optimization decisions based on trends.', 2, 1),

    (102, 'DBA_DailyHealthOverview', 1, 'DaysOfData', 7, 13, 'INFO',
     'Good historical data (1-2 weeks). Trends are becoming meaningful.',
     'You now have enough data to identify weekly patterns. Look for recurring issues at specific times/days.', 3, 1),

    (103, 'DBA_DailyHealthOverview', 1, 'DaysOfData', 14, NULL, 'INFO',
     'Excellent historical data (2+ weeks). Trends are highly reliable.',
     'Use trending data to predict capacity needs and identify long-term optimization opportunities.', 4, 1)

SET IDENTITY_INSERT dbo.FeedbackRule OFF

PRINT 'Report Header rules seeded: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' rules (IDs 100-103)'
GO

-- Result Set 2: Current System Health (IDs 110-149)
PRINT 'Seeding FeedbackRule - Current Health (IDs 110-126)...'
GO

SET IDENTITY_INSERT dbo.FeedbackRule ON

INSERT INTO dbo.FeedbackRule (FeedbackRuleID, ProcedureName, ResultSetNumber, MetricName, RangeFrom, RangeTo, Severity, FeedbackText, Recommendation, SortOrder, IsSystemRule)
VALUES
    -- CPU Signal Wait Percentage
    (110, 'DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 0, 5, 'INFO',
     'CPU signal wait is very low (< 5%). CPU is not a bottleneck.',
     'CPU is healthy. If experiencing performance issues, investigate disk I/O, memory, or query optimization.', 1, 1),

    (111, 'DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 5, 15, 'INFO',
     'CPU signal wait is normal (5-15%). Moderate CPU usage.',
     'CPU utilization is within normal range. Continue monitoring trends.', 2, 1),

    (112, 'DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 15, 30, 'ATTENTION',
     'CPU signal wait is elevated (15-30%). CPU is becoming busy.',
     'Monitor CPU-intensive queries (Result Set #6). Consider query optimization or additional CPU capacity if trend continues.', 3, 1),

    (113, 'DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 30, 50, 'WARNING',
     'CPU signal wait is high (30-50%). CPU pressure detected.',
     'Investigate Top CPU Queries immediately (Result Set #6). Review query plans, consider missing indexes, and check for long-running processes.', 4, 1),

    (114, 'DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 50, NULL, 'CRITICAL',
     'CPU signal wait is critical (> 50%). Severe CPU bottleneck.',
     'IMMEDIATE ACTION REQUIRED: Review Result Set #6 for CPU-intensive queries. Check for runaway queries, missing indexes, or parameter sniffing issues. Consider emergency query kills if necessary.', 5, 1),

    -- Blocking Sessions
    (115, 'DBA_DailyHealthOverview', 2, 'BlockingSessionCount', 0, 5, 'INFO',
     'Minimal blocking (0-5 sessions). Normal transactional activity.',
     'Blocking is within acceptable range. No action needed.', 10, 1),

    (116, 'DBA_DailyHealthOverview', 2, 'BlockingSessionCount', 6, 15, 'ATTENTION',
     'Moderate blocking (6-15 sessions). Some contention present.',
     'Monitor blocking trends. If persistent, review transaction isolation levels and query patterns.', 11, 1),

    (117, 'DBA_DailyHealthOverview', 2, 'BlockingSessionCount', 16, 30, 'WARNING',
     'High blocking (16-30 sessions). Significant lock contention.',
     'Use DBA_FindBlockingHistory to identify blocking chains. Review long-running transactions and consider query optimization.', 12, 1),

    (118, 'DBA_DailyHealthOverview', 2, 'BlockingSessionCount', 31, NULL, 'CRITICAL',
     'Critical blocking (> 30 sessions). Severe lock contention.',
     'IMMEDIATE ACTION: Execute "EXEC sp_who2" to identify blocking head. Review blocking queries and consider killing long-running transactions if necessary.', 13, 1),

    -- Deadlocks
    (119, 'DBA_DailyHealthOverview', 2, 'DeadlockCountRecent', 0, 0, 'INFO',
     'No deadlocks detected in last 10 minutes.',
     'Deadlock monitoring is active. No action needed.', 20, 1),

    (120, 'DBA_DailyHealthOverview', 2, 'DeadlockCountRecent', 1, 3, 'ATTENTION',
     'Low deadlock count (1-3 in last 10 minutes). Occasional deadlocks detected.',
     'Review SQL Server Error Log for deadlock graphs. Identify resources causing deadlocks and consider query reordering or index optimization.', 21, 1),

    (121, 'DBA_DailyHealthOverview', 2, 'DeadlockCountRecent', 4, 10, 'WARNING',
     'Moderate deadlock count (4-10 in last 10 minutes). Frequent deadlocks occurring.',
     'Investigate deadlock patterns immediately. Review application transaction logic and database design. Consider implementing retry logic in application.', 22, 1),

    (122, 'DBA_DailyHealthOverview', 2, 'DeadlockCountRecent', 11, NULL, 'CRITICAL',
     'High deadlock count (> 10 in last 10 minutes). Severe deadlock storm.',
     'CRITICAL: Deadlock storm detected. Review error log for deadlock graphs, identify problematic queries, and consider emergency application changes.', 23, 1),

    -- Minutes Since Snapshot
    (123, 'DBA_DailyHealthOverview', 2, 'MinutesSinceSnapshot', 0, 6, 'INFO',
     'Data is current (< 6 minutes old). Collection is running normally.',
     'Monitoring is functioning correctly. Data is fresh.', 30, 1),

    (124, 'DBA_DailyHealthOverview', 2, 'MinutesSinceSnapshot', 7, 15, 'ATTENTION',
     'Data is slightly stale (7-15 minutes old). Possible collection delay.',
     'Check SQL Agent job status (Result Set #11). Verify job is running and not blocked.', 31, 1),

    (125, 'DBA_DailyHealthOverview', 2, 'MinutesSinceSnapshot', 16, 60, 'WARNING',
     'Data is stale (16-60 minutes old). Collection may have stopped.',
     'Check collection job status immediately. Review error log (Result Set #10) for collection failures.', 32, 1),

    (126, 'DBA_DailyHealthOverview', 2, 'MinutesSinceSnapshot', 61, NULL, 'CRITICAL',
     'Data is very stale (> 60 minutes old). Monitoring is not running.',
     'CRITICAL: Monitoring has stopped. Check SQL Agent service status and review DBA_Collect_Perf_Snapshot job. This report data is outdated.', 33, 1)

SET IDENTITY_INSERT dbo.FeedbackRule OFF

PRINT 'Current Health rules seeded: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' rules (IDs 110-126)'
GO

-- Result Set 4: Summary Statistics (IDs 200-219)
PRINT 'Seeding FeedbackRule - Summary Statistics (IDs 200-206)...'
GO

SET IDENTITY_INSERT dbo.FeedbackRule ON

INSERT INTO dbo.FeedbackRule (FeedbackRuleID, ProcedureName, ResultSetNumber, MetricName, RangeFrom, RangeTo, Severity, FeedbackText, Recommendation, SortOrder, IsSystemRule)
VALUES
    -- Average CPU
    (200, 'DBA_DailyHealthOverview', 4, 'AvgCpuSignalWaitPct', 0, 10, 'INFO',
     'Average CPU signal wait is low (< 10%). CPU capacity is healthy.',
     'Current CPU capacity is adequate. Focus optimization efforts on other bottlenecks if performance issues exist.', 1, 1),

    (201, 'DBA_DailyHealthOverview', 4, 'AvgCpuSignalWaitPct', 10, 20, 'ATTENTION',
     'Average CPU signal wait is moderate (10-20%). CPU utilization is increasing.',
     'Monitor CPU trends. Plan for capacity upgrades if average continues to rise.', 2, 1),

    (202, 'DBA_DailyHealthOverview', 4, 'AvgCpuSignalWaitPct', 20, NULL, 'WARNING',
     'Average CPU signal wait is high (> 20%). CPU is consistently busy.',
     'CPU is a bottleneck. Review top CPU queries (Result Set #6) and plan for optimization or hardware upgrade.', 3, 1),

    -- Total Deadlocks
    (203, 'DBA_DailyHealthOverview', 4, 'TotalDeadlocks', 0, 0, 'INFO',
     'No deadlocks in the reporting period. Excellent transaction management.',
     'Continue current practices. No action needed.', 10, 1),

    (204, 'DBA_DailyHealthOverview', 4, 'TotalDeadlocks', 1, 5, 'ATTENTION',
     'Low deadlock count (1-5 total). Occasional deadlocks detected.',
     'Review error log for deadlock graphs. Not urgent, but should be investigated during routine maintenance.', 11, 1),

    (205, 'DBA_DailyHealthOverview', 4, 'TotalDeadlocks', 6, 20, 'WARNING',
     'Moderate deadlock count (6-20 total). Regular deadlocks occurring.',
     'Investigate deadlock patterns. Review application transaction logic and consider schema or query optimization.', 12, 1),

    (206, 'DBA_DailyHealthOverview', 4, 'TotalDeadlocks', 21, NULL, 'CRITICAL',
     'High deadlock count (> 20 total). Frequent deadlocking indicates design issues.',
     'CRITICAL: Systematic deadlock problem. Requires application code review and database design assessment.', 13, 1)

SET IDENTITY_INSERT dbo.FeedbackRule OFF

PRINT 'Summary Statistics rules seeded: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' rules (IDs 200-206)'
GO

-- Result Set 5: Slow Queries (IDs 300-319)
PRINT 'Seeding FeedbackRule - Slow Queries (IDs 300-307)...'
GO

SET IDENTITY_INSERT dbo.FeedbackRule ON

INSERT INTO dbo.FeedbackRule (FeedbackRuleID, ProcedureName, ResultSetNumber, MetricName, RangeFrom, RangeTo, Severity, FeedbackText, Recommendation, SortOrder, IsSystemRule)
VALUES
    -- Average Elapsed Time
    (300, 'DBA_DailyHealthOverview', 5, 'AvgElapsedMs', 0, 1000, 'INFO',
     'Query elapsed time is good (< 1 second). Acceptable performance.',
     'No immediate optimization needed. Monitor execution counts - high-frequency queries still benefit from small improvements.', 1, 1),

    (301, 'DBA_DailyHealthOverview', 5, 'AvgElapsedMs', 1000, 5000, 'ATTENTION',
     'Query elapsed time is slow (1-5 seconds). Consider optimization.',
     'Review execution plan. Check for missing indexes (Result Set #7), table scans, or inefficient joins.', 2, 1),

    (302, 'DBA_DailyHealthOverview', 5, 'AvgElapsedMs', 5000, 30000, 'WARNING',
     'Query elapsed time is very slow (5-30 seconds). Needs optimization.',
     'Priority optimization candidate. Analyze execution plan, check statistics, consider query rewrite or schema changes.', 3, 1),

    (303, 'DBA_DailyHealthOverview', 5, 'AvgElapsedMs', 30000, NULL, 'CRITICAL',
     'Query elapsed time is critical (> 30 seconds). Severe performance issue.',
     'CRITICAL: Exorbitantly slow query. Immediate action required - review execution plan, check for blocking, consider emergency optimization.', 4, 1),

    -- Impact Score
    (304, 'DBA_DailyHealthOverview', 5, 'ImpactScore', 0, 10000, 'INFO',
     'Low impact score (< 10,000). Query runs infrequently or is fast.',
     'Low priority for optimization. Focus on higher impact queries first.', 10, 1),

    (305, 'DBA_DailyHealthOverview', 5, 'ImpactScore', 10000, 100000, 'ATTENTION',
     'Moderate impact score (10K-100K). Query has measurable impact.',
     'Optimization would provide noticeable benefit. Consider for next optimization cycle.', 11, 1),

    (306, 'DBA_DailyHealthOverview', 5, 'ImpactScore', 100000, 1000000, 'WARNING',
     'High impact score (100K-1M). Query significantly affects performance.',
     'High priority optimization target. Calculate potential time savings: (ExecutionCount × improvement_ms) / 1000 seconds saved.', 12, 1),

    (307, 'DBA_DailyHealthOverview', 5, 'ImpactScore', 1000000, NULL, 'CRITICAL',
     'Critical impact score (> 1M). Query is major performance bottleneck.',
     'TOP PRIORITY: Optimizing this query will have dramatic system-wide impact. Allocate dedicated resources to resolve.', 13, 1)

SET IDENTITY_INSERT dbo.FeedbackRule OFF

PRINT 'Slow Queries rules seeded: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' rules (IDs 300-307)'
GO

-- Result Set 7: Missing Indexes (IDs 400-419)
PRINT 'Seeding FeedbackRule - Missing Indexes (IDs 400-406)...'
GO

SET IDENTITY_INSERT dbo.FeedbackRule ON

INSERT INTO dbo.FeedbackRule (FeedbackRuleID, ProcedureName, ResultSetNumber, MetricName, RangeFrom, RangeTo, Severity, FeedbackText, Recommendation, SortOrder, IsSystemRule)
VALUES
    -- Impact Score
    (400, 'DBA_DailyHealthOverview', 7, 'ImpactScore', 0, 100000, 'INFO',
     'Low impact index (< 100K). Marginal benefit expected.',
     'Low priority. Only create if storage and maintenance overhead are trivial. Test thoroughly in non-production.', 1, 1),

    (401, 'DBA_DailyHealthOverview', 7, 'ImpactScore', 100000, 1000000, 'ATTENTION',
     'Moderate impact index (100K-1M). Noticeable benefit expected.',
     'Good optimization candidate. Test in non-production, monitor index usage statistics after creation to verify benefit.', 2, 1),

    (402, 'DBA_DailyHealthOverview', 7, 'ImpactScore', 1000000, 10000000, 'WARNING',
     'High impact index (1M-10M). Significant performance gain expected.',
     'Strong candidate for creation. ALWAYS test in non-production first. Monitor query performance before/after and track index usage.', 3, 1),

    (403, 'DBA_DailyHealthOverview', 7, 'ImpactScore', 10000000, NULL, 'CRITICAL',
     'Critical impact index (> 10M). Major performance improvement expected.',
     'TOP PRIORITY index candidate. Very high potential benefit, but test thoroughly - wrong indexes can hurt more than help. Verify queries actually use the index after creation.', 4, 1),

    -- User Seeks
    (404, 'DBA_DailyHealthOverview', 7, 'UserSeeks', 0, 100, 'INFO',
     'Low seek count (< 100). Index is used infrequently.',
     'Question whether index is needed. Low usage may not justify maintenance overhead.', 10, 1),

    (405, 'DBA_DailyHealthOverview', 7, 'UserSeeks', 100, 10000, 'ATTENTION',
     'Moderate seek count (100-10K). Regular index usage.',
     'Index would be used regularly. Reasonable candidate for creation.', 11, 1),

    (406, 'DBA_DailyHealthOverview', 7, 'UserSeeks', 10000, NULL, 'WARNING',
     'High seek count (> 10K). Index would be heavily used.',
     'Index would be very active. Strong indicator of real need. Verify with execution plan analysis.', 12, 1)

SET IDENTITY_INSERT dbo.FeedbackRule OFF

PRINT 'Missing Indexes rules seeded: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' rules (IDs 400-406)'
GO

-- Result Set 9: Database Sizes (IDs 500-519)
PRINT 'Seeding FeedbackRule - Database Sizes (IDs 500-503)...'
GO

SET IDENTITY_INSERT dbo.FeedbackRule ON

INSERT INTO dbo.FeedbackRule (FeedbackRuleID, ProcedureName, ResultSetNumber, MetricName, RangeFrom, RangeTo, Severity, FeedbackText, Recommendation, SortOrder, IsSystemRule)
VALUES
    -- Total Size (MB)
    (500, 'DBA_DailyHealthOverview', 9, 'TotalSizeMB', 0, 1024, 'INFO',
     'Small database (< 1 GB). Size is not a concern.',
     'Monitor growth trends but no immediate action needed.', 1, 1),

    (501, 'DBA_DailyHealthOverview', 9, 'TotalSizeMB', 1024, 10240, 'INFO',
     'Medium database (1-10 GB). Normal size range.',
     'Monitor monthly growth trends. Plan for capacity if growth rate is high.', 2, 1),

    (502, 'DBA_DailyHealthOverview', 9, 'TotalSizeMB', 10240, 102400, 'ATTENTION',
     'Large database (10-100 GB). Monitor growth carefully.',
     'Track growth trends weekly. Ensure backup/restore strategies are tested. Plan for archival if growth is rapid.', 3, 1),

    (503, 'DBA_DailyHealthOverview', 9, 'TotalSizeMB', 102400, NULL, 'WARNING',
     'Very large database (> 100 GB). Requires active capacity management.',
     'Monitor growth daily. Implement data archival strategy. Verify backup windows are acceptable. Consider partitioning for large tables.', 4, 1)

SET IDENTITY_INSERT dbo.FeedbackRule OFF

PRINT 'Database Sizes rules seeded: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' rules (IDs 500-503)'
GO

-- =============================================
-- STEP 4: Summary
-- =============================================
PRINT ''
PRINT '=========================================='
PRINT 'Feedback Rules Reseeded Successfully'
PRINT '=========================================='
PRINT ''

-- Count total records
DECLARE @MetadataCount INT, @RuleCount INT

SELECT @MetadataCount = COUNT(*) FROM dbo.FeedbackMetadata WHERE ProcedureName = 'DBA_DailyHealthOverview'
SELECT @RuleCount = COUNT(*) FROM dbo.FeedbackRule WHERE ProcedureName = 'DBA_DailyHealthOverview'

PRINT 'FeedbackMetadata: ' + CAST(@MetadataCount AS VARCHAR(10)) + ' records'
PRINT 'FeedbackRule: ' + CAST(@RuleCount AS VARCHAR(10)) + ' rules'
PRINT ''

-- Show breakdown by result set
PRINT 'Rules by Result Set:'
SELECT
    ResultSetNumber,
    COUNT(*) AS RuleCount
FROM dbo.FeedbackRule
WHERE ProcedureName = 'DBA_DailyHealthOverview'
GROUP BY ResultSetNumber
ORDER BY ResultSetNumber

PRINT ''
PRINT 'Feedback system ready for use.'
PRINT '=========================================='
GO
