# SQL Monitor - Idempotent Deployment Guide

## 🎯 Overview

This deployment system provisions SQL Monitor from a fresh `git clone` with full idempotency - safe to run multiple times, can resume from any point, and never regresses working components.

**Key Features**:
- ✅ **Cross-Platform**: Works on Windows (PowerShell) and Linux/macOS (Bash)
- ✅ **Idempotent**: Run multiple times safely - only applies missing changes
- ✅ **Resumable**: Checkpoint system allows resuming from interruptions
- ✅ **Batched Metadata Collection**: Processes databases in configurable batches to avoid timeouts
- ✅ **Parameter-Driven**: Fully configurable via command-line arguments
- ✅ **Progress Tracking**: Per-database tracking for metadata collection

---

## 📋 Prerequisites

### All Platforms

- **SQL Server** (2016+) with TCP/IP enabled
- **SQL Server Command Line Tools** (`sqlcmd`)
  - Windows: Install [SQL Server Command Line Tools](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility)
  - Linux: `sudo apt-get install mssql-tools` (Ubuntu/Debian)
  - macOS: `brew install sqlcmd`

### Linux/macOS Only

- **jq** (JSON processor)
  - Ubuntu/Debian: `sudo apt-get install jq`
  - macOS: `brew install jq`

### Optional (for Grafana dashboards)

