# =====================================================
# Deploy SQL Server Monitor to Test Environment
# Target: sqltest.schoolvision.net,14333
# =====================================================

param(
    [string]$Server = "sqltest.schoolvision.net,14333",
    [string]$User = "sv",
    [string]$Password = "Gv51076!",
    [string]$DatabasePath = "$PSScriptRoot\..\database"
)

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "SQL Server Monitor - Test Environment Deployment" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Target Server: $Server" -ForegroundColor Yellow
Write-Host "Database Path: $DatabasePath" -ForegroundColor Yellow
Write-Host ""

# Step 1: Test Connectivity
Write-Host "Step 1/4: Testing SQL Server connectivity..." -ForegroundColor Green
$testQuery = "SELECT @@VERSION AS Version"
try {
    $result = sqlcmd -S $Server -U $User -P $Password -C -Q $testQuery -h -1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Connection successful" -ForegroundColor Green
    } else {
        throw "Connection failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "  [ERROR] Connection failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Verify SQL Server is accessible from this machine"
    Write-Host "  2. Check firewall allows port 14333"
    Write-Host "  3. Verify credentials are correct"
    Write-Host "  4. Ensure SQL Server allows SQL authentication"
    exit 1
}

# Step 2: Deploy Database Schema
Write-Host ""
Write-Host "Step 2/4: Deploying MonitoringDB database..." -ForegroundColor Green

# Run each SQL file individually in correct order
$sqlFiles = @(
    "01-create-database.sql",
    "03-create-partitions.sql",
    "02-create-tables.sql",
    "04-create-procedures.sql"
)

$logFile = "$PSScriptRoot\deployment.log"
Set-Content -Path $logFile -Value "========================================================`r`n"
Add-Content -Path $logFile -Value "SQL Server Monitor - Database Deployment`r`n"
Add-Content -Path $logFile -Value "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
Add-Content -Path $logFile -Value "========================================================`r`n`r`n"

$deploymentSuccess = $true

foreach ($sqlFile in $sqlFiles) {
    $fullPath = Join-Path $DatabasePath $sqlFile

    if (!(Test-Path $fullPath)) {
        Write-Host "  [ERROR] $sqlFile not found at: $fullPath" -ForegroundColor Red
        $deploymentSuccess = $false
        break
    }

    Write-Host "  Deploying $sqlFile..." -ForegroundColor Gray
    Add-Content -Path $logFile -Value "Deploying: $sqlFile`r`n"

    try {
        $output = sqlcmd -S $Server -U $User -P $Password -C -i $fullPath 2>&1
        Add-Content -Path $logFile -Value $output

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [ERROR] $sqlFile failed with exit code $LASTEXITCODE" -ForegroundColor Red
            $deploymentSuccess = $false
            break
        }
    } catch {
        Write-Host "  [ERROR] $sqlFile failed: $_" -ForegroundColor Red
        Add-Content -Path $logFile -Value "ERROR: $_`r`n"
        $deploymentSuccess = $false
        break
    }
}

Add-Content -Path $logFile -Value "`r`n========================================================`r`n"
Add-Content -Path $logFile -Value "Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
Add-Content -Path $logFile -Value "========================================================`r`n"

if ($deploymentSuccess) {
    Write-Host "  [OK] Database deployed successfully" -ForegroundColor Green
    Write-Host "  [INFO] See deployment.log for details" -ForegroundColor Gray
} else {
    Write-Host "  [ERROR] Database deployment failed" -ForegroundColor Red
    Write-Host "  [INFO] Check deployment.log for details" -ForegroundColor Yellow
    exit 1
}

# Step 3: Verify Deployment
Write-Host ""
Write-Host "Step 3/4: Verifying deployment..." -ForegroundColor Green

$verifyScript = Join-Path $PSScriptRoot "verify-deployment.sql"
$verifyContent = @"
USE MonitoringDB;

SELECT 'Tables' AS ObjectType, COUNT(*) AS Count
FROM sys.tables
WHERE name IN ('Servers', 'PerformanceMetrics')
UNION ALL
SELECT 'Stored Procedures', COUNT(*)
FROM sys.procedures
WHERE name IN ('usp_GetServers', 'usp_InsertMetrics', 'usp_GetMetrics')
UNION ALL
SELECT 'Partition Functions', COUNT(*)
FROM sys.partition_functions
WHERE name = 'PF_MonitoringByMonth';
GO
"@

Set-Content -Path $verifyScript -Value $verifyContent

try {
    sqlcmd -S $Server -U $User -P $Password -C -i $verifyScript
    Write-Host "  [OK] Verification complete" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Verification failed: $_" -ForegroundColor Red
}

# Step 4: Register Test Server
Write-Host ""
Write-Host "Step 4/4: Registering SQL Server for monitoring..." -ForegroundColor Green

$registerScript = Join-Path $PSScriptRoot "register-server.sql"
$registerContent = @"
USE MonitoringDB;
GO

-- Register server if not exists
IF NOT EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerName = '$Server')
BEGIN
    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES ('$Server', 'Test', 1);
    PRINT 'Server registered successfully';
END
ELSE
BEGIN
    PRINT 'Server already registered';
END
GO

-- Insert test metric
DECLARE @ServerID INT;
SELECT @ServerID = ServerID FROM dbo.Servers WHERE ServerName = '$Server';

IF @ServerID IS NOT NULL
BEGIN
    EXEC dbo.usp_InsertMetrics
        @ServerID = @ServerID,
        @CollectionTime = '2025-10-25 10:00:00',
        @MetricCategory = 'Test',
        @MetricName = 'DeploymentVerification',
        @MetricValue = 1.0;
    PRINT 'Test metric inserted';
END
GO

-- Show results
SELECT ServerID, ServerName, Environment, IsActive, CreatedDate
FROM dbo.Servers;
GO

-- Show test metric
EXEC dbo.usp_GetMetrics @ServerID = 1;
GO
"@

Set-Content -Path $registerScript -Value $registerContent

try {
    sqlcmd -S $Server -U $User -P $Password -C -i $registerScript
    Write-Host "  [OK] Server registration complete" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Server registration failed: $_" -ForegroundColor Red
}

# Cleanup temp files
Remove-Item -Path $verifyScript -ErrorAction SilentlyContinue
Remove-Item -Path $registerScript -ErrorAction SilentlyContinue

# Summary
Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Start Docker Desktop" -ForegroundColor White
Write-Host "  2. Copy .env.test to .env:" -ForegroundColor White
Write-Host "     copy .env.test .env" -ForegroundColor Gray
Write-Host "  3. Start containers:" -ForegroundColor White
Write-Host "     docker-compose up -d" -ForegroundColor Gray
Write-Host "  4. Access API: http://localhost:5000/swagger" -ForegroundColor White
Write-Host "  5. Access Grafana: http://localhost:3000 (admin/Admin123!)" -ForegroundColor White
Write-Host ""
Write-Host "Connection String for .env:" -ForegroundColor Yellow
Write-Host "  DB_CONNECTION_STRING=Server=$Server;Database=MonitoringDB;User Id=$User;Password=$Password;TrustServerCertificate=True;Encrypt=Optional;MultipleActiveResultSets=true;Connection Timeout=30" -ForegroundColor Gray
Write-Host ""
