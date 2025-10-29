<#
.SYNOPSIS
    SQL Monitor - Idempotent Deployment Script (PowerShell)

.DESCRIPTION
    Provisions SQL Monitor from scratch or resumes from any checkpoint.
    Safe to run multiple times - only applies missing components.

.PARAMETER SqlServer
    SQL Server instance (e.g., "localhost,14333" or "server.domain.com")

.PARAMETER SqlUser
    SQL Server username (SQL authentication)

.PARAMETER SqlPassword
    SQL Server password

.PARAMETER DatabaseName
    Target database name (default: MonitoringDB)

.PARAMETER GrafanaPort
    Grafana HTTP port (default: 9002)

.PARAMETER ApiPort
    REST API port (default: 9000)

.PARAMETER Environment
    Environment name (Development, Staging, Production)

.PARAMETER SkipDocker
    Skip Docker container setup (database only)

.PARAMETER Resume
    Resume from last checkpoint

.PARAMETER Status
    Show current deployment status and exit

.EXAMPLE
    .\Deploy.ps1 -SqlServer "localhost,14333" -SqlUser "sa" -SqlPassword "YourPassword" -Environment "Development"

.EXAMPLE
    .\Deploy.ps1 -Status

.EXAMPLE
    .\Deploy.ps1 -Resume
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$SqlServer = "localhost,1433",

    [Parameter(Mandatory=$false)]
    [string]$SqlUser,

    [Parameter(Mandatory=$false)]
    [string]$SqlPassword,

    [Parameter(Mandatory=$false)]
    [string]$DatabaseName = "MonitoringDB",

    [Parameter(Mandatory=$false)]
    [int]$GrafanaPort = 9002,

    [Parameter(Mandatory=$false)]
    [int]$ApiPort = 9000,

    [Parameter(Mandatory=$false)]
    [ValidateSet("Development", "Staging", "Production")]
    [string]$Environment = "Development",

    [Parameter(Mandatory=$false)]
    [switch]$SkipDocker,

    [Parameter(Mandatory=$false)]
    [switch]$Resume,

    [Parameter(Mandatory=$false)]
    [switch]$Status
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CheckpointFile = Join-Path $ScriptDir ".deploy-checkpoint.json"

# =============================================
# Helper Functions
# =============================================

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor White
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warning2 {
    param([string]$Message)
    Write-Host "  [SKIP] $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [INFO] $Message" -ForegroundColor Blue
}

function Get-Checkpoint {
    if (Test-Path $CheckpointFile) {
        return Get-Content $CheckpointFile | ConvertFrom-Json
    }
    return @{
        Steps = @()
        LastUpdated = $null
        SqlServer = $null
        DatabaseName = $null
        Environment = $null
    }
}

function Save-Checkpoint {
    param(
        [string]$StepName,
        [hashtable]$Config
    )

    $checkpoint = Get-Checkpoint
    if ($checkpoint.Steps -notcontains $StepName) {
        $checkpoint.Steps += $StepName
    }
    $checkpoint.LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $checkpoint.SqlServer = $Config.SqlServer
    $checkpoint.DatabaseName = $Config.DatabaseName
    $checkpoint.Environment = $Config.Environment

    $checkpoint | ConvertTo-Json | Set-Content $CheckpointFile
    Write-Success "Checkpoint saved: $StepName"
}

function Test-StepCompleted {
    param([string]$StepName)
    $checkpoint = Get-Checkpoint
    return $checkpoint.Steps -contains $StepName
}