- **Docker** and **Docker Compose**
  - [Install Docker](https://docs.docker.com/get-docker/)
  - Use `--skip-docker` flag if you only want database setup

---

## 🚀 Quick Start

### Windows (PowerShell)

```powershell
# Clone repository
git clone https://github.com/yourusername/sql-monitor.git
cd sql-monitor

# Run deployment (interactive - will prompt for password)
.\Deploy.ps1 -SqlServer "localhost,1433" -SqlUser "sa" -Environment "Development"

# Or with all parameters
.\Deploy.ps1 `
    -SqlServer "sqlserver.company.com" `
    -SqlUser "sa" `
    -SqlPassword "YourPassword123!" `
    -DatabaseName "MonitoringDB" `
    -Environment "Production" `
    -GrafanaPort 9002 `
    -ApiPort 9000
```

### Linux/macOS (Bash)

```bash
# Clone repository
git clone https://github.com/yourusername/sql-monitor.git
cd sql-monitor

# Run deployment (interactive - will prompt for password)
./deploy.sh --sql-server localhost,1433 --sql-user sa --environment Development

# Or with all parameters
./deploy.sh \
    --sql-server sqlserver.company.com \
    --sql-user sa \
    --sql-password 'YourPassword123!' \
    --database MonitoringDB \
    --environment Production \
    --grafana-port 9002 \
    --api-port 9000 \
    --batch-size 10
```

---

## 🔧 Configuration Options

### PowerShell Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `-SqlServer` | SQL Server instance | `localhost,1433` | Yes |
| `-SqlUser` | SQL username | - | Yes (or prompted) |
| `-SqlPassword` | SQL password | - | Yes (or prompted) |
| `-DatabaseName` | Database name | `MonitoringDB` | No |
| `-GrafanaPort` | Grafana HTTP port | `9002` | No |
| `-ApiPort` | REST API port | `9000` | No |
| `-Environment` | Environment (Development\|Staging\|Production) | `Development` | No |
| `-SkipDocker` | Skip Docker setup | `false` | No |
| `-Resume` | Resume from checkpoint | `false` | No |
| `-Status` | Show deployment status | `false` | No |

### Bash Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--sql-server` | SQL Server instance | `localhost,1433` | Yes |
| `--sql-user` | SQL username | - | Yes (or prompted) |
| `--sql-password` | SQL password | - | Yes (or prompted) |
| `--database` | Database name | `MonitoringDB` | No |
| `--grafana-port` | Grafana HTTP port | `9002` | No |
| `--api-port` | REST API port | `9000` | No |
| `--environment` | Environment | `Development` | No |
| `--skip-docker` | Skip Docker setup | `false` | No |
| `--batch-size` | Databases per batch | `10` | No |
| `--resume` | Resume from checkpoint | `false` | No |
| `--status` | Show deployment status | `false` | No |
| `--help` | Show help message | - | No |

---

## 📦 Deployment Steps

The deployment script performs these steps in order:

### Step 1: Prerequisites Check
- Verifies `sqlcmd` is installed
- Verifies `docker` (if not using `--skip-docker`)
- Verifies `jq` (Linux/macOS only)

**Checkpoint**: `Prerequisites`

### Step 2: Create Database
- Creates database if it doesn't exist
- Sets recovery model to SIMPLE
- Enables checksum page verification

**Checkpoint**: `DatabaseCreated`

### Step 3: Deploy Schema (Tables)
- Executes `*-create-*tables*.sql` scripts in order
- Skips if tables already exist (idempotent)

**Checkpoint**: `TablesCreated`

### Step 4: Deploy Procedures/Functions
- Executes `*-create-*procedure*.sql` scripts
- Uses `CREATE OR ALTER` for idempotency

**Checkpoint**: `ProceduresCreated`

### Step 5: Register Server
- Inserts local server into `Servers` table
- Skips if server already registered

**Checkpoint**: `ServerRegistered`

### Step 6: Initialize Metadata Collection (Batched)
- Discovers all user databases (excludes system databases)
- Processes databases in batches (default: 10 per batch)
- Tracks each database individually for resume capability
- Timeout: 5 minutes per database (configurable)

**Key Feature**: If interrupted, rerun with `--resume` to pick up where you left off.

**Checkpoint**: `MetadataInitialized` + per-database tracking

### Step 7: Configure Docker
- Generates `.env` file with connection strings
- Creates JWT secret
- Configures Grafana datasource

**Checkpoint**: `DockerConfigured`

### Step 8: Start Docker Containers
- Starts Grafana and API containers
- Maps ports (default: Grafana 9002, API 9000)

**Checkpoint**: `GrafanaStarted`

---

## 🔄 Idempotency and Resumability

### What is Idempotent?

**Idempotent** means running the script multiple times produces the same result without unintended side effects. The deployment script:

- ✅ Checks if each step is complete before running
- ✅ Uses `CREATE OR ALTER` for procedures (never drops)
- ✅ Uses `IF NOT EXISTS` for data insertion
- ✅ Never deletes or reverts existing data
- ✅ Tracks progress in `.deploy-checkpoint.json`

### Checkpoint System

The script saves a checkpoint file (`.deploy-checkpoint.json`) tracking:
- Completed deployment steps
- Processed databases (for metadata collection)
- Configuration (server, database name, environment)
- Last update timestamp

**Example checkpoint file**:
```json
{
  "steps": [
    "Prerequisites",
    "DatabaseCreated",
    "TablesCreated",
    "ProceduresCreated",
    "ServerRegistered"
  ],
  "processedDatabases": [
    "MonitoringDB",
    "AppDB",
    "CustomerDB"
  ],
  "lastUpdated": "2025-10-29 08:30:15",
  "sqlServer": "localhost,14333",
  "databaseName": "MonitoringDB",
  "environment": "Development"
}
```

### Resuming Deployment

If deployment is interrupted (network failure, timeout, CTRL+C):

**PowerShell**:
```powershell
.\Deploy.ps1 -Resume
```

**Bash**:
```bash
./deploy.sh --resume
```

The script will:
1. Load configuration from checkpoint
2. Skip completed steps
3. Resume metadata collection for unprocessed databases only
4. Continue from where it stopped

---

## 🔍 Checking Status

**PowerShell**:
```powershell
.\Deploy.ps1 -Status
```

**Bash**:
```bash
./deploy.sh --status
```

**Example output**:
```
========================================
Deployment Status
========================================

  ℹ  Last Updated: 2025-10-29 08:45:30
  ℹ  SQL Server: localhost,14333
  ℹ  Database: MonitoringDB
  ℹ  Environment: Development

Completed Steps:
  [X] Prerequisites
  [X] DatabaseCreated
  [X] TablesCreated
  [X] ProceduresCreated
  [X] ServerRegistered
  [ ] MetadataInitialized
  [ ] DockerConfigured
  [ ] GrafanaStarted

  ℹ  Databases processed for metadata: 15
```

---

## 🚦 Batch Processing for Large Environments

For servers with many databases (50+), use batched processing to avoid timeouts:

**PowerShell**:
```powershell
.\Deploy.ps1 `
    -SqlServer "prod-server" `
    -SqlUser "sa" `
    -SqlPassword "Pass123!" `
    -BatchSize 5  # Process 5 databases at a time
```

**Bash**:
```bash
./deploy.sh \
    --sql-server prod-server \
    --sql-user sa \
    --sql-password 'Pass123!' \
    --batch-size 5
```

**Batch Size Guidelines**:
- **1-20 databases**: Use default (10)
- **20-50 databases**: Use 5-8 per batch
- **50+ databases**: Use 3-5 per batch
- **Large databases (>10GB)**: Use 1-2 per batch

**Timeout Considerations**:
- Default timeout: 5 minutes per database
- If timeouts occur, reduce batch size
- Metadata collection is resumable - restart with `--resume`

---

## 🛠️ Troubleshooting

### Connection Errors

**Error**: `Client unable to establish connection`

**Solution**:
1. Verify SQL Server is running: `docker ps` (if containerized) or check Windows Services
2. Check TCP/IP is enabled: SQL Server Configuration Manager → Protocols
3. Verify firewall allows connections: Port 1433 (or your custom port)
4. Test connection: `sqlcmd -S localhost,1433 -U sa -P 'YourPassword' -Q "SELECT @@VERSION"`

### Login Failed

**Error**: `Login failed for user 'sa'`

**Solution**:
1. Verify username and password
2. Check SQL Server authentication mode (must allow SQL authentication)
3. Ensure user has `sysadmin` role or at minimum:
   - `CREATE DATABASE` permission
   - `db_owner` on target database

### Timeout During Metadata Collection

**Error**: `Timeout expired` during Step 6

**Solution**:
1. Reduce batch size: `--batch-size 5` or `-BatchSize 5`
2. Resume deployment: `--resume` or `-Resume`
3. Process databases manually:
   ```sql
   EXEC dbo.usp_RefreshMetadataCache
       @ServerID = 1,
       @DatabaseName = 'SpecificDatabase',
       @ForceRefresh = 0;
   ```

### Docker Errors

**Error**: `Cannot connect to the Docker daemon`

**Solution**:
1. Ensure Docker Desktop is running (Windows/macOS)
2. Verify Docker service: `sudo systemctl status docker` (Linux)
3. Skip Docker setup: `--skip-docker` or `-SkipDocker`
4. Run Docker commands manually:
   ```bash
   docker compose up -d
   ```

### Missing Tools

**Error**: `sqlcmd not found` or `jq not found`

**Solution**:
- **Windows**: Install [SQL Server Command Line Tools](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/)
- **Ubuntu/Debian**: `sudo apt-get install mssql-tools jq`
- **macOS**: `brew install sqlcmd jq`

---

## 🎓 Common Scenarios

### Scenario 1: Fresh Installation (Development)

```powershell
# Windows
git clone https://github.com/yourusername/sql-monitor.git
cd sql-monitor
.\Deploy.ps1 -SqlServer "localhost,1433" -SqlUser "sa" -SqlPassword "DevPass123!"
```

```bash
# Linux
git clone https://github.com/yourusername/sql-monitor.git
cd sql-monitor
./deploy.sh --sql-server localhost,1433 --sql-user sa --sql-password 'DevPass123!'
```

**Result**:
- Database created
- Schema deployed
- Metadata collected for all databases
- Grafana running on http://localhost:9002

### Scenario 2: Production Deployment (Database Only)

```powershell
# Windows - Skip Docker for production SQL Server
.\Deploy.ps1 `
    -SqlServer "prod-sql-01.company.com" `
    -SqlUser "monitor_svc" `
    -SqlPassword "ProdPass456!" `
    -Environment "Production" `
    -SkipDocker
```

```bash
# Linux
./deploy.sh \
    --sql-server prod-sql-01.company.com \
    --sql-user monitor_svc \
    --sql-password 'ProdPass456!' \
    --environment Production \
    --skip-docker
```

**Result**:
- Database and schema deployed
- Metadata collected
- No Docker containers (use existing Grafana/API)

### Scenario 3: Large Environment (100+ Databases)

```bash
# Start deployment with small batch size
./deploy.sh \
    --sql-server prod-sql-02.company.com \
    --sql-user sa \
    --sql-password 'Pass789!' \
    --batch-size 3 \
    --environment Production

# If interrupted, resume
./deploy.sh --resume

# Check progress
./deploy.sh --status
```

**Result**:
- Processes 3 databases at a time (reduces timeout risk)
- Can resume from any point
- Tracks individual database completion

### Scenario 4: Update Existing Deployment

```powershell
# Pull latest changes
git pull origin main

# Re-run deployment (safe - idempotent)
.\Deploy.ps1 -Resume
```

**Result**:
- Skips completed steps
- Applies new procedures (CREATE OR ALTER)
- Collects metadata for new databases only

---

## 📊 Expected Timing

| Deployment Step | Time (Small) | Time (Medium) | Time (Large) |
|-----------------|--------------|---------------|--------------|
| Prerequisites | 5 seconds | 5 seconds | 5 seconds |
| Database Creation | 2 seconds | 2 seconds | 2 seconds |
| Schema Deployment | 10 seconds | 10 seconds | 10 seconds |
| Procedure Deployment | 15 seconds | 15 seconds | 15 seconds |
| Server Registration | 1 second | 1 second | 1 second |
| **Metadata Collection** | **1-5 min** | **10-30 min** | **1-3 hours** |
| Docker Configuration | 5 seconds | 5 seconds | 5 seconds |
| Container Startup | 30 seconds | 30 seconds | 30 seconds |
| **Total** | **2-6 min** | **11-31 min** | **1-3.5 hours** |

**Environment Sizes**:
- **Small**: 1-10 databases, <1000 tables
- **Medium**: 10-50 databases, 1000-5000 tables
- **Large**: 50+ databases, 5000+ tables

**Note**: Metadata collection is the longest step and is fully resumable.

---

## 🔐 Security Considerations

### Credential Management

**Never commit credentials to source control**. The deployment scripts accept credentials via:

1. **Command-line arguments** (for CI/CD pipelines)
2. **Interactive prompts** (for manual deployment)
3. **Environment variables** (for containerized environments)

**Best Practices**:
- Use SQL authentication for service accounts
- Create dedicated monitoring user with minimal permissions:
  ```sql
  CREATE LOGIN [monitor_svc] WITH PASSWORD = 'SecurePassword123!';
  CREATE USER [monitor_svc] FOR LOGIN [monitor_svc];
  ALTER ROLE db_datareader ADD MEMBER [monitor_svc];
  GRANT VIEW DATABASE STATE TO [monitor_svc];
  GRANT VIEW SERVER STATE TO [monitor_svc];
  ```
- Rotate passwords regularly
- Use Windows authentication where possible (integrated security)

### Generated Secrets

The deployment script generates:
- **JWT secret** (32-byte random string for API authentication)
- **Grafana admin password** (default: `Admin123!` - change after first login)

These are stored in `.env` file (excluded from git via `.gitignore`).

---

## 📚 Additional Resources

- **Setup Guide**: `SETUP.md` - Manual setup instructions
- **Testing Guide**: `dashboards/grafana/TESTING-GUIDE.md` - Dashboard testing procedures
- **Data Setup**: `GRAFANA-DATA-SETUP.md` - Metadata collection troubleshooting
- **API Documentation**: `docs/api/` - REST API reference
- **Database Schema**: `database/README.md` - Schema documentation

---

## 🤝 Support

If you encounter issues:

1. Check deployment status: `.\Deploy.ps1 -Status` or `./deploy.sh --status`
2. Review checkpoint file: `.deploy-checkpoint.json`
3. Check prerequisites: `sqlcmd`, `docker`, `jq` (Linux/macOS)
4. Review logs: `docker logs sql-monitor-grafana` (if using Docker)
5. Open an issue: [GitHub Issues](https://github.com/yourusername/sql-monitor/issues)

---

**Created**: 2025-10-29
**Status**: Production-Ready
**Next**: Run deployment script and verify Grafana dashboards

🤖 Generated with [Claude Code](https://claude.com/claude-code)
