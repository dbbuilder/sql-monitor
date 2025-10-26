# SQL Server Monitor - Test Environment Deployment Guide

**Target Environment**: sqltest.schoolvision.net,14333
**Database User**: sv
**Password**: Gv51076!
**Date**: 2025-10-25

## Prerequisites

- SQL Server 2016+ accessible at sqltest.schoolvision.net,14333
- Docker and Docker Compose installed on deployment machine
- Network access from Docker host to SQL Server (port 14333)
- sqlcmd utility (for database deployment)

## Deployment Steps

### Step 1: Deploy MonitoringDB Database (10-15 minutes)

#### Option A: Using sqlcmd (Recommended)

```bash
# Test connectivity first
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT @@VERSION"

# Deploy complete database schema
cd /mnt/d/Dev2/sql-monitor/database

sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -i deploy-all.sql

# Expected output:
# - MonitoringDB database created
# - 2 tables created (Servers, PerformanceMetrics)
# - 3 stored procedures created
# - 1 partition function (13 partitions)
# - 1 partition scheme
# - 6 indexes created
```

#### Option B: Manual Step-by-Step

```bash
# 1. Create database
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -i 01-create-database.sql

# 2. Create partition function/scheme
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -i 03-create-partitions.sql

# 3. Create tables
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -i 02-create-tables.sql

# 4. Create stored procedures
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -i 04-create-procedures.sql
```

### Step 2: Verify Database Deployment

```bash
# Connect and verify
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB

# Run verification queries
SELECT name, type_desc FROM sys.objects WHERE type IN ('U', 'P') ORDER BY type_desc, name;
GO

SELECT name FROM sys.partition_functions;
GO

SELECT name FROM sys.partition_schemes;
GO

# Expected results:
# Tables: PerformanceMetrics, Servers
# Procedures: usp_GetMetrics, usp_GetServers, usp_InsertMetrics
# Partition Function: PF_MonitoringByMonth
# Partition Scheme: PS_MonitoringByMonth
```

### Step 3: Create .env File for Docker

```bash
cd /mnt/d/Dev2/sql-monitor

# Create .env file with actual credentials
cat > .env << 'EOF'
# Database Connection
DB_CONNECTION_STRING=Server=sqltest.schoolvision.net,14333;Database=MonitoringDB;User Id=sv;Password=Gv51076!;TrustServerCertificate=True;Encrypt=Optional;MultipleActiveResultSets=true;Connection Timeout=30

# API Configuration
ASPNETCORE_ENVIRONMENT=Development
ASPNETCORE_URLS=http://+:5000

# Grafana Configuration
GRAFANA_ADMIN_PASSWORD=Admin123!
GF_SERVER_HTTP_PORT=3000
GF_DATABASE_TYPE=mssql
GF_DATABASE_HOST=sqltest.schoolvision.net,14333
GF_DATABASE_NAME=MonitoringDB
GF_DATABASE_USER=sv
GF_DATABASE_PASSWORD=Gv51076!
EOF

# Verify .env file
cat .env
```

### Step 4: Test Database Connectivity from Docker Host

```bash
# Test connectivity using .NET connection string format
dotnet run --project api -- --urls "http://localhost:5000" &

# Or use sqlcmd to test from Docker host
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB -Q "SELECT COUNT(*) AS TableCount FROM sys.tables"
```

### Step 5: Start Docker Containers

```bash
# Build and start containers
docker-compose up -d

# Expected output:
# [+] Running 3/3
#  ✔ Network sql-monitor_sql-monitor-network  Created
#  ✔ Container sql-monitor-grafana             Started
#  ✔ Container sql-monitor-api                 Started

# Verify containers are running
docker-compose ps

# Expected output:
# NAME                     STATUS              PORTS
# sql-monitor-api          Up                  0.0.0.0:5000->5000/tcp
# sql-monitor-grafana      Up                  0.0.0.0:3000->3000/tcp
```

### Step 6: Verify API is Working

```bash
# Test API health (from Docker host)
curl http://localhost:5000/api/server

# Expected: HTTP 200 with empty array [] (no servers registered yet)

# Or use browser
# Navigate to: http://localhost:5000/swagger
```

### Step 7: Verify Grafana is Working

```bash
# Open browser to http://localhost:3000
# Login: admin / Admin123! (from .env GRAFANA_ADMIN_PASSWORD)
```

### Step 8: Register SQL Server for Monitoring

```sql
-- Option A: Register the SQL Server itself for monitoring
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB

-- Insert the server
INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
VALUES ('sqltest.schoolvision.net,14333', 'Test', 1);
GO

-- Verify
EXEC dbo.usp_GetServers;
GO
```

### Step 9: Insert Test Metrics

```sql
-- Insert a test metric
EXEC dbo.usp_InsertMetrics
    @ServerID = 1,
    @CollectionTime = '2025-10-25 10:00:00',
    @MetricCategory = 'CPU',
    @MetricName = 'Percent',
    @MetricValue = 25.5;
GO

-- Verify metrics
EXEC dbo.usp_GetMetrics @ServerID = 1;
GO
```

