# SQL Server Monitoring System - Quick Reference

**Last Updated:** 2025-10-27

## 🎯 What's Deployed

### All 3 Servers
- sqltest.schoolvision.net,14333
- svweb,14333
- suncity.schoolvision.net,14333

### Components Installed

1. **Performance Monitoring** (5-minute snapshots via SQL Agent job)
2. **Feedback Analysis System** (47 rules, 12 metadata records)
3. **HTML Report Generator** (web/email-ready output)

---

## 📊 Core Stored Procedures

### 1. Collect Performance Snapshot
```sql
-- Runs automatically every 5 minutes via SQL Agent job
-- Can also run manually for immediate snapshot
EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 0
```

### 2. Daily Health Overview (Text Output)
```sql
-- Returns 12 result sets with performance data
EXEC DBATools.dbo.DBA_DailyHealthOverview
    @TopSlowQueries = 20,
    @TopMissingIndexes = 20,
    @HoursBackForIssues = 48
```

### 3. Daily Health Overview (HTML Output)
```sql
-- Returns single HTML document ready for web/email
EXEC DBATools.dbo.DBA_DailyHealthOverview_HTML
    @TopSlowQueries = 20,
    @TopMissingIndexes = 20,
    @HoursBackForIssues = 48
```

---

## 🔧 Common Tasks

### Generate HTML Report

**Interactive Script:**
```bash
cd /mnt/e/Downloads/sql_monitor
./generate-html-report.sh
```

**Direct Command:**
```bash
sqlcmd -S svweb,14333 -U sv -P password -C -d DBATools -y 0 -Q "
SET NOCOUNT ON
EXEC DBATools.dbo.DBA_DailyHealthOverview_HTML
" -o report.html
```

### View Report in Browser

**WSL:**
```bash
wslpath -w report.html | xargs cmd.exe /c start
```

**Linux:**
```bash
cd reports
python3 -m http.server 8000
# Open: http://localhost:8000/report.html
```

### Email Report

```bash
cat report.html | mail -s "$(echo -e 'SQL Health\nContent-Type: text/html')" user@domain.com
```

### Check Collection Job Status

```sql
-- View job history
EXEC msdb.dbo.sp_help_jobhistory
    @job_name = 'DBA Collect Perf Snapshot',
    @mode = 'FULL'

-- Check if job is enabled
SELECT
    j.name AS JobName,
    j.enabled,
    js.last_run_date,
    js.last_run_time,
    js.last_run_outcome
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
WHERE j.name = 'DBA Collect Perf Snapshot'
```

---

## 📝 Feedback System

### View System Rules
```sql
-- All system-seeded feedback rules
SELECT
    FeedbackRuleID,
    ProcedureName,
    ResultSetNumber,
    MetricName,
    RangeFrom,
    RangeTo,
    Severity,
    FeedbackText
FROM DBATools.dbo.FeedbackRule
WHERE IsSystemRule = 1
ORDER BY ResultSetNumber, FeedbackRuleID
```

### Add Custom Rule
```sql
-- User rule gets ID >= 1,000,000,000 automatically
INSERT INTO DBATools.dbo.FeedbackRule
(ProcedureName, ResultSetNumber, MetricName, RangeFrom, RangeTo,
 Severity, FeedbackText, Recommendation, SortOrder)
VALUES
('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 70, NULL,
 'CRITICAL', 'Extreme CPU pressure detected',
 'Investigate and kill expensive queries immediately', 10)
```

### Reseed System Rules
```bash
# Preserves user customizations (ID >= 1B)
sqlcmd -S server,port -U user -P password -C -d DBATools \
    -i 13b_seed_feedback_rules.sql
```

---

## 📂 File Structure

### Core Scripts (Execute in Order)
```
01_create_DBATools_and_tables.sql      # Database and tables
02_create_DBA_LogEntry_Insert.sql      # Logging
03_create_DBA_CollectPerformanceSnapshot.sql  # Collector
04_create_agent_job_linux.sql          # Scheduled job
13_create_feedback_system.sql          # Feedback tables
13b_seed_feedback_rules.sql            # Seed data
14_enhance_daily_overview_with_feedback.sql  # Enhanced SP
15_create_html_formatter.sql           # HTML generator
```

### Deployment Scripts
```
deploy-feedback-system.sh              # Deploy feedback to all servers
generate-html-report.sh                # Interactive HTML generation
```

### Documentation
```
docs/
  ├── IDENTITY-SEED-PATTERN.md        # ID allocation guide
  ├── FEEDBACK-SYSTEM-GUIDE.md        # Usage guide
  └── HTML-FORMATTER-GUIDE.md         # HTML formatter docs

IDENTITY-SEED-IMPLEMENTATION-STATUS.md # Implementation status
HTML-FORMATTER-DEPLOYMENT-STATUS.md    # Deployment status
QUICK-REFERENCE.md                     # This file
```

