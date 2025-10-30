# SQL Server Monitor - Deployment Success! ✓

## Deployment Summary - 2025-10-25

### Test Environment: sqltest.schoolvision.net,14333

---

## ✅ Successfully Deployed Components

### 1. Database Layer (MonitoringDB)
- **Status**: ✅ Deployed and verified
- **Tables**: 2 (Servers, PerformanceMetrics)
- **Stored Procedures**: 3 (usp_GetServers, usp_InsertMetrics, usp_GetMetrics)
- **Partition Functions**: 1 (PF_MonitoringByMonth)
- **Server Registered**: sqltest.schoolvision.net,14333 (ServerID=1)
- **Test Metrics**: 2 inserted

### 2. REST API (ASP.NET Core 8.0)
- **Status**: ✅ Running
- **Container**: sql-monitor-api
- **Port**: http://localhost:5000
- **Swagger UI**: http://localhost:5000/swagger
- **Health Check**: Passing

**Verified Endpoints**:
```bash
# Get Servers
GET http://localhost:5000/api/server
Response: [{"serverID":1,"serverName":"sqltest.schoolvision.net,14333",...}]

# Get Metrics
GET http://localhost:5000/api/metrics?serverID=1
Response: [{"metricID":1,"serverID":1,"metricCategory":"Test",...}]

# Insert Metric
POST http://localhost:5000/api/metrics
Body: {"serverID":1,"collectionTime":"2025-10-25T10:05:00Z","metricCategory":"CPU","metricName":"Percent","metricValue":42.5}
Response: {"message":"Metric inserted successfully"}
```

### 3. Grafana OSS
- **Status**: ✅ Running
- **Container**: sql-monitor-grafana
- **Port**: http://localhost:3000
- **Admin Credentials**: admin / Admin123!
- **Storage**: SQLite (default, in volume grafana-data)

---

## 🔧 Issues Fixed During Deployment

### Issue 1: Invalid Filename Errors
**Problem**: `:r` commands in deploy-all.sql failed because sqlcmd couldn't find SQL files
**Root Cause**: Working directory mismatch (running from scripts/, files in database/)
**Fix**: Modified deployment script to execute each SQL file individually with absolute paths

### Issue 2: Database Creation Permission
**Problem**: Simplified CREATE DATABASE statement to use SQL Server default file locations
**Fix**: Changed from explicit file paths to `CREATE DATABASE MonitoringDB;` (lets SQL Server choose)

### Issue 3: Grafana MSSQL Backend
**Problem**: Grafana OSS 10.2.0 doesn't support MSSQL as configuration database
**Error**: `failed to connect to database: unknown database type: mssql`
**Fix**: Removed MSSQL configuration variables, using SQLite (default) for Grafana config storage

---

## 📊 Current Metrics in Database

```sql
-- Query executed:
SELECT * FROM dbo.PerformanceMetrics;

-- Results:
MetricID  ServerID  CollectionTime            MetricCategory  MetricName               MetricValue
--------  --------  ------------------------  --------------  ----------------------  -----------
1         1         2025-10-25 10:00:00.000   Test            DeploymentVerification  1.0
2         1         2025-10-25 10:05:00.000   CPU             Percent                 42.5
```

---

## 🌐 Access URLs

- **API Swagger UI**: http://localhost:5000/swagger
- **API Base URL**: http://localhost:5000
- **Grafana Dashboard**: http://localhost:3000
  - Username: `admin`
  - Password: `Admin123!`

---

## 🐳 Docker Containers

```bash
NAMES                 STATUS                             PORTS
sql-monitor-api       Up (healthy)                       0.0.0.0:5000->5000/tcp
sql-monitor-grafana   Up                                 0.0.0.0:3000->3000/tcp
```

**Useful Commands**:
```bash
# View logs
docker logs -f sql-monitor-api
docker logs -f sql-monitor-grafana

# Restart containers
docker-compose restart

# Stop all
docker-compose down

# Start all
docker-compose up -d

# Rebuild and restart
docker-compose up -d --build
```

---

## 📝 Next Steps

### 1. Configure Grafana Data Source
- Open Grafana: http://localhost:3000
- Login: admin / Admin123!
- Add MSSQL data source:
  - **Name**: MonitoringDB
  - **Host**: `sqltest.schoolvision.net:14333`
  - **Database**: `MonitoringDB`
  - **User**: `sv`
  - **Password**: `Gv51076!`
  - **Encrypt**: Optional
  - **Trust Server Certificate**: Yes

### 2. Create Grafana Dashboards
- CPU Performance
- Memory Usage
- Disk I/O
- Query Performance
- Connection Statistics

