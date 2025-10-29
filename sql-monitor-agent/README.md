# SQL Server Monitoring System

Lightweight performance monitoring for SQL Server 2019+ using DMVs and Extended Events.

## Quick Start

```bash
# Deploy to a server
./deploy_all.sh

# Or use PowerShell
pwsh Deploy-MonitoringSystem.ps1 -Server "server,port" -Username "user" -Password "pass"
```

See [docs/deployment/QUICK-START.md](docs/deployment/QUICK-START.md) for full instructions.

## Features

- **Per-Database Collection**: Query stats, missing indexes, and query plans per database
- **Smart Query Plans**: Only captures plans for queries >20 seconds, runs hourly (randomized 30-60 min window)
- **Automatic Deadlock Response**: Enables trace flags 1222/1204 when deadlocks detected
- **Blocking Monitoring**: Captures blocking chains and session details
- **Minimal Overhead**: P0+P1+P2 runs every 5 minutes in <20 seconds

## Architecture

- **DBATools Database**: Contains all tables, procedures, and configuration
- **Priority Levels**: P0 (Critical), P1 (Performance), P2 (Medium), P3 (Low/Disabled)
- **SQL Agent Jobs**: Automatic collection every 5 minutes, retention purge daily
- **Retention**: 14 days by default (configurable)

## Documentation

**For Non-DBAs:**
- [📖 User Guide](docs/USER-GUIDE.md) - **START HERE!** Explains what metrics mean and what to do
- [Daily Health Checks](docs/USER-GUIDE.md#daily-health-checks) - 5-minute morning routine
- [Troubleshooting Scenarios](docs/USER-GUIDE.md#troubleshooting-scenarios) - Real-world examples

**For DBAs:**
- [Deployment Guide](docs/deployment/COMPLETE_DEPLOYMENT_GUIDE.md)
- [Configuration](docs/reference/CONFIGURATION-GUIDE.md)
- [Verification](docs/deployment/DEPLOYMENT_VERIFICATION_REPORT.md)
- [Troubleshooting](docs/troubleshooting/)
- [Pre-Production Checklist](docs/PRE-PRODUCTION-CHECKLIST.md)

## Current Deployment

Deployed to 3 servers:
- svweb (data.schoolvision.net,14333)
- suncity.schoolvision.net,14333
- sqltest.schoolvision.net,14333

## Files

**Deployment:**
- `deploy_all.sh` - Bash deployment script
- `Deploy-MonitoringSystem.ps1` - PowerShell deployment script
- `servers.txt` - Server list (gitignored)

**SQL Scripts (numbered deployment order):**
- `01_create_DBATools_and_tables.sql` - Database and schema
- `02_create_DBA_LogEntry_Insert.sql` - Logging infrastructure
- `05_create_enhanced_tables.sql` - Performance snapshot tables
- `06_create_modular_collectors_P0_FIXED.sql` - P0 collectors
- `07_create_modular_collectors_P1_FIXED.sql` - P1 collectors
- `08_create_modular_collectors_P2_P3_FIXED.sql` - P2/P3 collectors
- `10_create_master_orchestrator_FIXED.sql` - Master orchestrator
- `13_create_config_table_and_functions.sql` - Configuration system
- `13b_create_database_filter_view.sql` - Database filtering
- `14_create_reporting_procedures.sql` - Reporting procedures
- `create_agent_job.sql` - SQL Agent collection job
- `create_retention_job.sql` - SQL Agent retention job
- `create_retention_policy.sql` - Retention policy procedure

**Testing:**
- `test-all-collectors.sh` - Test all collectors
- `99_QUICK_VALIDATE.sql` - Quick validation queries
- `99_TEST_AND_VALIDATE.sql` - Comprehensive validation

**Diagnostics:**
- `DIAGNOSE_PROCEDURE_TIMEOUTS.sql` - Identify procedures at risk of timeout (with microsecond fix)
- `ADJUST_COLLECTION_SCHEDULE.sql` - Modify SQL Agent job schedules to reduce overhead
- `DIAGNOSE_COLLECTORS.sql` - Troubleshoot collector execution issues

**Timeout Investigation Rescue Kit:**
- `TIMEOUT_RESCUE_KIT.sql` - 📊 **Comprehensive post-mortem analysis** (10 diagnostic sections)
- `CREATE_TIMEOUT_TRACKING_XE.sql` - 🔍 Set up Extended Events for real-time timeout tracking
- `TIMEOUT_INVESTIGATION_CHEATSHEET.md` - 📖 Quick reference guide and decision tree
- See [TIMEOUT_INVESTIGATION_CHEATSHEET.md](TIMEOUT_INVESTIGATION_CHEATSHEET.md) for workflow examples

## Recent Enhancements

**Timeout Investigation Rescue Kit** (Oct 29, 2025):
- 📊 **TIMEOUT_RESCUE_KIT.sql** - Comprehensive 10-section post-mortem analysis
  - Attention events (client-side timeouts)
  - Long-running queries from snapshots
  - Blocking chains (what was blocking what)
  - Wait statistics (resource bottlenecks)
  - Query Store plan regressions
  - DMV cache slow queries
  - Error log analysis
  - Deadlock correlation
  - Server resource pressure
  - Memory pressure indicators
- 🔍 **CREATE_TIMEOUT_TRACKING_XE.sql** - Extended Events session for proactive timeout tracking
  - Captures timeout events automatically
  - Includes full SQL text and execution context
  - Minimal overhead (<1%)
  - Persistent across SQL Server restarts
- 📖 **TIMEOUT_INVESTIGATION_CHEATSHEET.md** - Quick reference guide
  - Decision tree for root cause identification
  - Common timeout patterns with solutions
  - Sample investigation workflows
  - Quick commands reference

**Timeout Detection Bug Fix** (Oct 29, 2025):
- Fixed microsecond-to-millisecond conversion bug in timeout diagnostic query
- All DBATools procedures running well under 30-second threshold (1-5 seconds actual)
- Added `DIAGNOSE_PROCEDURE_TIMEOUTS.sql` with proper unit conversion
- Added `ADJUST_COLLECTION_SCHEDULE.sql` for performance tuning
- See `TIMEOUT-DETECTION-FIX-2025-10-29.md` for details

**Per-Database Collection** (Oct 27, 2025):
- Query stats: 2467 rows vs 100 (24x increase)
- Missing indexes: 391 rows vs 100 (4x increase)
- Ensures small databases get representation

**Query Plan Optimization**:
- Only captures plans for queries >20 seconds average elapsed time
- Runs every 30-60 minutes (randomized to avoid spikes)
- 95% reduction in query plan overhead

**Automatic Deadlock Response**:
- Enables trace flags 1222/1204 when deadlocks detected
- Provides detailed logging to SQL Server error log

## License

Internal use - SchoolVision/ServiceVision
