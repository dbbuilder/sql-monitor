USE DBATools
GO

SET NOCOUNT ON
SET QUOTED_IDENTIFIER ON

DECLARE @HTML NVARCHAR(MAX) = ''
DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME

SET @HTML = '<!DOCTYPE html><html><head><title>Test</title></head><body><h1>Server: ' + @ServerName + '</h1>'

-- Try to build report header section
DECLARE @ReportHeaderHTML NVARCHAR(MAX) = ''

SELECT @ReportHeaderHTML = '<table>' +
(SELECT
    '<tr><td>Server</td><td>' + ISNULL(ServerName, 'NULL') + '</td></tr>' +
    '<tr><td>Snapshot</td><td>' + ISNULL(CONVERT(NVARCHAR(50), SnapshotUTC, 120), 'NULL') + '</td></tr>'
    AS [text()]
FROM dbo.PerfSnapshotRun
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') + '</table>'

SET @HTML = @HTML + @ReportHeaderHTML + '</body></html>'

SELECT LEN(@HTML) AS HTMLLength, LEFT(@HTML, 500) AS HTML_Preview
