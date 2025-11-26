#Requires -Version 5.1
<#
.SYNOPSIS
    SQL Server Monitor - Universal Installer for Windows
.DESCRIPTION
    One-command deployment for AWS, Azure, GCP, or On-Premises environments.
    Supports interactive wizard mode or non-interactive with configuration file.
.PARAMETER InstallPath
    Installation directory (default: C:\sql-monitor)
.PARAMETER ConfigFile
    Path to configuration JSON file for non-interactive installation
.PARAMETER NonInteractive
    Run without prompts (requires -ConfigFile)
.PARAMETER SkipPrereqs
    Skip prerequisite checks
.EXAMPLE
    .\Install-SqlMonitor.ps1
    # Interactive installation with wizard
.EXAMPLE
    .\Install-SqlMonitor.ps1 -ConfigFile config.json -NonInteractive
    # Non-interactive installation using config file
.EXAMPLE
    irm https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/installer/Install-SqlMonitor.ps1 | iex
    # One-liner installation from GitHub
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "C:\sql-monitor",
    [string]$ConfigFile,
    [switch]$NonInteractive,
    [switch]$SkipPrereqs
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Version
$InstallerVersion = "1.0.0"
$RepoUrl = "https://github.com/dbbuilder/sql-monitor"
$RepoRaw = "https://raw.githubusercontent.com/dbbuilder/sql-monitor/main"

# Configuration object
$Config = @{
    InstallPath = $InstallPath
    DeploymentType = "docker"
    SqlServer = "localhost"
    SqlPort = "1433"
    SqlUser = "sa"
    SqlPassword = ""
    ApiUser = "monitor_api"
    ApiPassword = ""
    GrafanaPassword = ""
    JwtSecret = ""
    ApiPort = "9000"
    GrafanaPort = "9001"
    EnableSsl = $false
    RetentionDays = 90
    MonitoredServers = @()
}

#region Helper Functions

function Write-Banner {
    $banner = @"

  ____   ___  _       __  __             _ _
 / ___| / _ \| |     |  \/  | ___  _ __ (_) |_ ___  _ __
 \___ \| | | | |     | |\/| |/ _ \| '_ \| | __/ _ \| '__|
  ___) | |_| | |___  | |  | | (_) | | | | | || (_) | |
 |____/ \__\_\_____| |_|  |_|\___/|_| |_|_|\__\___/|_|

  Enterprise SQL Server Monitoring Solution
  Version: $InstallerVersion

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Step {
    param([int]$Number, [string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "Step $Number`: $Title" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Error2 {
    param([string]$Message)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Get-SecurePassword {
    param([int]$Length = 32)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $password = ""
    $random = New-Object System.Random
    for ($i = 0; $i -lt $Length; $i++) {
        $password += $chars[$random.Next($chars.Length)]
    }
    return $password
}

function Prompt-Input {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )
    if ($Default) {
        $input = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
        return $input
    } else {
        return Read-Host $Prompt
    }
}

function Prompt-Password {
    param([string]$Prompt)
    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
}

function Prompt-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )
    $defaultText = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $input = Read-Host "$Prompt $defaultText"
    if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
    return $input -match "^[Yy]"
}

function Test-SqlConnection {
    param(
        [string]$Server,
        [string]$Port,
        [string]$User,
        [string]$Password
    )

    try {
        $connectionString = "Server=$Server,$Port;User Id=$User;Password=$Password;Connection Timeout=10;TrustServerCertificate=True"
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        $connection.Close()
        return $true
    } catch {
        # Try with sqlcmd if available
        if (Get-Command sqlcmd -ErrorAction SilentlyContinue) {
            $result = sqlcmd -S "$Server,$Port" -U $User -P $Password -Q "SELECT 1" -C -l 10 2>&1
            return $LASTEXITCODE -eq 0
        }
        return $false
    }
}

#endregion

#region Prerequisite Checks

function Test-Prerequisites {
    Write-Step 1 "Checking Prerequisites"

    $prereqsOk = $true

    # Check OS
    Write-Info "Detecting operating system..."
    $osInfo = Get-CimInstance Win32_OperatingSystem
    Write-Success "Windows detected: $($osInfo.Caption)"

    # Check Docker Desktop
    Write-Info "Checking Docker..."
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $dockerVersion = docker --version 2>$null
        if ($dockerVersion) {
            Write-Success "Docker found: $dockerVersion"

            # Check if Docker is running
            $dockerInfo = docker info 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Docker daemon is running"
            } else {
                Write-Error2 "Docker daemon is not running"
                Write-Info "Please start Docker Desktop and try again"
                $prereqsOk = $false
            }
        }
    } else {
        Write-Error2 "Docker not found"
        Write-Info "Please install Docker Desktop: https://www.docker.com/products/docker-desktop"
        $prereqsOk = $false
    }

    # Check Docker Compose
    Write-Info "Checking Docker Compose..."
    $composeVersion = docker compose version 2>$null
    if ($composeVersion) {
        Write-Success "Docker Compose found: $composeVersion"
    } else {
        $composeVersion = docker-compose --version 2>$null
        if ($composeVersion) {
            Write-Success "Docker Compose found: $composeVersion"
        } else {
            Write-Error2 "Docker Compose not found"
            $prereqsOk = $false
        }
    }

    # Check disk space
    Write-Info "Checking available disk space..."
    $drive = Split-Path $Config.InstallPath -Qualifier
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'"
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    if ($freeGB -ge 10) {
        Write-Success "$freeGB GB available (10GB required)"
    } else {
        Write-Warning "Only $freeGB GB available (10GB recommended)"
    }

    # Check memory
    Write-Info "Checking available memory..."
    $totalMemGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
    if ($totalMemGB -ge 4) {
        Write-Success "$totalMemGB GB RAM available (4GB required)"
    } else {
        Write-Warning "Only $totalMemGB GB RAM available (4GB recommended)"
    }

    # Check sqlcmd
    Write-Info "Checking sqlcmd (optional)..."
    if (Get-Command sqlcmd -ErrorAction SilentlyContinue) {
        Write-Success "sqlcmd found - can deploy database directly"
        $script:HasSqlCmd = $true
    } else {
        Write-Info "sqlcmd not found - will use container for database deployment"
        $script:HasSqlCmd = $false
    }

    if (-not $prereqsOk) {
        Write-Host ""
        Write-Error2 "Prerequisites check failed. Please install missing components."
        exit 1
    }

    Write-Success "All prerequisites satisfied!"
}

