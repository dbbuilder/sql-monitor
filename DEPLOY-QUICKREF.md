# SQL Monitor Deployment - Quick Reference

## 🚀 One-Command Deploy

### Windows
```powershell
.\Deploy.ps1 -SqlServer "localhost,1433" -SqlUser "sa" -SqlPassword "Pass123!"
```

### Linux/macOS
```bash
./deploy.sh --sql-server localhost,1433 --sql-user sa --sql-password 'Pass123!'
```

---

## 📋 Common Commands

| Action | Windows | Linux/macOS |
|--------|---------|-------------|
| **Fresh install** | `.\Deploy.ps1 -SqlServer "server" -SqlUser "sa"` | `./deploy.sh --sql-server server --sql-user sa` |
| **Resume** | `.\Deploy.ps1 -Resume` | `./deploy.sh --resume` |
| **Check status** | `.\Deploy.ps1 -Status` | `./deploy.sh --status` |
| **Skip Docker** | `.\Deploy.ps1 -SkipDocker` | `./deploy.sh --skip-docker` |
| **Small batches** | `.\Deploy.ps1 -BatchSize 5` | `./deploy.sh --batch-size 5` |
| **Production** | `.\Deploy.ps1 -Environment Production` | `./deploy.sh --environment Production` |

---

## ⚙️ All Parameters

| Parameter | PowerShell | Bash | Default |
|-----------|------------|------|---------|
| SQL Server | `-SqlServer` | `--sql-server` | `localhost,1433` |
| Username | `-SqlUser` | `--sql-user` | - |
| Password | `-SqlPassword` | `--sql-password` | (prompted) |
| Database | `-DatabaseName` | `--database` | `MonitoringDB` |
| Environment | `-Environment` | `--environment` | `Development` |
| Grafana Port | `-GrafanaPort` | `--grafana-port` | `9002` |
| API Port | `-ApiPort` | `--api-port` | `9000` |
| Skip Docker | `-SkipDocker` | `--skip-docker` | `false` |
| Batch Size | N/A | `--batch-size` | `10` |
| Resume | `-Resume` | `--resume` | - |
| Status | `-Status` | `--status` | - |

---

## 🔄 Deployment Steps (8 Total)

1. ✅ **Prerequisites** - Check tools (sqlcmd, docker, jq)
2. ✅ **Database Created** - Create MonitoringDB
3. ✅ **Tables Created** - Deploy schema
4. ✅ **Procedures Created** - Deploy stored procedures
5. ✅ **Server Registered** - Add local server to Servers table
6. ✅ **Metadata Initialized** - Collect database metadata (longest step)
7. ✅ **Docker Configured** - Generate .env and configure Grafana
8. ✅ **Grafana Started** - Start containers

---

## 🚦 What to Do When...

### Timeout During Deployment
```bash
# Reduce batch size and resume
./deploy.sh --resume --batch-size 5
```

### Need to Start Over
```bash
# Delete checkpoint file
rm .deploy-checkpoint.json

# Re-run deployment
./deploy.sh --sql-server localhost --sql-user sa
```

### Check What's Complete
```bash
./deploy.sh --status
```

### Just Want Database (No Docker)
```bash
./deploy.sh --sql-server server --sql-user sa --skip-docker
```

### Interrupted During Metadata Collection
```bash
# Just resume - it will pick up where it left off
./deploy.sh --resume
```

---

## 📊 Timing Expectations

| Environment | Databases | Tables | Time |
|-------------|-----------|--------|------|
| **Small** | 1-10 | <1000 | 2-6 min |
| **Medium** | 10-50 | 1000-5000 | 11-31 min |
| **Large** | 50+ | 5000+ | 1-3 hours |

**Note**: 90% of time is metadata collection (Step 6). This is resumable.

---

## 🔍 Troubleshooting Quick Checks

```bash
# Test SQL connection
sqlcmd -S localhost,1433 -U sa -P 'Pass123!' -Q "SELECT @@VERSION"

# Check Docker
docker --version
docker ps

# Check checkpoint
cat .deploy-checkpoint.json | jq .

# Check Grafana logs
docker logs sql-monitor-grafana
```

---

## 🎯 After Deployment

1. Open Grafana: **http://localhost:9002**
2. Login: **admin** / **Admin123!**
3. Change default password
4. Explore dashboards (arcTrade branded landing page)

---

## 📁 Generated Files

| File | Purpose | Committed? |
|------|---------|------------|
| `.deploy-checkpoint.json` | Tracks deployment progress | ❌ No (local) |
| `.env` | Connection strings, secrets | ❌ No (secret) |
| `dashboards/grafana/provisioning/datasources/*.yaml` | Grafana datasource config | ✅ Yes |

---

## 🆘 Common Errors

| Error | Solution |
|-------|----------|
| `sqlcmd not found` | Install [SQL Server Command Line Tools](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/) |
| `Login failed` | Check username/password, verify SQL authentication enabled |
| `Timeout expired` | Reduce batch size: `--batch-size 5`, then `--resume` |
| `Cannot connect to Docker` | Start Docker Desktop, or use `--skip-docker` |
| `Database already exists` | Safe to continue - deployment is idempotent |

---

## 📚 Full Documentation

- **Complete Guide**: `DEPLOYMENT.md`
- **Manual Setup**: `SETUP.md`
- **Troubleshooting**: `GRAFANA-DATA-SETUP.md`
- **Testing**: `dashboards/grafana/TESTING-GUIDE.md`

---

**Quick Help**:
- Windows: `.\Deploy.ps1 -h` (get-help .\Deploy.ps1)
- Linux: `./deploy.sh --help`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
