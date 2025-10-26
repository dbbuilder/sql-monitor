# =====================================================
# Diagnose MonitoringDB Issue
# Purpose: Find out why MonitoringDB exists but can't be accessed
# =====================================================

param(
    [string]$Server = "sqltest.schoolvision.net,14333",
    [string]$User = "sv",
    [string]$Password = "Gv51076!"
)

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Diagnosing MonitoringDB" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# Query 1: Does MonitoringDB exist? (case-sensitive check)
Write-Host "Query 1: Checking for MonitoringDB (case-sensitive)..." -ForegroundColor Yellow
try {
    sqlcmd -S $Server -U $User -P $Password -C -Q @"
SELECT
    name AS DatabaseName,
    database_id,
    state_desc AS State,
    recovery_model_desc AS RecoveryModel,
    SUSER_SNAME(owner_sid) AS Owner
FROM sys.databases
WHERE name LIKE '%Monitor%'
ORDER BY name;
"@ -h -1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Query executed" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERROR] Query failed: $_" -ForegroundColor Red
}

# Query 2: What databases can sv access?
Write-Host ""
Write-Host "Query 2: Databases sv user can access..." -ForegroundColor Yellow
try {
    sqlcmd -S $Server -U $User -P $Password -C -Q @"
SELECT
    d.name AS DatabaseName,
    CASE
        WHEN HAS_DBACCESS(d.name) = 1 THEN 'Yes'
        ELSE 'No'
    END AS CanAccess
FROM sys.databases d
WHERE d.name LIKE '%Monitor%'
ORDER BY d.name;
"@ -h -1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Query executed" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERROR] Query failed: $_" -ForegroundColor Red
}

# Query 3: Try to access MonitoringDB directly
Write-Host ""
Write-Host "Query 3: Attempting to access MonitoringDB..." -ForegroundColor Yellow
try {
    $result = sqlcmd -S $Server -U $User -P $Password -C -d MonitoringDB -Q "SELECT DB_NAME() AS CurrentDB" -h -1 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Successfully accessed MonitoringDB" -ForegroundColor Green
        Write-Host "  Current database: $result" -ForegroundColor Gray
    } else {
        Write-Host "  [ERROR] Cannot access MonitoringDB" -ForegroundColor Red
        Write-Host "  Error: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "  [ERROR] Access failed: $_" -ForegroundColor Red
}

# Query 4: Check sv login permissions
Write-Host ""
Write-Host "Query 4: Checking sv login permissions..." -ForegroundColor Yellow
try {
    sqlcmd -S $Server -U $User -P $Password -C -Q @"
-- Server-level permissions
SELECT
    SUSER_NAME() AS LoginName,
    IS_SRVROLEMEMBER('sysadmin') AS IsSysAdmin,
    IS_SRVROLEMEMBER('dbcreator') AS IsDbCreator,
    HAS_PERMS_BY_NAME(null, null, 'CREATE DATABASE') AS CanCreateDB;
"@ -h -1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Permission check completed" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERROR] Permission check failed: $_" -ForegroundColor Red
}

# Query 5: Check deployment.log for actual errors
Write-Host ""
Write-Host "Query 5: Checking deployment.log for errors..." -ForegroundColor Yellow
$logPath = Join-Path $PSScriptRoot "deployment.log"
if (Test-Path $logPath) {
    Write-Host "  [INFO] Last 30 lines of deployment.log:" -ForegroundColor Cyan
    Get-Content $logPath -Tail 30 | ForEach-Object {
        if ($_ -match "error|failed|msg \d+") {
            Write-Host "    $_" -ForegroundColor Red
        } else {
            Write-Host "    $_" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "  [WARNING] deployment.log not found at: $logPath" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Diagnosis Complete" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Based on results above:" -ForegroundColor Yellow
Write-Host "  - If MonitoringDB exists but CanAccess=No: Need to grant user access" -ForegroundColor White
Write-Host "  - If MonitoringDB doesn't exist: deployment.log should show why creation failed" -ForegroundColor White
Write-Host "  - If error is about permissions: Need DBA to create database first" -ForegroundColor White
Write-Host ""
