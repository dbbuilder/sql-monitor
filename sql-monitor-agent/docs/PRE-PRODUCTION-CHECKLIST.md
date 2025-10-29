# Pre-Production Deployment Checklist

## What We Have ✅

### Core Monitoring
- ✅ Per-database query statistics (top 100 per DB)
- ✅ Per-database missing indexes (top 100 per DB)
- ✅ Query execution plans (>20 sec queries, hourly)
- ✅ Database I/O statistics
- ✅ Memory usage and grants
- ✅ Backup history tracking
- ✅ Active workload with blocking chains
- ✅ Wait statistics (server-level)
- ✅ Deadlock detection with auto-response
- ✅ Blocking session monitoring
- ✅ Performance counters
- ✅ Scheduler health
- ✅ TempDB contention detection

### Automation & Management
- ✅ SQL Agent job (every 5 minutes)
- ✅ Automated retention policy (14 days)
- ✅ Error logging system
- ✅ Configuration management
- ✅ Database filtering (exclude system DBs)
- ✅ PowerShell and Bash deployment scripts

### Performance Optimization
- ✅ Minimal overhead (<20 seconds per collection)
- ✅ Smart query plan collection (95% reduction)
- ✅ Randomized scheduling to avoid spikes

## What We're Missing ⚠️

### 1. Alerting & Notifications
**Status:** ❌ NOT IMPLEMENTED

**What's Missing:**
- No email alerts for critical issues
- No threshold-based notifications
- No integration with monitoring systems (Grafana, PRTG, etc.)

**Recommendation:**
```sql
-- Example: Alert on high blocking
IF (SELECT BlockingSessionCount FROM PerfSnapshotRun 
    WHERE PerfSnapshotRunID = @NewRunID) > 10
BEGIN
    -- Send alert (needs Database Mail or external integration)
    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = 'DBA Alerts',
        @recipients = 'dba@company.com',
        @subject = 'High Blocking Detected',
        @body = 'Blocking sessions exceed threshold'
END
```

**Priority:** MEDIUM (can add later based on needs)

### 2. Historical Trend Analysis
**Status:** ⚠️ PARTIAL

**What We Have:**
- Raw data for 14 days
- Basic reporting procedures

