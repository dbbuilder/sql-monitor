#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy SQL Monitoring System v1.0 to all servers

.DESCRIPTION
    Deploys the complete monitoring system including XML fix to multiple servers
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Username = "sv",

    [Parameter(Mandatory=$false)]
    [string]$Password = "Gv51076!"
)

$Servers = @(
    @{ Name="svweb"; Address="data.schoolvision.net,14333" },
    @{ Name="suncity"; Address="suncity.schoolvision.net,14333" },
    @{ Name="sqltest"; Address="sqltest.schoolvision.net,14333" }
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SuccessServers = @()
$FailedServers = @()

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "SQL Server Monitoring System v1.0 - Multi-Server Deployment" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "Deploying to $($Servers.Count) servers..." -ForegroundColor Yellow
Write-Host ""

foreach ($Server in $Servers) {
    Write-Host "=" * 70 -ForegroundColor Blue
    Write-Host "Server: $($Server.Name) ($($Server.Address))" -ForegroundColor Blue
    Write-Host "=" * 70 -ForegroundColor Blue
    Write-Host ""

    try {
        # Deploy main system
        Write-Host "Step 1: Deploying main system..." -ForegroundColor Yellow
        & "$ScriptRoot\Deploy-Complete-System-NoSqlCmd.ps1" `
            -Server $Server.Address `
            -Username $Username `
            -Password $Password

        if ($LASTEXITCODE -ne 0) {
            throw "Main deployment failed with exit code $LASTEXITCODE"
        }

        Write-Host ""
        Write-Host "Step 2: Deploying XML fix..." -ForegroundColor Yellow
        & "$ScriptRoot\deploy-xml-fix.ps1" `
            -Server $Server.Address `
            -User $Username `
            -Password $Password

        if ($LASTEXITCODE -ne 0) {
            throw "XML fix deployment failed with exit code $LASTEXITCODE"
        }

        Write-Host ""
        Write-Host "Step 3: Generating test HTML report..." -ForegroundColor Yellow
        $reportPath = Join-Path $ScriptRoot "reports\$($Server.Name)_health_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

        & "$ScriptRoot\Export-HealthReportHTML.ps1" `
            -Server $Server.Address `
            -User $Username `
            -Password $Password `
            -OutputPath $reportPath

        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: HTML report generation failed (not critical)" -ForegroundColor Yellow
        } else {
            Write-Host "  Report saved: $reportPath" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "SUCCESS: $($Server.Name) deployment complete!" -ForegroundColor Green
        $SuccessServers += $Server.Name

    }
    catch {
        Write-Host ""
        Write-Host "FAILED: $($Server.Name) deployment failed" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        $FailedServers += $Server.Name
    }

    Write-Host ""
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Green
Write-Host "Deployment Summary" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Green
Write-Host ""
Write-Host "Total Servers: $($Servers.Count)" -ForegroundColor Cyan
Write-Host "Successful: $($SuccessServers.Count)" -ForegroundColor Green
Write-Host "Failed: $($FailedServers.Count)" -ForegroundColor $(if ($FailedServers.Count -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($SuccessServers.Count -gt 0) {
    Write-Host "Successfully deployed to:" -ForegroundColor Green
    foreach ($s in $SuccessServers) {
        Write-Host "  ✓ $s" -ForegroundColor Green
    }
    Write-Host ""
}

if ($FailedServers.Count -gt 0) {
    Write-Host "Failed to deploy to:" -ForegroundColor Red
    foreach ($s in $FailedServers) {
        Write-Host "  ✗ $s" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Please review errors above and retry failed servers manually" -ForegroundColor Yellow
    exit 1
}

Write-Host "All servers deployed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Wait 5 minutes for first automated snapshot collection" -ForegroundColor White
Write-Host "  2. Generate HTML reports for each server" -ForegroundColor White
Write-Host "  3. Review reports in: $ScriptRoot\reports\" -ForegroundColor White
Write-Host ""
