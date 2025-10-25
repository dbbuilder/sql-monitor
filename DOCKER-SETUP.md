# Docker Desktop Setup Guide

## Issue: Docker Desktop Not Running

You saw this error:
```
unable to get image 'grafana/grafana-oss:10.2.0': error during connect:
Get "http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/v1.51/images/...":
open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.
```

**This means Docker Desktop is not running.**

## Fix: Start Docker Desktop

### Option 1: Start from Start Menu
1. Press Windows key
2. Type "Docker Desktop"
3. Click to start Docker Desktop
4. Wait for Docker icon in system tray to show "Docker Desktop is running"

### Option 2: Start from Command Line
```powershell
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
```

### Verify Docker is Running
```powershell
# Check Docker status
docker ps

# Expected output: List of running containers (may be empty)
# If you see an error, Docker is not running yet
```

## Complete Deployment Steps (Corrected)

### Step 0: Start Docker Desktop (FIRST!)
```powershell
# Open Docker Desktop and wait until it says "Docker Desktop is running"
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"

# Wait 30-60 seconds for Docker to start
Start-Sleep -Seconds 60

# Verify Docker is running
docker ps
```

### Step 1: Deploy Database
```powershell
cd D:\Dev2\sql-monitor\scripts
.\deploy-test-environment.cmd
```

### Step 2: Configure Environment
```powershell
cd D:\Dev2\sql-monitor
copy .env.test .env
```

### Step 3: Start Containers
```powershell
# Now this should work since Docker Desktop is running
docker-compose up -d

# Expected output:
# [+] Running 3/3
#  ✔ Network sql-monitor_sql-monitor-network  Created
#  ✔ Container sql-monitor-grafana             Started
#  ✔ Container sql-monitor-api                 Started
```

### Step 4: Verify Containers
```powershell
docker-compose ps

# Expected output:
# NAME                     STATUS              PORTS
# sql-monitor-api          Up                  0.0.0.0:5000->5000/tcp
# sql-monitor-grafana      Up                  0.0.0.0:3000->3000/tcp
```

### Step 5: Test API
```powershell
# Test API endpoint
Invoke-RestMethod -Uri http://localhost:5000/api/server

# Or open in browser
start http://localhost:5000/swagger
```

### Step 6: Access Grafana
```powershell
start http://localhost:3000
# Login: admin / Admin123!
```

## Troubleshooting

### Docker Desktop Won't Start

**Check if Hyper-V is enabled:**
```powershell
# Run as Administrator
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V

# If State is "Disabled", enable it:
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
# Restart computer after this
```

**Check if WSL 2 is installed:**
```powershell
# Run as Administrator
wsl --list --verbose

# If not installed, install WSL 2:
wsl --install
# Restart computer after this
```

### Docker Commands Fail

**Error**: `docker: command not found` or `docker is not recognized`

**Fix**: Add Docker to PATH or use full path:
```powershell
& "C:\Program Files\Docker\Docker\resources\bin\docker.exe" ps
```

### Containers Won't Start

**View detailed logs:**
```powershell
# API logs
docker logs sql-monitor-api

# Grafana logs
docker logs sql-monitor-grafana
```

**Common issues:**

1. **Port already in use**
   ```powershell
   # Check what's using port 5000
   netstat -ano | findstr :5000

   # Kill the process or change port in docker-compose.yml
   ```

2. **Cannot connect to SQL Server from container**
   ```powershell
   # Test from container
   docker exec -it sql-monitor-api /bin/bash
   # Then inside container, test connection (if tools available)
   ```

   **Fix**: Ensure connection string uses `Encrypt=Optional` in .env file

### Rebuild Containers

If containers are misbehaving:
```powershell
# Stop and remove everything
docker-compose down

# Rebuild from scratch
docker-compose build --no-cache

# Start fresh
docker-compose up -d
```

## Alternative: Manual Docker Commands

If docker-compose has issues, start containers manually:

### Start Grafana
```powershell
docker run -d `
  --name sql-monitor-grafana `
  -p 3000:3000 `
  -e GF_SECURITY_ADMIN_PASSWORD=Admin123! `
  grafana/grafana-oss:10.2.0
```

### Build and Start API
```powershell
# Build API image
cd D:\Dev2\sql-monitor\api
docker build -t sql-monitor-api .

# Run API container
docker run -d `
  --name sql-monitor-api `
  -p 5000:5000 `
  -e "ConnectionStrings__MonitoringDB=Server=sqltest.schoolvision.net,14333;Database=MonitoringDB;User Id=sv;Password=Gv51076!;TrustServerCertificate=True;Encrypt=Optional;MultipleActiveResultSets=true;Connection Timeout=30" `
  sql-monitor-api
```

## Quick Reference

### Check Docker Status
```powershell
# Is Docker running?
docker version

# List running containers
docker ps

# List all containers (including stopped)
docker ps -a
```

### Container Management
```powershell
# Start containers
docker-compose up -d

# Stop containers
docker-compose down

# Restart containers
docker-compose restart

# View logs
docker logs -f sql-monitor-api
docker logs -f sql-monitor-grafana
```

### Cleanup
```powershell
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove everything (BE CAREFUL!)
docker system prune -a
```

---

**Next**: After Docker Desktop is running and containers are up, continue with QUICKSTART-TEST.md