### Step 10: Test API with Real Data

```bash
# Get servers
curl http://localhost:5000/api/server

# Expected: JSON array with sqltest.schoolvision.net server

# Get metrics
curl "http://localhost:5000/api/metrics?serverID=1"

# Expected: JSON array with test metric

# Insert metric via API
curl -X POST http://localhost:5000/api/metrics \
  -H "Content-Type: application/json" \
  -d '{
    "serverID": 1,
    "collectionTime": "2025-10-25T10:05:00Z",
    "metricCategory": "Memory",
    "metricName": "UsedMB",
    "metricValue": 8192.0
  }'

# Expected: HTTP 201 Created
```

## Troubleshooting

### Database Deployment Issues

**Problem**: Database deployment reports success but MonitoringDB doesn't exist

This happens when sqlcmd exits with code 0 but the database wasn't created due to:
- User lacks CREATE DATABASE permissions
- Database file paths are invalid/inaccessible
- Errors occurred but were suppressed

**Solution 1**: Check deployment log for actual errors
```powershell
cat D:\Dev2\sql-monitor\scripts\deployment.log
```

**Solution 2**: Verify CREATE DATABASE permissions
```powershell
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT HAS_PERMS_BY_NAME(null, null, 'CREATE DATABASE') AS HasPermission"
# Should return 1 if user has permission
```

**Solution 3**: List existing databases to check if created with different name
```powershell
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT name FROM sys.databases ORDER BY name"
```

**Solution 4**: Run database creation script manually
```powershell
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -i D:\Dev2\sql-monitor\database\01-create-database.sql
```

**Solution 5**: If user lacks permissions, ask DBA to create database first
```sql
-- DBA runs this as sa or sysadmin
CREATE DATABASE MonitoringDB;
GO

-- Grant permissions to sv user
USE MonitoringDB;
GO
ALTER AUTHORIZATION ON DATABASE::MonitoringDB TO sv;
GO
```

Then re-run deployment script - it will skip database creation and deploy schema.

### Connection Issues

**Problem**: Cannot connect to SQL Server from Docker container

**Solution**:
```bash
# Check firewall allows port 14333
# Check SQL Server allows remote connections
# Verify SQL Server Browser service is running (for named instances)

# Test from Docker host first
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT @@SERVERNAME"

# If that works but container fails, check Docker network settings
docker exec -it sql-monitor-api /bin/bash
# Inside container: (note: may need to install tools)
# ping sqltest.schoolvision.net
```

**Common Fix**: Use `Encrypt=Optional` instead of `Encrypt=True` for SQL Server 2016+

### Docker Build Issues

```bash
# Rebuild containers from scratch
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### View Container Logs

```bash
# API logs
docker logs sql-monitor-api

# Grafana logs
docker logs sql-monitor-grafana

# Follow logs in real-time
docker logs -f sql-monitor-api
```

### Database Permission Issues

```sql
-- Grant necessary permissions to 'sv' user
USE MonitoringDB;
GO

GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO [sv];
GO

GRANT EXECUTE ON SCHEMA::dbo TO [sv];
GO
```

## Validation Checklist

After deployment, verify:

- [ ] MonitoringDB database exists on sqltest.schoolvision.net,14333
- [ ] 2 tables created (Servers, PerformanceMetrics)
- [ ] 3 stored procedures created
- [ ] Partition function with 13 partitions
- [ ] Docker containers running (api + grafana)
- [ ] API accessible at http://localhost:5000/swagger
- [ ] Grafana accessible at http://localhost:3000
- [ ] At least 1 server registered in Servers table
- [ ] Can insert and retrieve metrics via stored procedures
- [ ] Can insert and retrieve metrics via API

## Next Steps

Once validation is complete:

1. **Phase 3**: Create Grafana dashboards (Developer, DBA, Instance Health)
2. **Configure Collection**: Set up SQL Agent jobs on monitored servers
3. **Add More Servers**: Register additional SQL Servers to monitor
4. **Configure Alerts**: Set up alerting rules in Grafana
5. **Production Deployment**: Deploy to production environment

## Quick Commands Reference

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker logs -f sql-monitor-api

# Restart services
docker-compose restart

# Rebuild and restart
docker-compose down && docker-compose up -d --build

# Connect to database
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB

# Test API
curl http://localhost:5000/api/server
```

## Connection String Reference

**Database Connection** (for API):
```
Server=sqltest.schoolvision.net,14333;Database=MonitoringDB;User Id=sv;Password=Gv51076!;TrustServerCertificate=True;Encrypt=Optional;MultipleActiveResultSets=true;Connection Timeout=30
```

**sqlcmd Connection**:
```bash
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB
```

---

**Support**: See SETUP.md for detailed architecture and troubleshooting guide.
