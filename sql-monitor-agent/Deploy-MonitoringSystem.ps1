#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete SQL Server Monitoring System Deployment

.DESCRIPTION
    Deploys all components of the SQL Server monitoring system in correct order.
    Uses Microsoft.Data.SqlClient for reliable connections.

.PARAMETER Server
    SQL Server hostname or IP address

.PARAMETER Port
    SQL Server port number (default: 14333)

.PARAMETER Username
    SQL Server authentication username

.PARAMETER Password
    SQL Server authentication password

.EXAMPLE
    pwsh Deploy-MonitoringSystem.ps1 -Server svweb -Port 14333 -Username sv -Password 'Gv51076!'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Server = "svweb",

    [Parameter(Mandatory=$false)]
    [int]$Port = 14333,

    [Parameter(Mandatory=$false)]
    [string]$Username = "sv",

    [Parameter(Mandatory=$false)]
    [string]$Password = "Gv51076!"
)

# Import SqlClient assembly (use Unix runtime version for WSL)
Add-Type -Path "$HOME/.nuget/packages/microsoft.data.sqlclient/6.1.2/runtimes/unix/lib/net8.0/Microsoft.Data.SqlClient.dll"

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
Write-Host "SQL Server Monitoring System Deployment" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Info "Server: $Server,$Port"
Write-Info "Database: DBATools"
Write-Host ""

# Build connection string
$ConnectionString = "Server=$Server,$Port;User Id=$Username;Password=$Password;TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30"

# Function to execute SQL script
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
        $SqlContent = Get-Content -Path $FilePath -Raw

        # Build connection string with database
        $ConnStr = $ConnectionString
        if ($Database -ne "master") {
            $ConnStr = "Server=$Server,$Port;Database=$Database;User Id=$Username;Password=$Password;TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30"
        }

        # Split SQL content by GO batch separator (sqlcmd behavior)
        $Batches = $SqlContent -split '\r?\nGO\r?\n|\r?\nGO$|^GO\r?\n' | Where-Object { $_.Trim() -ne "" }

        # Create connection
        $Connection = New-Object Microsoft.Data.SqlClient.SqlConnection
        $Connection.ConnectionString = $ConnStr
        $Connection.Open()

        # Execute each batch
        foreach ($Batch in $Batches) {
            if ($Batch.Trim() -ne "") {
                $Command = $Connection.CreateCommand()
                $Command.CommandText = $Batch
                $Command.CommandTimeout = 120
                $Command.ExecuteNonQuery() | Out-Null
                $Command.Dispose()
            }
        }

        # Cleanup
        $Connection.Close()
        $Connection.Dispose()

        Write-Success "SUCCESS"
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

