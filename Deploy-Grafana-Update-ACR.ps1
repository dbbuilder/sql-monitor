# Deploy Grafana Update to Azure (Using ACR Build)
# This version uses Azure Container Registry to build the image (no Docker Desktop needed!)

param(
    [switch]$SkipBuild,
    [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GRAFANA UPDATE DEPLOYMENT (ACR BUILD)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$ResourceGroup = "rg-sqlmonitor-schoolvision"
$ContainerName = "grafana-schoolvision"
$RegistryName = "sqlmonitoracr"
$ImageName = "sql-monitor-grafana"
$ImageTag = "latest"

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
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to set subscription" -ForegroundColor Red
    exit 1
}

$account = az account show --query "{subscription: name, user: user.name}" -o json | ConvertFrom-Json
Write-Host "  Subscription: $($account.subscription)" -ForegroundColor Green
Write-Host "  User: $($account.user)" -ForegroundColor Green
Write-Host ""

# Step 2: Build image in Azure Container Registry (no Docker needed!)
if (-not $SkipBuild) {
    Write-Host "Step 2: Building Docker image in Azure Container Registry..." -ForegroundColor Yellow
    Write-Host "  Registry: $RegistryName" -ForegroundColor Gray
    Write-Host "  Image: ${ImageName}:${ImageTag}" -ForegroundColor Gray
    Write-Host "  Dockerfile: Dockerfile.grafana" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  This may take 3-5 minutes..." -ForegroundColor Gray
    Write-Host ""

    # Use ACR Tasks to build the image (runs in Azure, not locally)
    az acr build `
        --registry $RegistryName `
        --image "${ImageName}:${ImageTag}" `
        --file Dockerfile.grafana `
        .

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: ACR build failed" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "  Build successful!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "Step 2: Skipped (--SkipBuild)" -ForegroundColor Gray
    Write-Host ""
}

# Step 3: Restart container to pull new image
if (-not $SkipRestart) {
    Write-Host "Step 3: Restarting Azure container..." -ForegroundColor Yellow
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
    Write-Host "  Waiting 45 seconds for container to start and download dashboards..." -ForegroundColor Gray
    Start-Sleep -Seconds 45
    Write-Host ""
} else {
    Write-Host "Step 3: Skipped (--SkipRestart)" -ForegroundColor Gray
    Write-Host ""
}

# Step 4: Verify deployment
Write-Host "Step 4: Verifying deployment..." -ForegroundColor Yellow

$containerInfo = az container show `
    --resource-group $ResourceGroup `
    --name $ContainerName `
    --query "{state: instanceView.state, fqdn: ipAddress.fqdn}" `
    -o json | ConvertFrom-Json

Write-Host "  Container State: $($containerInfo.state)" -ForegroundColor Green
Write-Host "  FQDN: $($containerInfo.fqdn)" -ForegroundColor Green
Write-Host ""

# Step 5: Check logs for dashboard download
Write-Host "Step 5: Checking container logs..." -ForegroundColor Yellow
$logs = az container logs --resource-group $ResourceGroup --name $ContainerName --tail 150

# Check for dashboard downloads
if ($logs -match "Downloaded:.*dashboards") {
    $matches = $logs | Select-String "Downloaded: (\d+) dashboards"
    if ($matches) {
        $dashboardCount = $matches.Matches.Groups[1].Value
        Write-Host "  Dashboard download: SUCCESS!" -ForegroundColor Green
        Write-Host "  Dashboards loaded: $dashboardCount" -ForegroundColor Green
    }
} else {
    Write-Host "  Warning: Dashboard download not confirmed yet" -ForegroundColor Yellow
    Write-Host "  Container may still be starting..." -ForegroundColor Gray
}

# Check for webhook server
if ($logs -match "webhook.*started|Starting.*webhook") {
    Write-Host "  Webhook server: STARTED!" -ForegroundColor Green
} else {
    Write-Host "  Warning: Webhook server not confirmed" -ForegroundColor Yellow
}

# Check for specific new dashboards
if ($logs -match "08-aws-rds-performance-insights") {
    Write-Host "  AWS RDS dashboard: DOWNLOADED!" -ForegroundColor Green
}

if ($logs -match "99-admin-dashboard-refresh") {
    Write-Host "  Admin refresh dashboard: DOWNLOADED!" -ForegroundColor Green
}

Write-Host ""

# Step 6: Display access URLs
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
Write-Host "  1. Open browser and login to Grafana" -ForegroundColor White
Write-Host "  2. Go to Dashboards menu (left sidebar)" -ForegroundColor White
Write-Host "  3. Look for new dashboards:" -ForegroundColor White
Write-Host "     - AWS RDS Performance Insights" -ForegroundColor Gray
Write-Host "     - Admin - Dashboard Refresh" -ForegroundColor Gray
Write-Host ""
Write-Host "To Use Auto-Refresh:" -ForegroundColor Yellow
Write-Host "  1. Navigate to 'Admin - Dashboard Refresh'" -ForegroundColor White
Write-Host "  2. Click 'Refresh Dashboards from GitHub' button" -ForegroundColor White
Write-Host "  3. Wait 15 seconds for page reload" -ForegroundColor White
Write-Host "  4. New dashboards appear automatically!" -ForegroundColor White
Write-Host ""
Write-Host "View Full Logs:" -ForegroundColor Yellow
Write-Host "  az container logs --resource-group $ResourceGroup --name $ContainerName --tail 200" -ForegroundColor Gray
Write-Host ""

# Optional: Open browser to Grafana
$openBrowser = Read-Host "Open Grafana in browser? (Y/n)"
if ($openBrowser -ne 'n' -and $openBrowser -ne 'N') {
    Start-Process "http://$($containerInfo.fqdn):3000"
}