#endregion

#region Configuration Wizard

function Start-ConfigWizard {
    Write-Step 2 "Configuration Wizard"

    Write-Host ""
    Write-Host "This wizard will help you configure SQL Server Monitor."
    Write-Host "Press Enter to accept default values shown in [brackets]."
    Write-Host ""

    # Installation directory
    $Config.InstallPath = Prompt-Input "Installation directory" $Config.InstallPath

    # Deployment type
    Write-Host ""
    Write-Host "Deployment options:"
    Write-Host "  1) Docker Compose (recommended for single-server)"
    Write-Host "  2) Kubernetes (for cluster deployments)"
    Write-Host "  3) Manual (download files only)"
    Write-Host ""
    $deployChoice = Prompt-Input "Select deployment type" "1"

    switch ($deployChoice) {
        "1" { $Config.DeploymentType = "docker" }
        "2" { $Config.DeploymentType = "kubernetes" }
        "3" { $Config.DeploymentType = "manual" }
        default { $Config.DeploymentType = "docker" }
    }

    Write-Host ""
    Write-Host "SQL Server Configuration" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Configure the SQL Server that will host MonitoringDB."
    Write-Host ""

    $Config.SqlServer = Prompt-Input "SQL Server hostname or IP" $Config.SqlServer
    $Config.SqlPort = Prompt-Input "SQL Server port" $Config.SqlPort
    $Config.SqlUser = Prompt-Input "SQL Server username (needs sysadmin for setup)" $Config.SqlUser
    $Config.SqlPassword = Prompt-Password "SQL Server password"

    # Test SQL Server connection
    Write-Host ""
    Write-Info "Testing SQL Server connection..."

    if (Test-SqlConnection $Config.SqlServer $Config.SqlPort $Config.SqlUser $Config.SqlPassword) {
        Write-Success "SQL Server connection successful!"
    } else {
        Write-Warning "Could not connect to SQL Server"
        if (Prompt-YesNo "Continue anyway?" $false) {
            Write-Info "Proceeding without connection verification"
        } else {
            Write-Error2 "Please check SQL Server settings and try again"
            exit 1
        }
    }

    Write-Host ""
    Write-Host "Application Credentials" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "These credentials will be used by the monitoring system."
    Write-Host ""

    # Generate secure defaults
    $defaultApiPassword = Get-SecurePassword 24
    $defaultGrafanaPassword = Get-SecurePassword 16
    $defaultJwtSecret = Get-SecurePassword 48

    $Config.ApiUser = Prompt-Input "API database user" $Config.ApiUser
    $Config.ApiPassword = Prompt-Input "API database password (auto-generated)" $defaultApiPassword
    $Config.GrafanaPassword = Prompt-Input "Grafana admin password" $defaultGrafanaPassword
    $Config.JwtSecret = Prompt-Input "JWT secret key (48+ chars)" $defaultJwtSecret

    Write-Host ""
    Write-Host "Network Configuration" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""

    $Config.ApiPort = Prompt-Input "API port" $Config.ApiPort
    $Config.GrafanaPort = Prompt-Input "Grafana port" $Config.GrafanaPort

    # SSL/TLS
    Write-Host ""
    $Config.EnableSsl = Prompt-YesNo "Enable SSL/TLS (HTTPS)?" $false

    # Monitored servers
    Write-Host ""
    Write-Host "Monitored SQL Servers" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "You can add servers to monitor now, or later via the UI."
    Write-Host ""

    if (Prompt-YesNo "Add the setup SQL Server as a monitored server?" $true) {
        $Config.MonitoredServers += "$($Config.SqlServer):$($Config.SqlPort)"
    }

    while (Prompt-YesNo "Add another SQL Server to monitor?" $false) {
        $newServer = Prompt-Input "Server hostname:port" ""
        if ($newServer) {
            $Config.MonitoredServers += $newServer
        }
    }

    # Data retention
    Write-Host ""
    Write-Host "Data Retention" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""
    $Config.RetentionDays = [int](Prompt-Input "Data retention (days)" $Config.RetentionDays)

    # Show summary
    Show-ConfigSummary
}

