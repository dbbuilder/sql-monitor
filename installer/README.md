# SQL Server Monitor - Quick Install Guide

One-command deployment for AWS, Azure, GCP, or On-Premises environments.

## Quick Start (Linux/macOS/WSL)

```bash
# One-liner installation
curl -sSL https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/installer/install.sh | bash
```

## Quick Start (Windows PowerShell)

```powershell
# One-liner installation
irm https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/installer/Install-SqlMonitor.ps1 | iex

# Or download and run
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/installer/Install-SqlMonitor.ps1" -OutFile Install-SqlMonitor.ps1
.\Install-SqlMonitor.ps1
```

## Prerequisites

Before running the installer, ensure you have:

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Docker | v20.10+ | Latest |
| Docker Compose | v2.0+ | Latest |
| RAM | 4GB | 8GB+ |
| Disk Space | 10GB | 50GB+ |
| SQL Server | 2016 SP2+ | 2019+ |

## Installation Modes

### Interactive Mode (Default)

The installer will guide you through:

1. **Prerequisites Check** - Validates Docker, disk space, memory
2. **SQL Server Configuration** - Server address, port, credentials
3. **Application Credentials** - Auto-generates secure passwords
4. **Network Configuration** - API and Grafana ports
5. **Server Registration** - Add SQL Servers to monitor
6. **Deployment** - Database schema, containers, verification

### Non-Interactive Mode

For automated deployments (CI/CD, scripts):

```bash
# Linux/macOS
./install.sh --config config.json --non-interactive

# Windows PowerShell
.\Install-SqlMonitor.ps1 -ConfigFile config.json -NonInteractive
```

Create a `config.json` file (see `config.example.json`):

```json
{
  "InstallPath": "/opt/sql-monitor",
  "DeploymentType": "docker",
  "SqlServer": "sql-server.example.com",
  "SqlPort": "1433",
  "SqlUser": "sa",
  "SqlPassword": "YourSecurePassword",
  "ApiUser": "monitor_api",
  "ApiPassword": "GeneratedApiPassword123",
  "GrafanaPassword": "GeneratedGrafanaPass456",
  "JwtSecret": "48CharacterLongSecretKeyForJWTTokenSigning123456",
  "ApiPort": "9000",
  "GrafanaPort": "9001",
  "EnableSsl": false,
  "RetentionDays": 90,
  "MonitoredServers": [
    "server1.example.com:1433",
    "server2.example.com:1433"
  ]
}
```

## Cloud-Specific Deployment

### AWS EC2

```bash
# Install Docker
sudo yum update -y
sudo amazon-linux-extras install docker -y
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Run installer
curl -sSL https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/installer/install.sh | bash
```

### Azure VM

```bash
# Install Docker
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo systemctl start docker
sudo usermod -aG docker $USER

# Run installer
curl -sSL https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/installer/install.sh | bash
```

### GCP Compute Engine

```bash
# Install Docker
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Run installer
curl -sSL https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/installer/install.sh | bash
```

### On-Premises (Windows Server)

```powershell
# Install Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop

# Run installer
.\Install-SqlMonitor.ps1
```

## What Gets Installed

```
/opt/sql-monitor/           (or C:\sql-monitor on Windows)
├── .env                    # Configuration (auto-generated)
├── docker-compose.yml      # Container orchestration
├── api/                    # REST API source code
├── database/               # SQL Server schema scripts
├── dashboards/             # Grafana dashboards
└── grafana-plugins/        # Custom T-SQL editor plugin
```

### Services Started

| Service | Port | Description |
|---------|------|-------------|
| Grafana | 9001 | Dashboard UI |
| API | 9000 | REST API |
| Renderer | 8081 | PDF/PNG export |

## Post-Installation

### Access Your Dashboard

1. Open Grafana: `http://localhost:9001`
2. Login: `admin` / `<your-generated-password>`
3. Navigate to "SQL Server Monitoring" dashboard

### Add More Servers

Via API:
```bash
curl -X POST http://localhost:9000/api/servers \
  -H "Content-Type: application/json" \
  -d '{"serverName": "new-server:1433", "description": "Production DB"}'
```

Via SQL:
```sql
USE MonitoringDB;
EXEC dbo.usp_AddServer
    @ServerName = 'new-server,1433',
    @Description = 'Production DB',
    @IsActive = 1;
```

### Configure Alerts

1. In Grafana, go to Alerting > Alert Rules
2. Create rules based on metrics:
   - CPU > 90%
   - Memory > 85%
   - Long-running queries > 30 seconds
   - Blocking chains detected

## Maintenance Commands

```bash
# View logs
cd /opt/sql-monitor && docker compose logs -f

# Restart services
cd /opt/sql-monitor && docker compose restart

# Stop services
cd /opt/sql-monitor && docker compose down

# Update to latest version
cd /opt/sql-monitor && git pull && docker compose up -d --build

# Backup configuration
cp /opt/sql-monitor/.env /opt/sql-monitor/.env.backup
```

## Troubleshooting

### Docker not running
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### SQL Server connection failed
- Check firewall rules (port 1433)
- Verify SQL Server allows remote connections
- Test with: `sqlcmd -S server,port -U user -P password -Q "SELECT 1"`

### Grafana shows "No data"
1. Verify SQL Server datasource in Grafana (Settings > Data Sources)
2. Check that collection jobs are running: `SELECT * FROM MonitoringDB.dbo.CollectionHistory`
3. Verify metrics: `SELECT TOP 10 * FROM MonitoringDB.dbo.PerformanceMetrics ORDER BY CollectionTime DESC`

### Container health check failing
```bash
# Check container logs
docker compose logs api
docker compose logs grafana

# Restart specific container
docker compose restart api
```

## Security Recommendations

1. **Change default passwords** - The installer generates secure passwords, but review them
2. **Enable SSL** - Set `EnableSsl=true` and provide certificates
3. **Firewall rules** - Only expose ports 9000/9001 to authorized networks
4. **Database permissions** - The `monitor_api` user has minimal required permissions
5. **JWT secret rotation** - Rotate the JWT secret periodically

## Support

- Documentation: https://github.com/dbbuilder/sql-monitor/docs
- Issues: https://github.com/dbbuilder/sql-monitor/issues
- Discussions: https://github.com/dbbuilder/sql-monitor/discussions

## License

Apache 2.0 - Free for commercial use