# Function to verify step
function Test-SqlQuery {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Description,

        [Parameter(Mandatory=$true)]
        [string]$Query,

        [Parameter(Mandatory=$false)]
        [string]$Database = "DBATools"
    )

    Write-Host -NoNewline "  Verifying... "

    try {
        # Build connection string with database
        $ConnStr = "Server=$Server,$Port;Database=$Database;User Id=$Username;Password=$Password;TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30"

        # Create connection
        $Connection = New-Object Microsoft.Data.SqlClient.SqlConnection
        $Connection.ConnectionString = $ConnStr
        $Connection.Open()

        # Create command
        $Command = $Connection.CreateCommand()
        $Command.CommandText = $Query
        $Command.CommandTimeout = 30

        # Execute and get result
        $Result = $Command.ExecuteScalar()

        # Cleanup
        $Command.Dispose()
        $Connection.Close()
        $Connection.Dispose()

        if ($Result -and $Result -gt 0) {
            Write-Success "OK ($Result)"
            return $true
        }
        else {
            Write-Warning2 "WARNING (no results or zero count)"
            return $true  # Don't fail on verification warnings
        }
    }
    catch {
        Write-Error2 "FAILED"
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Test prerequisites
Write-Info "Checking prerequisites..."

Write-Host -NoNewline "  Network connectivity: "
if (Test-Connection -ComputerName $Server -Count 1 -Quiet) {
    Write-Success "OK"
}
else {
    Write-Error2 "FAILED"
    Write-Error2 "Cannot reach server $Server"
    exit 1
}

Write-Host -NoNewline "  SQL Server reachable: "
try {
    $TestConn = New-Object Microsoft.Data.SqlClient.SqlConnection
    $TestConn.ConnectionString = $ConnectionString
    $TestConn.Open()
    $TestConn.Close()
    $TestConn.Dispose()
    Write-Success "OK"
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

# Deployment steps with proper ordering
$Steps = @(
    @{ Num="01"; Desc="Create DBATools database and base tables"; File="01_create_DBATools_and_tables.sql"; DB="master"; Verify="SELECT COUNT(*) FROM sys.tables WHERE name IN ('LogEntry','PerfSnapshotRun','PerfSnapshotDB','PerfSnapshotWorkload','PerfSnapshotErrorLog')"; VerifyDB="DBATools" },
    @{ Num="02"; Desc="Create logging infrastructure"; File="02_create_DBA_LogEntry_Insert.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM sys.procedures WHERE name = 'DBA_LogEntry_Insert'"; VerifyDB="DBATools" },
    @{ Num="03"; Desc="Create configuration system"; File="13_create_config_table_and_functions.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM dbo.MonitoringConfig"; VerifyDB="DBATools" },
    @{ Num="04"; Desc="Create database filter view"; File="13b_create_database_filter_view.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM dbo.vw_MonitoredDatabases"; VerifyDB="DBATools" },
    @{ Num="05"; Desc="Create enhanced snapshot tables (P0/P1/P2/P3)"; File="05_create_enhanced_tables.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM sys.tables WHERE name LIKE 'PerfSnapshot%'"; VerifyDB="DBATools" },
    @{ Num="06"; Desc="Create P0 (Critical) collectors"; File="06_create_modular_collectors_P0_FIXED.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'DBA_Collect_P0%'"; VerifyDB="DBATools" },
    @{ Num="07"; Desc="Create P1 (Performance) collectors"; File="07_create_modular_collectors_P1_FIXED.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'DBA_Collect_P1%'"; VerifyDB="DBATools" },
    @{ Num="08"; Desc="Create P2/P3 (Medium/Low) collectors"; File="08_create_modular_collectors_P2_P3_FIXED.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'DBA_Collect_P2%'"; VerifyDB="DBATools" },
    @{ Num="09"; Desc="Create master orchestrator"; File="10_create_master_orchestrator_FIXED.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM sys.procedures WHERE name = 'DBA_CollectPerformanceSnapshot'"; VerifyDB="DBATools" },
    @{ Num="10"; Desc="Create reporting procedures"; File="14_create_reporting_procedures.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'DBA_%' AND name NOT LIKE 'DBA_Collect%' AND name NOT LIKE 'DBA_LogEntry%'"; VerifyDB="DBATools" },
    @{ Num="11"; Desc="Create retention policy procedure"; File="create_retention_policy.sql"; DB="DBATools"; Verify="SELECT COUNT(*) FROM sys.procedures WHERE name = 'DBA_PurgeOldSnapshots'"; VerifyDB="DBATools" },
    @{ Num="12"; Desc="Create SQL Agent collection job"; File="create_agent_job.sql"; DB="msdb"; Verify="SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot'"; VerifyDB="msdb" },
    @{ Num="13"; Desc="Create SQL Agent retention job"; File="create_retention_job.sql"; DB="msdb"; Verify="SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name = 'DBA Purge Old Snapshots'"; VerifyDB="msdb" }
)

foreach ($Step in $Steps) {
    if (-not (Invoke-SqlScript -StepNum $Step.Num -Description $Step.Desc -SqlFile $Step.File -Database $Step.DB)) {
        Write-Error2 "Deployment failed at step $($Step.Num)"
        exit 1
    }
    Test-SqlQuery -Description $Step.Desc -Query $Step.Verify -Database $Step.VerifyDB
    Write-Host ""
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

Write-Success "All 13 deployment steps completed successfully!"
Write-Host ""
Write-Info "Running test collection (P0+P1+P2)..."

# Run test collection
Write-Host -NoNewline "  Executing... "
$StartTime = Get-Date
try {
    $ConnStr = "Server=$Server,$Port;Database=DBATools;User Id=$Username;Password=$Password;TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30"
    $Connection = New-Object Microsoft.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnStr
    $Connection.Open()

    $Command = $Connection.CreateCommand()
    $Command.CommandText = "EXEC DBA_CollectPerformanceSnapshot @IncludeP0=1, @IncludeP1=1, @IncludeP2=1, @IncludeP3=0, @Debug=1"
    $Command.CommandTimeout = 60
    $Command.ExecuteNonQuery() | Out-Null

    $Command.Dispose()
    $Connection.Close()
    $Connection.Dispose()

    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalMilliseconds
    Write-Success "SUCCESS ($([int]$Duration) ms)"

    # Get run ID
    $Connection2 = New-Object Microsoft.Data.SqlClient.SqlConnection
    $Connection2.ConnectionString = $ConnStr
    $Connection2.Open()

    $Command2 = $Connection2.CreateCommand()
    $Command2.CommandText = "SELECT TOP 1 PerfSnapshotRunID FROM dbo.PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC"
    $RunID = $Command2.ExecuteScalar()

    $Command2.Dispose()
    $Connection2.Close()
    $Connection2.Dispose()

    if ($RunID) {
        Write-Host "  Run ID: $RunID"
        Write-Host ""
        Write-Info "Verifying data collection..."

        $Tables = @(
            "PerfSnapshotQueryStats", "PerfSnapshotIOStats", "PerfSnapshotMemory", "PerfSnapshotBackupHistory",
            "PerfSnapshotIndexUsage", "PerfSnapshotMissingIndexes", "PerfSnapshotWaitStats",
            "PerfSnapshotConfig", "PerfSnapshotCounters", "PerfSnapshotSchedulers"
        )

        foreach ($Table in $Tables) {
            $Connection3 = New-Object Microsoft.Data.SqlClient.SqlConnection
            $Connection3.ConnectionString = $ConnStr
            $Connection3.Open()

            $Command3 = $Connection3.CreateCommand()
            $Command3.CommandText = "SELECT COUNT(*) FROM dbo.$Table WHERE PerfSnapshotRunID = $RunID"
            $Count = $Command3.ExecuteScalar()

            $Command3.Dispose()
            $Connection3.Close()
            $Connection3.Dispose()

            if ($Count -and $Count -gt 0) {
                Write-Host "  $Table`: " -NoNewline
                Write-Success "$Count rows"
            }
            else {
                Write-Host "  $Table`: " -NoNewline
                Write-Warning2 "0 rows"
            }
        }
    }
}
catch {
    Write-Error2 "FAILED"
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Deployment Summary" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

# Get counts
try {
    $ConnStr = "Server=$Server,$Port;Database=DBATools;User Id=$Username;Password=$Password;TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30"

    # Tables count
    $Connection = New-Object Microsoft.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnStr
    $Connection.Open()
    $Command = $Connection.CreateCommand()
    $Command.CommandText = "SELECT COUNT(*) FROM sys.tables"
    $TablesCount = $Command.ExecuteScalar()
    $Command.Dispose()
    $Connection.Close()
    $Connection.Dispose()

    # Procedures count
    $Connection = New-Object Microsoft.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnStr
    $Connection.Open()
    $Command = $Connection.CreateCommand()
    $Command.CommandText = "SELECT COUNT(*) FROM sys.procedures"
    $ProceduresCount = $Command.ExecuteScalar()
    $Command.Dispose()
    $Connection.Close()
    $Connection.Dispose()

    # Functions count
    $Connection = New-Object Microsoft.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnStr
    $Connection.Open()
    $Command = $Connection.CreateCommand()
    $Command.CommandText = "SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN','IF','TF')"
    $FunctionsCount = $Command.ExecuteScalar()
    $Command.Dispose()
    $Connection.Close()
    $Connection.Dispose()

    # Views count
    $Connection = New-Object Microsoft.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnStr
    $Connection.Open()
    $Command = $Connection.CreateCommand()
    $Command.CommandText = "SELECT COUNT(*) FROM sys.views"
    $ViewsCount = $Command.ExecuteScalar()
    $Command.Dispose()
    $Connection.Close()
    $Connection.Dispose()

    # Jobs count
    $ConnStr2 = "Server=$Server,$Port;Database=msdb;User Id=$Username;Password=$Password;TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30"
    $Connection = New-Object Microsoft.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnStr2
    $Connection.Open()
    $Command = $Connection.CreateCommand()
    $Command.CommandText = "SELECT COUNT(*) FROM dbo.sysjobs WHERE name LIKE 'DBA %'"
    $JobsCount = $Command.ExecuteScalar()
    $Command.Dispose()
    $Connection.Close()
    $Connection.Dispose()

    Write-Host "Database: DBATools"
    Write-Host "Tables: $TablesCount"
    Write-Host "Procedures: $ProceduresCount"
    Write-Host "Functions: $FunctionsCount"
    Write-Host "Views: $ViewsCount"
    Write-Host "SQL Agent Jobs: $JobsCount"
}
catch {
    Write-Warning2 "Could not retrieve summary counts: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Collection Schedule: Every 5 minutes (P0+P1+P2)"
Write-Host "Retention Policy: 14 days (purged daily at 2 AM)"
Write-Host "Expected Performance: <20 seconds per collection"
Write-Host ""
Write-Host "Next Steps:"
Write-Host "  1. Review test collection results above"
Write-Host "  2. Monitor job execution: EXEC msdb.dbo.sp_help_jobhistory @job_name='DBA Collect Perf Snapshot'"
Write-Host "  3. View system health: EXEC DBATools.dbo.DBA_CheckSystemHealth"
Write-Host "  4. Check backup status: EXEC DBATools.dbo.DBA_ShowBackupStatus"
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Success "Deployment complete!"
