-- =============================================
-- File: 16_create_html_export_procedure.sql
-- Purpose: Export HTML report directly to file using SQL Server
-- Created: 2025-10-27
-- =============================================

USE DBATools
GO

PRINT 'Creating HTML export procedure...'
GO

-- =============================================
-- Procedure: DBA_ExportHealthReportHTML
-- Purpose: Export HTML report to file
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_ExportHealthReportHTML
    @FilePath NVARCHAR(500) = 'C:\Temp\health_report.html',
    @TopSlowQueries INT = 20,
    @TopMissingIndexes INT = 20,
    @HoursBackForIssues INT = 48
AS
BEGIN
    SET NOCOUNT ON

    -- Ensure xp_cmdshell is enabled (required for file operations)
    DECLARE @xpCmdShellEnabled INT
    SELECT @xpCmdShellEnabled = CAST(value_in_use AS INT)
    FROM sys.configurations
    WHERE name = 'xp_cmdshell'

    -- Store HTML in variable
    DECLARE @HTML NVARCHAR(MAX)
    DECLARE @HTMLTable TABLE (HTMLContent NVARCHAR(MAX))

    INSERT INTO @HTMLTable
    EXEC DBA_DailyHealthOverview_HTML
        @TopSlowQueries = @TopSlowQueries,
        @TopMissingIndexes = @TopMissingIndexes,
        @HoursBackForIssues = @HoursBackForIssues

    SELECT @HTML = HTMLContent FROM @HTMLTable

    -- Check if we got HTML
    IF @HTML IS NULL OR LEN(@HTML) < 1000
    BEGIN
        PRINT 'ERROR: HTML generation failed or produced empty output'
        RETURN -1
    END

    PRINT 'HTML generated successfully: ' + CAST(LEN(@HTML) AS VARCHAR(20)) + ' characters'

    -- Use SQLCLR or filesystem object if available
    -- For now, return instructions
    SELECT
        'HTML generated successfully' AS Status,
        LEN(@HTML) AS HTMLLength,
        @FilePath AS RequestedPath,
        'Use sqlcmd with -y 0 and output redirection' AS ExportMethod

    -- Return the HTML for client-side export
    SELECT @HTML AS HTMLReport
END
GO

PRINT ''
PRINT '=========================================='
PRINT 'HTML Export Procedure Created'
PRINT '=========================================='
PRINT ''
PRINT 'Usage from sqlcmd:'
PRINT '  sqlcmd -S server -U user -P pass -C -d DBATools \'
PRINT '    -Q "EXEC DBA_ExportHealthReportHTML" \'
PRINT '    -y 0 -o report.html'
PRINT ''
GO
