#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Update HTML formatter with NULL character fix

.PARAMETER Server
    SQL Server hostname or IP address

.PARAMETER Port
    SQL Server port number (default: 1433)

.PARAMETER Username
    SQL Server authentication username

.PARAMETER Password
    SQL Server authentication password
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Server,

    [Parameter(Mandatory=$false)]
    [int]$Port = 1433,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [Parameter(Mandatory=$true)]
    [string]$Password
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SqlFile = Join-Path $ScriptRoot "15_create_html_formatter.sql"

Write-Host "Updating HTML formatter on $Server,$Port..." -ForegroundColor Cyan
Write-Host "  File: $SqlFile"
Write-Host ""

try {
    # Read SQL file
    $SqlContent = Get-Content -Path $SqlFile -Raw -Encoding UTF8

    # Build connection string
    $ConnectionString = "Server=$Server,$Port;Database=DBATools;User Id=$Username;Password=$Password;TrustServerCertificate=True;Connection Timeout=30;Encrypt=False"

    # Split by GO statements
    $Batches = $SqlContent -split '(?m)^\s*GO\s*$' | Where-Object { $_.Trim() -ne "" }

    # Create connection
    $Connection = New-Object System.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnectionString
    $Connection.Open()

    Write-Host -NoNewline "Executing... "

    # Execute each batch
    foreach ($Batch in $Batches) {
        $BatchTrimmed = $Batch.Trim()
        if ($BatchTrimmed -ne "") {
            $Command = $Connection.CreateCommand()
            $Command.CommandText = $BatchTrimmed
            $Command.CommandTimeout = 60
            $Command.ExecuteNonQuery() | Out-Null
            $Command.Dispose()
        }
    }

    # Cleanup
    $Connection.Close()
    $Connection.Dispose()

    Write-Host "SUCCESS" -ForegroundColor Green
    Write-Host ""
    Write-Host "HTML formatter updated successfully!" -ForegroundColor Green
    Write-Host "The NULL character issue has been fixed." -ForegroundColor Green
    Write-Host ""
    Write-Host "Try generating the HTML report again:" -ForegroundColor Cyan
    Write-Host "  .\Export-HealthReportHTML.ps1 -Server '$Server' -Port $Port -User '$Username' -Password '***'"
    Write-Host ""
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
