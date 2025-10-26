# SSMS Integration - Implementation Complete

## Summary

**Three SSMS integration methods** have been implemented, allowing users to view and open problematic database objects directly from Grafana dashboards.

---

## What Was Built

### 1. API Endpoints (CodeController)

**File**: `api/Controllers/CodeController.cs`

**Endpoints Created**:

| Endpoint | Purpose | HTTP Method |
|----------|---------|-------------|
| `/api/code/{serverId}/{database}/{schema}/{object}` | Get object code (JSON) | GET |
| `/api/code/{serverId}/{database}/{schema}/{object}/download` | Download SQL file | GET |
| `/api/code/{serverId}/{database}/{schema}/{object}/ssms-launcher` | Download SSMS launcher (.bat) | GET |
| `/api/code/connection-info/{serverId}/{database}` | Get connection strings | GET |

---

### 2. Service Layer Updates

**Files Modified**:
- `api/Services/ISqlService.cs` - Added interface methods
- `api/Services/SqlService.cs` - Implemented:
  - `GetServerByIdAsync()` - Retrieves server details for connection info
  - `GetObjectCodeAsync()` - Calls `usp_GetObjectCode` stored procedure

**Model Created**:
- `api/Models/ObjectCode.cs` - Represents database object definitions

---

### 3. Integration Methods

#### Method 1: SQL File Download (Universal - **RECOMMENDED**)

**How It Works**:
1. User clicks link in Grafana
2. Downloads `.sql` file with embedded connection info
3. User opens file in SSMS
4. Connection details are in header comments

**Example File** (`dbo.usp_ProcessOrders.sql`):
```sql
/*
==============================================================================
  Object: dbo.usp_ProcessOrders
  Database: ALPHA_SVDB_POS
  Server: sqltest.schoolvision.net,14333
  Type: Procedure
  Retrieved: 2025-10-25 15:30:00 UTC
==============================================================================

CONNECTION INFO:
  Server: sqltest.schoolvision.net,14333
  Database: ALPHA_SVDB_POS

INSTRUCTIONS:
  1. Open this file in SQL Server Management Studio (SSMS)
  2. Connect to server: sqltest.schoolvision.net,14333
  3. Switch to database: ALPHA_SVDB_POS
  4. Review and execute as needed
==============================================================================
*/

USE [ALPHA_SVDB_POS];
GO

CREATE PROCEDURE dbo.usp_ProcessOrders
AS
BEGIN
    ...
END
```

**Pros**:
- ✅ Works on Windows, Linux, macOS
- ✅ No setup required
- ✅ Files can be saved, shared, archived
- ✅ Connection info documented in comments

---

#### Method 2: SSMS Launcher (Windows Batch File)

**How It Works**:
1. User clicks link in Grafana
2. Downloads `.bat` file
3. User double-clicks batch file
4. SSMS opens automatically with correct server/database/code

**Example** (`Open-dbo.usp_ProcessOrders-in-SSMS.bat`):
```batch
@echo off
echo Creating SQL file...
echo USE [ALPHA_SVDB_POS]; > %TEMP%\dbo.usp_ProcessOrders.sql
echo GO >> %TEMP%\dbo.usp_ProcessOrders.sql
echo CREATE PROCEDURE... >> %TEMP%\dbo.usp_ProcessOrders.sql

echo Launching SSMS...
start "" "C:\Program Files (x86)\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe" -S "sqltest.schoolvision.net,14333" -d "ALPHA_SVDB_POS" %TEMP%\dbo.usp_ProcessOrders.sql
```

**Pros**:
- ✅ Fully automated - one click
- ✅ No manual connection required
- ✅ Perfect for power users

**Cons**:
- ❌ Windows-only
- ❌ Requires SSMS in default location

---

#### Method 3: Code Preview API (JSON)

**How It Works**:
- API returns object code as JSON
- Can be displayed inline in Grafana or other UIs

**Response**:
```json
{
  "codeID": 1,
  "serverID": 1,
  "databaseName": "ALPHA_SVDB_POS",
  "schemaName": "dbo",
  "objectName": "usp_ProcessOrders",
  "objectType": "Procedure",
  "definition": "CREATE PROCEDURE dbo.usp_ProcessOrders...",
  "lastUpdated": "2025-10-25T15:30:00Z"
}
```

**Use Case**: Inline code preview without leaving Grafana

---

## Database Infrastructure (Already Exists)

**Tables** (created in `database/10-create-extended-events-tables.sql`):
- `dbo.ObjectCode` - Caches object definitions for fast retrieval

**Stored Procedures** (created in `database/11-create-extended-events-procedures.sql`):
- `dbo.usp_CacheObjectCode` - Caches object definition
- `dbo.usp_GetObjectCode` - Retrieves code (caches if not found)

---

## How to Use

### From Grafana Dashboard

**Option A: Add Data Links to Table Columns**

1. Edit panel (e.g., "Long-Running Queries")
2. Field → Overrides → Add override
3. Match field: `ProcedureName`
4. Add override: **Data links**
5. Add link:
   - Title: "Download SQL"
   - URL: `http://localhost:5000/api/code/1/${__data.fields.DatabaseName}/${__data.fields.SchemaName}/${__data.fields.ProcedureName}/download`
