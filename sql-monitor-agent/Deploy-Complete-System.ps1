#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete SQL Server Monitoring System with Feedback and HTML Reporting

.DESCRIPTION
    Deploys the full monitoring system including:
    - Base monitoring infrastructure (P0/P1/P2/P3 collectors)
    - Feedback system with configurable rules
    - HTML report generation
    - SQL Agent jobs for automated collection and retention

.PARAMETER Server
    SQL Server hostname or IP address

.PARAMETER Port
    SQL Server port number (default: 1433)

.PARAMETER Username
    SQL Server authentication username

.PARAMETER Password
    SQL Server authentication password

.EXAMPLE
    pwsh Deploy-Complete-System.ps1 -Server "10.10.2.201" -Username "sa" -Password "testArcTradeSql!@#"
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

# Color functions for output
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
Write-Host ""

# Build base connection string
$ServerPort = "$Server,$Port"

# Function to execute SQL script using sqlcmd
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
        if ($Database -eq "master") {
            $result = sqlcmd -S $ServerPort -U $Username -P $Password -C -i $FilePath -b 2>&1
        } else {
            $result = sqlcmd -S $ServerPort -U $Username -P $Password -C -d $Database -i $FilePath -b 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Error2 "FAILED"
            Write-Host "  Error: sqlcmd returned exit code $LASTEXITCODE" -ForegroundColor Red
            Write-Host "  Output: $result" -ForegroundColor Red
            return $false
        }

        Write-Success "SUCCESS"
        return $true
    }
    catch {
        Write-Error2 "FAILED"
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Test prerequisites
Write-Info "Checking prerequisites..."

Write-Host -NoNewline "  sqlcmd available: "
if (Get-Command sqlcmd -ErrorAction SilentlyContinue) {
    Write-Success "OK"
}
else {
    Write-Error2 "FAILED"
    Write-Error2 "sqlcmd not found. Please install SQL Server command line tools."
    exit 1
}

Write-Host -NoNewline "  SQL Server reachable: "
try {
    $testResult = sqlcmd -S $ServerPort -U $Username -P $Password -C -Q "SELECT 1" -b 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "OK"
    } else {
        Write-Error2 "FAILED"
        Write-Error2 "Cannot connect to SQL Server: $testResult"
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

# Complete deployment steps including feedback system and HTML formatter
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
        Write-Warning2 "Step $($Step.Num) failed, continuing with remaining steps..."
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
Write-Info "Running test collection (P0+P1+P2)..."

# Run test collection
Write-Host -NoNewline "  Executing... "
try {
    $result = sqlcmd -S $ServerPort -U $Username -P $Password -C -d DBATools `
        -Q "EXEC DBA_CollectPerformanceSnapshot @IncludeP0=1, @IncludeP1=1, @IncludeP2=1, @IncludeP3=0, @Debug=1" -b 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Success "SUCCESS"
    } else {
        Write-Warning2 "FAILED (may be expected if this is first run)"
    }
}
catch {
    Write-Warning2 "FAILED: $($_.Exception.Message)"
}

Write-Host ""
Write-Info "Verifying installation..."

# Verify feedback system
Write-Host -NoNewline "  Feedback rules: "
try {
    $result = sqlcmd -S $ServerPort -U $Username -P $Password -C -d DBATools `
        -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM FeedbackRule WHERE IsSystemRule = 1" -h -1 2>&1
    if ($LASTEXITCODE -eq 0) {
        $count = $result.Trim()
        if ($count -eq "47") {
            Write-Success "$count (expected)"
        } else {
            Write-Warning2 "$count (expected 47)"
        }
    }
}
catch {
    Write-Warning2 "Could not verify"
}

Write-Host -NoNewline "  Feedback metadata: "
try {
    $result = sqlcmd -S $ServerPort -U $Username -P $Password -C -d DBATools `
        -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM FeedbackMetadata WHERE IsSystemMetadata = 1" -h -1 2>&1
    if ($LASTEXITCODE -eq 0) {
        $count = $result.Trim()
        if ($count -eq "12") {
            Write-Success "$count (expected)"
        } else {
            Write-Warning2 "$count (expected 12)"
        }
    }
}
catch {
    Write-Warning2 "Could not verify"
}

Write-Host -NoNewline "  HTML formatter: "
try {
    $result = sqlcmd -S $ServerPort -U $Username -P $Password -C -d DBATools `
        -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.procedures WHERE name = 'DBA_DailyHealthOverview_HTML'" -h -1 2>&1
    if ($LASTEXITCODE -eq 0) {
        $count = $result.Trim()
        if ($count -eq "1") {
            Write-Success "Installed"
        } else {
            Write-Warning2 "Not found"
        }
    }
}
catch {
    Write-Warning2 "Could not verify"
}

Write-Host -NoNewline "  SQL Agent jobs: "
try {
    $result = sqlcmd -S $ServerPort -U $Username -P $Password -C -d msdb `
        -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.sysjobs WHERE name LIKE 'DBA %'" -h -1 2>&1
    if ($LASTEXITCODE -eq 0) {
        $count = $result.Trim()
        Write-Success "$count jobs created"
    }
}
catch {
    Write-Warning2 "Could not verify"
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Deployment Summary" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Database: DBATools"
Write-Host "Collection Schedule: Every 5 minutes (P0+P1+P2)"
Write-Host "Retention Policy: 14 days (purged daily at 2 AM)"
Write-Host "Expected Performance: <20 seconds per collection"
Write-Host ""
Write-Host "Features Installed:"
Write-Host "  - Performance snapshot collectors (P0/P1/P2/P3)"
Write-Host "  - Feedback system with 47 configurable rules"
Write-Host "  - Daily health overview with inline feedback"
Write-Host "  - HTML report generation"
Write-Host "  - Automated SQL Agent jobs"
Write-Host "  - Retention policies"
Write-Host ""
Write-Host "Next Steps:"
Write-Host "  1. Generate HTML report:"
Write-Host "     pwsh Export-HealthReportHTML.ps1 -Server '$ServerPort' -User '$Username' -Password '***'"
Write-Host ""
Write-Host "  2. View text report:"
Write-Host "     sqlcmd -S $ServerPort -U $Username -P *** -C -d DBATools -Q \"EXEC DBA_DailyHealthOverview\""
Write-Host ""
Write-Host "  3. Monitor job execution:"
Write-Host "     sqlcmd -S $ServerPort -U $Username -P *** -C -d msdb -Q \"EXEC sp_help_jobhistory @job_name='DBA Collect Perf Snapshot'\""
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
