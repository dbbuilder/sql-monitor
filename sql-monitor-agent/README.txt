SQL Server Linux 2022 Standard Monitoring Bootstrap
---------------------------------------------------

Run order:

1. 01_create_DBATools_and_tables.sql
   - Creates DBATools database if missing
   - Creates LogEntry, PerfSnapshotRun, PerfSnapshotDB, PerfSnapshotWorkload, PerfSnapshotErrorLog tables

2. 02_create_DBA_LogEntry_Insert.sql
   - Creates logging proc

3. 03_create_DBA_CollectPerformanceSnapshot.sql
   - Creates the main collector proc
   - You can test manually with:
     EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1

   After test:
     SELECT TOP 10 * FROM DBATools.dbo.PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC
     SELECT TOP 20 * FROM DBATools.dbo.LogEntry ORDER BY LogEntryID DESC

4. 04_create_agent_job_linux.sql
   - Creates a SQL Server Agent job "DBA Collect Perf Snapshot"
   - Runs every 5 minutes

Prereqs on Linux host:
- SQL Server Agent service installed and running
  sudo systemctl enable mssql-server-agent
  sudo systemctl start mssql-server-agent

Performance impact:
- Each run does lightweight DMV sampling and inserts rows.
- It does NOT:
  * scan entire user tables
  * rebuild indexes
  * run DBCC CHECKDB
  * force WAITFOR DELAY loops
- Overhead is very small for normal workloads.

If you see performance issues:
- Increase the schedule interval (e.g. every 15 minutes instead of 5)
- Temporarily disable the job

Retention:
- Consider a purge job later to delete old PerfSnapshotWorkload rows
  older than 14 days.
