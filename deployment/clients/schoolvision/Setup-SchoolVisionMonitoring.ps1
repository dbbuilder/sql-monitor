# =============================================================================
# SchoolVision SQL Server Monitoring - Setup Script
# =============================================================================
# This script:
#   1. Prompts for new SQL password
#   2. Resets password on all 3 servers
#   3. Creates MonitoringDB on primary server (sqltest.schoolvision.net)
#   4. Registers all servers in monitoring system
#   5. Sets up linked servers for remote monitoring
#   6. Deploys monitoring infrastructure
#   7. Creates SQL Agent jobs for collection
# =============================================================================

param(
    [switch]$SkipPasswordReset,
    [switch]$SkipDatabaseCreation,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# =============================================================================
# Configuration
# =============================================================================

$ScriptDir = $PSScriptRoot
$ProjectRoot = (Get-Item $ScriptDir).Parent.Parent.Parent.FullName
$DatabaseScriptsPath = Join-Path $ProjectRoot "database"

# Load configuration
$EnvFile = Join-Path $ScriptDir ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Host "ERROR: .env file not found!" -ForegroundColor Red
    Write-Host "Please copy .env.template to .env and configure it first." -ForegroundColor Yellow
    exit 1
}

# Parse .env file
$Config = @{}
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+?)\s*=\s*(.+?)\s*$') {
        $Config[$matches[1].Trim()] = $matches[2].Trim()
    }
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  SCHOOLVISION SQL SERVER MONITORING - SETUP" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Client: $($Config.CLIENT_NAME)" -ForegroundColor Green
Write-Host "Environment: $($Config.CLIENT_ENVIRONMENT)" -ForegroundColor Green
Write-Host ""
Write-Host "Servers to Monitor:" -ForegroundColor Yellow
Write-Host "  1. Primary (MonitoringDB): $($Config.PRIMARY_SERVER_NAME) ($($Config.PRIMARY_SERVER_IP))" -ForegroundColor White
Write-Host "  2. Remote Server 1: $($Config.REMOTE_SERVER_1_NAME) ($($Config.REMOTE_SERVER_1_IP))" -ForegroundColor White
Write-Host "  3. Remote Server 2: $($Config.REMOTE_SERVER_2_NAME) ($($Config.REMOTE_SERVER_2_IP))" -ForegroundColor White
Write-Host ""

# =============================================================================
# Step 1: Password Reset
# =============================================================================

