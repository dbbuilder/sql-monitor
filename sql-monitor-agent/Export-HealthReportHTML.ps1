<#
.SYNOPSIS
    Export SQL Server Health Report as HTML

.DESCRIPTION
    Generates a complete HTML health report from SQL Server monitoring data.
    Handles large NVARCHAR(MAX) output that sqlcmd truncates.

.PARAMETER Server
    SQL Server address (e.g., 'servername,14333')

.PARAMETER User
    SQL Server username

.PARAMETER Password
    SQL Server password

.PARAMETER OutputPath
    Output HTML file path (default: auto-generated with timestamp)

.PARAMETER TopSlowQueries
    Number of slow queries to include (default: 20)

.PARAMETER TopMissingIndexes
    Number of missing indexes to include (default: 20)

.PARAMETER HoursBackForIssues
    Hours to look back for statistics (default: 48)

.EXAMPLE
    .\Export-HealthReportHTML.ps1

.EXAMPLE
    .\Export-HealthReportHTML.ps1 -Server "svweb,14333" -User "sv" -Password "password"

.EXAMPLE
    .\Export-HealthReportHTML.ps1 -OutputPath "C:\Reports\health.html"
#>

param(
    [string]$Server = "sqltest.schoolvision.net,14333",
    [string]$User = "sv",
    [string]$Password = "Gv51076!",
    [string]$OutputPath = "",
    [int]$TopSlowQueries = 20,
    [int]$TopMissingIndexes = 20,
    [int]$HoursBackForIssues = 48
)

# Auto-generate filename if not provided
if ([string]::IsNullOrEmpty($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $reportsDir = Join-Path $scriptDir "reports"

    # Create reports directory if it doesn't exist
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir | Out-Null
    }

    $OutputPath = Join-Path $reportsDir "health_report_$timestamp.html"
}

Write-Host "=" * 60
Write-Host "SQL Server Health Report Generator"
Write-Host "=" * 60
Write-Host "Server:  $Server"
Write-Host "Output:  $OutputPath"
Write-Host ""

try {
    # Build connection string
    $connectionString = "Server=$Server;Database=DBATools;User Id=$User;Password=$Password;TrustServerCertificate=True;Connection Timeout=30"

    Write-Host "Connecting to SQL Server..."

    # Create SQL connection
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()

    Write-Host "Generating HTML report..."

    # Create SQL command
    $command = $connection.CreateCommand()
    $command.CommandText = @"
SET NOCOUNT ON
EXEC DBATools.dbo.DBA_DailyHealthOverview_HTML
    @TopSlowQueries = $TopSlowQueries,
    @TopMissingIndexes = $TopMissingIndexes,
    @HoursBackForIssues = $HoursBackForIssues
"@
    $command.CommandTimeout = 120

    # Execute and get result
    $reader = $command.ExecuteReader()

    if ($reader.Read()) {
        $htmlContent = $reader.GetString(0)

        if ([string]::IsNullOrEmpty($htmlContent)) {
            Write-Host ""
            Write-Host "ERROR: No HTML content returned from procedure" -ForegroundColor Red
            exit 1
        }

        # Write to file with UTF-8 encoding
        [System.IO.File]::WriteAllText($OutputPath, $htmlContent, [System.Text.Encoding]::UTF8)

        # Get file stats
        $fileInfo = Get-Item $OutputPath
        $fileSizeKB = [math]::Round($fileInfo.Length / 1024, 1)

        Write-Host ""
        Write-Host "✅ Report generated successfully" -ForegroundColor Green
        Write-Host "   File: $OutputPath"
        Write-Host "   Size: $($fileInfo.Length) bytes ($fileSizeKB KB)"
        Write-Host "   HTML Length: $($htmlContent.Length) characters"
        Write-Host ""

        # Offer to open in browser
        $open = Read-Host "Open in browser? (Y/N)"
        if ($open -eq 'Y' -or $open -eq 'y') {
            Start-Process $OutputPath
        }

        Write-Host ""
        Write-Host "Report location:"
        Write-Host "  file:///$($OutputPath.Replace('\', '/'))"

    } else {
        Write-Host ""
        Write-Host "ERROR: No data returned from procedure" -ForegroundColor Red
        exit 1
    }

    $reader.Close()
    $connection.Close()

} catch {
    Write-Host ""
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=" * 60
Write-Host "✅ Done" -ForegroundColor Green
Write-Host "=" * 60
