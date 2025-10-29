# SQL Server Monitoring System - Version History

## Version 1.0 (2025-10-27)

**Status:** ✅ Production Ready

### Features

**Core Monitoring:**
- Performance snapshot collection (P0/P1/P2/P3 priority levels)
- Per-database query statistics (top 10 per database)
- Missing index recommendations
- Wait statistics and blocking detection
- Deadlock monitoring with automatic trace flag enablement
- Error log capture
- Database size and growth tracking
- 5-minute automated collection via SQL Agent
- 14-day retention policy

**Feedback System:**
- 47 configurable rules for health analysis
- Range-based severity levels (INFO/ATTENTION/WARNING/CRITICAL)
- 12 metadata records explaining each metric
- Inline feedback in text reports
- Identity seed pattern (1 billion) for safe reseeding

**HTML Reporting:**
- Self-contained HTML reports (no external dependencies)
- Color-coded severity indicators
- Per-database slow query grouping with visual headers
- Top 10 queries per database (ensures all databases represented)
- Export via PowerShell script (handles large output correctly)
- XML-safe text cleaning function (`fn_CleanTextForXML`)
  - Removes control characters (including CHAR(0))
  - Preserves printable ASCII and common Unicode
  - Prevents FOR XML serialization errors

**Documentation:**
- Complete installation guide
- Metrics interpretation guide (~25,000 words)
- HTML formatter user guide with reading workflow
- Troubleshooting documentation
- Pre-production checklist

### Components

**Database Objects:**
- 1 database (DBATools)
- 20+ tables (snapshot storage, configuration, feedback)
- 30+ stored procedures (collectors, reporting, orchestration)
- 3+ functions (configuration, feedback, text cleaning)
- 2 SQL Agent jobs (collection, retention)

**Scripts:**
- `Deploy-Complete-System.ps1` - Full automated deployment
- `Deploy-Complete-System-NoSqlCmd.ps1` - PowerShell-only deployment (no sqlcmd required)
- `Export-HealthReportHTML.ps1` - HTML report generation
- `deploy-xml-fix.ps1` - Deploy text cleaning function and formatter

### Deployment Servers

- ✅ 10.10.2.201 (validated)
- svweb (data.schoolvision.net,14333)
- suncity.schoolvision.net,14333
- sqltest.schoolvision.net,14333

### Known Issues & Resolutions

**Issue:** FOR XML serialization error with NULL characters (CHAR(0)) in SQL query text
**Resolution:** Created `fn_CleanTextForXML` function that extracts only printable characters
**Status:** ✅ Fixed in v1.0

### Installation

```powershell
# Full installation
.\Deploy-Complete-System-NoSqlCmd.ps1 -Server "server" -Username "user" -Password "pass"

# XML fix (if upgrading from pre-1.0)
.\deploy-xml-fix.ps1 -Server "server" -User "user" -Password "pass"

# Generate HTML report
.\Export-HealthReportHTML.ps1 -Server "server" -User "user" -Password "pass" -OutputPath "report.html"
```

### File Manifest (v1.0)

**Core Infrastructure:**
- `01_create_DBATools_and_tables.sql` - Database and base tables
- `02_create_DBA_LogEntry_Insert.sql` - Logging infrastructure
- `05_create_enhanced_tables.sql` - Snapshot tables (P0/P1/P2/P3)
- `06_create_modular_collectors_P0_FIXED.sql` - Critical collectors
- `07_create_modular_collectors_P1_FIXED.sql` - Performance collectors
- `08_create_modular_collectors_P2_P3_FIXED.sql` - Medium/Low collectors
- `10_create_master_orchestrator_FIXED.sql` - Master orchestrator
- `13_create_config_table_and_functions.sql` - Configuration system
- `13b_create_database_filter_view.sql` - Database filtering

**Feedback System:**
- `13_create_feedback_system.sql` - Feedback tables
- `13b_seed_feedback_rules.sql` - 47 rules + 12 metadata records
- `14_enhance_daily_overview_with_feedback.sql` - Enhanced daily overview

**HTML Reporting:**
- `15_create_html_formatter.sql` - HTML report formatter
- `16_create_clean_text_function.sql` - XML-safe text cleaning
- `Export-HealthReportHTML.ps1` - PowerShell export script

**Automation:**
- `create_agent_job.sql` - Collection job (every 5 minutes)
- `create_retention_job.sql` - Retention job (daily at 2 AM)
- `create_retention_policy.sql` - Purge procedure

**Deployment:**
- `Deploy-Complete-System.ps1` - Full deployment (requires sqlcmd)
- `Deploy-Complete-System-NoSqlCmd.ps1` - PowerShell-only deployment
- `deploy-xml-fix.ps1` - Deploy text cleaning fix

**Documentation:**
- `README.md` - Project overview
- `CLAUDE.md` - Claude Code instructions
- `docs/INTERPRETING-METRICS-GUIDE.md` - Metrics interpretation
- `docs/HTML-FORMATTER-GUIDE.md` - HTML report user guide
- `SLOW-QUERIES-PER-DATABASE.md` - Per-database query grouping
- `REPORT-EXAMPLE.md` - Visual examples
- `GENERATING-HTML-REPORTS.md` - HTML generation guide

### System Requirements

- SQL Server 2019+ (Standard or Enterprise Edition)
- Windows or Linux
- SQL Server Agent enabled and running
- PowerShell 5.1+ (for deployment and HTML export)
- 500 MB disk space (initial)
- ~10 GB disk space (30 days of snapshots)

### Performance Impact

- Collection time: <20 seconds (P0+P1+P2)
- CPU overhead: <1%
- Disk I/O: Minimal (DMV queries only)
- Recommended schedule: Every 5 minutes

### Support

- GitHub Issues: (internal use - SchoolVision/ServiceVision)
- Documentation: `docs/` directory
- Troubleshooting: `docs/troubleshooting/`

---

## Roadmap (Future Versions)

**v1.1 (Planned):**
- Custom dashboard views
- Email alerts for critical issues
- Trend analysis and anomaly detection
- Query plan capture optimization

**v2.0 (Future):**
- Multi-server centralized monitoring
- Power BI/Grafana integration
- Advanced workload analysis
- Predictive capacity planning
