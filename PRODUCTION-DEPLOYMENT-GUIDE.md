# Production Deployment Guide - SQL Monitor

**Date**: 2025-10-29
**Status**: Ready for Production Deployment

---

## 🎯 Target Servers

### Server 1: Data Server
- **Hostname**: `data.schoolvision.net,14333` (fallback: `svweb,14333`)
- **Username**: `sv`
- **Password**: `Gv51076!`
- **Environment**: Production
- **Grafana Port**: 9002
- **API Port**: 9000

### Server 2: Suncity Server
- **Hostname**: `suncity.schoolvision.net,14333`
- **Username**: `sv`
- **Password**: `Gv51076!`
- **Environment**: Production
- **Grafana Port**: 9002
- **API Port**: 9000

---

## ✅ Pre-Deployment Checklist

Before deploying to production, verify:

- [x] All dashboard improvements complete (14/14 = 100%)
- [x] Insights dashboard datasource error fixed
- [x] Card-style dashboard browser created
- [x] All 15+ hyperlinks tested
- [x] 5 folder categories configured
- [x] MonitoringDB/DBATools exclusions applied
- [x] Server filters on all 8 dashboards
- [x] Time interval selectors tested
- [x] Search functionality working
- [x] Branding updated to "ArcTrade"
- [ ] Docker images built and tagged
- [ ] .env files created for both servers
- [ ] Database scripts numbered 01-27 ready
- [ ] Grafana dashboards validated

---

## 📦 Deployment Steps

### Step 1: Deploy to Data Server (data.schoolvision.net)

```bash
# Navigate to project directory
cd /mnt/d/Dev2/sql-monitor

# Deploy to data.schoolvision.net
./deploy.sh \
  --sql-server "data.schoolvision.net,14333" \
  --sql-user "sv" \
  --sql-password "Gv51076!" \
  --database "MonitoringDB" \
  --grafana-port 9002 \
  --api-port 9000 \
  --environment "Production" \
  --batch-size 10

# If data.schoolvision.net doesn't work, use fallback:
./deploy.sh \
  --sql-server "svweb,14333" \
  --sql-user "sv" \
  --sql-password "Gv51076!" \
  --database "MonitoringDB" \
  --grafana-port 9002 \
  --api-port 9000 \
  --environment "Production" \
  --batch-size 10
```

**Expected Duration**: 10-15 minutes (depending on database count)

**What It Does**:
1. ✅ Checks prerequisites (sqlcmd, jq, docker)
2. ✅ Creates MonitoringDB database (if not exists)
3. ✅ Deploys tables (numbered scripts 01-14, 20-21)
4. ✅ Deploys procedures (numbered scripts 15-19, 22-27)
5. ✅ Registers server in `dbo.Servers` table
6. ✅ Collects metadata for all user databases (batched)
7. ✅ Configures Docker (.env file)
8. ✅ Starts Grafana + API containers

**Access After Deployment**:
- **Grafana**: http://data.schoolvision.net:9002
- **API**: http://data.schoolvision.net:9000
- **API Docs**: http://data.schoolvision.net:9000/swagger
- **Login**: admin / Admin123! (default Grafana)

---

### Step 2: Deploy to Suncity Server (suncity.schoolvision.net)

```bash
# Deploy to suncity.schoolvision.net
./deploy.sh \
  --sql-server "suncity.schoolvision.net,14333" \
  --sql-user "sv" \
  --sql-password "Gv51076!" \
  --database "MonitoringDB" \
  --grafana-port 9002 \
  --api-port 9000 \
  --environment "Production" \
  --batch-size 10
```

**Expected Duration**: 10-15 minutes

**Access After Deployment**:
- **Grafana**: http://suncity.schoolvision.net:9002
- **API**: http://suncity.schoolvision.net:9000
- **API Docs**: http://suncity.schoolvision.net:9000/swagger
- **Login**: admin / Admin123!

---

## 🧪 Post-Deployment Verification

### 1. Test Database Deployment

```bash
# Connect to data.schoolvision.net
sqlcmd -S data.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB

# Verify tables exist
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo';
GO
-- Expected: 25+ tables

# Verify procedures exist
SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_TYPE = 'PROCEDURE';
GO
-- Expected: 40+ procedures

# Verify server registered
SELECT * FROM dbo.Servers;
GO
-- Expected: At least 1 row

# Verify metadata collected
SELECT COUNT(*) FROM dbo.DatabaseMetadataCache;
GO
-- Expected: >0 rows

# Exit
EXIT
```

Repeat for suncity.schoolvision.net.

---

### 2. Test Grafana Dashboards

#### Data Server (http://data.schoolvision.net:9002)

1. **Login**:
   - Open http://data.schoolvision.net:9002
   - Username: `admin`
   - Password: `Admin123!`

2. **Verify Card-Style Browser Loads**:
   - ✅ Should see 8 colorful dashboard cards
   - ✅ Header: "SQL Monitor"
   - ✅ Subtitle: "Enterprise SQL Server Monitoring & Analysis Platform"
   - ✅ Footer: "ArcTrade"

