-- =============================================
-- Export HTML report to file
-- Usage: sqlcmd -S server -U user -P pass -C -d DBATools -i export_html_report.sql
-- =============================================

SET NOCOUNT ON
GO

-- Generate HTML into temp table
IF OBJECT_ID('tempdb..#HTMLReport') IS NOT NULL
    DROP TABLE #HTMLReport

CREATE TABLE #HTMLReport (HTMLContent NVARCHAR(MAX))

INSERT INTO #HTMLReport
EXEC DBATools.dbo.DBA_DailyHealthOverview_HTML
    @TopSlowQueries = 20,
    @TopMissingIndexes = 20,
    @HoursBackForIssues = 48

-- Output with maximum width
SELECT HTMLContent FROM #HTMLReport
GO
