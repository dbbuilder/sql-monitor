#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy XML-safe text cleaning function and updated HTML formatter
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Server,

    [Parameter(Mandatory=$true)]
    [string]$User,

    [Parameter(Mandatory=$true)]
    [string]$Password
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Deploying XML fix to $Server..." -ForegroundColor Cyan
Write-Host ""

function Deploy-SqlFile {
    param([string]$FilePath, [string]$Description)

    Write-Host "[$Description]" -ForegroundColor Blue
    Write-Host "  File: $FilePath"
    Write-Host -NoNewline "  Executing... "

    try {
        $sql = Get-Content $FilePath -Raw -Encoding UTF8
        $batches = $sql -split '(?m)^\s*GO\s*$' | Where-Object { $_.Trim() }

        $conn = New-Object System.Data.SqlClient.SqlConnection
        $conn.ConnectionString = "Server=$Server;Database=DBATools;User Id=$User;Password=$Password;TrustServerCertificate=True;Encrypt=False;Connection Timeout=30"
        $conn.Open()

        foreach ($batch in $batches) {
            if ($batch.Trim()) {
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $batch
                $cmd.CommandTimeout = 60
                $cmd.ExecuteNonQuery() | Out-Null
                $cmd.Dispose()
            }
        }

        $conn.Close()
        $conn.Dispose()

        Write-Host "SUCCESS" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Deploy in order
Write-Host "Step 1: Create text cleaning function" -ForegroundColor Yellow
if (-not (Deploy-SqlFile (Join-Path $ScriptRoot "16_create_clean_text_function.sql") "fn_CleanTextForXML")) {
    exit 1
}

Write-Host ""
Write-Host "Step 2: Update HTML formatter to use cleaning function" -ForegroundColor Yellow
if (-not (Deploy-SqlFile (Join-Path $ScriptRoot "15_create_html_formatter.sql") "DBA_DailyHealthOverview_HTML")) {
    exit 1
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Green
Write-Host ""
Write-Host "The HTML formatter now uses fn_CleanTextForXML which:" -ForegroundColor Cyan
Write-Host "  - Extracts only printable characters (ASCII 32-126)" -ForegroundColor Cyan
Write-Host "  - Keeps tabs, line feeds, carriage returns (9, 10, 13)" -ForegroundColor Cyan
Write-Host "  - Keeps extended Latin characters (128-591)" -ForegroundColor Cyan
Write-Host "  - Removes ALL control characters including CHAR(0)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Now generate your HTML report:" -ForegroundColor Yellow
Write-Host "  .\Export-HealthReportHTML.ps1 -Server '$Server' -User '$User' -Password '***'" -ForegroundColor White
Write-Host ""
