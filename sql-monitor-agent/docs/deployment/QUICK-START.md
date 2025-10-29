# Quick Start Guide

## Prerequisites

- SQL Server 2019+ (Linux or Windows)
- SQL Server Agent enabled and running
- sysadmin or equivalent permissions
- sqlcmd (Linux/WSL) or SSMS (Windows)

## Option 1: Bash Deployment (Linux/WSL)

```bash
# Edit servers.txt (or pass parameters)
./deploy_all.sh
```

The script will:
1. Deploy all 13 SQL scripts in order
2. Create 2 SQL Agent jobs (collection + retention)
3. Run a test collection
4. Verify all tables populated
5. Display summary

**Expected time:** 45-60 seconds

## Option 2: PowerShell Deployment

```powershell
pwsh Deploy-MonitoringSystem.ps1 `
    -Server "server,port" `
    -Username "user" `
    -Password "password"
```

Same 13-step process as bash script.

## Option 3: Manual Deployment (SSMS)

Execute scripts in order:
1. `01_create_DBATools_and_tables.sql`
2. `02_create_DBA_LogEntry_Insert.sql`
3. `05_create_enhanced_tables.sql`
4. `13_create_config_table_and_functions.sql`
5. `13b_create_database_filter_view.sql`
6. `06_create_modular_collectors_P0_FIXED.sql`
7. `07_create_modular_collectors_P1_FIXED.sql`
8. `08_create_modular_collectors_P2_P3_FIXED.sql`
9. `10_create_master_orchestrator_FIXED.sql`
10. `14_create_reporting_procedures.sql`
11. `create_retention_policy.sql`
12. `create_agent_job.sql`
13. `create_retention_job.sql`

## Verification

```sql
-- Check collection is running
SELECT TOP 5 *
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

-- Check SQL Agent jobs
SELECT name, enabled, date_created
FROM msdb.dbo.sysjobs
WHERE name LIKE 'DBA%'

-- View system health
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

## Next Steps

- [Configuration Guide](../reference/CONFIGURATION-GUIDE.md)
- [Verification Report](DEPLOYMENT_VERIFICATION_REPORT.md)
- [Troubleshooting](../troubleshooting/)

## Common Issues

**SQL Agent not running (Linux):**
```bash
sudo systemctl enable mssql-server-agent
sudo systemctl start mssql-server-agent
```

**Connection timeout:**
- Check firewall (port 1433 or custom)
- Use `-C` flag with sqlcmd to trust cert
- Verify SQL Server Browser running (UDP 1434)

**Job owner errors:**
- Fixed automatically (uses SUSER_SNAME())
- Older versions may need manual job owner update