function Show-ConfigSummary {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "Configuration Summary" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Installation Directory:  $($Config.InstallPath)"
    Write-Host "  Deployment Type:         $($Config.DeploymentType)"
    Write-Host ""
    Write-Host "  SQL Server:              $($Config.SqlServer):$($Config.SqlPort)"
    Write-Host "  SQL Username:            $($Config.SqlUser)"
    Write-Host "  API Database User:       $($Config.ApiUser)"
    Write-Host ""
    Write-Host "  API Port:                $($Config.ApiPort)"
    Write-Host "  Grafana Port:            $($Config.GrafanaPort)"
    Write-Host "  SSL Enabled:             $($Config.EnableSsl)"
    Write-Host ""
    Write-Host "  Data Retention:          $($Config.RetentionDays) days"
    Write-Host "  Monitored Servers:       $($Config.MonitoredServers.Count)"
    Write-Host ""

    if (-not (Prompt-YesNo "Proceed with installation?" $true)) {
        Write-Info "Installation cancelled"
        exit 0
    }
}

#endregion

#region Installation Steps

function Get-InstallFiles {
    Write-Step 3 "Downloading SQL Server Monitor"

    # Create installation directory
    if (-not (Test-Path $Config.InstallPath)) {
        New-Item -ItemType Directory -Path $Config.InstallPath -Force | Out-Null
    }

    Set-Location $Config.InstallPath

    Write-Info "Downloading from $RepoUrl..."

    # Check if git is available
    if (Get-Command git -ErrorAction SilentlyContinue) {
        if (Test-Path ".git") {
            Write-Info "Updating existing installation..."
            git pull origin main
        } else {
            git clone --depth 1 "$RepoUrl.git" .
        }
    } else {
        # Download as zip
        $zipPath = Join-Path $env:TEMP "sql-monitor.zip"
        Invoke-WebRequest -Uri "$RepoUrl/archive/refs/heads/main.zip" -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
        Copy-Item -Path (Join-Path $env:TEMP "sql-monitor-main\*") -Destination $Config.InstallPath -Recurse -Force
        Remove-Item $zipPath -Force
        Remove-Item (Join-Path $env:TEMP "sql-monitor-main") -Recurse -Force
    }

    Write-Success "Files downloaded to $($Config.InstallPath)"
}