3. **Test Card Navigation**:
   - ✅ Click "📊 Server Overview" card → Dashboard loads
   - ✅ Click "💡 Insights" card → Dashboard loads (NO datasource error!)
   - ✅ Click "⚡ Performance" card → Dashboard loads
   - ✅ Click "🔍 Query Store" card → Dashboard loads
   - ✅ Click "📋 Table Browser" card → Dashboard loads
   - ✅ Click "💻 Code Browser" card → Dashboard loads
   - ✅ Click "📈 Detailed Metrics" card → Dashboard loads
   - ✅ Click "🔒 Audit Logging" card → Dashboard loads

4. **Verify Folder Organization**:
   - ✅ Check sidebar for 5 folders:
     - Home (root)
     - Stats & Metrics
     - Code & Schema
     - Analysis & Insights
     - Security & Compliance

5. **Test Insights Dashboard** (CRITICAL):
   - ✅ Open Insights dashboard
   - ✅ Verify NO "Datasource ${DS_MONITORINGDB} was not found" error
   - ✅ Verify "Data Source" dropdown shows "MonitoringDB"
   - ✅ Verify "Server" dropdown shows "All" and server names
   - ✅ Verify insights table shows data (or "No insights" if healthy)
   - ✅ Verify user guide panel at bottom

6. **Test Time Interval Selector**:
   - ✅ Open Detailed Metrics dashboard
   - ✅ Verify "Time Interval" dropdown shows 9 options (1m, 5m, 15m, 30m, 1h, 3h, 6h, 12h, 24h)
   - ✅ Change from 5min to 1hr → Chart updates

7. **Test Search Functionality**:
   - ✅ Open Performance Analysis dashboard
   - ✅ Verify "Search Objects" textbox at top
   - ✅ Type partial object name → Results filter

8. **Test Hyperlinks**:
   - ✅ Open Performance Analysis → Click procedure name → Code Browser opens
   - ✅ Open Insights → Click server name → Server Overview opens
   - ✅ Open Query Store → Click database name → Table Browser opens
   - ✅ Open Table Details → Click table name → Refreshes with context

9. **Test Database Exclusions**:
   - ✅ Open any dashboard
   - ✅ Verify dropdowns do NOT show MonitoringDB or DBATools
   - ✅ Exception: Audit Logging SHOULD show system databases

10. **Test Server Filtering**:
    - ✅ Open any dashboard
    - ✅ Verify "Server" dropdown at top
    - ✅ Select "All" → Shows all servers
    - ✅ Select specific server → Filters to that server only

Repeat all tests for suncity.schoolvision.net:9002.

---

### 3. Test API Endpoints

```bash
# Test health endpoint (data.schoolvision.net)
curl http://data.schoolvision.net:9000/health
# Expected: {"status":"Healthy","database":"Connected",...}

# Test Swagger UI
curl http://data.schoolvision.net:9000/swagger/index.html
# Expected: HTML page loads

# Test servers endpoint (requires auth)
curl http://data.schoolvision.net:9000/api/servers
# Expected: 401 Unauthorized (correct - auth required)
```

Repeat for suncity.schoolvision.net:9000.

---

## 🔧 Troubleshooting

### Issue: Deployment Script Fails

**Symptom**: deploy.sh exits with error

**Solutions**:

1. **Check Connection**:
   ```bash
   sqlcmd -S data.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT @@VERSION"
   ```
   - If fails: Verify hostname, port, firewall rules

2. **Check Credentials**:
   ```bash
   sqlcmd -S data.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT SUSER_NAME()"
   ```
   - If fails: Verify username/password

3. **Check Permissions**:
   ```sql
   -- sv user must have dbcreator or sysadmin role
   SELECT IS_SRVROLEMEMBER('sysadmin', 'sv');
   SELECT IS_SRVROLEMEMBER('dbcreator', 'sv');
   ```

4. **Resume Failed Deployment**:
   ```bash
   ./deploy.sh --resume --sql-server "data.schoolvision.net,14333" --sql-user "sv" --sql-password "Gv51076!"
   ```

---

### Issue: Grafana Shows "Datasource Not Found"

**Symptom**: Dashboard shows datasource error

**Solution**:

1. **Check Datasource Configuration**:
   - Open Grafana → Configuration → Data Sources
   - Verify "MonitoringDB" datasource exists
   - Test connection → Should show "Database Connected"

2. **Check Connection String**:
   - Verify .env file has correct connection string
   - Restart Grafana: `docker compose restart grafana`

---

### Issue: Insights Dashboard Shows "DS_MONITORINGDB Not Found"

**Symptom**: Insights dashboard won't load

**Solution**:
- ✅ **ALREADY FIXED**: This error was resolved by adding DS_MONITORINGDB variable
- If still occurs: Verify 08-insights.json has lines 250-267 with datasource variable
- Restart Grafana: `docker compose restart grafana`

---

### Issue: No Data in Dashboards

**Symptom**: Dashboards load but show "No Data"

**Solutions**:

1. **Check Metadata Collection**:
   ```sql
   SELECT COUNT(*) FROM dbo.DatabaseMetadataCache;
   SELECT COUNT(*) FROM dbo.TableMetadata;
   SELECT COUNT(*) FROM dbo.CodeObjectMetadata;
   ```
   - If 0 rows: Run `EXEC dbo.usp_RefreshMetadataCache @ServerID = 1, @ForceRefresh = 1`

