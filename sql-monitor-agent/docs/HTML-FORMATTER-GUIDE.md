# HTML Report Formatter - User Guide

**Created:** 2025-10-27
**Updated:** 2025-10-27
**Procedure:** `DBATools.dbo.DBA_DailyHealthOverview_HTML`

## Overview

The HTML formatter wraps `DBA_DailyHealthOverview` and generates a complete, styled HTML report ready for:
- Web serving (Python HTTP server, IIS, Apache, etc.)
- Email delivery (inline HTML or attachment)
- File storage and viewing
- SharePoint/document management systems

## 📚 Related Documentation

**Before reading this guide, review:**
- **[INTERPRETING-METRICS-GUIDE.md](INTERPRETING-METRICS-GUIDE.md)** - Learn what the numbers mean and when to take action
- **[GENERATING-HTML-REPORTS.md](../GENERATING-HTML-REPORTS.md)** - How to generate reports (PowerShell method)
- **[SLOW-QUERIES-PER-DATABASE.md](../SLOW-QUERIES-PER-DATABASE.md)** - Understanding per-database grouping

## Features

- **Complete HTML document** - Includes DOCTYPE, CSS, and all formatting
- **Self-contained** - No external CSS/JS dependencies
- **Responsive design** - Basic mobile/tablet support via viewport meta tag
- **Severity-based styling** - Color-coded INFO/ATTENTION/WARNING/CRITICAL
- **Null-safe** - Handles NULL values gracefully with styled placeholders
- **Formatted numbers** - Thousands separators, decimal precision
- **Inline feedback** - Analysis and recommendations from FeedbackRule table
- **Truncated SQL text** - Long queries truncated with hover tooltip
- **Professional appearance** - Clean, legible, minimal design

## Usage

### Basic Execution

```sql
EXEC DBATools.dbo.DBA_DailyHealthOverview_HTML
    @TopSlowQueries = 20,
    @TopMissingIndexes = 20,
    @HoursBackForIssues = 48
```

**Output:** Single column named `HTMLReport` containing complete HTML document.

### Save to File (sqlcmd)

```bash
# Linux/WSL
sqlcmd -S "server,port" -U user -P password -C -d DBATools -h -1 -W \
    -Q "EXEC DBA_DailyHealthOverview_HTML" \
    -o health_report.html

# Windows PowerShell
sqlcmd -S "server,port" -U user -P password -C -d DBATools -h -1 -W `
    -Q "EXEC DBA_DailyHealthOverview_HTML" `
    -o health_report.html
```

**Important flags:**
- `-h -1` - No column headers
- `-W` - Remove trailing spaces
- `-o <file>` - Output to file

### Automated Report Generation Script

Use the provided `generate-html-report.sh` script:

```bash
# Generate report with interactive options
./generate-html-report.sh

# Specify server
./generate-html-report.sh "sqltest.schoolvision.net,14333" "sv" "password"

# Then choose:
# 1) Serve via HTTP server
# 2) Send via email
# 3) Just save to file
# 4) Open in browser (WSL only)
```

## How to Read the Report

### Report Structure

The HTML report contains **8 main sections**:

1. **Header** - Server name, report date, parameters
2. **Report Header** - Server info, snapshot details
3. **Current System Health** - Real-time health status with color-coded severity
4. **Summary Statistics** - Aggregated metrics over lookback period
5. **Top 10 Slow Queries per Database** - CPU-intensive queries grouped by database
6. **Top Missing Indexes** - Index recommendations sorted by impact
7. **Database Sizes** - Storage usage for all databases
8. **Recent Error Log** - Last 20 error log entries

### Understanding Color Codes

The report uses **color-coded severity levels**:

| Color | Severity | Meaning | Action Required |
|-------|----------|---------|-----------------|
| 🔵 **Blue/Gray** | INFO | Normal operation | None - for information only |
| 🟡 **Yellow** | ATTENTION | Watch this metric | Monitor trends |
| 🟠 **Orange** | WARNING | Issue detected | Investigate and plan fix |
| 🔴 **Red** | CRITICAL | Urgent issue | Immediate action required |

