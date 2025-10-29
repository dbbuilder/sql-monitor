# Quick test of Deploy-MonitoringSystem.ps1
# Tests connection string syntax fix from global CLAUDE.md

$ServerName = "172.31.208.1"
$Port = 14333
$Username = "sv"
$Password = "Gv51076!"

Write-Host "Testing deployment with fixed scripts..." -ForegroundColor Cyan
Write-Host "Server: $ServerName`:$Port" -ForegroundColor Gray
Write-Host ""

# Run deployment
& "$PSScriptRoot\Deploy-MonitoringSystem.ps1" `
    -ServerName $ServerName `
    -Port $Port `
    -Username $Username `
    -Password $Password `
    -TrustServerCertificate `
    -SkipValidation

Write-Host ""
Write-Host "Test deployment complete" -ForegroundColor Green