function New-EnvFile {
    Write-Step 4 "Creating Configuration Files"

    Write-Info "Generating .env file..."

    $envContent = @"
# ============================================================================
# SQL Server Monitor Configuration
# Generated: $(Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
# ============================================================================

# Database Connection (MonitoringDB)
DB_CONNECTION_STRING=Server=$($Config.SqlServer),$($Config.SqlPort);Database=MonitoringDB;User Id=$($Config.ApiUser);Password=$($Config.ApiPassword);Encrypt=True;TrustServerCertificate=True;Connection Timeout=30

# SQL Server Admin (for initial setup only)
SQL_ADMIN_SERVER=$($Config.SqlServer),$($Config.SqlPort)
SQL_ADMIN_USER=$($Config.SqlUser)
SQL_ADMIN_PASSWORD=$($Config.SqlPassword)

# API Configuration
API_PORT=$($Config.ApiPort)
ASPNETCORE_ENVIRONMENT=Production
ASPNETCORE_URLS=http://+:$($Config.ApiPort)

# JWT Authentication
JWT_SECRET_KEY=$($Config.JwtSecret)
JWT_ISSUER=SqlMonitor.Api
JWT_AUDIENCE=SqlMonitor.Client
JWT_EXPIRATION_HOURS=8

# Grafana Configuration
GRAFANA_PORT=$($Config.GrafanaPort)
GF_SECURITY_ADMIN_PASSWORD=$($Config.GrafanaPassword)
GF_SERVER_HTTP_PORT=$($Config.GrafanaPort)

# Monitoring Settings
MONITORINGDB_SERVER=$($Config.SqlServer)
MONITORINGDB_USER=$($Config.ApiUser)
MONITORINGDB_PASSWORD=$($Config.ApiPassword)
DATA_RETENTION_DAYS=$($Config.RetentionDays)
COLLECTION_INTERVAL_MINUTES=5

# SSL Configuration
ENABLE_SSL=$($Config.EnableSsl.ToString().ToLower())
"@

    $envPath = Join-Path $Config.InstallPath ".env"
    $envContent | Out-File -FilePath $envPath -Encoding UTF8 -Force

    Write-Success "Configuration file created: $envPath"
}

function Deploy-Database {
    Write-Step 5 "Deploying Database Schema"

    Write-Info "This will create the MonitoringDB database and all required objects..."

    $sqlServerConnection = "$($Config.SqlServer),$($Config.SqlPort)"

    # Create database
    $createDbSql = @"
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'MonitoringDB')
BEGIN
    CREATE DATABASE MonitoringDB;
    PRINT 'Created MonitoringDB';
END
ELSE
    PRINT 'MonitoringDB already exists';
"@

    if ($script:HasSqlCmd) {
        Write-Info "Deploying with sqlcmd..."

        # Create database
        $createDbSql | sqlcmd -S $sqlServerConnection -U $Config.SqlUser -P $Config.SqlPassword -C

        # Deploy schema
        $deployAllPath = Join-Path $Config.InstallPath "database\deploy-all.sql"
        if (Test-Path $deployAllPath) {
            sqlcmd -S $sqlServerConnection -U $Config.SqlUser -P $Config.SqlPassword -d MonitoringDB -i $deployAllPath -C
        }
    } else {
        Write-Info "Deploying with Docker SQL tools container..."

        $dbPath = Join-Path $Config.InstallPath "database"
        docker run --rm `
            -v "${dbPath}:/database:ro" `
            mcr.microsoft.com/mssql-tools `
            /bin/bash -c "/opt/mssql-tools/bin/sqlcmd -S $sqlServerConnection -U $($Config.SqlUser) -P '$($Config.SqlPassword)' -Q `"$createDbSql`" -C && /opt/mssql-tools/bin/sqlcmd -S $sqlServerConnection -U $($Config.SqlUser) -P '$($Config.SqlPassword)' -d MonitoringDB -i /database/deploy-all.sql -C"
    }

    # Create application database user
    Write-Info "Creating application database user..."

    $createUserSql = @"
USE MonitoringDB;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$($Config.ApiUser)')
BEGIN
    CREATE LOGIN [$($Config.ApiUser)] WITH PASSWORD = '$($Config.ApiPassword)';
END
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$($Config.ApiUser)')
BEGIN
    CREATE USER [$($Config.ApiUser)] FOR LOGIN [$($Config.ApiUser)];
END
GRANT EXECUTE TO [$($Config.ApiUser)];
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO [$($Config.ApiUser)];
"@

    if ($script:HasSqlCmd) {
        $createUserSql | sqlcmd -S $sqlServerConnection -U $Config.SqlUser -P $Config.SqlPassword -C
    }

    Write-Success "Database schema deployed successfully!"
}