function Show-Status {
    Write-Header "Deployment Status"

    if (-not (Test-Path $CheckpointFile)) {
        Write-Warning2 "No deployment checkpoint found. Run .\Deploy.ps1 to start."
        return
    }

    $checkpoint = Get-Checkpoint
    Write-Info "Last Updated: $($checkpoint.LastUpdated)"
    Write-Info "SQL Server: $($checkpoint.SqlServer)"
    Write-Info "Database: $($checkpoint.DatabaseName)"
    Write-Info "Environment: $($checkpoint.Environment)"
    Write-Host ""
    Write-Host "Completed Steps:" -ForegroundColor Cyan

    $allSteps = @(
        "Prerequisites",
        "DatabaseCreated",
        "TablesCreated",
        "ProceduresCreated",
        "ServerRegistered",
        "MetadataInitialized",
        "DockerConfigured",
        "GrafanaStarted"
    )

    foreach ($step in $allSteps) {
        if ($checkpoint.Steps -contains $step) {
            Write-Host "  [X] $step" -ForegroundColor Green
        } else {
            Write-Host "  [ ] $step" -ForegroundColor Gray
        }
    }
}

function Test-Prerequisite {
    param(
        [string]$Command,
        [string]$Name,
        [string]$InstallInstructions
    )

    $found = $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
    if ($found) {
        Write-Success "$Name found"
    } else {
        Write-Host "  [ERROR] $Name not found" -ForegroundColor Red
        Write-Host "    Install: $InstallInstructions" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Invoke-SqlCommand {
    param(
        [string]$Query,
        [string]$Server,
        [string]$User,
        [string]$Password,
        [string]$Database = "master",
        [switch]$TrustServerCertificate
    )

    $certParam = if ($TrustServerCertificate) { "-C" } else { "" }
    $authParams = if ($User) {
        "-U `"$User`" -P `"$Password`""
    } else {
        "-E"
    }

    $cmd = "sqlcmd -S `"$Server`" $authParams -d `"$Database`" $certParam -Q `"$Query`" -h -1"
    $result = Invoke-Expression $cmd 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "SQL command failed: $result"
    }

    return $result
}

function Test-DatabaseExists {
    param(
        [string]$Server,
        [string]$User,
        [string]$Password,
        [string]$Database
    )

    try {
        $query = "SELECT COUNT(*) FROM sys.databases WHERE name = '$Database'"
        $result = Invoke-SqlCommand -Query $query -Server $Server -User $User -Password $Password -Database "master" -TrustServerCertificate
        return ([int]$result.Trim()) -gt 0
    } catch {
        return $false
    }
}

function Test-TableExists {
    param(
        [string]$Server,
        [string]$User,
        [string]$Password,
        [string]$Database,
        [string]$TableName
    )

    try {
        $query = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$TableName'"
        $result = Invoke-SqlCommand -Query $query -Server $Server -User $User -Password $Password -Database $Database -TrustServerCertificate
        return ([int]$result.Trim()) -gt 0
    } catch {
        return $false
    }
}

# =============================================
# Main Deployment Logic
# =============================================

if ($Status) {
    Show-Status
    exit 0
}

Write-Header "SQL Monitor - Idempotent Deployment"

# Load configuration from checkpoint if resuming
if ($Resume) {
    $checkpoint = Get-Checkpoint
    if ($checkpoint.SqlServer) {
        Write-Info "Resuming from checkpoint..."
        $SqlServer = $checkpoint.SqlServer
        $DatabaseName = $checkpoint.DatabaseName
        $Environment = $checkpoint.Environment
    } else {
        Write-Warning2 "No checkpoint found. Starting fresh deployment."
        $Resume = $false
    }
}

# Prompt for credentials if not provided
if (-not $SqlUser -and -not $Resume) {
    $SqlUser = Read-Host "SQL Server Username"
}
if (-not $SqlPassword -and -not $Resume) {
    $securePassword = Read-Host "SQL Server Password" -AsSecureString
    $SqlPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    )
}

$config = @{
    SqlServer = $SqlServer
    SqlUser = $SqlUser
    SqlPassword = $SqlPassword
    DatabaseName = $DatabaseName
    GrafanaPort = $GrafanaPort
    ApiPort = $ApiPort
    Environment = $Environment
}

# =============================================
# Step 1: Check Prerequisites
# =============================================

