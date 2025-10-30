# SQL Server Monitor - Quick Start (Test Environment)

## Prerequisites

✅ Windows machine with Docker Desktop installed
✅ Network access to sqltest.schoolvision.net:14333
✅ sqlcmd installed (comes with SQL Server Management Studio)

## 5-Minute Setup

### Step 1: Deploy Database (2 minutes)

Open **PowerShell** or **Command Prompt** and run:

```powershell
cd D:\Dev2\sql-monitor\scripts
.\deploy-test-environment.cmd
```

This will:
- ✅ Create MonitoringDB on sqltest.schoolvision.net
- ✅ Create tables (Servers, PerformanceMetrics)
- ✅ Create stored procedures (usp_GetServers, usp_InsertMetrics, usp_GetMetrics)
- ✅ Set up monthly partitioning
- ✅ Register the SQL Server for monitoring
- ✅ Insert a test metric

### Step 2: Configure Environment (30 seconds)

```powershell
cd D:\Dev2\sql-monitor

# Copy test environment config
copy .env.test .env
```

### Step 3: Start Docker Containers (2 minutes)

```powershell
# Start API + Grafana
docker-compose up -d

# Verify containers are running
docker-compose ps
```

Expected output:
```
NAME                     STATUS              PORTS
sql-monitor-api          Up                  0.0.0.0:5000->5000/tcp
sql-monitor-grafana      Up                  0.0.0.0:3000->3000/tcp
```

### Step 4: Verify API is Working (30 seconds)

Open browser to: **http://localhost:5000/swagger**

Try the API:
```powershell
# Get list of servers
curl http://localhost:5000/api/server

# Expected: JSON with sqltest.schoolvision.net server
```

### Step 5: Access Grafana (30 seconds)

Open browser to: **http://localhost:3000**

- **Username**: admin
- **Password**: Admin123!

---

## Test the Complete Flow

### Insert a Metric via API

```powershell
$body = @{
    serverID = 1
    collectionTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    metricCategory = "CPU"
    metricName = "Percent"
    metricValue = 42.5
} | ConvertTo-Json

Invoke-RestMethod -Uri http://localhost:5000/api/metrics -Method Post -Body $body -ContentType "application/json"
```

### Query Metrics via API

```powershell
# Get all metrics for server 1
Invoke-RestMethod -Uri "http://localhost:5000/api/metrics?serverID=1"

# Get CPU metrics only
Invoke-RestMethod -Uri "http://localhost:5000/api/metrics?serverID=1&metricCategory=CPU"
```

### Query Metrics via Database

```powershell
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB -Q "EXEC dbo.usp_GetMetrics @ServerID=1"
```

---

## Troubleshooting

### Cannot Connect to SQL Server

```powershell
# Test connectivity
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT @@VERSION"
```

If this fails:
- Check VPN connection
- Verify firewall allows port 14333
- Confirm SQL Server is running

### Docker Containers Won't Start

```powershell
# Check Docker Desktop is running
docker ps

# View logs
docker logs sql-monitor-api
docker logs sql-monitor-grafana

# Rebuild containers
docker-compose down
docker-compose up -d --build
```

### API Returns 500 Error

```powershell
# Check connection string in .env
cat .env

# Verify MonitoringDB exists
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT name FROM sys.databases WHERE name='MonitoringDB'"

# Check API logs
docker logs sql-monitor-api
```

---

## Next Steps

1. **Configure SQL Agent Collection** - Set up automated metric collection
2. **Create Grafana Dashboards** - Visualize CPU, Memory, I/O metrics
3. **Add More Servers** - Monitor additional SQL Server instances
4. **Set Up Alerts** - Configure Grafana alerts for critical thresholds

---

## Quick Commands Reference

```powershell
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker logs -f sql-monitor-api

# Restart services
docker-compose restart

# Access database
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB

# Test API
curl http://localhost:5000/api/server

# Access Grafana
start http://localhost:3000

# Access Swagger UI
start http://localhost:5000/swagger
```

---

## What's Deployed?

### Database (sqltest.schoolvision.net,14333)
- **MonitoringDB** database
- **Servers** table - Inventory of monitored servers
- **PerformanceMetrics** table - Time-series metrics (partitioned by month)
- **3 stored procedures** - usp_GetServers, usp_InsertMetrics, usp_GetMetrics

### Docker Containers (Local)
- **sql-monitor-api** - REST API on port 5000
- **sql-monitor-grafana** - Grafana on port 3000

### API Endpoints
- `GET /api/server` - List monitored servers
- `GET /api/metrics?serverID={id}` - Get metrics with filters
- `POST /api/metrics` - Insert new metric

---

**Need help?** See DEPLOYMENT-TEST.md for detailed troubleshooting guide.
