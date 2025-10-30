# SSMS Integration Guide

## Overview

The SQL Server Monitor provides **three methods** to open problematic database objects directly in SQL Server Management Studio (SSMS) with the correct server/database context.

---

## API Endpoints

### 1. Get Object Code (Preview)

**Endpoint**: `GET /api/code/{serverId}/{database}/{schema}/{objectName}`

**Purpose**: Retrieve object code for inline preview in Grafana or other UI

**Response**:
```json
{
  "codeID": 1,
  "serverID": 1,
  "databaseName": "ALPHA_SVDB_POS",
  "schemaName": "dbo",
  "objectName": "usp_GetCustomerOrders",
  "objectType": "Procedure",
  "definition": "CREATE PROCEDURE dbo.usp_GetCustomerOrders...",
  "lastUpdated": "2025-10-25T10:30:00Z"
}
```

**Example**:
```bash
curl http://localhost:5000/api/code/1/ALPHA_SVDB_POS/dbo/usp_GetCustomerOrders
```

---

### 2. Download SQL File (Recommended)

**Endpoint**: `GET /api/code/{serverId}/{database}/{schema}/{objectName}/download`

**Purpose**: Download a `.sql` file with embedded connection info that opens directly in SSMS

**File Format**:
```sql
/*
==============================================================================
  Object: dbo.usp_GetCustomerOrders
  Database: ALPHA_SVDB_POS
  Server: sqltest.schoolvision.net,14333
  Type: Procedure
  Retrieved: 2025-10-25 10:30:00 UTC
==============================================================================

CONNECTION INFO:
  Server: sqltest.schoolvision.net,14333
  Database: ALPHA_SVDB_POS
  Authentication: SQL Server Authentication or Windows Authentication

INSTRUCTIONS:
  1. Open this file in SQL Server Management Studio (SSMS)
  2. Connect to server: sqltest.schoolvision.net,14333
  3. Switch to database: ALPHA_SVDB_POS
  4. Review and execute as needed
==============================================================================
*/

USE [ALPHA_SVDB_POS];
GO

CREATE PROCEDURE dbo.usp_GetCustomerOrders
...
```

**Workflow**:
1. User clicks "Download SQL" link in Grafana
2. File downloads as `dbo.usp_GetCustomerOrders.sql`
3. User double-clicks file → SSMS opens automatically
4. User connects to the server specified in the header comments
5. Object code is ready to view/edit

**Pros**:
- ✅ Works immediately, no setup required
- ✅ Connection info embedded in comments
- ✅ File can be saved for later or shared with team
- ✅ Cross-platform (works on any OS with SSMS)

**Cons**:
- Requires two clicks (download, then open)
- User must manually connect to correct server/database

---

### 3. Download SSMS Launcher (Windows Batch File)

**Endpoint**: `GET /api/code/{serverId}/{database}/{schema}/{objectName}/ssms-launcher`

**Purpose**: Download a `.bat` file that automatically launches SSMS with the correct connection

**File Format** (`Open-dbo.usp_GetCustomerOrders-in-SSMS.bat`):
```batch
@echo off
REM ===================================================================
REM   SSMS Launcher for dbo.usp_GetCustomerOrders
REM   Server: sqltest.schoolvision.net,14333
REM   Database: ALPHA_SVDB_POS
REM ===================================================================

echo Creating SQL file...
echo USE [ALPHA_SVDB_POS]; > %TEMP%\dbo.usp_GetCustomerOrders.sql
echo GO >> %TEMP%\dbo.usp_GetCustomerOrders.sql
echo CREATE PROCEDURE dbo.usp_GetCustomerOrders >> %TEMP%\dbo.usp_GetCustomerOrders.sql
...

echo Launching SSMS...
start "" "C:\Program Files (x86)\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe" -S "sqltest.schoolvision.net,14333" -d "ALPHA_SVDB_POS" %TEMP%\dbo.usp_GetCustomerOrders.sql

pause
```

**Workflow**:
1. User clicks "Open in SSMS" link in Grafana
2. Batch file downloads
3. User double-clicks `.bat` file
4. SSMS launches automatically with:
   - Server: `sqltest.schoolvision.net,14333`
   - Database: `ALPHA_SVDB_POS`
   - Object code loaded in a new query window

**SSMS Command-Line Parameters**:
- `-S "server"` - Connect to specific server
- `-d "database"` - Switch to specific database
- `filepath` - Open SQL file in query window

**Pros**:
- ✅ Fully automated - one click opens SSMS with correct context
- ✅ No manual connection required
- ✅ Ideal for power users

**Cons**:
- ❌ Windows-only
- ❌ Requires SSMS installed in default location
- ❌ May need path adjustment for SSMS 18 vs 19