if (-not (Test-StepCompleted "Prerequisites")) {
    Write-Header "Step 1: Checking Prerequisites"

    $allFound = $true
    $allFound = $allFound -and (Test-Prerequisite "sqlcmd" "SQL Server Command Line Tools" "https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility")

    if (-not $SkipDocker) {
        $allFound = $allFound -and (Test-Prerequisite "docker" "Docker" "https://docs.docker.com/get-docker/")
    }

    if (-not $allFound) {
        throw "Prerequisites not met. Install missing tools and try again."
    }

    Save-Checkpoint "Prerequisites" $config
} else {
    Write-Warning2 "Prerequisites already checked"
}

# =============================================
# Step 2: Create Database
# =============================================

if (-not (Test-StepCompleted "DatabaseCreated")) {
    Write-Header "Step 2: Creating Database"

    if (Test-DatabaseExists -Server $SqlServer -User $SqlUser -Password $SqlPassword -Database $DatabaseName) {
        Write-Warning2 "Database '$DatabaseName' already exists"
    } else {
        Write-Step "Creating database '$DatabaseName'..."
        $createDbQuery = @"
CREATE DATABASE [$DatabaseName];
ALTER DATABASE [$DatabaseName] SET RECOVERY SIMPLE;
ALTER DATABASE [$DatabaseName] SET PAGE_VERIFY CHECKSUM;
"@
        Invoke-SqlCommand -Query $createDbQuery -Server $SqlServer -User $SqlUser -Password $SqlPassword -Database "master" -TrustServerCertificate
        Write-Success "Database created"
    }

    Save-Checkpoint "DatabaseCreated" $config
} else {
    Write-Warning2 "Database creation already completed"
}

# =============================================
# Step 3: Deploy Schema (Tables)
# =============================================

if (-not (Test-StepCompleted "TablesCreated")) {
    Write-Header "Step 3: Creating Tables"

    $tableScripts = Get-ChildItem (Join-Path $ScriptDir "database") -Filter "*-create-*tables*.sql" | Sort-Object Name

    foreach ($script in $tableScripts) {
        Write-Step "Executing: $($script.Name)"
        sqlcmd -S $SqlServer -U $SqlUser -P $SqlPassword -d $DatabaseName -C -i $script.FullName -b
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to execute $($script.Name)"
        }
    }

    Write-Success "Tables created"
    Save-Checkpoint "TablesCreated" $config
} else {
    Write-Warning2 "Tables already created"
}

# =============================================
# Step 4: Deploy Procedures/Functions
# =============================================

if (-not (Test-StepCompleted "ProceduresCreated")) {
    Write-Header "Step 4: Creating Procedures and Functions"

    $procScripts = Get-ChildItem (Join-Path $ScriptDir "database") -Filter "*-create-*procedure*.sql" | Sort-Object Name

    foreach ($script in $procScripts) {
        Write-Step "Executing: $($script.Name)"
        sqlcmd -S $SqlServer -U $SqlUser -P $SqlPassword -d $DatabaseName -C -i $script.FullName -b
        if ($LASTEXITCODE -ne 0) {
            Write-Warning2 "Warning executing $($script.Name) - may already exist"
        }
    }

    Write-Success "Procedures created"
    Save-Checkpoint "ProceduresCreated" $config
} else {
    Write-Warning2 "Procedures already created"
}

# =============================================
# Step 5: Register Server
# =============================================

if (-not (Test-StepCompleted "ServerRegistered")) {
    Write-Header "Step 5: Registering Server"

    $checkServerQuery = "SELECT COUNT(*) FROM dbo.Servers"
    $serverCount = Invoke-SqlCommand -Query $checkServerQuery -Server $SqlServer -User $SqlUser -Password $SqlPassword -Database $DatabaseName -TrustServerCertificate

    if (([int]$serverCount.Trim()) -eq 0) {
        Write-Step "Registering local server..."
        $registerQuery = "INSERT INTO dbo.Servers (ServerName, Environment, IsActive) VALUES (@@SERVERNAME, '$Environment', 1)"
        Invoke-SqlCommand -Query $registerQuery -Server $SqlServer -User $SqlUser -Password $SqlPassword -Database $DatabaseName -TrustServerCertificate
        Write-Success "Server registered"
    } else {
        Write-Warning2 "Server already registered"
    }

    Save-Checkpoint "ServerRegistered" $config
} else {
    Write-Warning2 "Server registration already completed"
}

