# PowerShell Automated Deployment Guide

**Script:** `Deploy-MonitoringSystem.ps1`
**Requirements:** PowerShell 5.1+, sqlcmd utility

---

## Quick Start

### Basic Deployment (Standard Port)
```powershell
cd E:\Downloads\sql_monitor

.\Deploy-MonitoringSystem.ps1 `
    -ServerName "your-server.domain.com" `
    -Username "sa" `
    -Password "YourPassword123" `
    -TrustServerCertificate
```

### Custom Port
```powershell
.\Deploy-MonitoringSystem.ps1 `
    -ServerName "192.168.1.100" `
    -Port 14333 `
    -Username "sa" `
    -Password "YourPassword123" `
    -TrustServerCertificate
```

### Skip SQL Agent Job (If Agent Not Running)
```powershell
.\Deploy-MonitoringSystem.ps1 `
    -ServerName "sqlserver.company.com" `
    -Username "sa" `
    -Password "YourPassword123" `
    -TrustServerCertificate `
    -SkipAgentJob
```

### Skip Validation Tests
```powershell
.\Deploy-MonitoringSystem.ps1 `
    -ServerName "localhost" `
    -Username "sa" `
    -Password "YourPassword123" `
    -TrustServerCertificate `
    -SkipValidation
```

---

## Parameters

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-ServerName` | SQL Server hostname or IP | `"sqlserver.company.com"` or `"192.168.1.100"` |
| `-Username` | SQL authentication username | `"sa"` or `"dbadmin"` |
| `-Password` | SQL authentication password | `"MyP@ssw0rd123"` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Port` | `1433` | SQL Server port number |
| `-TrustServerCertificate` | `$false` | Skip SSL certificate validation (recommended) |
| `-SkipAgentJob` | `$false` | Don't create SQL Agent job |
| `-SkipValidation` | `$false` | Skip validation tests |

---

## What the Script Does

### 1. Prerequisites Check
- ✓ Verifies sqlcmd utility is installed
- ✓ Checks all deployment files exist
- ✓ Tests SQL Server connection

### 2. Automated Deployment (Steps 1-10)
1. Creates DBATools database and 24 tables
2. Creates logging procedure
3. Creates configuration system (28 settings)
4. Creates P0 (Critical) collection procedures
5. Creates P1 (High) collection procedures
6. Creates P2/P3 (Medium/Low) collection procedures
7. Creates master orchestrator
8. Creates purge procedure
9. Creates SQL Agent job (every 5 minutes)
10. Runs validation tests

### 3. Validation
- Verifies database created
- Counts tables (expects 24)
- Counts procedures (expects 24)
- Counts functions (expects 5)
- Verifies config records (expects 28)
- Tests snapshot collection
- Checks for errors

### 4. Results
- Shows deployment summary
- Reports any errors or warnings
- Provides next steps

---

## Output Example

```
╔═══════════════════════════════════════════════════════════╗
║   SQL Server Monitoring System - Automated Deployment    ║
║                      Version 1.0                          ║
╚═══════════════════════════════════════════════════════════╝

Deployment Configuration:
  Server:   sqlserver.company.com:1433
  Username: sa
  Trust Certificate: True

ℹ Checking prerequisites...
✓ sqlcmd utility found
✓ Script directory found: E:\Downloads\sql_monitor
✓ All deployment files found
ℹ Testing connection to sqlserver.company.com...
✓ Connected successfully to sqlserver.company.com

═══════════════════════════════════════════════════
  Beginning Deployment
═══════════════════════════════════════════════════

[1/10] Database and tables
ℹ Executing: Database and tables...
✓ Database and tables completed

[2/10] Logging procedure
ℹ Executing: Logging procedure...
✓ Logging procedure completed

[3/10] Configuration system
ℹ Executing: Configuration system...
✓ Configuration system completed

... (continues for all steps)

═══════════════════════════════════════════════════
  Deployment Summary
═══════════════════════════════════════════════════

  Successful: 10
  Failed:     0
  Skipped:    0

═══════════════════════════════════════════════════
  Running Validation
═══════════════════════════════════════════════════

ℹ Validating deployment...
✓ DBATools database: 1
✓ Tables created: 24
✓ Procedures created: 24
✓ Functions created: 5
✓ Config records: 28
✓ SQL Agent job created

ℹ Testing snapshot collection...
✓ Test collection completed
✓ Snapshots collected: 1

ℹ Checking for deployment errors...
✓ No errors found in LogEntry

═══════════════════════════════════════════════════
  ✓ DEPLOYMENT COMPLETED SUCCESSFULLY
═══════════════════════════════════════════════════

ℹ Next Steps:
  1. Monitor collection for 24 hours
  2. Check DBATools.dbo.PerfSnapshotRun for data
  3. Review DBATools.dbo.LogEntry for any errors
  4. Adjust config if needed: EXEC DBATools.dbo.DBA_ViewConfig

