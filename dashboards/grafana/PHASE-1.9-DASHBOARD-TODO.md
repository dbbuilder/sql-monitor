# Phase 1.9 Dashboard Consolidation - TODO

**Date**: 2025-10-28
**Status**: ⚠️ In Progress - Requires Completion

## Current Status

### ✅ Completed
- [x] Merged dashboard sources from two locations into unified directory
- [x] Fixed Docker volume mount conflict in docker-compose.yml
- [x] Updated dashboards.yaml provisioning config
- [x] All 7 dashboards now in: `dashboards/grafana/dashboards/`

### ⏳ Pending Completion

#### 1. Verify All Dashboards Work
- [ ] Test **SQL Server Overview** dashboard
  - Verify connection to MonitoringDB datasource
  - Check all panels load data
  - Validate queries execute without errors

- [ ] Test **Detailed Metrics** dashboard
  - CPU metrics panel
  - Memory metrics panel
  - I/O metrics panel
  - Session counts panel

- [ ] Test **Performance Analysis** dashboard
  - Top queries by CPU
  - Top queries by duration
  - Top queries by reads
  - Query execution trends

#### 2. Rename Dashboards for Consistency

Currently mixed naming conventions:
```
✅ 01-table-browser.json        (numbered, kebab-case)
✅ 02-table-details.json         (numbered, kebab-case)
✅ 03-code-browser.json          (numbered, kebab-case)
❓ 05-performance-analysis.json  (numbered, kebab-case) ← gap in numbering
✅ 07-audit-logging.json         (numbered, kebab-case)
❌ detailed-metrics.json         (no number, kebab-case)
❌ sql-server-overview.json      (no number, kebab-case)
```

**Proposed Renaming:**
```bash
# Phase 1.9 Core Monitoring Dashboards
detailed-metrics.json       → 04-detailed-metrics.json
sql-server-overview.json    → 06-server-overview.json
# Keep: 05-performance-analysis.json (already numbered)
```

#### 3. Create Missing Phase 1.9 Dashboards

According to CLAUDE.md, Phase 1.9 should have these dashboards:

**Missing:**
- [ ] `01-instance-health.json` - Overview of all servers (health status, CPU, memory, sessions)
- [ ] `02-developer-procedures.json` - Stored procedure performance (execution counts, avg duration, CPU)
- [ ] `03-dba-waits.json` - Wait statistics analysis (top waits, wait categories, trends)
- [ ] `04-blocking-deadlocks.json` - Real-time blocking chains, deadlock graphs
- [ ] `05-query-store.json` - Plan regressions, query performance (RENAME from 05-performance-analysis.json?)
- [ ] `06-capacity-planning.json` - Growth trends, resource forecasting

**Existing (from other phases):**
- 01-table-browser.json (Phase 1.25)
- 02-table-details.json (Phase 1.25)
- 03-code-browser.json (Phase 1.25)
- 07-audit-logging.json (Phase 2.0)

#### 4. Dashboard Organization Strategy

**Option A: Separate by Phase** (Recommended)
```
dashboards/grafana/dashboards/
├── phase-1.25/
│   ├── 01-table-browser.json
│   ├── 02-table-details.json
│   └── 03-code-browser.json
├── phase-1.9/
│   ├── 01-instance-health.json
│   ├── 02-developer-procedures.json
│   ├── 03-dba-waits.json
│   ├── 04-blocking-deadlocks.json
│   ├── 05-query-store.json
│   └── 06-capacity-planning.json
└── phase-2.0/
    └── 01-audit-logging.json
```

**Option B: Flat with Prefixes**
```
dashboards/grafana/dashboards/
├── phase1.25-01-table-browser.json
├── phase1.25-02-table-details.json
├── phase1.25-03-code-browser.json
├── phase1.9-01-instance-health.json
├── phase1.9-02-developer-procedures.json
├── ...
└── phase2.0-01-audit-logging.json
```

**Option C: Keep Flat, Number by Feature** (Current)
```
Continue with 01-99 numbering regardless of phase
```

**Decision Needed:** Choose organization strategy before finalizing Phase 1.9.

#### 5. Update Documentation

- [ ] Update `DASHBOARD-QUICKSTART.md` with all dashboard descriptions
- [ ] Update `GRAFANA-DASHBOARDS-GUIDE.md` with Phase 1.9 dashboards
- [ ] Create dashboard screenshots for documentation
- [ ] Document query patterns used in each dashboard
- [ ] Create troubleshooting guide for dashboard issues

#### 6. Data Requirements

Ensure stored procedures exist for all dashboard queries:
- [ ] `usp_GetServerHealthStatus` (exists - Days 4-5)
- [ ] `usp_GetTopQueries` (exists - Days 4-5)
- [ ] `usp_GetResourceTrends` (exists - Days 4-5)
- [ ] `usp_GetDatabaseSummary` (exists - Days 4-5)
- [ ] `usp_GetWaitStats` (missing? - check)
- [ ] `usp_GetBlockingChains` (missing? - check)
- [ ] `usp_GetDeadlockGraphs` (missing? - check)

#### 7. Cleanup Old Locations

After verifying dashboards work:
- [ ] Remove `/grafana/dashboards/` directory (deprecated location)
- [ ] Remove `/grafana/provisioning/` if it exists
- [ ] Update any documentation referencing old paths

## Commands

### Restart Grafana to Pick Up Changes
```bash
docker-compose restart grafana
```

### Verify Dashboards Loaded
```bash
curl -s -u admin:Admin123! http://localhost:3000/api/search?type=dash-db | \
  python3 -m json.tool | grep -E "title|uid"
```

### Test Datasource Connection
```bash
curl -s -u admin:Admin123! http://localhost:3000/api/datasources | \
  python3 -m json.tool | grep -E "name|type|url"
```

## Timeline

- **Start**: 2025-10-28 (dashboard sources merged)
- **Target Completion**: Before Phase 1.9 final delivery
- **Estimated Effort**: 4-6 hours
  - Dashboard creation: 3-4 hours
  - Testing: 1 hour
  - Documentation: 1 hour

## Notes

- Grafana provisioning checks for new dashboards every 10 seconds (`updateIntervalSeconds: 10`)
- Dashboards are mounted read-only (`:ro`) to prevent accidental edits in Grafana UI
- Dashboard JSON files must be valid JSON (use `jq` to validate)
- Dashboard UIDs must be unique across all dashboards
- All dashboards should use the `MonitoringDB` datasource (provisioned automatically)

## References

- CLAUDE.md (Architecture and patterns)
- docs/phases/PHASE-01.9-DAYS-6-7-COMPLETE.md (API and stored procedures)
- dashboards/grafana/provisioning/dashboards/dashboards.yaml (Provisioning config)
- docker-compose.yml (Volume mounts)
