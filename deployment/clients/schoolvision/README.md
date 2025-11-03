# SchoolVision SQL Server Monitoring - Deployment Guide

## Overview

This folder contains the deployment configuration for SchoolVision's SQL Server monitoring solution.

**Client:** SchoolVision
**Environment:** Test
**Deployment Date:** 2025-11-03

## Server Topology

```
┌─────────────────────────────────────────────────────┐
│ Primary Server (MonitoringDB Host)                   │
│ sqltest.schoolvision.net:14333                      │
│ - Hosts MonitoringDB                                 │
│ - Runs SQL Agent Jobs (collect every 5 min)         │
│ - Has Linked Servers to remote servers              │
└─────────────────────────────────────────────────────┘
           │
           ├───────────────────┐
           │                   │
           ▼                   ▼
┌──────────────────┐  ┌──────────────────┐
│ Remote Server 1  │  │ Remote Server 2  │
│ svweb:14333      │  │ suncity.school   │
│                  │  │ vision.net:14333 │
│ - Monitored      │  │ - Monitored      │
│ - Via Linked Srv │  │ - Via Linked Srv │
└──────────────────┘  └──────────────────┘
```

## Quick Start

### 1. Prerequisites

- **PowerShell 5.1+** or **PowerShell Core 7+**
- **sqlcmd** CLI tool installed
- Network access to all 3 SQL Servers
- `sv` account credentials

### 2. Initial Setup

```powershell
# Navigate to this directory
cd D:\Dev2\sql-monitor\deployment\clients\schoolvision

# Run the setup script (will prompt for new password)
.\Setup-SchoolVisionMonitoring.ps1
```

The script will:
1. ✅ Prompt for a NEW SQL password (more secure than default)
2. ✅ Reset `sa` password on all 3 servers
3. ✅ Update `.env` file with new password
4. ✅ Test connectivity to all servers
5. ✅ Create `MonitoringDB` on sqltest.schoolvision.net
6. ✅ Register all 3 servers in monitoring system
7. ✅ Create linked servers for remote monitoring
8. ✅ Deploy monitoring infrastructure (tables, procedures, jobs)
9. ✅ Create SQL Agent jobs (collect metrics every 5 minutes)

### 3. Verify Installation

**Check SQL Agent Jobs on sqltest.schoolvision.net:**
```sql
USE msdb;
GO

SELECT
    job.name AS JobName,
    schedule.name AS ScheduleName,
    schedule.active_start_time AS StartTime,
    schedule.freq_interval AS FrequencyDays
FROM sysjobs job
JOIN sysjobschedules jobsched ON job.job_id = jobsched.job_id
JOIN sysschedules schedule ON jobsched.schedule_id = schedule.schedule_id
WHERE job.name LIKE '%Monitor%'
ORDER BY job.name;
```

**Check Data Collection:**
```sql
USE MonitoringDB;
GO

-- Verify servers are registered
SELECT * FROM dbo.Servers ORDER BY ServerID;

-- Check latest metrics
SELECT TOP 10
    s.ServerName,
    pm.MetricCategory,
    pm.MetricName,
    pm.MetricValue,
    pm.CollectionTime
FROM dbo.PerformanceMetrics pm
JOIN dbo.Servers s ON pm.ServerID = s.ServerID
ORDER BY pm.CollectionTime DESC;

-- Verify collection time
SELECT
    s.ServerName,
    MAX(pm.CollectionTime) AS LastCollectionTime,
    DATEDIFF(MINUTE, MAX(pm.CollectionTime), GETUTCDATE()) AS MinutesAgo
FROM dbo.PerformanceMetrics pm
JOIN dbo.Servers s ON pm.ServerID = s.ServerID
GROUP BY s.ServerName
ORDER BY s.ServerName;
```

## Configuration Files

### .env (SENSITIVE - DO NOT COMMIT)

Contains actual passwords and server IPs. This file is automatically updated by the setup script.

```bash
# Current password
SQL_PASSWORD=Gv51076!  # Will be changed by setup script

# Server IPs
PRIMARY_SERVER_IP=sqltest.schoolvision.net
REMOTE_SERVER_1_IP=svweb
REMOTE_SERVER_2_IP=suncity.schoolvision.net
```

**⚠️ SECURITY:**
- `.env` is in `.gitignore` - will not be committed to git
- Keep this file secure and backed up
- Only share via secure channels (not email/chat)

### .env.template

Template file for creating new deployments. Safe to commit to git (no passwords).

## Manual Operations

### Trigger Metrics Collection Manually

```powershell
# Run on sqltest.schoolvision.net
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P YourPassword -C -Q "EXEC MonitoringDB.dbo.usp_CollectAllMetrics @ServerID = 1, @VerboseOutput = 1"
```

### Check Linked Server Connectivity

```sql
-- Run on PRIMARY_SERVER
USE master;
GO

-- Test remote server 1
SELECT 'Server 1 Test' AS Test, * FROM [svweb_LINK].master.sys.databases WHERE database_id = 1;

-- Test remote server 2
SELECT 'Server 2 Test' AS Test, * FROM [suncity_LINK].master.sys.databases WHERE database_id = 1;
```

### Manually Register a New Server

```sql
USE MonitoringDB;
GO

EXEC dbo.usp_AddServer
    @ServerName = 'NewServerName',
    @Environment = 'Test',
    @IsActive = 1;
```