**Supported SSMS Paths**:
```batch
# SSMS 19 (default)
C:\Program Files (x86)\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe

# SSMS 18 (fallback)
C:\Program Files (x86)\Microsoft SQL Server Management Studio 18\Common7\IDE\Ssms.exe
```

---

### 4. Get Connection Info

**Endpoint**: `GET /api/code/connection-info/{serverId}/{database}`

**Purpose**: Get connection strings and command-line examples for manual use

**Response**:
```json
{
  "server": "sqltest.schoolvision.net,14333",
  "database": "ALPHA_SVDB_POS",
  "ssmsCommandLine": "Ssms.exe -S \"sqltest.schoolvision.net,14333\" -d \"ALPHA_SVDB_POS\"",
  "sqlcmdCommandLine": "sqlcmd -S \"sqltest.schoolvision.net,14333\" -d \"ALPHA_SVDB_POS\" -E",
  "connectionString": "Server=sqltest.schoolvision.net,14333;Database=ALPHA_SVDB_POS;Integrated Security=true;"
}
```

---

## Integration with Grafana Dashboards

### Option 1: Data Links (Recommended)

**Configure in Grafana Panel**:

1. Edit panel (e.g., "Long-Running Queries" table)
2. Field → Override → Add field override
3. Match field: `ProcedureName` or `QueryPreview`
4. Add override: **Data links**
5. Add data link:
   - **Title**: "Download SQL"
   - **URL**: `http://localhost:5000/api/code/1/${__data.fields.DatabaseName}/${__data.fields.SchemaName}/${__data.fields.ProcedureName}/download`
   - **Open in new tab**: Yes

6. Add second data link:
   - **Title**: "Open in SSMS"
   - **URL**: `http://localhost:5000/api/code/1/${__data.fields.DatabaseName}/${__data.fields.SchemaName}/${__data.fields.ProcedureName}/ssms-launcher`
   - **Open in new tab**: Yes

**Result**: Clickable links appear next to procedure/object names

---

### Option 2: Custom Panel with Buttons

