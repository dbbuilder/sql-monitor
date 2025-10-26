# =====================================================
# Fix MonitoringDB Access
# Purpose: Grant sv user access to MonitoringDB
# =====================================================

param(
    [string]$Server = "sqltest.schoolvision.net,14333",
    [string]$User = "sv",
    [string]$Password = "Gv51076!"
)

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Fixing MonitoringDB Access" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if MonitoringDB exists
Write-Host "Step 1: Checking if MonitoringDB exists..." -ForegroundColor Yellow
$checkScript = @"
USE master;
GO

-- Check if database exists
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'MonitoringDB')
BEGIN
    PRINT 'MonitoringDB exists';

    -- Check if sv user has access
    USE MonitoringDB;
    GO

    IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'sv')
    BEGIN
        PRINT 'Creating user sv in MonitoringDB';
        CREATE USER [sv] FOR LOGIN [sv];
        GO

        -- Grant db_owner role
        ALTER ROLE db_owner ADD MEMBER [sv];
        GO

        PRINT 'User sv granted db_owner access';
    END
    ELSE
    BEGIN
        PRINT 'User sv already exists in MonitoringDB';

        -- Ensure db_owner role
        ALTER ROLE db_owner ADD MEMBER [sv];
        GO

        PRINT 'Verified sv has db_owner access';
    END
END
ELSE
BEGIN
    PRINT 'MonitoringDB does not exist - will create it';

    CREATE DATABASE MonitoringDB;
    GO

    USE MonitoringDB;
    GO

    -- Create user and grant permissions
    CREATE USER [sv] FOR LOGIN [sv];
    GO

    ALTER ROLE db_owner ADD MEMBER [sv];
    GO

    PRINT 'MonitoringDB created and sv granted access';
END
GO
"@

# Save to temp file
$tempScript = Join-Path $PSScriptRoot "fix-access.sql"
Set-Content -Path $tempScript -Value $checkScript

try {
    Write-Host "  Running fix script..." -ForegroundColor Cyan
    sqlcmd -S $Server -U $User -P $Password -C -i $tempScript

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Database access fixed" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] Fix failed with exit code $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  [INFO] You may need DBA help to run this script as sa/sysadmin" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [ERROR] Fix failed: $_" -ForegroundColor Red
}

# Cleanup
Remove-Item -Path $tempScript -ErrorAction SilentlyContinue

# Step 2: Verify access
Write-Host ""
Write-Host "Step 2: Verifying access..." -ForegroundColor Yellow
try {
    $result = sqlcmd -S $Server -U $User -P $Password -C -d MonitoringDB -Q "SELECT DB_NAME() AS CurrentDB, SUSER_NAME() AS CurrentUser" -h -1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] sv user can now access MonitoringDB" -ForegroundColor Green
        Write-Host "  Result: $result" -ForegroundColor Gray
    } else {
        Write-Host "  [ERROR] Still cannot access MonitoringDB" -ForegroundColor Red
    }
} catch {
    Write-Host "  [ERROR] Access verification failed: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Next Steps" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "If the fix succeeded, run:" -ForegroundColor Yellow
Write-Host "  .\\deploy-test-environment.cmd" -ForegroundColor White
Write-Host ""
Write-Host "If the fix failed, you need a DBA to run as sa/sysadmin:" -ForegroundColor Yellow
Write-Host "  USE MonitoringDB;" -ForegroundColor Gray
Write-Host "  CREATE USER [sv] FOR LOGIN [sv];" -ForegroundColor Gray
Write-Host "  ALTER ROLE db_owner ADD MEMBER [sv];" -ForegroundColor Gray
Write-Host ""
