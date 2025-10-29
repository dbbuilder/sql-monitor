# Generating HTML Reports - Complete Guide

**Issue:** sqlcmd truncates NVARCHAR(MAX) output, resulting in blank or incomplete HTML files

**Solution:** Use PowerShell for reliable export

---

## ✅ Recommended Method: PowerShell

### Windows or WSL with PowerShell

**Option 1: Interactive Script**
```bash
./generate-html-report.sh
```

**Option 2: Direct PowerShell**
```powershell
# Windows PowerShell or pwsh
.\Export-HealthReportHTML.ps1

# With custom parameters
.\Export-HealthReportHTML.ps1 -Server "svweb,14333" -User "sv" -Password "password"

# With custom output path
.\Export-HealthReportHTML.ps1 -OutputPath "C:\Reports\health.html"
```

**Why it works:**
- PowerShell's SqlClient handles large NVARCHAR(MAX) properly
- No output truncation
- Full ~65KB HTML report exported
- UTF-8 encoding support

---

## ⚠️ Issue: sqlcmd Truncation

### The Problem

sqlcmd has limitations with NVARCHAR(MAX) columns:

```bash
# This FAILS - produces truncated output (257 chars instead of 65,000)
sqlcmd -S server,port -U user -P pass -C -d DBATools -y 0 -Q "
EXEC DBA_DailyHealthOverview_HTML
" -o report.html
```