# =============================================
# Step 6: Initialize Metadata Collection
# =============================================

if (-not (Test-StepCompleted "MetadataInitialized")) {
    Write-Header "Step 6: Initializing Metadata Collection"

    Write-Step "This may take 1-5 minutes per database..."
    $initScript = Join-Path $ScriptDir "database\29-initialize-metadata-collection.sql"

    if (Test-Path $initScript) {
        sqlcmd -S $SqlServer -U $SqlUser -P $SqlPassword -d $DatabaseName -C -i $initScript
        Write-Success "Metadata collection initialized"
    } else {
        Write-Warning2 "Initialization script not found: $initScript"
    }

    Save-Checkpoint "MetadataInitialized" $config
} else {
    Write-Warning2 "Metadata initialization already completed"
}

# =============================================
# Step 7: Configure Docker (if not skipped)
# =============================================

if (-not $SkipDocker -and -not (Test-StepCompleted "DockerConfigured")) {
    Write-Header "Step 7: Configuring Docker"

    # Create .env file
    $envFile = Join-Path $ScriptDir ".env"
    $jwtSecret = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})

    $envContent = @"
DB_CONNECTION_STRING=Server=$SqlServer;Database=$DatabaseName;User Id=$SqlUser;Password=$SqlPassword;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30
JWT_SECRET_KEY=$jwtSecret
GRAFANA_PASSWORD=Admin123!
ASPNETCORE_ENVIRONMENT=$Environment
GF_SERVER_HTTP_PORT=$GrafanaPort
"@

    Set-Content -Path $envFile -Value $envContent
    Write-Success ".env file created"

    # Update Grafana datasource
    $datasourcePath = Join-Path $ScriptDir "dashboards\grafana\provisioning\datasources\monitoringdb.yaml"
    if (Test-Path $datasourcePath) {
        $datasourceContent = Get-Content $datasourcePath -Raw
        $datasourceContent = $datasourceContent -replace "url: .*", "url: $SqlServer"
        $datasourceContent = $datasourceContent -replace "user: .*", "user: $SqlUser"
        $datasourceContent = $datasourceContent -replace "password: .*", "password: $SqlPassword"
        Set-Content -Path $datasourcePath -Value $datasourceContent
        Write-Success "Grafana datasource configured"
    }

    Save-Checkpoint "DockerConfigured" $config
} elseif ($SkipDocker) {
    Write-Warning2 "Docker setup skipped (--SkipDocker)"
} else {
    Write-Warning2 "Docker already configured"
}

# =============================================
# Step 8: Start Docker Containers
# =============================================

if (-not $SkipDocker -and -not (Test-StepCompleted "GrafanaStarted")) {
    Write-Header "Step 8: Starting Docker Containers"

    Write-Step "Starting containers..."
    docker compose up -d

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Containers started"
        Write-Info "Grafana: http://localhost:$GrafanaPort (admin/Admin123!)"
        Write-Info "API: http://localhost:$ApiPort"
    } else {
        Write-Warning2 "Failed to start containers. Run 'docker compose up -d' manually."
    }

    Save-Checkpoint "GrafanaStarted" $config
} elseif ($SkipDocker) {
    Write-Warning2 "Docker startup skipped"
} else {
    Write-Warning2 "Containers already started"
}

# =============================================
# Deployment Complete
# =============================================

Write-Header "Deployment Complete!"

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Open Grafana: http://localhost:$GrafanaPort" -ForegroundColor White
Write-Host "  2. Login: admin / Admin123!" -ForegroundColor White
Write-Host "  3. Explore dashboards (landing page should be home)" -ForegroundColor White
Write-Host ""
Write-Host "Run '.\Deploy.ps1 -Status' to check deployment status" -ForegroundColor Gray
Write-Host ""
