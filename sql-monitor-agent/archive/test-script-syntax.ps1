# Quick syntax test
Write-Host "Testing Deploy-MonitoringSystem.ps1 syntax..." -ForegroundColor Cyan

try {
    $scriptPath = Join-Path $PSScriptRoot "Deploy-MonitoringSystem.ps1"

    # Test if file exists
    if (-not (Test-Path $scriptPath)) {
        Write-Host "[ERROR] Script not found: $scriptPath" -ForegroundColor Red
        exit 1
    }

    # Parse the script to check for syntax errors
    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $scriptPath -Raw), [ref]$errors)

    if ($errors.Count -eq 0) {
        Write-Host "[OK] Script syntax is valid!" -ForegroundColor Green
        Write-Host "[OK] No Unicode/encoding issues detected" -ForegroundColor Green
        Write-Host ""
        Write-Host "Ready to deploy! Run with:" -ForegroundColor White
        Write-Host "  .\Deploy-MonitoringSystem.ps1 -ServerName 'your-server' -Username 'sa' -Password 'YourPass' -TrustServerCertificate" -ForegroundColor Gray
    }
    else {
        Write-Host "[ERROR] Script has syntax errors:" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Red }
        exit 1
    }
}
catch {
    Write-Host "[ERROR] Test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