if (-not $SkipPasswordReset) {
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "STEP 1: PASSWORD RESET" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current password from .env: $($Config.SQL_PASSWORD)" -ForegroundColor Gray
    Write-Host ""

    $NewPassword = Read-Host "Enter NEW SQL password for 'sa' account" -AsSecureString
    $NewPasswordConfirm = Read-Host "Confirm NEW password" -AsSecureString

    $NewPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewPassword))
    $NewPasswordConfirmPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewPasswordConfirm))

    if ($NewPasswordPlain -ne $NewPasswordConfirmPlain) {
        Write-Host "ERROR: Passwords do not match!" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "Resetting password on all servers..." -ForegroundColor Yellow

    $Servers = @(
        @{Name=$Config.PRIMARY_SERVER_NAME; IP=$Config.PRIMARY_SERVER_IP; Port=$Config.PRIMARY_SERVER_PORT},
        @{Name=$Config.REMOTE_SERVER_1_NAME; IP=$Config.REMOTE_SERVER_1_IP; Port=$Config.REMOTE_SERVER_1_PORT},
        @{Name=$Config.REMOTE_SERVER_2_NAME; IP=$Config.REMOTE_SERVER_2_IP; Port=$Config.REMOTE_SERVER_2_PORT}
    )

    foreach ($Server in $Servers) {
        Write-Host "  Resetting password on $($Server.Name) ($($Server.IP))..." -NoNewline

        if ($WhatIf) {
            Write-Host " [WHATIF]" -ForegroundColor Gray
            continue
        }

        try {
            $SqlCmd = @"
ALTER LOGIN [sa] WITH PASSWORD = '$NewPasswordPlain';
GO
"@
            $SqlCmd | sqlcmd -S "$($Server.IP),$($Server.Port)" -U $Config.SQL_USER -P $Config.SQL_PASSWORD -C -b

            if ($LASTEXITCODE -eq 0) {
                Write-Host " SUCCESS" -ForegroundColor Green
            } else {
                Write-Host " FAILED" -ForegroundColor Red
                Write-Host "    Error code: $LASTEXITCODE" -ForegroundColor Red
            }
        }
        catch {
            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Update .env file with new password
    Write-Host ""
    Write-Host "Updating .env file with new password..." -ForegroundColor Yellow

    if (-not $WhatIf) {
        $EnvContent = Get-Content $EnvFile
        $EnvContent = $EnvContent -replace "SQL_PASSWORD=.*", "SQL_PASSWORD=$NewPasswordPlain"
        $EnvContent | Set-Content $EnvFile

        # Reload config
        $Config.SQL_PASSWORD = $NewPasswordPlain

        Write-Host "  .env file updated" -ForegroundColor Green
    } else {
        Write-Host "  [WHATIF] Would update .env file" -ForegroundColor Gray
    }

    Write-Host ""
} else {
    Write-Host "STEP 1: SKIPPED (--SkipPasswordReset)" -ForegroundColor Gray
    Write-Host ""
}

# =============================================================================
# Step 2: Test Connectivity
# =============================================================================

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "STEP 2: TEST CONNECTIVITY" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

$AllServersReachable = $true

foreach ($Server in $Servers) {
    Write-Host "  Testing $($Server.Name) ($($Server.IP))..." -NoNewline

    if ($WhatIf) {
        Write-Host " [WHATIF]" -ForegroundColor Gray
        continue
    }

    try {
        $TestQuery = "SELECT @@VERSION AS Version;"
        $Result = $TestQuery | sqlcmd -S "$($Server.IP),$($Server.Port)" -U $Config.SQL_USER -P $Config.SQL_PASSWORD -C -h -1 -W

        if ($LASTEXITCODE -eq 0) {
            Write-Host " CONNECTED" -ForegroundColor Green
        } else {
            Write-Host " FAILED" -ForegroundColor Red
            $AllServersReachable = $false
        }
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        $AllServersReachable = $false
    }
}

if (-not $AllServersReachable -and -not $WhatIf) {
    Write-Host ""
    Write-Host "ERROR: Not all servers are reachable!" -ForegroundColor Red
    Write-Host "Please verify network connectivity and credentials." -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# =============================================================================
# Step 3: Create MonitoringDB on Primary Server
# =============================================================================

if (-not $SkipDatabaseCreation) {
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "STEP 3: CREATE MONITORING DATABASE" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Creating MonitoringDB on $($Config.PRIMARY_SERVER_NAME)..." -ForegroundColor Yellow
    Write-Host ""

    # Get list of database scripts in order
    $DatabaseScripts = Get-ChildItem -Path $DatabaseScriptsPath -Filter "*.sql" |
        Where-Object { $_.Name -match '^\d+' } |
        Sort-Object Name

    Write-Host "Found $($DatabaseScripts.Count) database scripts" -ForegroundColor Gray
    Write-Host ""

    if ($WhatIf) {
        Write-Host "  [WHATIF] Would execute scripts:" -ForegroundColor Gray
        $DatabaseScripts | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Gray }
    } else {
        $SuccessCount = 0
        $FailCount = 0

        foreach ($Script in $DatabaseScripts) {
            Write-Host "  Executing $($Script.Name)..." -NoNewline

            try {
                sqlcmd -S "$($Config.PRIMARY_SERVER_IP),$($Config.PRIMARY_SERVER_PORT)" `
                       -U $Config.SQL_USER `
                       -P $Config.SQL_PASSWORD `
                       -C `
                       -i $Script.FullName `
                       -o "$ScriptDir\logs\$($Script.Name).log" `
                       -b

                if ($LASTEXITCODE -eq 0) {
                    Write-Host " SUCCESS" -ForegroundColor Green
                    $SuccessCount++
                } else {
                    Write-Host " FAILED (exit code: $LASTEXITCODE)" -ForegroundColor Red
                    $FailCount++
                }
            }
            catch {
                Write-Host " FAILED" -ForegroundColor Red
                Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
                $FailCount++
            }
        }

        Write-Host ""
        Write-Host "  Database Deployment Summary:" -ForegroundColor Yellow
        Write-Host "    Success: $SuccessCount" -ForegroundColor Green
        Write-Host "    Failed: $FailCount" -ForegroundColor $(if ($FailCount -gt 0) { "Red" } else { "Green" })
    }

    Write-Host ""
} else {
    Write-Host "STEP 3: SKIPPED (--SkipDatabaseCreation)" -ForegroundColor Gray
    Write-Host ""
}

# =============================================================================
# Step 4: Register Servers in MonitoringDB
# =============================================================================

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "STEP 4: REGISTER SERVERS" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

$RegisterServersScript = @"
USE MonitoringDB;
GO

-- Register Primary Server
EXEC dbo.usp_AddServer
    @ServerName = '$($Config.PRIMARY_SERVER_NAME)',
    @Environment = '$($Config.CLIENT_ENVIRONMENT)',
    @IsActive = 1;

-- Register Remote Server 1
EXEC dbo.usp_AddServer
    @ServerName = '$($Config.REMOTE_SERVER_1_NAME)',
    @Environment = '$($Config.CLIENT_ENVIRONMENT)',
    @IsActive = 1;

-- Register Remote Server 2
EXEC dbo.usp_AddServer
    @ServerName = '$($Config.REMOTE_SERVER_2_NAME)',
    @Environment = '$($Config.CLIENT_ENVIRONMENT)',
    @IsActive = 1;

-- Verify registration
SELECT ServerID, ServerName, Environment, IsActive, CreatedDate
FROM dbo.Servers
ORDER BY ServerID;
GO
"@

if ($WhatIf) {
    Write-Host "  [WHATIF] Would register 3 servers" -ForegroundColor Gray
} else {
    Write-Host "  Registering servers..." -ForegroundColor Yellow

    $RegisterServersScript | sqlcmd -S "$($Config.PRIMARY_SERVER_IP),$($Config.PRIMARY_SERVER_PORT)" `
                                    -U $Config.SQL_USER `
                                    -P $Config.SQL_PASSWORD `
                                    -C

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  SUCCESS: All servers registered" -ForegroundColor Green
    } else {
        Write-Host "  FAILED: Error registering servers (exit code: $LASTEXITCODE)" -ForegroundColor Red
    }
}

Write-Host ""

# =============================================================================
# Step 5: Create Linked Servers
# =============================================================================

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "STEP 5: CREATE LINKED SERVERS" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

$LinkedServersScript = @"
USE master;
GO

-- Drop existing linked servers if they exist
IF EXISTS (SELECT 1 FROM sys.servers WHERE name = '$($Config.LINKED_SERVER_1_NAME)')
    EXEC sp_dropserver @server = '$($Config.LINKED_SERVER_1_NAME)', @droplogins = 'droplogins';

IF EXISTS (SELECT 1 FROM sys.servers WHERE name = '$($Config.LINKED_SERVER_2_NAME)')
    EXEC sp_dropserver @server = '$($Config.LINKED_SERVER_2_NAME)', @droplogins = 'droplogins';
GO

-- Create linked server for svweb
EXEC sp_addlinkedserver
    @server = '$($Config.LINKED_SERVER_1_NAME)',
    @srvproduct = '',
    @provider = 'SQLNCLI',
    @datasrc = '$($Config.REMOTE_SERVER_1_IP),$($Config.REMOTE_SERVER_1_PORT)';

EXEC sp_addlinkedsrvlogin
    @rmtsrvname = '$($Config.LINKED_SERVER_1_NAME)',
    @useself = 'FALSE',
    @locallogin = NULL,
    @rmtuser = '$($Config.SQL_USER)',
    @rmtpassword = '$($Config.SQL_PASSWORD)';

-- Create linked server for suncity.schoolvision.net
EXEC sp_addlinkedserver
    @server = '$($Config.LINKED_SERVER_2_NAME)',
    @srvproduct = '',
    @provider = 'SQLNCLI',
    @datasrc = '$($Config.REMOTE_SERVER_2_IP),$($Config.REMOTE_SERVER_2_PORT)';

EXEC sp_addlinkedsrvlogin
    @rmtsrvname = '$($Config.LINKED_SERVER_2_NAME)',
    @useself = 'FALSE',
    @locallogin = NULL,
    @rmtuser = '$($Config.SQL_USER)',
    @rmtpassword = '$($Config.SQL_PASSWORD)';
GO

-- Test linked servers
SELECT 'Linked Server Test' AS Test, * FROM [$($Config.LINKED_SERVER_1_NAME)].master.sys.databases WHERE database_id = 1;
SELECT 'Linked Server Test' AS Test, * FROM [$($Config.LINKED_SERVER_2_NAME)].master.sys.databases WHERE database_id = 1;
GO

PRINT 'Linked servers created and tested successfully!';
GO
"@

if ($WhatIf) {
    Write-Host "  [WHATIF] Would create 2 linked servers" -ForegroundColor Gray
} else {
    Write-Host "  Creating linked servers..." -ForegroundColor Yellow

    $LinkedServersScript | sqlcmd -S "$($Config.PRIMARY_SERVER_IP),$($Config.PRIMARY_SERVER_PORT)" `
                                  -U $Config.SQL_USER `
                                  -P $Config.SQL_PASSWORD `
                                  -C

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  SUCCESS: Linked servers created" -ForegroundColor Green
    } else {
        Write-Host "  FAILED: Error creating linked servers (exit code: $LASTEXITCODE)" -ForegroundColor Red
    }
}

Write-Host ""

# =============================================================================
# Step 6: Create SQL Agent Jobs
# =============================================================================

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "STEP 6: CREATE SQL AGENT JOBS" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

$JobScript = Join-Path $DatabaseScriptsPath "09-create-sql-agent-jobs.sql"

if (Test-Path $JobScript) {
    if ($WhatIf) {
        Write-Host "  [WHATIF] Would create SQL Agent jobs" -ForegroundColor Gray
    } else {
        Write-Host "  Creating SQL Agent jobs..." -ForegroundColor Yellow

        sqlcmd -S "$($Config.PRIMARY_SERVER_IP),$($Config.PRIMARY_SERVER_PORT)" `
               -U $Config.SQL_USER `
               -P $Config.SQL_PASSWORD `
               -C `
               -i $JobScript

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  SUCCESS: SQL Agent jobs created" -ForegroundColor Green
        } else {
            Write-Host "  FAILED: Error creating jobs (exit code: $LASTEXITCODE)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  WARNING: Job script not found at $JobScript" -ForegroundColor Yellow
}

Write-Host ""

# =============================================================================
# Completion Summary
# =============================================================================

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "SETUP COMPLETE!" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "SchoolVision SQL Monitoring has been configured:" -ForegroundColor Green
Write-Host ""
Write-Host "  Primary Server: $($Config.PRIMARY_SERVER_NAME) ($($Config.PRIMARY_SERVER_IP))" -ForegroundColor White
Write-Host "    - MonitoringDB created" -ForegroundColor Gray
Write-Host "    - SQL Agent jobs configured" -ForegroundColor Gray
Write-Host "    - Collecting metrics every $($Config.COLLECTION_INTERVAL_MINUTES) minutes" -ForegroundColor Gray
Write-Host ""
Write-Host "  Remote Servers:" -ForegroundColor White
Write-Host "    - $($Config.REMOTE_SERVER_1_NAME) ($($Config.REMOTE_SERVER_1_IP))" -ForegroundColor Gray
Write-Host "    - $($Config.REMOTE_SERVER_2_NAME) ($($Config.REMOTE_SERVER_2_IP))" -ForegroundColor Gray
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Verify SQL Agent jobs are running on $($Config.PRIMARY_SERVER_NAME)" -ForegroundColor White
Write-Host "  2. Wait 5-10 minutes for initial data collection" -ForegroundColor White
Write-Host "  3. Connect Grafana to MonitoringDB datasource:" -ForegroundColor White
Write-Host "       Server: $($Config.PRIMARY_SERVER_IP),$($Config.PRIMARY_SERVER_PORT)" -ForegroundColor Gray
Write-Host "       Database: $($Config.MONITORING_DB_NAME)" -ForegroundColor Gray
Write-Host "  4. Import Grafana dashboards from /dashboards/grafana/dashboards/" -ForegroundColor White
Write-Host ""
Write-Host "Logs saved to: $ScriptDir\logs\" -ForegroundColor Gray
Write-Host ""