**Result:** File contains only:
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SQL Server Health Report - SQLTEST\TEST</title>
    <style>
        body {
            font-family: "Segoe UI", A
```

**Why it fails:**
- sqlcmd `-y 0` parameter doesn't fully work with NVARCHAR(MAX)
- Maximum output width still applies (~8000 characters)
- Variable-length data types get truncated

---

## 🔧 Solutions by Platform

### 1. Windows (Recommended)

**Use PowerShell:**
```powershell
cd E:\Downloads\sql_monitor
.\Export-HealthReportHTML.ps1
```

**Benefits:**
- ✅ Full HTML export (65KB+)
- ✅ No truncation
- ✅ UTF-8 encoding
- ✅ Built into Windows 10+

### 2. Linux with PowerShell Core

**Install PowerShell:**
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y powershell

# Or download from: https://aka.ms/install-powershell
```

**Generate report:**
```bash
pwsh /path/to/Export-HealthReportHTML.ps1
```

### 3. Python Alternative

**If Python + pyodbc is available:**

```bash
# Install pyodbc
sudo apt-get install -y python3-pyodbc

# Generate report
python3 export_html_report.py
```

**Benefits:**
- ✅ Cross-platform
- ✅ Handles large output
- ✅ Programmatic control

### 4. BCP (Advanced)

**For bulk export:**
```bash
# Create temp table with HTML
sqlcmd -S server -U user -P pass -C -d DBATools -Q "
IF OBJECT_ID('tempdb..#HTML') IS NOT NULL DROP TABLE #HTML
CREATE TABLE #HTML (Content NVARCHAR(MAX))
INSERT INTO #HTML EXEC DBA_DailyHealthOverview_HTML
"

# Export using BCP
bcp "SELECT Content FROM tempdb..#HTML" queryout report.html -S server -U user -P pass -c -C UTF8
```

**Complexity:** High, requires coordination

---

## 📋 Verification

After generating a report, verify it's complete:

```bash
# Check file size
FILE="reports/health_report_*.html"
CHARS=$(wc -c < "$FILE")

if [ "$CHARS" -gt 60000 ]; then
    echo "✅ Report is complete ($CHARS characters)"
else
    echo "❌ Report is truncated ($CHARS characters - expected 60000+)"
fi

# Check content
head -20 "$FILE"  # Should show full HTML header
tail -20 "$FILE"  # Should show closing </html> tag
```

**Complete report characteristics:**
- Size: ~62-67 KB (63,000-68,000 characters)
- Lines: ~490-800 lines
- Starts with: `<!DOCTYPE html>`
- Ends with: `</body>\n</html>`
- Contains all 8 sections

---

## 🎯 Quick Commands

### Generate Report (PowerShell)
```powershell
# Windows
.\Export-HealthReportHTML.ps1

# WSL/Linux with pwsh
pwsh Export-HealthReportHTML.ps1
```

### View Report
```bash
# WSL - Open in Windows browser
wslpath -w /mnt/e/Downloads/sql_monitor/reports/health_report_*.html | xargs cmd.exe /c start

# Windows
start reports\health_report_*.html

# Linux
xdg-open reports/health_report_*.html

# Any platform - HTTP server
cd reports
python3 -m http.server 8000
# Open: http://localhost:8000
```

### Email Report
```bash
# Linux (mailutils required)
cat report.html | mail -s "$(echo -e 'SQL Health Report\nContent-Type: text/html')" user@domain.com

# PowerShell
Send-MailMessage -To "user@domain.com" -From "sql@server.com" -Subject "SQL Health Report" -Body (Get-Content report.html -Raw) -BodyAsHtml -SmtpServer smtp.server.com
```

---

## 🐛 Troubleshooting

### Report is blank/truncated

**Check file size:**
```bash
wc -c reports/health_report_*.html
```

**If < 60,000 characters:**
1. ✅ Use PowerShell method (recommended)
2. ⚠️ sqlcmd truncates output - don't use
3. Install PowerShell Core if not available

### PowerShell connection errors

**Error:** "Invalid value for key 'encrypt'"

**Fix:** Use `TrustServerCertificate=True` instead of `Encrypt=Optional`

**Correct connection string:**
```powershell
$connectionString = "Server=$Server;Database=DBATools;User Id=$User;Password=$Password;TrustServerCertificate=True;Connection Timeout=30"
```

### Python pyodbc not found

**Install via apt (preferred):**
```bash
sudo apt-get update
sudo apt-get install -y python3-pyodbc
```

**Or via pip:**
```bash
pip3 install pyodbc --break-system-packages  # Use with caution
```

---

## 📊 Report Contents

A complete HTML report includes:

1. **Header** - Server, date, parameters
2. **Report Header** - Server info, snapshot date
3. **Current System Health** - CPU, blocking, deadlocks (color-coded)
4. **Summary Statistics** - Aggregated metrics
5. **Top Slow Queries** - CPU usage, execution stats
6. **Top Missing Indexes** - Impact scores, recommendations
7. **Database Sizes** - Data/log sizes, recovery model
8. **Recent Error Log** - Last 20 entries
9. **Footer** - Generation timestamp

**Total size:** ~65 KB
**Sections:** 8
**Styling:** Embedded CSS, no external dependencies

---

## 🚀 Automation

### Daily Reports (Windows Task Scheduler)

```powershell
# Create scheduled task
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\Export-HealthReportHTML.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 8am
Register-ScheduledTask -TaskName "SQL Health Report" -Action $action -Trigger $trigger
```

### Hourly Reports (Linux cron)

```bash
# Add to crontab
0 * * * * /usr/bin/pwsh /path/to/Export-HealthReportHTML.ps1
```

### Email on Completion

```powershell
# In Export-HealthReportHTML.ps1 (add after file generation)
Send-MailMessage `
    -To "dba@company.com" `
    -From "sql@server.com" `
    -Subject "Daily SQL Health Report - $(Get-Date -Format 'yyyy-MM-dd')" `
    -Body (Get-Content $OutputPath -Raw) `
    -BodyAsHtml `
    -SmtpServer "smtp.company.com"
```

---

## ✅ Best Practices

1. **Always use PowerShell** for generating reports
2. **Verify file size** after generation (should be ~65KB)
3. **Test in browser** before emailing
4. **Archive old reports** (keep last 30 days)
5. **Schedule daily generation** for trend monitoring
6. **Use HTTPS** if serving via web server

---

## 📞 Summary

**Problem:** sqlcmd truncates NVARCHAR(MAX) output

**Solution:** Use PowerShell script `Export-HealthReportHTML.ps1`

**Quick Start:**
```powershell
# Windows
.\Export-HealthReportHTML.ps1

# WSL/Linux
pwsh Export-HealthReportHTML.ps1
```

**Files:**
- `Export-HealthReportHTML.ps1` - PowerShell export (recommended)
- `export_html_report.py` - Python alternative
- `generate-html-report.sh` - Bash wrapper (uses PowerShell if available)

**Result:** Complete 65KB HTML report ready for viewing/emailing