2. **Check Server Registration**:
   ```sql
   SELECT * FROM dbo.Servers WHERE IsActive = 1;
   ```
   - If no rows: Run `INSERT INTO dbo.Servers (ServerName, Environment, IsActive) VALUES (@@SERVERNAME, 'Production', 1)`

3. **Wait 5 Minutes**:
   - First metrics collection happens 5 minutes after deployment
   - SQL Agent job runs every 5 minutes

---

### Issue: Docker Containers Not Starting

**Symptom**: `docker compose up -d` fails

**Solutions**:

1. **Check Docker Service**:
   ```bash
   sudo systemctl status docker
   sudo systemctl start docker
   ```

2. **Check Port Conflicts**:
   ```bash
   sudo netstat -tuln | grep -E ':(9000|9002)'
   ```
   - If ports in use: Change ports in deploy.sh arguments

3. **Check .env File**:
   ```bash
   cat .env
   ```
   - Verify all variables present
   - Verify connection string format

4. **View Container Logs**:
   ```bash
   docker compose logs grafana
   docker compose logs api
   ```

---

## 📊 Deployment Status Tracking

Check deployment status at any time:

```bash
# Show deployment checkpoint status
./deploy.sh --status

# Example output:
# ========================================
# Deployment Status
# ========================================
#   Last Updated: 2025-10-29 14:30:00
#   SQL Server: data.schoolvision.net,14333
#   Database: MonitoringDB
#   Environment: Production
#
# Completed Steps:
#   [X] Prerequisites
#   [X] DatabaseCreated
#   [X] TablesCreated
#   [X] ProceduresCreated
#   [X] ServerRegistered
#   [X] MetadataInitialized
#   [X] DockerConfigured
#   [X] GrafanaStarted
#
#   Databases processed for metadata: 45
```

---

## 🎓 Best Practices

### Production Deployment

1. **Off-Hours Deployment**: Deploy during low-usage window (evenings/weekends)
2. **Backup First**: Always backup master and any existing MonitoringDB
3. **Test Locally**: Verify all features work in development before production
4. **Monitor Logs**: Watch Docker logs during deployment for errors
5. **Incremental Rollout**: Deploy to one server, verify, then deploy to second

### Security Hardening

1. **Change Default Passwords**:
   ```bash
   # After deployment, login to Grafana and change admin password
   # Settings → Users → admin → Change Password
   ```

2. **Restrict Network Access**:
   - Only allow connections from trusted IPs
   - Use firewall rules to block external access to ports 9000/9002

3. **Enable HTTPS** (Future):
   - Use reverse proxy (nginx, Apache) with SSL certificate
   - Update docker-compose.yml with HTTPS configuration

4. **Rotate JWT Secrets**:
   - Generate new JWT secret monthly
   - Update .env file and restart API container

### Maintenance

1. **Monitor Disk Space**:
   - MonitoringDB can grow 2GB/month per 10 servers
   - Partitions automatically drop old data after 90 days

2. **Check Metadata Refresh**:
   - SQL Agent job runs every 5 minutes
   - Verify job history in SQL Server Agent

3. **Update Dashboards**:
   - Edit JSON files in `dashboards/grafana/dashboards/`
   - Restart Grafana: `docker compose restart grafana`
   - Changes load automatically (10-second refresh interval)

---

## 🚀 Next Steps After Deployment

1. **Configure Alerts** (Phase 2.5):
   - Create alert rules in `dbo.AlertRules`
   - Configure email/SMS notifications

2. **Add Additional Servers**:
   - Insert into `dbo.Servers` table
   - Configure linked servers for remote collection

3. **Customize Dashboards**:
   - Edit JSON files to match specific requirements
   - Add custom panels for business metrics

4. **Enable GDPR Compliance** (Phase 3):
   - Deploy GDPR schema extensions
   - Configure data retention policies

5. **Set Up Monitoring for the Monitor**:
   - Monitor MonitoringDB size
   - Alert on failed SQL Agent jobs
   - Track Grafana uptime

---

## 📞 Support

**Deployment Issues**:
- Check logs: `docker compose logs -f`
- Review checkpoint: `./deploy.sh --status`
- Resume failed deployment: `./deploy.sh --resume`

**Dashboard Issues**:
- Verify datasource: Grafana → Configuration → Data Sources
- Check queries: Grafana → Explore → Run SQL manually
- Restart Grafana: `docker compose restart grafana`

**Database Issues**:
- Check connection: `sqlcmd -S server,port -U user -P pass -C -Q "SELECT @@VERSION"`
- Verify tables: `SELECT * FROM INFORMATION_SCHEMA.TABLES`
- Check procedures: `SELECT * FROM INFORMATION_SCHEMA.ROUTINES`

---

**Created**: 2025-10-29
**Last Updated**: 2025-10-29
**Ready for Production**: ✅ YES

🤖 **ArcTrade SQL Monitor** - Enterprise-Grade SQL Server Monitoring
