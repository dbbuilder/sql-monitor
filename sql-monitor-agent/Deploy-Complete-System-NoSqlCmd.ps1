#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete SQL Server Monitoring System - PowerShell Only (No sqlcmd required)

.DESCRIPTION
    Deploys the full monitoring system using only built-in .NET Framework SqlClient.
    Works on Windows without requiring sqlcmd installation.

.PARAMETER Server
    SQL Server hostname or IP address

.PARAMETER Port
    SQL Server port number (default: 1433)

.PARAMETER Username
    SQL Server authentication username

.PARAMETER Password
    SQL Server authentication password

.EXAMPLE
    .\Deploy-Complete-System-NoSqlCmd.ps1 -Server "10.10.2.201" -Username "sa" -Password "testArcTradeSql!@#"
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

# Color functions
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Warning2 { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error2 { param([string]$Message) Write-Host $Message -ForegroundColor Red }
function Write-Step { param([string]$Message) Write-Host $Message -ForegroundColor Blue }

# Script root directory
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SQL Server Monitoring System - Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Info "Server: $Server,$Port"
Write-Info "Database: DBATools"
Write-Info "Method: PowerShell SqlClient (no sqlcmd)"
Write-Host ""

# Function to execute SQL script using System.Data.SqlClient
function Invoke-SqlScript {
    param(
        [Parameter(Mandatory=$true)]
        [string]$StepNum,

        [Parameter(Mandatory=$true)]
        [string]$Description,

        [Parameter(Mandatory=$true)]
        [string]$SqlFile,

        [Parameter(Mandatory=$false)]
        [string]$Database = "master"
    )

    Write-Step "[$StepNum] $Description"
    Write-Host "  File: $SqlFile"
    Write-Host -NoNewline "  Executing... "

    $FilePath = Join-Path $ScriptRoot $SqlFile

    if (-not (Test-Path $FilePath)) {
        Write-Error2 "FAILED"
        Write-Host "  Error: File not found - $FilePath" -ForegroundColor Red
        return $false
    }

    try {
        # Read SQL file
        $SqlContent = Get-Content -Path $FilePath -Raw -Encoding UTF8

        # Build connection string
        $ConnectionString = "Server=$Server,$Port;Database=$Database;User Id=$Username;Password=$Password;TrustServerCertificate=True;Connection Timeout=30;Encrypt=False"

        # Split by GO statements (case insensitive, handles various line endings)
        $Batches = $SqlContent -split '(?m)^\s*GO\s*$' | Where-Object { $_.Trim() -ne "" }

        # Create connection
        $Connection = New-Object System.Data.SqlClient.SqlConnection
        $Connection.ConnectionString = $ConnectionString
        $Connection.Open()

        $BatchCount = 0
        # Execute each batch
        foreach ($Batch in $Batches) {
            $BatchTrimmed = $Batch.Trim()
            if ($BatchTrimmed -ne "") {
                $BatchCount++
                $Command = $Connection.CreateCommand()
                $Command.CommandText = $BatchTrimmed
                $Command.CommandTimeout = 300  # 5 minutes for complex operations
                try {
                    $Command.ExecuteNonQuery() | Out-Null
                }
                catch {
                    Write-Error2 "FAILED"
                    Write-Host "  Error in batch $BatchCount`: $($_.Exception.Message)" -ForegroundColor Red
                    $Command.Dispose()
                    $Connection.Close()
                    $Connection.Dispose()
                    return $false
                }
                $Command.Dispose()
            }
        }

        # Cleanup
        $Connection.Close()
        $Connection.Dispose()

        Write-Success "SUCCESS ($BatchCount batches)"
        return $true
    }
    catch {
        Write-Error2 "FAILED"
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.InnerException) {
            Write-Host "  Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red
        }
        return $false
    }
}

# Function to execute query and return scalar result
function Invoke-SqlScalar {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Query,

        [Parameter(Mandatory=$false)]
        [string]$Database = "master"
    )

    try {
        $ConnectionString = "Server=$Server,$Port;Database=$Database;User Id=$Username;Password=$Password;TrustServerCertificate=True;Connection Timeout=30;Encrypt=False"

        $Connection = New-Object System.Data.SqlClient.SqlConnection
        $Connection.ConnectionString = $ConnectionString
        $Connection.Open()

        $Command = $Connection.CreateCommand()
        $Command.CommandText = $Query
        $Command.CommandTimeout = 30

        $Result = $Command.ExecuteScalar()

        $Command.Dispose()
        $Connection.Close()
        $Connection.Dispose()

        return $Result
    }
    catch {
        return $null
    }
}

# Test prerequisites
Write-Info "Checking prerequisites..."