**HTML Panel** (using Grafana's Text panel with HTML):

```html
<script>
function downloadSQL(database, schema, object) {
  window.open('http://localhost:5000/api/code/1/' + database + '/' + schema + '/' + object + '/download', '_blank');
}

function openInSSMS(database, schema, object) {
  window.open('http://localhost:5000/api/code/1/' + database + '/' + schema + '/' + object + '/ssms-launcher', '_blank');
}
</script>

<button onclick="downloadSQL('ALPHA_SVDB_POS', 'dbo', 'usp_GetCustomerOrders')">
  Download SQL
</button>
<button onclick="openInSSMS('ALPHA_SVDB_POS', 'dbo', 'usp_GetCustomerOrders')">
  Open in SSMS
</button>
```

---

### Option 3: URL Parameters in Table

**Grafana Transformation**:

1. Add transformation: **Add field from calculation**
2. Mode: **Binary operation**
3. Operation: **Concatenate**
4. Field 1: `DatabaseName`
5. Field 2: `SchemaName`
6. Result: `DownloadLink`
7. Template: `http://localhost:5000/api/code/1/${DatabaseName}/${SchemaName}/${ProcedureName}/download`

**Then**: Configure column as clickable link

---

## Usage Examples

### Example 1: Slow Stored Procedure Investigation

**Scenario**: Grafana dashboard shows `dbo.usp_ProcessOrders` is running slow (avg 5000ms)

**Workflow**:
1. User clicks "Download SQL" next to the procedure name
2. File `dbo.usp_ProcessOrders.sql` downloads
3. User opens file in SSMS
4. Header shows: Server = sqltest.schoolvision.net,14333, Database = ALPHA_SVDB_POS
5. User connects to that server/database
6. User reviews procedure code looking for:
   - Missing WHERE clauses
   - Table scans
   - Inefficient joins
7. User optimizes and re-deploys

---

### Example 2: Long-Running Query Analysis

**Scenario**: Grafana shows a query with 10 million logical reads

**Workflow**:
1. User clicks "Download SQL" in the "Long-Running Queries" table
2. File downloads with the problematic query
3. User opens in SSMS
4. User runs `SET STATISTICS IO ON; SET STATISTICS TIME ON;`
5. User executes the query
6. User analyzes execution plan
7. User adds missing index based on plan recommendations

---

### Example 3: Automated SSMS Launch (Power Users)

**Scenario**: DBA wants instant access to problematic code

**Workflow**:
1. User clicks "Open in SSMS" (batch file link)
2. `.bat` file downloads
3. User double-clicks the batch file
4. SSMS opens automatically with:
   - Connection to correct server
   - Database context set
   - Object code loaded in query window
5. User immediately starts troubleshooting

---

## Testing the Integration

### Test 1: Code Preview API

```bash
# Get object code
curl http://localhost:5000/api/code/1/ALPHA_SVDB_POS/dbo/usp_CollectCPUMetrics

# Expected: JSON response with procedure definition
```

### Test 2: SQL File Download

```bash
# Download SQL file
curl -O http://localhost:5000/api/code/1/ALPHA_SVDB_POS/dbo/usp_CollectCPUMetrics/download

# Expected: dbo.usp_CollectCPUMetrics.sql file downloaded
```

### Test 3: SSMS Launcher Download

```bash
# Download batch file
curl -O http://localhost:5000/api/code/1/ALPHA_SVDB_POS/dbo/usp_CollectCPUMetrics/ssms-launcher

# Expected: Open-dbo.usp_CollectCPUMetrics-in-SSMS.bat file downloaded
```

### Test 4: Connection Info

```bash
# Get connection details
curl http://localhost:5000/api/code/connection-info/1/ALPHA_SVDB_POS

# Expected: JSON with connection string and command-line examples
```

---

## Troubleshooting

### Issue: "Object not found"

**Cause**: Object code not cached yet

**Solution**: Object code is cached on first retrieval. The `usp_GetObjectCode` stored procedure will automatically cache it. If it still fails, the object may not exist.

**Verify**:
```sql
-- Check if object exists
SELECT * FROM ALPHA_SVDB_POS.sys.objects
WHERE name = 'usp_CollectCPUMetrics' AND schema_id = SCHEMA_ID('dbo');

-- Manually cache object
EXEC dbo.usp_CacheObjectCode
    @ServerID = 1,
    @DatabaseName = 'ALPHA_SVDB_POS',
    @SchemaName = 'dbo',
    @ObjectName = 'usp_CollectCPUMetrics';
```

---

### Issue: SSMS Launcher doesn't work

**Cause**: SSMS not installed in default location

**Solution**: Edit the `.bat` file and update the SSMS path:

```batch
REM Find your SSMS installation:
REM - Check: C:\Program Files (x86)\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe
REM - Check: C:\Program Files (x86)\Microsoft SQL Server Management Studio 18\Common7\IDE\Ssms.exe
REM - Check: C:\Program Files\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe

REM Update the path in the batch file accordingly
start "" "YOUR_SSMS_PATH_HERE" -S "server" -d "database" %TEMP%\file.sql
```

---

### Issue: API returns 500 error

**Cause**: Database connection failure or stored procedure error

**Solution**: Check API logs and verify stored procedure exists:

```sql
-- Verify stored procedure exists
SELECT * FROM MonitoringDB.sys.procedures
WHERE name = 'usp_GetObjectCode';

-- Test stored procedure manually
EXEC dbo.usp_GetObjectCode
    @ServerID = 1,
    @DatabaseName = 'ALPHA_SVDB_POS',
    @SchemaName = 'dbo',
    @ObjectName = 'usp_CollectCPUMetrics';
```

---

## Architecture Decisions

### Why SQL File Download is Primary Method

1. **Universal Compatibility**: Works on Windows, Linux (with Wine), macOS
2. **No Client-Side Setup**: No browser extensions, no protocol handlers
3. **Shareability**: Files can be emailed, stored in tickets, shared via Teams/Slack
4. **Audit Trail**: Downloaded files serve as point-in-time snapshots
5. **Connection Documentation**: Header comments document which server/database had the issue

### Why Custom URL Protocol (`ssms://`) Was Rejected

1. **No Native Support**: SSMS doesn't register a custom URL protocol by default
2. **Client-Side Configuration**: Would require installing a protocol handler on every workstation
3. **Security Concerns**: Browser prompts for launching external applications
4. **Maintenance Burden**: Protocol handlers break across SSMS versions

### Why Batch File is Secondary Method

1. **Windows-Only**: ~80% of DBAs use Windows, but not 100%
2. **Path Dependency**: SSMS installation path varies (18 vs 19, x86 vs x64, custom installs)
3. **Security Warnings**: Windows Defender may flag downloaded `.bat` files
4. **Power User Feature**: Advanced users who want one-click automation will configure it

---

## Future Enhancements

### Planned Improvements

1. **Linux Support**: Generate shell scripts (`.sh`) for SSMS on Linux
2. **Azure Data Studio Integration**: Generate `.sql` files optimized for Azure Data Studio
3. **Code Diff**: Compare current object definition vs. cached version (detect changes)
4. **Execution Plan Download**: Include actual execution plans for slow queries
5. **Grafana Plugin**: Custom Grafana panel with embedded code viewer (no download required)

---

## Summary

**Recommended Workflow**:

1. **Preview** → Use `GET /api/code/{serverId}/{database}/{schema}/{object}` for inline code display in Grafana
2. **Download SQL** → Use `/download` endpoint for universal SSMS access (works everywhere)
3. **Power Users** → Use `/ssms-launcher` for one-click automated SSMS launch (Windows only)

**Next Step**: Integrate these endpoints into Grafana dashboards as data links on object/procedure names.
