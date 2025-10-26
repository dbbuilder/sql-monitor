# =====================================================
# Test Database Creation
# Purpose: Verify sv user can create MonitoringDB
# =====================================================

param(
    [string]$Server = "sqltest.schoolvision.net,14333",
    [string]$User = "sv",
    [string]$Password = "Gv51076!"
)

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Testing Database Creation" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check connectivity
Write-Host "Test 1: Checking SQL Server connectivity..." -ForegroundColor Yellow
try {
    $version = sqlcmd -S $Server -U $User -P $Password -C -Q "SELECT @@VERSION" -h -1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Connected to SQL Server" -ForegroundColor Green
    } else {
        throw "Connection failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "  [ERROR] Cannot connect: $_" -ForegroundColor Red
    exit 1
}

# Test 2: Check CREATE DATABASE permission
Write-Host ""
Write-Host "Test 2: Checking CREATE DATABASE permission..." -ForegroundColor Yellow
try {
    $hasPerm = sqlcmd -S $Server -U $User -P $Password -C -Q "SELECT HAS_PERMS_BY_NAME(null, null, 'CREATE DATABASE') AS HasPermission" -h -1
    if ($hasPerm -match "1") {
        Write-Host "  [OK] User has CREATE DATABASE permission" -ForegroundColor Green
    } else {
        Write-Host "  [WARNING] User does NOT have CREATE DATABASE permission" -ForegroundColor Red
        Write-Host "  [INFO] You will need a DBA to create the database first" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [ERROR] Permission check failed: $_" -ForegroundColor Red
}

# Test 3: Check if MonitoringDB already exists
Write-Host ""
Write-Host "Test 3: Checking if MonitoringDB exists..." -ForegroundColor Yellow
try {
    $dbExists = sqlcmd -S $Server -U $User -P $Password -C -Q "SELECT CASE WHEN EXISTS(SELECT name FROM sys.databases WHERE name='MonitoringDB') THEN 1 ELSE 0 END AS Exists" -h -1
    if ($dbExists -match "1") {
        Write-Host "  [INFO] MonitoringDB already exists" -ForegroundColor Yellow

        # Check if we can access it
        $canAccess = sqlcmd -S $Server -U $User -P $Password -C -d MonitoringDB -Q "SELECT 1" -h -1 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Can access MonitoringDB" -ForegroundColor Green
        } else {
            Write-Host "  [WARNING] MonitoringDB exists but cannot access it" -ForegroundColor Red
        }
    } else {
        Write-Host "  [INFO] MonitoringDB does not exist - will be created" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  [ERROR] Database check failed: $_" -ForegroundColor Red
}

# Test 4: List all databases (for debugging)
Write-Host ""
Write-Host "Test 4: Listing all databases on server..." -ForegroundColor Yellow
try {
    Write-Host "  Databases:" -ForegroundColor Gray
    sqlcmd -S $Server -U $User -P $Password -C -Q "SELECT name FROM sys.databases ORDER BY name" -h -1 | ForEach-Object {
        Write-Host "    - $_" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [ERROR] Cannot list databases: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Test Complete" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. If CREATE DATABASE permission is OK, run:" -ForegroundColor White
Write-Host "     .\\deploy-test-environment.cmd" -ForegroundColor Gray
Write-Host "  2. If no CREATE DATABASE permission, ask DBA to run:" -ForegroundColor White
Write-Host "     CREATE DATABASE MonitoringDB;" -ForegroundColor Gray
Write-Host "     ALTER AUTHORIZATION ON DATABASE::MonitoringDB TO sv;" -ForegroundColor Gray
Write-Host ""