✓ SQL Agent job will run every 5 minutes automatically
```

---

## Troubleshooting

### "sqlcmd is not recognized"

**Solution:** Install SQL Server Command Line Tools

**Download:** https://learn.microsoft.com/en-us/sql/tools/sqlcmd-utility

Or install via Chocolatey:
```powershell
choco install sqlserver-cmdlineutils
```

### "Login failed for user"

**Check:**
1. Username and password are correct
2. SQL authentication is enabled on the server
3. User has sysadmin or sufficient permissions

**Test connection manually:**
```powershell
sqlcmd -S "your-server" -U "sa" -P "YourPassword"
```

### "Cannot connect to server"

**Check:**
1. Server name/IP is correct
2. Port is correct (default 1433)
3. Firewall allows SQL Server port
4. SQL Server is running

**Test network connectivity:**
```powershell
Test-NetConnection -ComputerName "your-server" -Port 1433
```

### "SQL Server Agent is not running"

If you see Agent-related warnings:

**Option 1:** Start SQL Agent on Linux server
```bash
sudo systemctl start mssql-server-agent
sudo systemctl enable mssql-server-agent
```

**Option 2:** Skip Agent job during deployment
```powershell
.\Deploy-MonitoringSystem.ps1 ... -SkipAgentJob
```

Then create the job manually later via SSMS.

### "Script execution is disabled"

If you get an execution policy error:

```powershell
# Allow scripts for current session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Then run deployment
.\Deploy-MonitoringSystem.ps1 ...
```

### Re-running the Script

**Safe to re-run:** The script uses `CREATE OR ALTER` - it will update existing objects without errors.

If deployment fails partway:
1. Review error messages
2. Fix any issues (permissions, connectivity, etc.)
3. Re-run the script - it will skip already-created objects

---

## Advanced Usage

### Get Help
```powershell
Get-Help .\Deploy-MonitoringSystem.ps1 -Full
```

### Example Parameters
```powershell
Get-Help .\Deploy-MonitoringSystem.ps1 -Examples
```

### Verbose Output
```powershell
.\Deploy-MonitoringSystem.ps1 `
    -ServerName "localhost" `
    -Username "sa" `
    -Password "MyPass123" `
    -TrustServerCertificate `
    -Verbose
```

---

## After Deployment

### Monitor Collection
```powershell
# Run in PowerShell
sqlcmd -S "your-server" -U "sa" -P "YourPassword" -C -Q "SELECT TOP 10 * FROM DBATools.dbo.PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC"
```

### Check Job Status
```powershell
sqlcmd -S "your-server" -U "sa" -P "YourPassword" -C -Q "SELECT name, enabled, date_created FROM msdb.dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot'"
```

### View Configuration
```powershell
sqlcmd -S "your-server" -U "sa" -P "YourPassword" -C -Q "EXEC DBATools.dbo.DBA_ViewConfig"
```

### Check for Errors
```powershell
sqlcmd -S "your-server" -U "sa" -P "YourPassword" -C -Q "SELECT TOP 10 * FROM DBATools.dbo.LogEntry WHERE IsError = 1 ORDER BY LogEntryID DESC"
```

---

## Comparison: PowerShell vs SSMS

| Aspect | PowerShell Script | SSMS Manual |
|--------|-------------------|-------------|
| **Time** | 2-3 minutes | 5-10 minutes |
| **Steps** | 1 command | 10 files manually |
| **Validation** | Automatic | Manual |
| **Errors** | Detected automatically | Must review manually |
| **Repeatability** | Perfect | Manual process |
| **Prerequisites** | sqlcmd utility | SSMS installed |
| **Remote Access** | Command line | GUI required |
| **Best For** | Automation, multiple servers | First-time deployment |

---

## Multiple Server Deployment

Deploy to multiple servers in sequence:

```powershell
$servers = @(
    @{ Server="sql01.company.com"; Port=1433 },
    @{ Server="sql02.company.com"; Port=1433 },
    @{ Server="192.168.1.100"; Port=14333 }
)

$cred = Get-Credential -Message "Enter SQL credentials"

foreach ($srv in $servers) {
    Write-Host "`n=== Deploying to $($srv.Server) ===" -ForegroundColor Cyan

    .\Deploy-MonitoringSystem.ps1 `
        -ServerName $srv.Server `
        -Port $srv.Port `
        -Username $cred.UserName `
        -Password $cred.GetNetworkCredential().Password `
        -TrustServerCertificate

    Write-Host "`nPress any key to continue to next server..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

Write-Host "`n✓ All servers deployed!" -ForegroundColor Green
```

---

## Best Practices

1. **Test connection first:**
   ```powershell
   sqlcmd -S "your-server" -U "sa" -P "YourPassword" -C -Q "SELECT @@VERSION"
   ```

2. **Use `-TrustServerCertificate`** for most deployments (required for self-signed certs)

3. **Review output** for any warnings or errors

4. **Keep script with deployment files** in same directory

5. **Backup existing DBATools database** if re-deploying:
   ```sql
   BACKUP DATABASE DBATools TO DISK = 'C:\Backups\DBATools.bak'
   ```

6. **Test on dev server first** before production

---

## Support

- **Full Documentation:** See `SSMS-DEPLOYMENT-GUIDE.md`
- **Configuration:** See `CONFIGURATION-GUIDE.md`
- **System Overview:** See `FINAL-DEPLOYMENT-SUMMARY.md`

---

**Ready to deploy? Run the script with your server details!**
