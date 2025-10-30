# Deploy Grafana Update to Azure
# Updates grafana-schoolvision container with auto-refresh system and AWS RDS dashboard

param(
    [switch]$SkipBuild,
    [switch]$SkipPush,
    [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GRAFANA UPDATE DEPLOYMENT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$ResourceGroup = "rg-sqlmonitor-schoolvision"
$ContainerName = "grafana-schoolvision"
$RegistryName = "sqlmonitoracr"
$ImageName = "sql-monitor-grafana"
$ImageTag = "latest"
$FullImageName = "${RegistryName}.azurecr.io/${ImageName}:${ImageTag}"

# Navigate to project directory
$ProjectRoot = "D:\Dev2\sql-monitor"
if (-not (Test-Path $ProjectRoot)) {
    Write-Host "ERROR: Project directory not found: $ProjectRoot" -ForegroundColor Red
    exit 1
}

Set-Location $ProjectRoot
Write-Host "Working directory: $ProjectRoot" -ForegroundColor Green
Write-Host ""

# Step 1: Set Azure subscription
Write-Host "Step 1: Setting Azure subscription..." -ForegroundColor Yellow
az account set --subscription "Test Environment"
$account = az account show --query "{subscription: name, user: user.name}" -o json | ConvertFrom-Json
Write-Host "  Subscription: $($account.subscription)" -ForegroundColor Green
Write-Host "  User: $($account.user)" -ForegroundColor Green
Write-Host ""

# Step 2: Login to Azure Container Registry
Write-Host "Step 2: Logging into Azure Container Registry..." -ForegroundColor Yellow
az acr login --name $RegistryName
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to login to ACR" -ForegroundColor Red
    exit 1
}
Write-Host "  Logged in to $RegistryName" -ForegroundColor Green
Write-Host ""

# Step 3: Build Docker image
if (-not $SkipBuild) {
    Write-Host "Step 3: Building Docker image..." -ForegroundColor Yellow
    Write-Host "  Image: $FullImageName" -ForegroundColor Gray
    Write-Host "  Dockerfile: Dockerfile.grafana" -ForegroundColor Gray
    Write-Host ""

    docker build -f Dockerfile.grafana -t $FullImageName .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Docker build failed" -ForegroundColor Red
        exit 1
    }

    Write-Host "  Build successful!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "Step 3: Skipped (--SkipBuild)" -ForegroundColor Gray
    Write-Host ""
}

# Step 4: Push image to ACR
if (-not $SkipPush) {
    Write-Host "Step 4: Pushing image to Azure Container Registry..." -ForegroundColor Yellow
    Write-Host "  Pushing: $FullImageName" -ForegroundColor Gray
    Write-Host ""

    docker push $FullImageName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Docker push failed" -ForegroundColor Red
        exit 1
    }

    Write-Host "  Push successful!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "Step 4: Skipped (--SkipPush)" -ForegroundColor Gray
    Write-Host ""
}

# Step 5: Restart container
if (-not $SkipRestart) {
    Write-Host "Step 5: Restarting Azure container..." -ForegroundColor Yellow
    Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Gray
    Write-Host "  Container: $ContainerName" -ForegroundColor Gray
    Write-Host ""

    az container restart --resource-group $ResourceGroup --name $ContainerName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Container restart failed" -ForegroundColor Red
        exit 1
    }

    Write-Host "  Container restarted!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Waiting 30 seconds for container to start..." -ForegroundColor Gray
    Start-Sleep -Seconds 30
    Write-Host ""
} else {
    Write-Host "Step 5: Skipped (--SkipRestart)" -ForegroundColor Gray
    Write-Host ""
}

# Step 6: Verify deployment
Write-Host "Step 6: Verifying deployment..." -ForegroundColor Yellow

$containerInfo = az container show `
    --resource-group $ResourceGroup `
    --name $ContainerName `
    --query "{state: instanceView.state, fqdn: ipAddress.fqdn}" `
    -o json | ConvertFrom-Json

Write-Host "  Container State: $($containerInfo.state)" -ForegroundColor Green
Write-Host "  FQDN: $($containerInfo.fqdn)" -ForegroundColor Green
Write-Host ""

# Step 7: Check logs for dashboard download
Write-Host "Step 7: Checking container logs..." -ForegroundColor Yellow
$logs = az container logs --resource-group $ResourceGroup --name $ContainerName --tail 100

if ($logs -match "Downloaded:.*dashboards") {
    $dashboardCount = ($logs | Select-String "Downloaded: (\d+) dashboards").Matches.Groups[1].Value
    Write-Host "  Dashboard download successful!" -ForegroundColor Green
    Write-Host "  Dashboards loaded: $dashboardCount" -ForegroundColor Green
} else {
    Write-Host "  Warning: Could not find dashboard download confirmation in logs" -ForegroundColor Yellow
}

if ($logs -match "webhook") {
    Write-Host "  Webhook server started!" -ForegroundColor Green
} else {
    Write-Host "  Warning: Webhook server startup not confirmed" -ForegroundColor Yellow
}

Write-Host ""

# Step 8: Display access URLs
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DEPLOYMENT COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Grafana URL:" -ForegroundColor Yellow
Write-Host "  http://$($containerInfo.fqdn):3000" -ForegroundColor White
Write-Host ""
Write-Host "New Dashboards:" -ForegroundColor Yellow
Write-Host "  1. AWS RDS Performance Insights" -ForegroundColor White
Write-Host "     http://$($containerInfo.fqdn):3000/d/aws-rds-performance-insights" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Admin - Dashboard Refresh" -ForegroundColor White
Write-Host "     http://$($containerInfo.fqdn):3000/d/admin-dashboard-refresh" -ForegroundColor Gray
Write-Host ""
Write-Host "Login Credentials:" -ForegroundColor Yellow
Write-Host "  Username: admin" -ForegroundColor White
Write-Host "  Password: NewSecurePassword123" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Login to Grafana" -ForegroundColor White
Write-Host "  2. Navigate to Admin - Dashboard Refresh" -ForegroundColor White
Write-Host "  3. Click 'Refresh Dashboards from GitHub' button" -ForegroundColor White
Write-Host "  4. Wait 15 seconds for page reload" -ForegroundColor White
Write-Host "  5. New dashboards will appear in sidebar!" -ForegroundColor White
Write-Host ""
Write-Host "View Logs:" -ForegroundColor Yellow
Write-Host "  az container logs --resource-group $ResourceGroup --name $ContainerName --tail 50" -ForegroundColor Gray
Write-Host ""