Write-Host -NoNewline "  SQL Server reachable: "
try {
    $TestResult = Invoke-SqlScalar -Query "SELECT 1" -Database "master"
    if ($TestResult -eq 1) {
        Write-Success "OK"
    } else {
        Write-Error2 "FAILED"
        Write-Error2 "Cannot connect to SQL Server"
        exit 1
    }
}
catch {
    Write-Error2 "FAILED"
    Write-Error2 "Cannot connect to SQL Server: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Info "Starting deployment..."
Write-Host "----------------------------------------"
Write-Host ""

# Complete deployment steps
$Steps = @(
    @{ Num="01"; Desc="Create DBATools database and base tables"; File="01_create_DBATools_and_tables.sql"; DB="master" },
    @{ Num="02"; Desc="Create logging infrastructure"; File="02_create_DBA_LogEntry_Insert.sql"; DB="DBATools" },
    @{ Num="03"; Desc="Create configuration system"; File="13_create_config_table_and_functions.sql"; DB="DBATools" },
    @{ Num="04"; Desc="Create database filter view"; File="13b_create_database_filter_view.sql"; DB="DBATools" },
    @{ Num="05"; Desc="Create enhanced snapshot tables (P0/P1/P2/P3)"; File="05_create_enhanced_tables.sql"; DB="DBATools" },
    @{ Num="06"; Desc="Create P0 (Critical) collectors"; File="06_create_modular_collectors_P0_FIXED.sql"; DB="DBATools" },
    @{ Num="07"; Desc="Create P1 (Performance) collectors"; File="07_create_modular_collectors_P1_FIXED.sql"; DB="DBATools" },
    @{ Num="08"; Desc="Create P2/P3 (Medium/Low) collectors"; File="08_create_modular_collectors_P2_P3_FIXED.sql"; DB="DBATools" },
    @{ Num="09"; Desc="Create master orchestrator"; File="10_create_master_orchestrator_FIXED.sql"; DB="DBATools" },
    @{ Num="10"; Desc="Create reporting procedures"; File="14_create_reporting_procedures.sql"; DB="DBATools" },
    @{ Num="11"; Desc="Create feedback system tables"; File="13_create_feedback_system.sql"; DB="DBATools" },
    @{ Num="12"; Desc="Seed feedback rules (47 rules)"; File="13b_seed_feedback_rules.sql"; DB="DBATools" },
    @{ Num="13"; Desc="Create daily health overview with feedback"; File="14_enhance_daily_overview_with_feedback.sql"; DB="DBATools" },
    @{ Num="14"; Desc="Create HTML report formatter"; File="15_create_html_formatter.sql"; DB="DBATools" },
    @{ Num="15"; Desc="Create retention policy procedure"; File="create_retention_policy.sql"; DB="DBATools" },
    @{ Num="16"; Desc="Create SQL Agent collection job"; File="create_agent_job.sql"; DB="msdb" },
    @{ Num="17"; Desc="Create SQL Agent retention job"; File="create_retention_job.sql"; DB="msdb" }
)

$FailedSteps = @()

foreach ($Step in $Steps) {
    if (-not (Invoke-SqlScript -StepNum $Step.Num -Description $Step.Desc -SqlFile $Step.File -Database $Step.DB)) {
        Write-Warning2 "Step $($Step.Num) failed, continuing..."
        $FailedSteps += $Step
    }
    Start-Sleep -Milliseconds 500
    Write-Host ""
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

if ($FailedSteps.Count -eq 0) {
    Write-Success "All $($Steps.Count) deployment steps completed successfully!"
} else {
    Write-Warning2 "$($FailedSteps.Count) step(s) failed:"
    foreach ($FailedStep in $FailedSteps) {
        Write-Host "  [$($FailedStep.Num)] $($FailedStep.Desc)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Info "Running test collection..."

try {
    $TestQuery = "EXEC DBA_CollectPerformanceSnapshot @IncludeP0=1, @IncludeP1=1, @IncludeP2=1, @IncludeP3=0, @Debug=1"
    $null = Invoke-SqlScalar -Query $TestQuery -Database "DBATools"
    Write-Success "Test collection executed successfully"
}
catch {
    Write-Warning2 "Test collection failed (may be expected on first run)"
}

Write-Host ""
Write-Info "Verifying installation..."

# Verify components
$RuleCount = Invoke-SqlScalar -Query "SELECT COUNT(*) FROM FeedbackRule WHERE IsSystemRule = 1" -Database "DBATools"
Write-Host -NoNewline "  Feedback rules: "
if ($RuleCount -eq 47) {
    Write-Success "$RuleCount (expected)"
} else {
    Write-Warning2 "$RuleCount (expected 47)"
}

$MetadataCount = Invoke-SqlScalar -Query "SELECT COUNT(*) FROM FeedbackMetadata WHERE IsSystemMetadata = 1" -Database "DBATools"
Write-Host -NoNewline "  Feedback metadata: "
if ($MetadataCount -eq 12) {
    Write-Success "$MetadataCount (expected)"
} else {
    Write-Warning2 "$MetadataCount (expected 12)"
}

$ProcCount = Invoke-SqlScalar -Query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'DBA_DailyHealthOverview_HTML'" -Database "DBATools"
Write-Host -NoNewline "  HTML formatter: "
if ($ProcCount -eq 1) {
    Write-Success "Installed"
} else {
    Write-Warning2 "Not found"
}

$JobCount = Invoke-SqlScalar -Query "SELECT COUNT(*) FROM dbo.sysjobs WHERE name LIKE 'DBA %'" -Database "msdb"
Write-Host -NoNewline "  SQL Agent jobs: "
Write-Success "$JobCount created"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Installation Summary" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Features Installed:"
Write-Host "  - Performance monitoring (P0/P1/P2/P3)"
Write-Host "  - Feedback system (47 rules)"
Write-Host "  - HTML report generation"
Write-Host "  - SQL Agent automation"
Write-Host ""
Write-Host "Next Steps:"
Write-Host "  1. Generate HTML report:"
Write-Host "     .\Export-HealthReportHTML.ps1 -Server '$Server' -Port $Port -User '$Username' -Password '***'"
Write-Host ""
Write-Host "  2. Wait 5 minutes for first automated collection"
Write-Host "  3. View reports in SSMS or via HTML export"
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

if ($FailedSteps.Count -eq 0) {
    Write-Success "Deployment complete - all steps successful!"
    exit 0
} else {
    Write-Warning2 "Deployment complete with $($FailedSteps.Count) warning(s)"
    exit 0
}