6. Add second link:
   - Title: "Open in SSMS"
   - URL: `http://localhost:5000/api/code/1/${__data.fields.DatabaseName}/${__data.fields.SchemaName}/${__data.fields.ProcedureName}/ssms-launcher`

**Option B: Direct URLs**

```
# SQL file download
http://localhost:5000/api/code/1/ALPHA_SVDB_POS/dbo/usp_ProcessOrders/download

# SSMS launcher
http://localhost:5000/api/code/1/ALPHA_SVDB_POS/dbo/usp_ProcessOrders/ssms-launcher

# Code preview (JSON)
http://localhost:5000/api/code/1/ALPHA_SVDB_POS/dbo/usp_ProcessOrders
```

---

## Testing the Implementation

### Test 1: Code Preview

```bash
curl http://localhost:5000/api/code/1/MonitoringDB/dbo/usp_CollectCPUMetrics
```

**Expected**: JSON with procedure definition

---

### Test 2: SQL File Download

```bash
curl -O http://localhost:5000/api/code/1/MonitoringDB/dbo/usp_CollectCPUMetrics/download
```

**Expected**: File `dbo.usp_CollectCPUMetrics.sql` downloaded

---

### Test 3: SSMS Launcher

```bash
curl -O http://localhost:5000/api/code/1/MonitoringDB/dbo/usp_CollectCPUMetrics/ssms-launcher
```

**Expected**: File `Open-dbo.usp_CollectCPUMetrics-in-SSMS.bat` downloaded

---

### Test 4: Connection Info

```bash
curl http://localhost:5000/api/code/connection-info/1/MonitoringDB
```

**Expected**:
```json
{
  "server": "sqltest.schoolvision.net,14333",
  "database": "MonitoringDB",
  "ssmsCommandLine": "Ssms.exe -S \"sqltest.schoolvision.net,14333\" -d \"MonitoringDB\"",
  "sqlcmdCommandLine": "sqlcmd -S \"sqltest.schoolvision.net,14333\" -d \"MonitoringDB\" -E",
  "connectionString": "Server=sqltest.schoolvision.net,14333;Database=MonitoringDB;Integrated Security=true;"
}
```

---

## Files Created/Modified

### New Files

| File | Purpose |
|------|---------|
| `api/Controllers/CodeController.cs` | SSMS integration API endpoints |
| `api/Models/ObjectCode.cs` | Object code model |
| `SSMS-INTEGRATION-GUIDE.md` | Complete implementation guide |
| `SSMS-INTEGRATION-COMPLETE.md` | This summary document |

### Modified Files

| File | Changes |
|------|---------|
| `api/Services/ISqlService.cs` | Added `GetServerByIdAsync()`, `GetObjectCodeAsync()` |
| `api/Services/SqlService.cs` | Implemented new interface methods |

---

## Architecture Decisions

### Why SQL File Download is Primary

1. **Universal** - Works on any platform with SSMS
2. **No Setup** - No client-side configuration
3. **Shareable** - Files can be emailed or archived
4. **Documented** - Connection info embedded in comments

### Why Batch File is Secondary

1. **Windows-Only** - Not cross-platform
2. **Path Dependency** - SSMS installation path varies
3. **Security** - May trigger browser/OS warnings
4. **Power User Feature** - For advanced users who configure it

---

## Next Steps

1. **Test API Endpoints** - Verify all endpoints work
2. **Update Grafana Dashboards** - Add data links to procedure/query columns
3. **User Training** - Document workflow for DBAs
4. **Optional**: Create Grafana plugin for embedded code viewer (no download required)

---

## Benefits

### For DBAs

- ✅ **Instant Access** - One click from dashboard to SSMS
- ✅ **Correct Context** - Automatically connects to right server/database
- ✅ **Time Savings** - No manual searching for problematic code
- ✅ **Audit Trail** - Downloaded files document what was investigated

### For Developers

- ✅ **Self-Service** - Can investigate slow queries without DBA intervention
- ✅ **Learning** - See actual query text that caused performance issues
- ✅ **Optimization** - Immediate access to code for tuning

---

## Example Workflow

**Scenario**: Grafana shows `dbo.usp_ProcessOrders` running slow (avg 5000ms)

1. User clicks "Download SQL" next to procedure name
2. File downloads: `dbo.usp_ProcessOrders.sql`
3. User opens in SSMS
4. Header shows: `Server: sqltest.schoolvision.net,14333`, `Database: ALPHA_SVDB_POS`
5. User connects and reviews code
6. User identifies missing WHERE clause causing table scan
7. User adds index, re-tests
8. Performance improves to 50ms (100x faster)

---

## Status

**✅ IMPLEMENTATION COMPLETE**

- API endpoints built and compiled successfully
- Database stored procedures already deployed
- Documentation complete
- Ready for testing and Grafana integration

**Next**: Deploy API via Docker Compose and integrate with Grafana dashboards.