**Example:**
```
CPU Signal Wait %: 35%
[Orange/Warning background]
Status: WARNING - Elevated CPU usage
```

### Reading Each Section

#### 1. Current System Health

**What to look for:**
- **CPU Signal Wait %**
  - < 10% = ✅ Normal
  - 10-20% = ⚠️ Monitor
  - 20-40% = ⚠️ Investigate
  - > 40% = 🔴 Urgent
  - See: [INTERPRETING-METRICS-GUIDE.md#cpu-signal-wait](INTERPRETING-METRICS-GUIDE.md#1-cpu-signal-wait-)

- **Blocking Sessions**
  - 0-5 = ✅ Normal
  - 6-15 = ⚠️ Watch
  - 16-30 = ⚠️ High
  - 30+ = 🔴 Critical
  - See: [INTERPRETING-METRICS-GUIDE.md#blocking-sessions](INTERPRETING-METRICS-GUIDE.md#2-blocking-sessions)

- **Recent Deadlocks** (last 10 min)
  - 0 = ✅ None
  - 1-4 = ⚠️ Some
  - 5+ = 🔴 Frequent
  - See: [INTERPRETING-METRICS-GUIDE.md#deadlocks](INTERPRETING-METRICS-GUIDE.md#3-recent-deadlocks)

- **Memory Grant Warnings**
  - 0 = ✅ No spills
  - 1-9 = ⚠️ Some spills
  - 10+ = 🔴 Frequent spills
  - See: [INTERPRETING-METRICS-GUIDE.md#memory-grant-warnings](INTERPRETING-METRICS-GUIDE.md#4-memory-grant-warnings)

#### 2. Top 10 Slow Queries per Database

**Look for these patterns:**

**High CPU + High Executions:**
```
Database: DB_Production
Rank: 1
Total CPU: 5,234,567 ms
Execution Count: 10,000
→ Issue: Frequently executed expensive query
→ Action: Optimize query, add indexes
```

**High Duration + Low CPU:**
```
Avg Duration: 1,500 ms
Avg CPU: 100 ms
Avg Reads: 500,000
→ Issue: I/O-bound query
→ Action: Add covering index to reduce reads
```

**High Reads:**
```
Avg Logical Reads: 250,000 pages
→ Issue: Table scan or missing index
→ Action: Check missing indexes section
```

See: [INTERPRETING-METRICS-GUIDE.md#query-performance-metrics](INTERPRETING-METRICS-GUIDE.md#query-performance-metrics)

#### 3. Top Missing Indexes

**Prioritize by Impact Score:**

```
Impact Score = Avg User Impact × User Seeks

Example:
Index 1: Score = 2,500,000 (Impact: 90%, Seeks: 27,778)
→ Create this index first!

Index 2: Score = 450,000 (Impact: 30%, Seeks: 15,000)
→ Lower priority
```

**Index recommendations show:**
- **Equality Columns** - Columns with = predicates (create index on these)
- **Inequality Columns** - Columns with >, <, BETWEEN (include in index)
- **Included Columns** - SELECT columns (add to INCLUDE clause)

**Creating the index:**
```sql
-- Example from report
Equality Columns: CustomerID, OrderDate
Included Columns: OrderTotal, Status

-- Create index
CREATE INDEX IX_Orders_Customer_Date ON Orders
(
    CustomerID,    -- Equality column
    OrderDate      -- Equality column
)
INCLUDE (OrderTotal, Status)  -- Included columns
```

See: [INTERPRETING-METRICS-GUIDE.md#missing-indexes-metrics](INTERPRETING-METRICS-GUIDE.md#missing-indexes-metrics)

#### 4. Database Sizes

**What to check:**

**Log Size vs Data Size:**
```
Database: DB_Production
Data Size: 450 GB
Log Size: 120 GB (27% of data)

Normal: Log = 10-25% of data
Concern: Log > 50% of data
Critical: Log > data size
```

**Log Reuse Wait:**
- **NOTHING** = ✅ Normal (log truncating)
- **LOG_BACKUP** = 🔴 Need log backup
- **ACTIVE_TRANSACTION** = 🔴 Long-running transaction
- See: [INTERPRETING-METRICS-GUIDE.md#log-reuse-wait](INTERPRETING-METRICS-GUIDE.md#3-log-reuse-wait)

### Visual Database Groups

Slow queries are grouped by database with visual headers:

```
📊 Database: DB_Analytics
Rank 1-10: Top queries for this database

📊 Database: DB_Production
Rank 1-10: Top queries for this database
```

This ensures **all databases** are represented, not just the busiest ones.

### Quick Assessment Workflow

**Step 1: Check Current Health (30 seconds)**
- Scroll to "Current System Health" section
- Look for red/orange colored rows
- Note any CRITICAL or WARNING status

**Step 2: Review Summary Statistics (1 minute)**
- Check Avg CPU Signal Wait % (should be < 20%)
- Check Total Deadlocks (should be < 10)
- Check Snapshots with Blocking (should be < 25%)

**Step 3: Find Problem Queries (2-5 minutes)**
- Scroll to "Top 10 Slow Queries per Database"
- Find your database (📊 Database: YourDBName)
- Look at Rank 1-3 queries (highest impact)
- Note Total CPU > 1,000,000 (critical)

**Step 4: Check Missing Indexes (2 minutes)**
- Scroll to "Top Missing Indexes"
- Look at Impact Score column
- Create indexes with Score > 1,000,000 first

**Step 5: Review Error Log (1 minute)**
- Scroll to "Recent Error Log"
- Look for errors, not just informational messages
- Investigate any recurring errors

**Total time:** 6-9 minutes for complete review

### When to Take Action

**🔴 Immediate Action (within 1 hour):**
- CPU Signal Wait > 40%
- Blocking Sessions > 30
- Deadlocks > 5 in 10 minutes
- Log Reuse Wait = ACTIVE_TRANSACTION with log > data size

**⚠️ Plan Action (within 24 hours):**
- CPU Signal Wait 20-40%
- Blocking Sessions 16-30
- Avg Duration > 2,000ms in top queries
- Missing indexes with Impact Score > 1,000,000

**⚠️ Monitor (check next report):**
- CPU Signal Wait 10-20%
- Blocking Sessions 6-15
- Deadlocks 1-4
- Log Size 25-50% of data size

See full action matrix: [INTERPRETING-METRICS-GUIDE.md#when-to-take-action](INTERPRETING-METRICS-GUIDE.md#when-to-take-action)

### Example Report Review

**Report shows:**
```
Current System Health:
- CPU Signal Wait %: 35% [WARNING - Elevated CPU usage]
- Blocking Sessions: 8 [ATTENTION - Moderate blocking]

Top 10 Slow Queries per Database:
📊 Database: DB_Production
Rank 1: Total CPU = 5,234,567 ms, Executions = 10,000

Top Missing Indexes:
Rank 1: Impact Score = 2,500,000 (90% impact, 27,778 seeks)
```

**Analysis:**
1. ⚠️ CPU usage elevated but not critical
2. ⚠️ Some blocking (acceptable for production)
3. 🔴 One query consuming 5M ms CPU (critical)
4. 🔴 Missing index could improve 90% (critical)

**Action Plan:**
1. **Today:** Create missing index (Rank 1) - 90% improvement expected
2. **Today:** Optimize slow query (Rank 1) or add caching
3. **This week:** Monitor CPU trend (may improve after above fixes)
4. **This week:** Review blocking patterns (currently acceptable)

**Expected outcome:**
- Missing index will reduce reads → lower CPU
- Query optimization will reduce executions → lower total CPU
- CPU Signal Wait should drop to < 20%

## Serving Options

### Option 1: Python HTTP Server (Development)

```bash
# Generate report first
./generate-html-report.sh

# Navigate to reports directory
cd reports

# Start HTTP server
python3 -m http.server 8000

# Open browser to:
# http://localhost:8000/health_report_YYYYMMDD_HHMMSS.html
```

**Use cases:**
- Quick ad-hoc viewing
- Local development
- Temporary sharing on LAN

### Option 2: Email Delivery

```bash
# Using generate-html-report.sh (option 2)
./generate-html-report.sh
# Choose option 2, enter recipient email

# Or manually with mailx/mutt
cat health_report.html | mail -s "$(echo -e 'SQL Health Report\nContent-Type: text/html')" user@domain.com
```

**Requirements:**
- `mailutils` package installed (`sudo apt-get install mailutils`)
- Mail server configured (postfix, sendmail, or relay)

### Option 3: Web Server Deployment

#### IIS (Windows)

1. Copy HTML file to `C:\inetpub\wwwroot\reports\`
2. Create IIS application or virtual directory
3. Access via `http://server/reports/health_report.html`

#### Apache/Nginx (Linux)

```bash
# Copy to web root
sudo cp health_report.html /var/www/html/reports/

# Set permissions
sudo chown www-data:www-data /var/www/html/reports/health_report.html
sudo chmod 644 /var/www/html/reports/health_report.html

# Access via http://server/reports/health_report.html
```

### Option 4: Scheduled Email Reports

Create a cron job to generate and email reports daily:

```bash
# Edit crontab
crontab -e

# Add entry (runs daily at 8 AM)
0 8 * * * /mnt/e/Downloads/sql_monitor/generate-html-report.sh "server,port" "user" "password" && \
    cat /mnt/e/Downloads/sql_monitor/reports/health_report_*.html | \
    mail -s "$(echo -e 'Daily SQL Health Report\nContent-Type: text/html')" dba-team@company.com
```

## HTML Structure

The generated HTML includes these sections:

1. **Header** - Server name, report date, parameters
2. **Report Header** - Data collection status
3. **Current System Health** - Latest snapshot with CPU, blocking, deadlocks, memory
4. **Summary Statistics** - Aggregated metrics over lookback period
5. **Top Slow Queries** - Highest CPU queries with analysis
6. **Top Missing Indexes** - Highest impact missing indexes
7. **Database Sizes** - All databases sorted by total size
8. **Recent Error Log** - Last 20 error log entries
9. **Footer** - Generation metadata

## Customization

### Modify CSS Styling

Edit `15_create_html_formatter.sql` and update the `<style>` block:

```sql
-- Example: Change header color
.header {
    background-color: #0078d4;  -- Change this
    color: white;
    padding: 20px;
    border-radius: 5px;
    margin-bottom: 20px;
}

-- Example: Change severity colors
.severity-CRITICAL {
    background-color: #ffebee;
    border-left: 4px solid #f44336;
}
```

Then redeploy:
```bash
sqlcmd -S server -U user -P password -C -d DBATools \
    -i 15_create_html_formatter.sql
```

### Add Custom Sections

To add additional result sets to the HTML output:

1. Edit `15_create_html_formatter.sql`
2. Add a new section similar to existing ones:
   ```sql
   DECLARE @CustomSectionHTML NVARCHAR(MAX) = ''

   SELECT @CustomSectionHTML = '<div class="section">
       <div class="section-header">Custom Section</div>
       <table>...' +
       (SELECT ... FROM ... FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)') +
       '</table></div>'

   SET @HTML = @HTML + @CustomSectionHTML
   ```
3. Redeploy procedure

### Change Report Parameters

Modify default parameters in the procedure definition:

```sql
CREATE OR ALTER PROCEDURE dbo.DBA_DailyHealthOverview_HTML
    @TopSlowQueries INT = 50,        -- Increase from 20
    @TopMissingIndexes INT = 30,     -- Increase from 20
    @HoursBackForIssues INT = 72     -- Increase from 48
AS
```

## Performance Considerations

**Execution time:** < 2 seconds (typical)
**HTML size:** 50-500 KB (depends on data volume)
**Memory:** Minimal (uses XML PATH for concatenation)

**For large servers:**
- Reduce `@TopSlowQueries` to 10-15
- Reduce `@TopMissingIndexes` to 10-15
- SQL text truncated at 100 characters (configurable)

## Troubleshooting

### HTML Not Displaying Correctly

**Problem:** HTML shows as plain text
**Cause:** Content-Type header not set
**Solution:**
- For email: Use `-s "$(echo -e 'Subject\nContent-Type: text/html')"` format
- For web server: Ensure file has `.html` extension
- For Python server: File must have `.html` extension (auto-detects MIME type)

### Special Characters Appear Garbled

**Problem:** SQL text with `<`, `>`, `&` displays incorrectly
**Cause:** HTML entity encoding needed
**Solution:** Already handled via `REPLACE(REPLACE(SqlText, '<', '&lt;'), '>', '&gt;')`

### Report File is Empty or Corrupt

**Problem:** Generated file is 0 bytes or contains error messages
**Cause:** SQL connection failed or procedure errored
**Solution:**
- Check sqlcmd output for error messages
- Run procedure directly in SSMS first to verify
- Check server connectivity

### NULL Values Not Styled

**Problem:** NULL appears as blank cells
**Cause:** Missing NULL handling
**Solution:** Already handled via `ISNULL(value, '<span class="null-value">NULL</span>')`

## Integration Examples

### SharePoint Document Library

```powershell
# PowerShell script to upload to SharePoint
$reportPath = "C:\reports\health_report.html"
$siteUrl = "https://company.sharepoint.com/sites/DBA"
$libraryName = "Health Reports"

Connect-PnPOnline -Url $siteUrl -Interactive
Add-PnPFile -Path $reportPath -Folder $libraryName
```

### Azure Blob Storage

```bash
# Upload to Azure Blob Storage
az storage blob upload \
    --account-name storageaccount \
    --container-name reports \
    --name health_report_$(date +%Y%m%d).html \
    --file health_report.html \
    --content-type "text/html"
```

### Slack Notification

```bash
# Send report link via Slack webhook
REPORT_URL="http://server/reports/health_report.html"
curl -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"Daily SQL Health Report: $REPORT_URL\"}" \
    https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

## Best Practices

1. **Schedule regular reports** - Use cron/Task Scheduler for daily reports
2. **Archive old reports** - Keep 30-90 days, then delete
3. **Version control** - Keep HTML formatter script in Git
4. **Test before production** - Generate reports on dev/test first
5. **Monitor email delivery** - Check bounce/spam rates
6. **Use HTTPS for web serving** - Protect sensitive performance data
7. **Restrict access** - Use authentication for web-served reports
8. **Include timestamp in filename** - `health_report_YYYYMMDD_HHMMSS.html`

## Security Considerations

**Sensitive data in reports:**
- SQL query text (may contain table/column names)
- Database names
- Error messages (may contain paths)
- Session login names

**Recommendations:**
- Restrict web server access (IP allowlist, authentication)
- Use encrypted email (TLS)
- Sanitize SQL text if needed (remove literals, schema names)
- Store reports in secure locations only
- Set appropriate file permissions (640 or 600)

## Summary

**File:** `15_create_html_formatter.sql`
**Procedure:** `DBA_DailyHealthOverview_HTML`
**Script:** `generate-html-report.sh`
**Output:** Self-contained HTML document

**Key Benefits:**
- ✅ No external dependencies (CSS/JS)
- ✅ Ready for email, web, or file storage
- ✅ Professional appearance
- ✅ Severity-based color coding
- ✅ Mobile-friendly (basic responsive design)
- ✅ Null-safe and error-resistant
- ✅ Easy customization via CSS

**Usage:** Run once, view anywhere (browser, email client, mobile device)
