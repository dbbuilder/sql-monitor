-- =============================================
-- File: 15_create_html_formatter.sql
-- Purpose: Format DBA_DailyHealthOverview output as HTML
-- Created: 2025-10-27
-- =============================================

USE DBATools
GO

PRINT 'Creating HTML formatter for DBA_DailyHealthOverview...'
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Procedure: DBA_DailyHealthOverview_HTML
-- Purpose: Generate HTML-formatted health report
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_DailyHealthOverview_HTML
    @TopSlowQueries INT = 20,
    @TopMissingIndexes INT = 20,
    @HoursBackForIssues INT = 48
AS
BEGIN
    SET NOCOUNT ON
    SET QUOTED_IDENTIFIER ON

    DECLARE @HTML NVARCHAR(MAX) = ''
    DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME
    DECLARE @ReportDate NVARCHAR(50) = CONVERT(NVARCHAR(50), GETUTCDATE(), 120) + ' UTC'

    -- HTML Header with embedded CSS
    SET @HTML = '<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SQL Server Health Report - ' + @ServerName + '</title>
    <style>
        body {
            font-family: "Segoe UI", Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
            color: #333;
        }
        .header {
            background-color: #0078d4;
            color: white;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .header h1 {
            margin: 0 0 10px 0;
            font-size: 24px;
        }
        .header p {
            margin: 5px 0;
            font-size: 14px;
        }
        .section {
            background-color: white;
            margin-bottom: 20px;
            border-radius: 5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .section-header {
            background-color: #e8e8e8;
            padding: 12px 15px;
            font-weight: bold;
            font-size: 16px;
            border-bottom: 2px solid #ccc;
        }
        .field-guide {
            background-color: #f9f9f9;
            border-left: 4px solid #0078d4;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th {
            background-color: #f0f0f0;
            padding: 10px;
            text-align: left;
            font-weight: 600;
            font-size: 13px;
            border-bottom: 2px solid #ddd;
        }
        td {
            padding: 8px 10px;
            border-bottom: 1px solid #eee;
            font-size: 13px;
        }
        tr:hover {
            background-color: #fafafa;
        }
        .severity-INFO {
            background-color: #e7f3ff;
            border-left: 4px solid #0078d4;
        }
        .severity-ATTENTION {
            background-color: #fff8e1;
            border-left: 4px solid #ffc107;
        }
        .severity-WARNING {
            background-color: #fff3e0;
            border-left: 4px solid #ff9800;
        }
        .severity-CRITICAL {
            background-color: #ffebee;
            border-left: 4px solid #f44336;
        }
        .metric-value {
            font-weight: 600;
            color: #0078d4;
        }
        .analysis {
            font-style: italic;
            color: #555;
        }
        .recommendation {
            color: #d32f2f;
            font-weight: 500;
        }
        .null-value {
            color: #999;
            font-style: italic;
        }
        .db-group-header {
            background-color: #e8e8e8;
            font-weight: bold;
            border-top: 2px solid #0078d4;
        }
        .footer {
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>SQL Server Daily Health Report</h1>
        <p><strong>Server:</strong> ' + @ServerName + '</p>
        <p><strong>Report Generated:</strong> ' + @ReportDate + '</p>
        <p><strong>Parameters:</strong> Top ' + CAST(@TopSlowQueries AS VARCHAR(10)) + ' Slow Queries, Top ' +
            CAST(@TopMissingIndexes AS VARCHAR(10)) + ' Missing Indexes, ' + CAST(@HoursBackForIssues AS VARCHAR(10)) + ' hours lookback</p>
    </div>
'

    -- =============================================
    -- RESULT SET 1: Report Header
    -- =============================================
    DECLARE @ReportHeaderHTML NVARCHAR(MAX) = ''

    SELECT @ReportHeaderHTML = '<div class="section">
    <div class="section-header">Report Header</div>
    <table>' +
    (SELECT
        '<tr><th>Field</th><th>Value</th></tr>' +
        '<tr><td>Server Name</td><td>' + ISNULL(ServerName, '<span class="null-value">NULL</span>') + '</td></tr>' +
        '<tr><td>Snapshot Date (UTC)</td><td>' + ISNULL(CONVERT(NVARCHAR(50), SnapshotUTC, 120), '<span class="null-value">NULL</span>') + '</td></tr>' +
        '<tr><td>SQL Version</td><td>' + ISNULL(SqlVersion, '<span class="null-value">NULL</span>') + '</td></tr>' +
        '<tr><td>Total Sessions</td><td class="metric-value">' + ISNULL(CAST(SessionsCount AS VARCHAR(20)), '<span class="null-value">NULL</span>') + '</td></tr>' +
        '<tr><td>Total Requests</td><td class="metric-value">' + ISNULL(CAST(RequestsCount AS VARCHAR(20)), '<span class="null-value">NULL</span>') + '</td></tr>'
        AS [text()]
    FROM dbo.PerfSnapshotRun
    WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
    FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') + '</table></div>'

    SET @HTML = @HTML + @ReportHeaderHTML

    -- =============================================
    -- RESULT SET 2: Current System Health
    -- =============================================
    DECLARE @CurrentHealthHTML NVARCHAR(MAX) = ''

    SELECT @CurrentHealthHTML = '<div class="section">
    <div class="section-header">Current System Health</div>
    <table>
        <tr>
            <th>Metric</th>
            <th>Value</th>
            <th>Status</th>
        </tr>' +
    (SELECT
        '<tr class="' +
            CASE
                WHEN CpuSignalWaitPct >= 40 THEN 'severity-CRITICAL'
                WHEN CpuSignalWaitPct >= 20 THEN 'severity-WARNING'
                WHEN CpuSignalWaitPct >= 10 THEN 'severity-ATTENTION'
                ELSE 'severity-INFO'
            END + '">' +
        '<td>CPU Signal Wait %</td>' +
        '<td class="metric-value">' + ISNULL(CAST(CpuSignalWaitPct AS VARCHAR(20)), '<span class="null-value">NULL</span>') + '%</td>' +
        '<td>' +
            CASE
                WHEN CpuSignalWaitPct >= 40 THEN 'CRITICAL - High CPU pressure'
                WHEN CpuSignalWaitPct >= 20 THEN 'WARNING - Elevated CPU usage'
                WHEN CpuSignalWaitPct >= 10 THEN 'ATTENTION - Moderate CPU usage'
                ELSE 'INFO - Normal'
            END +
        '</td>' +
        '</tr>' +
        '<tr class="' +
            CASE
                WHEN BlockingSessionCount >= 30 THEN 'severity-CRITICAL'
                WHEN BlockingSessionCount >= 15 THEN 'severity-WARNING'
                WHEN BlockingSessionCount >= 5 THEN 'severity-ATTENTION'
                ELSE 'severity-INFO'
            END + '">' +
        '<td>Blocking Sessions</td>' +
        '<td class="metric-value">' + ISNULL(CAST(BlockingSessionCount AS VARCHAR(20)), '<span class="null-value">NULL</span>') + '</td>' +
        '<td>' +
            CASE
                WHEN BlockingSessionCount >= 30 THEN 'CRITICAL - Severe blocking'
                WHEN BlockingSessionCount >= 15 THEN 'WARNING - High blocking'
                WHEN BlockingSessionCount >= 5 THEN 'ATTENTION - Moderate blocking'
                ELSE 'INFO - Normal'
            END +
        '</td>' +
        '</tr>' +
        '<tr class="' +
            CASE
                WHEN DeadlockCountRecent >= 5 THEN 'severity-CRITICAL'
                WHEN DeadlockCountRecent >= 1 THEN 'severity-WARNING'
                ELSE 'severity-INFO'
            END + '">' +
        '<td>Recent Deadlocks (last 10 min)</td>' +
        '<td class="metric-value">' + ISNULL(CAST(DeadlockCountRecent AS VARCHAR(20)), '<span class="null-value">NULL</span>') + '</td>' +
        '<td>' +
            CASE
                WHEN DeadlockCountRecent >= 5 THEN 'CRITICAL - Frequent deadlocks'
                WHEN DeadlockCountRecent >= 1 THEN 'WARNING - Deadlocks detected'
                ELSE 'INFO - None detected'
            END +
        '</td>' +
        '</tr>' +
        '<tr class="' +
            CASE
                WHEN MemoryGrantWarningCount >= 10 THEN 'severity-CRITICAL'
                WHEN MemoryGrantWarningCount >= 1 THEN 'severity-WARNING'
                ELSE 'severity-INFO'
            END + '">' +
        '<td>Memory Grant Warnings</td>' +
        '<td class="metric-value">' + ISNULL(CAST(MemoryGrantWarningCount AS VARCHAR(20)), '<span class="null-value">NULL</span>') + '</td>' +
        '<td>' +
            CASE
                WHEN MemoryGrantWarningCount >= 10 THEN 'CRITICAL - Frequent spills'
                WHEN MemoryGrantWarningCount >= 1 THEN 'WARNING - Memory spills detected'
                ELSE 'INFO - None detected'
            END +
        '</td>' +
        '</tr>' +
        '<tr>' +
        '<td>Top Wait Type</td>' +
        '<td class="metric-value">' + ISNULL(TopWaitType, '<span class="null-value">NULL</span>') + '</td>' +
        '<td>' + ISNULL(CAST(TopWaitMsPerSec AS VARCHAR(20)), '<span class="null-value">NULL</span>') + ' ms/sec</td>' +
        '</tr>'
        AS [text()]
    FROM (
        SELECT
            CpuSignalWaitPct,
            BlockingSessionCount,
            DeadlockCountRecent,
            MemoryGrantWarningCount,
            REPLACE(TopWaitType, CHAR(0), '') AS TopWaitType,
            TopWaitMsPerSec
        FROM dbo.PerfSnapshotRun
        WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
    ) r
    FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') + '</table></div>'

    SET @HTML = @HTML + @CurrentHealthHTML

    -- =============================================
    -- RESULT SET 4: Summary Statistics
    -- =============================================
    DECLARE @SummaryStatsHTML NVARCHAR(MAX) = ''

    SELECT @SummaryStatsHTML = '<div class="section">
    <div class="section-header">Summary Statistics (Last ' + CAST(@HoursBackForIssues AS VARCHAR(10)) + ' Hours)</div>
    <table>
        <tr>
            <th>Metric</th>
            <th>Value</th>
        </tr>' +
    (SELECT
        '<tr>' +
        '<td>Total Snapshots</td>' +
        '<td class="metric-value">' + ISNULL(FORMAT(TotalSnapshots, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
        '</tr>' +
        '<tr>' +
        '<td>Avg CPU Signal Wait %</td>' +
        '<td class="metric-value">' + ISNULL(FORMAT(AvgCpuSignalWaitPct, 'N2'), '<span class="null-value">NULL</span>') + '%</td>' +
        '</tr>' +
        '<tr>' +
        '<td>Max CPU Signal Wait %</td>' +
        '<td class="metric-value">' + ISNULL(FORMAT(MaxCpuSignalWaitPct, 'N2'), '<span class="null-value">NULL</span>') + '%</td>' +
        '</tr>' +
        '<tr>' +
        '<td>Total Deadlocks</td>' +
        '<td class="metric-value">' + ISNULL(CAST(TotalDeadlocks AS VARCHAR(20)), '<span class="null-value">NULL</span>') + '</td>' +
        '</tr>' +
        '<tr>' +
        '<td>Snapshots with Blocking</td>' +
        '<td class="metric-value">' + ISNULL(CAST(SnapshotsWithBlocking AS VARCHAR(20)), '<span class="null-value">NULL</span>') + '</td>' +
        '</tr>' +
        '<tr>' +
        '<td>Avg Sessions</td>' +
        '<td class="metric-value">' + ISNULL(FORMAT(AvgSessions, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
        '</tr>' +
        '<tr>' +
        '<td>Max Sessions</td>' +
        '<td class="metric-value">' + ISNULL(CAST(MaxSessions AS VARCHAR(20)), '<span class="null-value">NULL</span>') + '</td>' +
        '</tr>'
        AS [text()]
    FROM (
        SELECT
            COUNT(*) AS TotalSnapshots,
            AVG(CpuSignalWaitPct) AS AvgCpuSignalWaitPct,
            MAX(CpuSignalWaitPct) AS MaxCpuSignalWaitPct,
            SUM(DeadlockCountRecent) AS TotalDeadlocks,
            SUM(CASE WHEN BlockingSessionCount > 0 THEN 1 ELSE 0 END) AS SnapshotsWithBlocking,
            AVG(SessionsCount) AS AvgSessions,
            MAX(SessionsCount) AS MaxSessions
        FROM dbo.PerfSnapshotRun
        WHERE SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())
    ) stats
    FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') + '</table></div>'

    SET @HTML = @HTML + @SummaryStatsHTML

    -- =============================================
    -- RESULT SET 5: Slow Queries
    -- =============================================
    DECLARE @SlowQueriesHTML NVARCHAR(MAX) = ''

    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun))
    BEGIN
        -- Pre-clean data into temp table to avoid FOR XML issues with CHAR(0)
        DECLARE @CleanQueries TABLE (
            DatabaseName NVARCHAR(128),
            SqlTextClean NVARCHAR(4000),  -- Limit size to avoid NVARCHAR(MAX) issues
            TotalCpuMs BIGINT,
            AvgElapsedMs DECIMAL(18,2),
            ExecutionCount BIGINT,
            AvgLogicalReads BIGINT,
            RowNum INT
        )

        INSERT INTO @CleanQueries
        SELECT
            dbo.fn_CleanTextForXML(DatabaseName) AS DatabaseName,
            dbo.fn_CleanTextForXML(SqlText) AS SqlTextClean,
            TotalCpuMs,
            AvgElapsedMs,
            ExecutionCount,
            AvgLogicalReads,
            ROW_NUMBER() OVER (PARTITION BY dbo.fn_CleanTextForXML(DatabaseName) ORDER BY TotalCpuMs DESC) AS RowNum
        FROM dbo.PerfSnapshotQueryStats
        WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)

        -- Now build HTML from clean data
        SELECT @SlowQueriesHTML = '<div class="section">
        <div class="section-header">Top 10 Slow Queries per Database (by Total CPU)</div>
        <table>
            <tr>
                <th>Rank</th>
                <th>Database</th>
                <th>SQL Text</th>
                <th>Total CPU (ms)</th>
                <th>Avg Duration (ms)</th>
                <th>Execution Count</th>
                <th>Avg Reads</th>
            </tr>' +
        (SELECT
            CASE
                WHEN RowNum = 1 THEN
                    '<tr class="db-group-header"><td colspan="7" style="padding: 8px 10px;">📊 Database: ' +
                    ISNULL(DatabaseName, 'NULL') + '</td></tr>'
                ELSE ''
            END +
            '<tr>' +
            '<td>' + CAST(RowNum AS VARCHAR(10)) + '</td>' +
            '<td style="font-weight: bold;">' + ISNULL(DatabaseName, '<span class="null-value">NULL</span>') + '</td>' +
            '<td style="font-family: monospace; font-size: 11px;">' +
                ISNULL(LEFT(SqlTextClean, 100), '<span class="null-value">NULL</span>') +
                CASE WHEN LEN(SqlTextClean) > 100 THEN '...' ELSE '' END +
            '</td>' +
            '<td class="metric-value">' + ISNULL(FORMAT(TotalCpuMs, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
            '<td class="metric-value">' + ISNULL(FORMAT(AvgElapsedMs, 'N2'), '<span class="null-value">NULL</span>') + '</td>' +
            '<td>' + ISNULL(FORMAT(ExecutionCount, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
            '<td>' + ISNULL(FORMAT(AvgLogicalReads, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
            '</tr>'
            AS [text()]
        FROM @CleanQueries
        WHERE RowNum <= 10
        ORDER BY DatabaseName, RowNum
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') + '</table></div>'

        SET @HTML = @HTML + @SlowQueriesHTML
    END

    -- =============================================
    -- RESULT SET 7: Missing Indexes
    -- =============================================
    DECLARE @MissingIndexesHTML NVARCHAR(MAX) = ''

    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun))
    BEGIN
        SELECT @MissingIndexesHTML = '<div class="section">
        <div class="section-header">Top ' + CAST(@TopMissingIndexes AS VARCHAR(10)) + ' Missing Indexes</div>
        <table>
            <tr>
                <th>#</th>
                <th>Database</th>
                <th>Table</th>
                <th>Equality Columns</th>
                <th>Inequality Columns</th>
                <th>Included Columns</th>
                <th>Avg Impact</th>
                <th>User Seeks</th>
                <th>Impact Score</th>
            </tr>' +
        (SELECT TOP (@TopMissingIndexes)
            '<tr>' +
            '<td>' + CAST(ROW_NUMBER() OVER (ORDER BY ImpactScore DESC) AS VARCHAR(10)) + '</td>' +
            '<td>' + ISNULL(DatabaseName, '<span class="null-value">NULL</span>') + '</td>' +
            '<td style="font-family: monospace; font-size: 11px;">' + ISNULL(ObjectName, '<span class="null-value">NULL</span>') + '</td>' +
            '<td style="font-family: monospace; font-size: 11px;">' + ISNULL(EqualityColumns, '<span class="null-value">-</span>') + '</td>' +
            '<td style="font-family: monospace; font-size: 11px;">' + ISNULL(InequalityColumns, '<span class="null-value">-</span>') + '</td>' +
            '<td style="font-family: monospace; font-size: 11px;">' + ISNULL(IncludedColumns, '<span class="null-value">-</span>') + '</td>' +
            '<td class="metric-value">' + ISNULL(FORMAT(AvgUserImpact, 'N2'), '<span class="null-value">NULL</span>') + '%</td>' +
            '<td>' + ISNULL(FORMAT(UserSeeks, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
            '<td class="metric-value">' + ISNULL(FORMAT(ImpactScore, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
            '</tr>'
            AS [text()]
        FROM (
            SELECT
                REPLACE(DatabaseName, CHAR(0), '') AS DatabaseName,
                REPLACE(ObjectName, CHAR(0), '') AS ObjectName,
                REPLACE(EqualityColumns, CHAR(0), '') AS EqualityColumns,
                REPLACE(InequalityColumns, CHAR(0), '') AS InequalityColumns,
                REPLACE(IncludedColumns, CHAR(0), '') AS IncludedColumns,
                AvgUserImpact,
                UserSeeks,
                ImpactScore
            FROM dbo.PerfSnapshotMissingIndexes
            WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
        ) cleaned
        ORDER BY ImpactScore DESC
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') + '</table></div>'

        SET @HTML = @HTML + @MissingIndexesHTML
    END

    -- =============================================
    -- RESULT SET 9: Database Sizes
    -- =============================================
    DECLARE @DatabaseSizesHTML NVARCHAR(MAX) = ''

    SELECT @DatabaseSizesHTML = '<div class="section">
    <div class="section-header">Database Sizes</div>
    <table>
        <tr>
            <th>Database</th>
            <th>State</th>
            <th>Recovery Model</th>
            <th>Data Size (MB)</th>
            <th>Log Size (MB)</th>
            <th>Total Size (MB)</th>
            <th>Log Reuse Wait</th>
        </tr>' +
    (SELECT
        '<tr>' +
        '<td>' + ISNULL(DatabaseName, '<span class="null-value">NULL</span>') + '</td>' +
        '<td>' + ISNULL(StateDesc, '<span class="null-value">NULL</span>') + '</td>' +
        '<td>' + ISNULL(RecoveryModelDesc, '<span class="null-value">NULL</span>') + '</td>' +
        '<td class="metric-value">' + ISNULL(FORMAT(TotalDataMB, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
        '<td class="metric-value">' + ISNULL(FORMAT(TotalLogMB, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
        '<td class="metric-value">' + ISNULL(FORMAT(TotalDataMB + TotalLogMB, 'N0'), '<span class="null-value">NULL</span>') + '</td>' +
        '<td style="font-size: 11px;">' + ISNULL(LogReuseWaitDesc, '<span class="null-value">NULL</span>') + '</td>' +
        '</tr>'
        AS [text()]
    FROM (
        SELECT
            REPLACE(DatabaseName, CHAR(0), '') AS DatabaseName,
            REPLACE(StateDesc, CHAR(0), '') AS StateDesc,
            REPLACE(RecoveryModelDesc, CHAR(0), '') AS RecoveryModelDesc,
            REPLACE(LogReuseWaitDesc, CHAR(0), '') AS LogReuseWaitDesc,
            TotalDataMB,
            TotalLogMB
        FROM dbo.PerfSnapshotDB
        WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
    ) cleaned
    ORDER BY (TotalDataMB + TotalLogMB) DESC
    FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') + '</table></div>'

    SET @HTML = @HTML + @DatabaseSizesHTML

    -- =============================================
    -- RESULT SET 10: Recent Error Log
    -- =============================================
    DECLARE @ErrorLogHTML NVARCHAR(MAX) = ''

    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotErrorLog WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun))
    BEGIN
        SELECT @ErrorLogHTML = '<div class="section">
        <div class="section-header">Recent Error Log Entries (Last 20)</div>
        <table>
            <tr>
                <th>Date/Time (UTC)</th>
                <th>Process</th>
                <th>Message</th>
            </tr>' +
        (SELECT
            '<tr>' +
            '<td style="white-space: nowrap;">' + ISNULL(CONVERT(NVARCHAR(50), LogDateUTC, 120), '<span class="null-value">NULL</span>') + '</td>' +
            '<td>' + ISNULL(ProcessInfo, '<span class="null-value">NULL</span>') + '</td>' +
            '<td style="font-size: 11px;">' + ISNULL(REPLACE(REPLACE(LogText, '<', '&lt;'), '>', '&gt;'), '<span class="null-value">NULL</span>') + '</td>' +
            '</tr>'
            AS [text()]
        FROM (
            SELECT
                LogDateUTC,
                REPLACE(ProcessInfo, CHAR(0), '') AS ProcessInfo,
                REPLACE(LogText, CHAR(0), '') AS LogText
            FROM dbo.PerfSnapshotErrorLog
            WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
        ) cleaned
        ORDER BY LogDateUTC DESC
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') + '</table></div>'

        SET @HTML = @HTML + @ErrorLogHTML
    END

    -- HTML Footer
    SET @HTML = @HTML + '
    <div class="footer">
        <p>Generated by DBATools.dbo.DBA_DailyHealthOverview_HTML</p>
        <p>SQL Server Health Monitoring System</p>
    </div>
</body>
</html>'

    -- Return HTML
    SELECT @HTML AS HTMLReport
END
GO

PRINT ''
PRINT '=========================================='
PRINT 'HTML Formatter Created Successfully'
PRINT '=========================================='
PRINT ''
PRINT 'Usage:'
PRINT '  EXEC DBATools.dbo.DBA_DailyHealthOverview_HTML'
PRINT '      @TopSlowQueries = 20,'
PRINT '      @TopMissingIndexes = 20,'
PRINT '      @HoursBackForIssues = 48'
PRINT ''
PRINT 'Output:'
PRINT '  - Single column named HTMLReport'
PRINT '  - Contains complete HTML document'
PRINT '  - Ready for web server, email, or file storage'
PRINT ''
PRINT 'To save to file (using sqlcmd):'
PRINT '  sqlcmd -S server -d DBATools -Q "EXEC DBA_DailyHealthOverview_HTML" -h -1 -W -o report.html'
PRINT ''
PRINT 'To serve via Python HTTP server:'
PRINT '  # Save HTML to file first, then:'
PRINT '  python -m http.server 8000'
PRINT '  # Open browser to http://localhost:8000/report.html'
PRINT '=========================================='
GO
