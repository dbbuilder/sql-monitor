# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SQL Server Linux 2022 Standard Edition monitoring bootstrap system. Creates a lightweight performance monitoring infrastructure using DMVs (Dynamic Management Views) to capture server health, database statistics, active workload, and error logs every 5 minutes via SQL Server Agent job.

**Key Design Goals:**
- Minimal performance overhead (lightweight DMV sampling only)
- Linux-compatible (no Windows-specific features)
- SQL Server Standard Edition compatible (no Enterprise-only DMVs)
- Self-contained within DBATools database

## Installation Order

Execute scripts in strict numerical order:

1. **01_create_DBATools_and_tables.sql** - Database and schema creation
2. **02_create_DBA_LogEntry_Insert.sql** - Logging infrastructure
3. **03_create_DBA_CollectPerformanceSnapshot.sql** - Main collector procedure
4. **04_create_agent_job_linux.sql** - Automated job scheduling

## Architecture

### Database Schema (DBATools)

**Core Tables:**
- `LogEntry` - Error and diagnostic logging with procedure context tracking
- `PerfSnapshotRun` - Parent table for each snapshot execution (server-level metrics)
- `PerfSnapshotDB` - Database-level statistics (size, recovery model, log reuse wait)
- `PerfSnapshotWorkload` - Active session/request details at snapshot time
- `PerfSnapshotErrorLog` - Recent SQL Server error log entries (top 20)

**Relationships:**
- All Perf* tables foreign key to `PerfSnapshotRun.PerfSnapshotRunID`
- Single snapshot creates 1 run record + N database records + M workload records + 20 error log records

### Main Collection Procedure

`DBA_CollectPerformanceSnapshot` performs sectioned data collection with error isolation:

**Sections (in order):**
1. **WAITS** - Calculates CPU signal wait percentage and identifies top wait type
2. **SESSION_REQUEST_COUNTS** - Active sessions, requests, blocking sessions
3. **HEALTH_COUNTS** - Recent deadlocks and memory grant warnings (from system_health XEvent)
4. **INSERT_RUN** - Creates parent PerfSnapshotRun record
5. **DB_STATS** - Per-database size, file counts, log reuse status
6. **WORKLOAD** - Active requests with statement text and blocking chains
7. **ERRORLOG** - Last 20 entries from SQL Server error log via xp_readerrorlog

**Error Handling:**
- TRY/CATCH wraps entire procedure
- `@Section` variable tracks progress for error context
- Failures logged to `LogEntry` table with section name and full error details

## Testing & Verification

### Manual Test Execution
```sql
-- Enable debug mode for detailed logging
EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1

-- Verify snapshot run created
SELECT TOP 10 *
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

-- Check debug/error logs
SELECT TOP 20 *
FROM DBATools.dbo.LogEntry
ORDER BY LogEntryID DESC

-- View database statistics captured
SELECT *
FROM DBATools.dbo.PerfSnapshotDB
WHERE PerfSnapshotRunID = <latest_run_id>

-- View active workload captured
SELECT *
FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID = <latest_run_id>
```

### Agent Job Verification
```sql
-- Check job exists and is enabled
SELECT
    j.name AS JobName,
    j.enabled,
    js.last_run_date,
    js.last_run_time,
    js.last_run_outcome
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
WHERE j.name = 'DBA Collect Perf Snapshot'

-- View job history
EXEC msdb.dbo.sp_help_jobhistory
    @job_name = 'DBA Collect Perf Snapshot',
    @mode = 'FULL'
```

## Linux Prerequisites

SQL Server Agent must be installed and running:
```bash
sudo systemctl enable mssql-server-agent
sudo systemctl start mssql-server-agent
sudo systemctl status mssql-server-agent
```

## Performance Impact

**Designed for minimal overhead:**
- DMV queries only (no table scans, index operations, or DBCC commands)
- No WAITFOR delays or blocking operations
- Typical execution time: < 1 second per snapshot
- Runs every 5 minutes by default (configurable via schedule)

**If performance issues occur:**
- Increase schedule interval (e.g., 15 minutes instead of 5)
- Temporarily disable job: `EXEC msdb.dbo.sp_update_job @job_name='DBA Collect Perf Snapshot', @enabled=0`

## Data Retention

**Retention Strategy:**
- No automatic purge mechanism included
- `PerfSnapshotWorkload` grows fastest (multiple rows per snapshot)
- **Recommended:** Create purge job to delete rows older than 14-30 days

**Example Purge Query:**
```sql
DELETE FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID
    FROM DBATools.dbo.PerfSnapshotRun
    WHERE SnapshotUTC < DATEADD(DAY, -14, SYSUTCDATETIME())
)

-- Then cascade to other tables or delete PerfSnapshotRun last
```

## Key Metrics Captured

**Server-Level (PerfSnapshotRun):**
- CPU signal wait percentage (CPU pressure indicator)
- Top wait type and wait time per second
- Active session/request counts
- Blocking session count
- Recent deadlock count (last 10 minutes from system_health)
- Memory grant warnings (spills, last 10 minutes)

**Database-Level (PerfSnapshotDB):**
- Database state, recovery model, read-only status
- Total data file size (MB), log file size (MB)
- Log reuse wait description (identifies log growth issues)
- File count, compatibility level

**Workload-Level (PerfSnapshotWorkload):**
- Session ID, login name, host name
- Current database, status, command
- Wait type and wait time
- Blocking session ID (identifies blocking chains)
- CPU time, elapsed time, logical reads, writes
- Statement text and resolved object name

## Connection Strings

When connecting from external tools, use this format (from global CLAUDE.md):
```
Server=172.31.208.1,14333;Database=DBATools;User Id=sv;Password=YourPassword;TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30
```

**WSL Environment:** Use WSL host IP (172.31.208.1), not localhost
**Port Syntax:** Use comma separator (e.g., `server,port`)
**Microsoft.Data.SqlClient 5.2+:** Requires "Connection Timeout" (with space), not "ConnectTimeout"
