# SQL Server Monitor - Quick Reference Card

## 🚀 System Access

| Component | URL | Credentials |
|-----------|-----|-------------|
| **Grafana** | http://localhost:3000 | admin / Admin123! |
| **API** | http://localhost:5000 | No auth required |
| **Swagger** | http://localhost:5000/swagger | No auth required |
| **SQL Server** | sqltest.schoolvision.net,14333 | sv / Gv51076! |
| **Database** | MonitoringDB | - |

---

## 📊 Key Dashboards

**Performance Analysis** (Main Dashboard)
- **URL**: http://localhost:3000/d/performance-analysis
- **What it shows**: Top 100 slowest queries and most-run procedures
- **Features**: Sort, filter by database, color-coded thresholds
- **Refresh**: Every 30 seconds

---

## 🔗 SSMS Integration Endpoints

**Base URL**: `http://localhost:5000/api/code`

### 1. Download SQL File (Universal)
```
GET /api/code/{serverId}/{database}/{schema}/{object}/download

Example:
http://localhost:5000/api/code/1/MonitoringDB/dbo/usp_CollectCPUMetrics/download
```
**Returns**: `.sql` file with connection info in header

---

### 2. Download SSMS Launcher (Windows)
```
GET /api/code/{serverId}/{database}/{schema}/{object}/ssms-launcher

Example:
http://localhost:5000/api/code/1/MonitoringDB/dbo/usp_CollectCPUMetrics/ssms-launcher
```
**Returns**: `.bat` file that auto-launches SSMS

---

### 3. Get Code Preview (JSON)
```
GET /api/code/{serverId}/{database}/{schema}/{object}

Example:
http://localhost:5000/api/code/1/MonitoringDB/dbo/usp_CollectCPUMetrics
```
**Returns**: JSON with procedure definition

---

### 4. Get Connection Info
```
GET /api/code/connection-info/{serverId}/{database}

Example:
http://localhost:5000/api/code/connection-info/1/MonitoringDB
```
**Returns**: Connection strings and SSMS command line

---

## 🗄️ Key SQL Commands

### Check Collection Job Status
```sql
-- View job history
SELECT TOP 10
    j.name AS JobName,
    jh.run_date,
    jh.run_time,
    CASE jh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS Status
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory jh ON j.job_id = jh.job_id
WHERE j.name LIKE 'SQL Monitor%'
ORDER BY jh.instance_id DESC;
```

---

### Manual Metrics Collection
```sql
-- Collect all metrics now
EXEC dbo.usp_CollectAllMetrics @ServerID = 1;

-- Collect advanced metrics (blocking, index analysis, etc.)
EXEC dbo.usp_CollectAllAdvancedMetrics @ServerID = 1;
```

---

### Cache Object Code for SSMS Integration
```sql
-- Cache a procedure for download
EXEC dbo.usp_CacheObjectCode
    @ServerID = 1,
    @DatabaseName = 'YourDatabase',
    @SchemaName = 'dbo',
    @ObjectName = 'usp_YourProcedure';

-- Retrieve cached code
EXEC dbo.usp_GetObjectCode
    @ServerID = 1,
    @DatabaseName = 'YourDatabase',
    @SchemaName = 'dbo',
    @ObjectName = 'usp_YourProcedure';
```

---

### View Latest Metrics
```sql
-- Top 10 slowest queries (last 24 hours)
SELECT TOP 10
    DatabaseName,
    LEFT(QueryText, 100) AS QueryPreview,
    AvgDurationMs,
    ExecutionCount,
    AvgLogicalReads,
    CollectionTime
FROM dbo.QueryMetrics
WHERE ServerID = 1
  AND CollectionTime > DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY AvgDurationMs DESC;

-- Top 10 most frequently run procedures
SELECT TOP 10
    DatabaseName,
    SchemaName + '.' + ProcedureName AS FullName,
    ExecutionCount,
    AvgDurationMs,
    AvgCPUMs,
    CollectionTime
FROM dbo.ProcedureMetrics
WHERE ServerID = 1
  AND CollectionTime > DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY ExecutionCount DESC;

-- Index analysis recommendations
SELECT TOP 20
    DatabaseName,
    SchemaName + '.' + TableName AS FullTableName,
    AnalysisType,
    FragmentationPercent,
    LEFT(Recommendation, 200) AS RecommendationPreview
FROM dbo.IndexAnalysis
WHERE ServerID = 1
ORDER BY CollectionTime DESC;
```

---

## 🐳 Docker Commands

```bash
# Start containers
docker-compose up -d

# Stop containers
docker-compose down

# Rebuild and restart API
docker-compose up --build -d api

# View logs
docker-compose logs -f api
docker-compose logs -f grafana

# Check container status
docker-compose ps
```

---

## 🎨 Grafana Tips

### Filter Dashboard by Database
1. Use the **Database** dropdown at the top of the dashboard
2. Select "All" or a specific database
3. All panels filter automatically

### Sort Table Columns
- Click any column header to sort
- Click again to reverse sort order

### Filter Table Rows
- Click filter icon next to column header
- Type search text
- Click "Apply"

### Export Data
- Panel menu (three dots) → Inspect → Data → Download CSV

---

## 🔧 Troubleshooting

### Dashboard Shows "No Data"
**Solution**:
```sql
-- Check if metrics are being collected
SELECT COUNT(*) FROM dbo.PerformanceMetrics WHERE ServerID = 1;

-- Manually collect metrics
EXEC dbo.usp_CollectAllMetrics @ServerID = 1;
```

---

### API Not Responding
**Solution**:
```bash
# Check if API container is running
docker-compose ps

# Restart API
docker-compose restart api

# View API logs for errors
docker-compose logs api
```

---

### "Object not found" when downloading SQL
**Solution**:
```sql
-- Cache the object first
EXEC dbo.usp_CacheObjectCode
    @ServerID = 1,
    @DatabaseName = 'DatabaseName',
    @SchemaName = 'dbo',
    @ObjectName = 'ProcedureName';
```

---

## 📁 Important Files

| File | Purpose |
|------|---------|
| `DEPLOYMENT-STATUS.md` | Overall system status |
| `SSMS-INTEGRATION-GUIDE.md` | Complete SSMS integration reference |
| `GRAFANA-SSMS-LINKS-SETUP.md` | How to add SSMS links to Grafana |
| `DASHBOARD-QUICKSTART.md` | How to use dashboards |
| `docker-compose.yml` | Container configuration |
| `.env` | Environment variables (connection strings) |

---

## 🎯 Common Workflows

### Workflow 1: Investigate Slow Query
1. Open http://localhost:3000/d/performance-analysis
2. Look at "Long-Running Queries" table
3. Click "Download SQL" next to slow query
4. Open file in SSMS
5. Review query and execution plan
6. Add missing index or optimize query

---

### Workflow 2: Find High-Frequency Procedures
1. Open Performance Analysis dashboard
2. Look at "Stored Procedures" table
3. Sort by "ExecutionCount" (click column header)
4. Red cells = very frequently run (> 1000 times)
5. Click "Download SQL" to review code
6. Consider caching results if appropriate

---

### Workflow 3: Database Performance Deep Dive
1. Select specific database from dropdown
2. Review query duration trends
3. Check procedure execution patterns
4. Look for spikes or degradation
5. Download SQL for problematic objects
6. Investigate in SSMS

---

**Quick Help**: See `DEPLOYMENT-STATUS.md` for full system status and next steps.