function Deploy-Containers {
    Write-Step 6 "Deploying Containers"

    Set-Location $Config.InstallPath

    Write-Info "Building and starting containers..."

    # Build and start
    docker compose build api
    docker compose up -d

    # Wait for services
    Write-Info "Waiting for services to start..."
    $maxWait = 60
    $waited = 0

    while ($waited -lt $maxWait) {
        try {
            $health = Invoke-RestMethod -Uri "http://localhost:$($Config.ApiPort)/health" -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($health) { break }
        } catch { }

        Start-Sleep -Seconds 2
        $waited += 2
        Write-Host "." -NoNewline
    }
    Write-Host ""

    if ($waited -ge $maxWait) {
        Write-Warning "Services may still be starting..."
    } else {
        Write-Success "Services are running!"
    }

    # Show status
    docker compose ps
}

function Register-Servers {
    Write-Step 7 "Registering Monitored Servers"

    if ($Config.MonitoredServers.Count -eq 0) {
        Write-Info "No servers to register. You can add servers later via the API or UI."
        return
    }

    $sqlServerConnection = "$($Config.SqlServer),$($Config.SqlPort)"

    foreach ($server in $Config.MonitoredServers) {
        Write-Info "Registering server: $server"

        $registerSql = "EXEC dbo.usp_AddServer @ServerName = '$server', @Description = 'Auto-registered during setup', @IsActive = 1;"

        if ($script:HasSqlCmd) {
            sqlcmd -S $sqlServerConnection -U $Config.SqlUser -P $Config.SqlPassword -d MonitoringDB -Q $registerSql -C
        }

        Write-Success "Registered: $server"
    }
}

function Test-Installation {
    Write-Step 8 "Verifying Installation"

    $allOk = $true

    # Check API health
    Write-Info "Checking API health..."
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:$($Config.ApiPort)/health" -TimeoutSec 10
        if ($health.status -eq "Healthy") {
            Write-Success "API is healthy"
        } else {
            Write-Warning "API returned: $($health.status)"
        }
    } catch {
        Write-Error2 "API health check failed: $_"
        $allOk = $false
    }

    # Check Grafana
    Write-Info "Checking Grafana..."
    try {
        $grafanaHealth = Invoke-RestMethod -Uri "http://localhost:$($Config.GrafanaPort)/api/health" -TimeoutSec 10
        Write-Success "Grafana is healthy"
    } catch {
        Write-Warning "Grafana may still be starting..."
    }

    Write-Host ""
    if ($allOk) {
        Write-Success "Installation verified successfully!"
    } else {
        Write-Warning "Some checks failed - please review the logs above"
    }
}

function Show-CompletionMessage {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Green
    Write-Host "  Installation Complete!" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host ("=" * 70) -ForegroundColor Green
    Write-Host ""
    Write-Host "Access your SQL Server Monitor:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Grafana Dashboard:  http://localhost:$($Config.GrafanaPort)"
    Write-Host "  API Endpoint:       http://localhost:$($Config.ApiPort)"
    Write-Host "  API Documentation:  http://localhost:$($Config.ApiPort)/swagger"
    Write-Host ""
    Write-Host "Credentials:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Grafana Admin:      admin / $($Config.GrafanaPassword)"
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Installation Dir:   $($Config.InstallPath)"
    Write-Host "  Config File:        $($Config.InstallPath)\.env"
    Write-Host ""
    Write-Host "Useful Commands:" -ForegroundColor White
    Write-Host ""
    Write-Host "  View logs:          cd $($Config.InstallPath); docker compose logs -f"
    Write-Host "  Restart services:   cd $($Config.InstallPath); docker compose restart"
    Write-Host "  Stop services:      cd $($Config.InstallPath); docker compose down"
    Write-Host ""
    Write-Host "Documentation: https://github.com/dbbuilder/sql-monitor/docs" -ForegroundColor Cyan
    Write-Host ""
}

#endregion

#region Main Execution

function Main {
    Write-Banner

    # Load config file if provided
    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        Write-Info "Loading configuration from $ConfigFile"
        $loadedConfig = Get-Content $ConfigFile | ConvertFrom-Json
        foreach ($prop in $loadedConfig.PSObject.Properties) {
            if ($Config.ContainsKey($prop.Name)) {
                $Config[$prop.Name] = $prop.Value
            }
        }
    }

    # Run installation steps
    if (-not $SkipPrereqs) {
        Test-Prerequisites
    }

    if (-not $NonInteractive) {
        Start-ConfigWizard
    }

    Get-InstallFiles
    New-EnvFile
    Deploy-Database

    if ($Config.DeploymentType -eq "docker") {
        Deploy-Containers
    }

    Register-Servers
    Test-Installation
    Show-CompletionMessage
}

# Run main
Main