## Script Options

### Partial Deployment

```powershell
# Skip password reset (if already done)
.\Setup-SchoolVisionMonitoring.ps1 -SkipPasswordReset

# Skip database creation (if already exists)
.\Setup-SchoolVisionMonitoring.ps1 -SkipDatabaseCreation

# Dry run (show what would be done)
.\Setup-SchoolVisionMonitoring.ps1 -WhatIf

# Combine options
.\Setup-SchoolVisionMonitoring.ps1 -SkipPasswordReset -WhatIf
```

## Grafana Integration

### Connect Grafana to MonitoringDB

1. **Add Data Source** in Grafana:
   - Type: **Microsoft SQL Server**
   - Host: `sqltest.schoolvision.net:14333`
   - Database: `MonitoringDB`
   - User: `sv` (or create dedicated read-only user)
   - Password: (from `.env` file)
   - Encryption: **Disable** or **Trust Server Certificate**

2. **Import Dashboards**:
   - Navigate to `D:\Dev2\sql-monitor\dashboards\grafana\dashboards\`
   - Import each `.json` file via Grafana UI
   - Or use provisioning (automated)

### Key Dashboards

- **00-landing-page.json** - Overview of all servers
- **08-aws-rds-performance-insights.json** - Detailed performance metrics
- **03-code-browser.json** - Browse stored procedures/functions
- **08-insights.json** - 24-hour priorities and issues

## Monitoring Coverage

Each server collects:

| Category | Metrics | Frequency |
|----------|---------|-----------|
| **CPU** | SQL Server %, System Idle %, Other Processes % | 5 minutes |
| **Memory** | Buffer Cache Hit Ratio, Page Life Expectancy, Grants Pending | 5 minutes |
| **Disk I/O** | Read/Write IOPS, Throughput (MB/s), Latency (ms) | 5 minutes |
| **Connections** | Total, Active, Sleeping, User, System | 5 minutes |
| **Wait Stats** | Top 10 wait types by wait time | 5 minutes |
| **Query Performance** | Avg CPU, Duration, Logical/Physical Reads | 5 minutes |

**Data Retention:** 90 days (configurable in `.env`)

## Troubleshooting

### Issue: SQL Agent Jobs Not Running

**Check SQL Server Agent Service:**
```powershell
Get-Service -ComputerName sqltest.schoolvision.net -Name "SQLSERVERAGENT"
```

**Enable SQL Agent:**
```sql
-- Run on sqltest.schoolvision.net
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
```

### Issue: Linked Server Connection Fails

**Test manually:**
```sql
USE master;
GO

EXEC sp_testlinkedserver @servername = 'svweb_LINK';
```

**Recreate linked server:**
```sql
-- Drop
EXEC sp_dropserver @server = 'svweb_LINK', @droplogins = 'droplogins';

-- Recreate
EXEC sp_addlinkedserver
    @server = 'svweb_LINK',
    @srvproduct = '',
    @provider = 'SQLNCLI',
    @datasrc = 'svweb,14333';

EXEC sp_addlinkedsrvlogin
    @rmtsrvname = 'svweb_LINK',
    @useself = 'FALSE',
    @locallogin = NULL,
    @rmtuser = 'sv',
    @rmtpassword = 'YourPassword';
```

### Issue: No Data in Grafana

**Verify data collection:**
```sql
USE MonitoringDB;
GO

-- Check record count (should be > 0)
SELECT
    MetricCategory,
    COUNT(*) AS RecordCount,
    MAX(CollectionTime) AS LastCollection
FROM dbo.PerformanceMetrics
GROUP BY MetricCategory
ORDER BY MetricCategory;
```

**If no data:**
1. Check SQL Agent service is running
2. Check job history for errors: `EXEC msdb.dbo.sp_help_jobhistory @job_name = 'Collect Metrics - Server 1'`
3. Manually run collection: `EXEC MonitoringDB.dbo.usp_CollectAllMetrics @ServerID = 1`

## Security Best Practices

1. ✅ **Change default password** immediately after setup
2. ✅ **Use dedicated monitoring account** instead of `sa`
3. ✅ **Restrict network access** to SQL Server ports (firewall rules)
4. ✅ **Enable encryption** for SQL Server connections
5. ✅ **Audit access** to MonitoringDB regularly
6. ✅ **Backup MonitoringDB** daily
7. ✅ **Rotate passwords** quarterly

## Support

**Project:** SQL Server Monitor
**Repository:** https://github.com/dbbuilder/sql-monitor
**Documentation:** `/docs/` in repository

For issues specific to SchoolVision deployment, check logs in `logs/` directory.

## File Structure

```
deployment/clients/schoolvision/
├── .env                                # Actual configuration (SENSITIVE - not committed)
├── .env.template                       # Template for new deployments
├── .gitignore                          # Prevents committing sensitive files
├── README.md                           # This file
├── Setup-SchoolVisionMonitoring.ps1   # Main setup script
└── logs/                               # Script execution logs (auto-created)
    ├── 01-create-database.sql.log
    ├── 02-create-tables.sql.log
    └── ...
```

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2025-11-03 | 1.0.0 | Initial deployment setup for SchoolVision |

---

**Last Updated:** 2025-11-03
**Maintained By:** SQL Monitor Team
