# =====================================================
# Deploy SQL Server Monitor to Test Environment
# Target: sqltest.schoolvision.net,14333
# User: sv
# Password: Gv51076!
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
Write-Host "Step 1/5: Testing SQL Server connectivity..." -ForegroundColor Green
try {
    $result = sqlcmd -S $Server -U $User -P $Password -C -Q "SELECT @@VERSION AS Version" -h -1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Connection successful" -ForegroundColor Green
    } else {
        throw "Connection failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "  ✗ Connection failed: $_" -ForegroundColor Red
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
Write-Host "Step 2/5: Deploying MonitoringDB database..." -ForegroundColor Green

$deployScript = Join-Path $DatabasePath "deploy-all.sql"
if (!(Test-Path $deployScript)) {
    Write-Host "  ✗ deploy-all.sql not found at: $deployScript" -ForegroundColor Red
    exit 1
}

try {
    sqlcmd -S $Server -U $User -P $Password -C -i $deployScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Database deployed successfully" -ForegroundColor Green
    } else {
        throw "Database deployment failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "  ✗ Database deployment failed: $_" -ForegroundColor Red
    exit 1
}

# Step 3: Verify Deployment
Write-Host ""
Write-Host "Step 3/5: Verifying deployment..." -ForegroundColor Green

$verifyQuery = @"
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
"@

try {
    $result = sqlcmd -S $Server -U $User -P $Password -C -Q $verifyQuery -h -1
    Write-Host $result
    Write-Host "  ✓ Verification complete" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Verification failed: $_" -ForegroundColor Red
}

# Step 4: Register Test Server
Write-Host ""
Write-Host "Step 4/5: Registering SQL Server for monitoring..." -ForegroundColor Green

$registerQuery = @"
USE MonitoringDB;

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

SELECT ServerID, ServerName, Environment, IsActive, CreatedDate
FROM dbo.Servers;
"@

try {
    sqlcmd -S $Server -U $User -P $Password -C -Q $registerQuery
    Write-Host "  ✓ Server registration complete" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Server registration failed: $_" -ForegroundColor Red
}

# Step 5: Insert Test Metric
Write-Host ""
Write-Host "Step 5/5: Inserting test metric..." -ForegroundColor Green

$testMetricQuery = @"
USE MonitoringDB;

DECLARE @ServerID INT;
SELECT @ServerID = ServerID FROM dbo.Servers WHERE ServerName = '$Server';

EXEC dbo.usp_InsertMetrics
    @ServerID = @ServerID,
    @CollectionTime = '2025-10-25 10:00:00',
    @MetricCategory = 'Test',
    @MetricName = 'DeploymentVerification',
    @MetricValue = 1.0;

PRINT 'Test metric inserted';

-- Show metrics
EXEC dbo.usp_GetMetrics @ServerID = @ServerID;
"@

try {
    sqlcmd -S $Server -U $User -P $Password -C -Q $testMetricQuery
    Write-Host "  ✓ Test metric inserted" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Test metric insertion failed: $_" -ForegroundColor Red
}

# Summary
Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Create .env file with connection string"
Write-Host "  2. Run: docker-compose up -d"
Write-Host "  3. Access API at: http://localhost:5000/swagger"
Write-Host "  4. Access Grafana at: http://localhost:3000"
Write-Host ""
Write-Host "Connection String for .env:" -ForegroundColor Yellow
Write-Host "  DB_CONNECTION_STRING=Server=$Server;Database=MonitoringDB;User Id=$User;Password=$Password;TrustServerCertificate=True;Encrypt=Optional;MultipleActiveResultSets=true;Connection Timeout=30"
Write-Host ""