---

## 🔍 Troubleshooting

### No Data in Reports
```sql
-- Check if snapshots are being collected
SELECT TOP 10
    PerfSnapshotRunID,
    SnapshotUTC,
    ServerName,
    CpuSignalWaitPct,
    BlockingSessionCount
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

-- If empty, check job status
EXEC msdb.dbo.sp_help_job @job_name = 'DBA Collect Perf Snapshot'

-- Manually run collector
EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1
```

### Job Not Running
```bash
# Linux: Ensure SQL Server Agent is running
sudo systemctl status mssql-server-agent
sudo systemctl start mssql-server-agent
sudo systemctl enable mssql-server-agent
```

### HTML Report Empty or Truncated
```bash
# Check procedure exists
sqlcmd -S server,port -U user -P password -C -d DBATools -Q "
SELECT name FROM sys.procedures WHERE name = 'DBA_DailyHealthOverview_HTML'
"

# Regenerate with correct parameters (use -y 0, not -h -1 -W)
sqlcmd -S server,port -U user -P password -C -d DBATools -y 0 -Q "
EXEC DBATools.dbo.DBA_DailyHealthOverview_HTML
" -o report.html
```

### Connection Errors
```bash
# WSL: Use WSL host IP, not localhost
Server=172.31.208.1,14333

# Windows: Use server name with port
Server=servername,14333

# Always use comma (not colon) for port separator
# Always include -C flag for certificate trust
```

---

## 📊 What Gets Captured (Every 5 Minutes)

**Server-Level:**
- CPU signal wait %
- Top wait type
- Active sessions/requests
- Blocking sessions
- Recent deadlocks
- Memory grant warnings

**Database-Level:**
- Database size (data + log)
- Recovery model
- Log reuse wait status
- File counts

**Query-Level:**
- Top CPU queries
- Execution stats
- SQL text

**Error Log:**
- Last 20 entries

**Missing Indexes:**
- Impact score
- Column recommendations

---

## 🎨 HTML Report Features

- **Size:** ~65KB per report
- **Sections:** 8 (header, health, stats, queries, indexes, databases, errors, footer)
- **Styling:** Embedded CSS, no external dependencies
- **Severity Colors:**
  - 🔵 INFO (normal)
  - 🟡 ATTENTION (watch)
  - 🟠 WARNING (investigate)
  - 🔴 CRITICAL (urgent)
- **Responsive:** Works on mobile/tablet
- **Safe:** HTML entity escaping for SQL text

---

## 🚀 Automation Examples

### Daily Email Reports
```bash
# Add to crontab (run daily at 8 AM)
0 8 * * * /mnt/e/Downloads/sql_monitor/generate-html-report.sh \
    svweb,14333 sv password && \
    cat /mnt/e/Downloads/sql_monitor/reports/health_report_*.html | \
    mail -s "$(echo -e 'Daily SQL Health\nContent-Type: text/html')" dba@company.com
```

### Hourly Snapshots to SharePoint
```powershell
# PowerShell scheduled task
$report = "C:\reports\health_$(Get-Date -f yyyyMMdd_HHmmss).html"
sqlcmd -S server,port -U user -P password -C -d DBATools -y 0 `
    -Q "EXEC DBA_DailyHealthOverview_HTML" -o $report

Connect-PnPOnline -Url "https://company.sharepoint.com/sites/DBA" -Interactive
Add-PnPFile -Path $report -Folder "Health Reports"
```

---

## 📞 Support

**Documentation:**
- `/docs/IDENTITY-SEED-PATTERN.md` - ID allocation strategy
- `/docs/FEEDBACK-SYSTEM-GUIDE.md` - Feedback rules
- `/docs/HTML-FORMATTER-GUIDE.md` - HTML generation

**Status Files:**
- `IDENTITY-SEED-IMPLEMENTATION-STATUS.md` - Feedback system status
- `HTML-FORMATTER-DEPLOYMENT-STATUS.md` - HTML formatter status

**Scripts Location:**
- `/mnt/e/Downloads/sql_monitor/`

**Deployed Servers:**
- sqltest.schoolvision.net,14333
- svweb,14333
- suncity.schoolvision.net,14333

---

## ✅ System Status

| Component | Status | Notes |
|-----------|--------|-------|
| Performance Collector | ✅ Active | Runs every 5 min via SQL Agent |
| Feedback System | ✅ Active | 47 rules, 12 metadata |
| HTML Formatter | ✅ Active | All 3 servers deployed |
| Documentation | ✅ Complete | All guides available |
| Deployment Scripts | ✅ Ready | Automated deployment |

**Last Verified:** 2025-10-27 20:03
**Deployed Servers:** 3 of 3 (100%)
**Production Ready:** ✅ YES