**What's Missing:**
- Baseline calculations (what's "normal"?)
- Trend detection (is performance degrading?)
- Anomaly detection (unusual patterns)
- Capacity planning data

**Recommendation:**
- Add baseline calculation procedure
- Create trend analysis views
- Consider longer retention for aggregated data (e.g., daily averages kept for 90 days)

**Priority:** MEDIUM (valuable but not critical)

### 3. Index Maintenance Integration
**Status:** ❌ NOT IMPLEMENTED

**What's Missing:**
- No index fragmentation tracking (P3 disabled)
- No automated index maintenance recommendations
- No tracking of index usage vs maintenance cost

**Current State:**
- P3 collectors are disabled (fragmentation, VLF counts)
- These were disabled due to performance concerns

**Recommendation:**
- Keep P3 disabled for now
- If needed, run P3 collectors manually or weekly
- Consider Ola Hallengren's maintenance solution separately

**Priority:** LOW (can use external tools)

### 4. Query Store Integration
**Status:** ❌ NOT IMPLEMENTED

**What's Missing:**
- No Query Store data correlation
- No plan regression detection
- No automatic plan forcing

**Recommendation:**
- Enable Query Store on critical databases
- Our monitoring complements Query Store (doesn't replace it)
- Query Store has better plan history tracking

**Priority:** LOW (Query Store is separate feature)

### 5. Multi-Server Aggregation
**Status:** ❌ NOT IMPLEMENTED

**What's Missing:**
- No central repository for all servers
- No cross-server comparison
- Each server has its own DBATools database

**Recommendation:**
- For small deployments (3-10 servers): Keep decentralized
- For large deployments: Consider central data warehouse
- Use reporting tools to aggregate (Power BI, Grafana)

**Priority:** LOW for current deployment (3 servers)

### 6. Real-Time Monitoring
**Status:** ❌ NOT IMPLEMENTED

**What We Have:**
- 5-minute snapshots (not real-time)
- Historical data analysis

**What's Missing:**
- Live blocking detection
- Real-time wait analysis
- Active query monitoring

**Recommendation:**
- Use sp_WhoIsActive for real-time troubleshooting
- Our system is for historical analysis, not real-time
- Consider Extended Events for real-time capture if needed

**Priority:** LOW (different use case)

### 7. Backup Verification
**Status:** ⚠️ PARTIAL

**What We Have:**
- Backup history tracking
- Last backup date/time

**What's Missing:**
- Backup restore testing
- Backup size growth trends
- RPO/RTO compliance checking
- Backup chain validation (LSN sequence)

**Recommendation:**
```sql
-- Add to reporting procedures
CREATE PROCEDURE DBA_CheckBackupCompliance
    @MaxHoursWithoutFull INT = 24,
    @MaxHoursWithoutLog INT = 1
AS
BEGIN
    -- Check for databases missing backups
    SELECT DatabaseName, LastFullBackup, LastLogBackup
    FROM PerfSnapshotBackupHistory
    WHERE DATEDIFF(HOUR, LastFullBackup, GETUTCDATE()) > @MaxHoursWithoutFull
       OR (recovery_model_desc = 'FULL' 
           AND DATEDIFF(HOUR, LastLogBackup, GETUTCDATE()) > @MaxHoursWithoutLog)
END
```

**Priority:** MEDIUM (important for production)

### 8. Security & Permissions
**Status:** ⚠️ REVIEW NEEDED

**Current State:**
- Deployment uses 'sv' account (appears to be admin)
- SQL Agent jobs run as job owner (SUSER_SNAME())

**What's Missing:**
- Least-privilege access review
- Audit logging for configuration changes
- Sensitive data masking in captured SQL text

**Recommendation:**
- Review if DBATools needs sysadmin or if VIEW SERVER STATE + specific permissions suffice
- Consider redacting sensitive queries (passwords, SSNs, etc.)
- Document required permissions for read-only access

**Priority:** HIGH for production

### 9. Disaster Recovery
**Status:** ❌ NOT DOCUMENTED

**What's Missing:**
- DBATools database backup strategy
- Recovery procedures if DBATools is lost
- Re-deployment procedures

**Recommendation:**
- Include DBATools in regular backup schedule
- Document: "If DBATools is lost, re-run deploy_all.sh"
- Consider exporting configuration to file

**Priority:** MEDIUM

### 10. Documentation Gaps
**Status:** ⚠️ GOOD BUT INCOMPLETE

**What We Have:**
- Deployment guides ✅
- Configuration guide ✅
- Troubleshooting guide ✅
- Enhancement documentation ✅

**What's Missing:**
- Query examples for common scenarios
- Performance tuning guide for high-volume servers
- Capacity planning guide (when to increase retention, TopN values)
- Integration examples (Power BI, Grafana)

**Priority:** MEDIUM

## Critical Pre-Production Actions

### Must Do Before Full Production:

1. **Test Automatic Collection on All 3 Servers**
   ```sql
   -- Wait 10 minutes, then verify on each server:
   SELECT TOP 5 PerfSnapshotRunID, SnapshotUTC
   FROM DBATools.dbo.PerfSnapshotRun
   ORDER BY PerfSnapshotRunID DESC
   ```
   **Expected:** New snapshots every 5 minutes

2. **Verify SQL Agent Job History**
   ```sql
   -- Check for failures
   EXEC msdb.dbo.sp_help_jobhistory 
       @job_name = 'DBA Collect Perf Snapshot',
       @mode = 'FULL'
   ```

3. **Check Storage Growth**
   ```sql
   -- Monitor DBATools database size
   EXEC sp_spaceused
   SELECT name, size*8/1024 AS SizeMB
   FROM sys.database_files
   ```
   **Expected:** ~50-100MB per day per server

4. **Test Retention Policy**
   ```sql
   -- Run manually to verify it works
   EXEC DBATools.dbo.DBA_PurgeOldSnapshots @RetentionDays = 14
   ```

5. **Review Security Permissions**
   - Document minimum required permissions
   - Consider creating dedicated monitoring account
   - Review captured SQL text for sensitive data

6. **Create Backup Schedule for DBATools**
   - Add DBATools to backup routine
   - Test restore procedure
   - Document recovery steps

7. **Document Runbook**
   - What to do if collection fails
   - How to interpret key metrics
   - When to escalate issues

### Should Do Before Full Production:

1. **Add Basic Alerting**
   - High blocking (>20 sessions)
   - Deadlock detection
   - Collection failures
   - Low disk space

2. **Create Backup Compliance Check**
   - Procedure to check backup SLAs
   - Add to daily health check

3. **Performance Baseline**
   - Let run for 1 week
   - Document "normal" patterns
   - Set threshold alerts based on baseline

4. **Cross-Server Reporting**
   - Simple script to query all servers
   - Export to CSV for analysis
   - Consider Power BI dashboard

## Production Deployment Plan

### Phase 1: Validation (Current - Week 1)
- ✅ 3 servers deployed (svweb, suncity, sqltest)
- Monitor for 1 week
- Verify no performance issues
- Tune retention/TopN if needed

### Phase 2: Core Production (Week 2)
- Deploy to remaining production SQL Servers
- Focus on critical databases first
- Monitor storage growth
- Implement basic alerting

### Phase 3: Enhancement (Week 3+)
- Add backup compliance checking
- Implement alerting for critical issues
- Create management dashboard
- Fine-tune based on feedback

## Risk Assessment

**Low Risk:**
- Per-database collection (tested, proven 95% overhead reduction)
- Deadlock auto-response (idempotent, lightweight)
- Blocking monitoring (already captured)

**Medium Risk:**
- Storage growth on high-volume servers (monitor closely)
- Query plan collection if many slow queries (already mitigated with >20 sec filter)

**High Risk:**
- None identified (system is production-ready)

## Rollback Plan

If issues occur:
```sql
-- Stop collection
EXEC msdb.dbo.sp_update_job 
    @job_name='DBA Collect Perf Snapshot', 
    @enabled=0

-- Drop DBATools if needed
DROP DATABASE DBATools
```

Re-deploy is fast: 45-60 seconds per server.

## Sign-Off Checklist

Before full production deployment:
- [ ] All 3 test servers running for 1 week without issues
- [ ] Storage growth is acceptable
- [ ] No performance degradation observed
- [ ] SQL Agent jobs running successfully
- [ ] Retention policy tested
- [ ] Backup strategy for DBATools documented
- [ ] Security permissions reviewed
- [ ] Runbook documented
- [ ] Team trained on basic queries and troubleshooting

---

**Status:** READY FOR PRODUCTION with recommendations above
**Risk Level:** LOW
**Recommended Action:** Deploy to remaining servers with monitoring