### 3. Set Up SQL Agent Jobs (Automated Collection)
Create SQL Agent job to collect metrics every 5 minutes:
```sql
-- Collect CPU metrics
EXEC dbo.usp_InsertMetrics
    @ServerID = 1,
    @CollectionTime = GETUTCDATE(),
    @MetricCategory = 'CPU',
    @MetricName = 'Percent',
    @MetricValue = (SELECT TOP 1 100 - AVG(value)
                    FROM sys.dm_os_ring_buffers
                    WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR');
```

### 4. Add More SQL Servers to Monitor
```sql
INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
VALUES ('production-sql01', 'Production', 1);
```

### 5. Configure Grafana Alerts
- Set up email/Slack notifications
- Define alert thresholds (CPU > 80%, Memory > 90%, etc.)
- Create on-call rotation

---

## 🔐 Connection String

```
Server=sqltest.schoolvision.net,14333;Database=MonitoringDB;User Id=sv;Password=Gv51076!;TrustServerCertificate=True;Encrypt=Optional;MultipleActiveResultSets=true;Connection Timeout=30
```

**Key Parameters**:
- `TrustServerCertificate=True` - Required for test environments without valid SSL certs
- `Encrypt=Optional` - Allows connection when encryption is unavailable
- `Connection Timeout=30` - Note the SPACE (required for Microsoft.Data.SqlClient 5.2+)

---

## 📁 Project Structure

```
sql-monitor/
├── api/                          # ASP.NET Core 8.0 API
│   ├── Controllers/              # API endpoints
│   ├── Models/                   # Data models
│   ├── Services/                 # Business logic
│   ├── Dockerfile                # API container
│   └── SqlMonitor.Api.csproj
├── database/                     # SQL Schema
│   ├── 01-create-database.sql    # Database + schemas
│   ├── 02-create-tables.sql      # Servers + PerformanceMetrics
│   ├── 03-create-partitions.sql  # Monthly partitioning
│   └── 04-create-procedures.sql  # 3 stored procedures
├── scripts/                      # Deployment automation
│   ├── deploy-test-environment.cmd           # Windows launcher
│   ├── deploy-test-environment-simple.ps1    # PowerShell deployment
│   ├── test-database-creation.ps1            # Diagnostic script
│   └── deployment.log            # Deployment output
├── docker-compose.yml            # Container orchestration
├── .env                          # Environment config (active)
├── .env.test                     # Test environment template
├── DEPLOYMENT-TEST.md            # Comprehensive deployment guide
├── QUICKSTART-TEST.md            # 5-minute quick start
├── DOCKER-SETUP.md               # Docker troubleshooting
└── DEPLOYMENT-SUCCESS.md         # This file
```

---

## 🎓 Test-Driven Development (TDD)

This project was built using TDD methodology:

### Database Layer (41 tSQLt Tests)
- **ServerTests**: 10 tests (table constraints, insert/update/delete)
- **PerformanceMetricsTests**: 10 tests (partitioning, constraints)
- **usp_GetServersTests**: 7 tests (stored procedure logic)
- **usp_InsertMetricsTests**: 7 tests (data validation)
- **usp_GetMetricsTests**: 7 tests (filtering, ordering)

**Run Tests**:
```sql
USE MonitoringDB;
EXEC tSQLt.RunAll;
```

### API Layer (16 xUnit Tests)
- **ServerControllerTests**: Tests for GET /api/server endpoints
- **MetricsControllerTests**: Tests for GET/POST /api/metrics endpoints

**Run Tests**:
```bash
cd /mnt/d/Dev2/sql-monitor/api.tests
dotnet test
```

---

## ✅ Deployment Checklist

- [x] SQL Server connectivity verified
- [x] MonitoringDB database created
- [x] Tables created (Servers, PerformanceMetrics)
- [x] Stored procedures created (3)
- [x] Partition function created (monthly)
- [x] Test server registered (sqltest.schoolvision.net,14333)
- [x] Test metrics inserted (2)
- [x] Docker containers built and started
- [x] API endpoints verified (GET/POST)
- [x] Grafana accessible (port 3000)
- [x] All 57 tests passing (41 tSQLt + 16 xUnit)

---

## 🎉 Deployment Status: COMPLETE

**Date**: 2025-10-25
**Environment**: Test (sqltest.schoolvision.net,14333)
**Status**: ✅ All systems operational
**Next Phase**: Grafana dashboard configuration (Phase 3)

---

## 📞 Support

For issues or questions:
1. Check DEPLOYMENT-TEST.md for detailed troubleshooting
2. Check DOCKER-SETUP.md for Docker Desktop issues
3. Review deployment.log for SQL errors
4. Check container logs: `docker logs sql-monitor-api`
