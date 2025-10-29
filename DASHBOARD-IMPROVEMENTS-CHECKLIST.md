# Dashboard Improvements Checklist

**Created**: 2025-10-29
**Status**: In Progress

---

## 📊 Detailed Metrics & Stats Views

- [x] **Add time interval selector** (1min, 5min, 15min, 30min, 1hr, 3hr, 6hr, 12hr, 24hr)
  - ✅ Added to `detailed-metrics.json`
  - ✅ TimeInterval variable with 9 options
  - ✅ Time series queries use dynamic bucketing
  - **Status**: COMPLETE

- [ ] **Make it easy to see multiple metrics over time**
  - ⏳ Need to add metric comparison feature
  - ⏳ Consider multi-metric overlay or separate panels
  - **Status**: PENDING

---

## 🗂️ Dashboard Organization

- [ ] **Categorize dashboards by type** (stats, code, etc.)
  - ⏳ Create folder structure in Grafana
  - ⏳ Update provisioning configuration
  - ⏳ Categories: Stats, Code, Performance, Security, Overview
  - **Status**: PENDING

- [x] **Hide initial Grafana page (show landing page instead)**
  - ✅ Added `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH` to docker-compose.yml
  - ✅ Documented in GRAFANA-DATA-SETUP.md (4 methods)
  - ✅ Set to `/var/lib/grafana/dashboards/00-landing-page.json`
  - **Status**: COMPLETE (requires Grafana restart)

---

## 🔍 Search & Filtering

- [x] **Add search box to Performance Analysis**
  - ✅ Added `SearchFilter` textbox variable
  - ✅ Filters ObjectName and DatabaseName
  - ✅ Applied to all 4 panels
  - **Status**: COMPLETE

---

## 🚫 Database Exclusions

- [x] **Remove MonitoringDB and DBATools from all dashboards**
  - ✅ Query Store (06-query-store.json)
  - ✅ Performance Analysis (05-performance-analysis.json)
  - ✅ Detailed Metrics (detailed-metrics.json)
  - [ ] SQL Server Overview (sql-server-overview.json)
  - [ ] Table Browser (01-table-browser.json) - Already has exclusion
  - [ ] Code Browser (03-code-browser.json) - Already has exclusion
  - [ ] Table Details (02-table-details.json)
  - [ ] Audit Logging (07-audit-logging.json)
  - **Status**: 3 of 8 COMPLETE

- [ ] **Add config option to customize excluded databases**
  - ⏳ Create dashboard variable for excluded databases
  - ⏳ Update all queries to reference variable
  - ⏳ Add to deployment config template
  - **Status**: PENDING

---

## 📈 Query Store

- [x] **Fix Query Store data collection**
  - ✅ Identified issue: Dashboard used `QueryStoreSnapshots` (doesn't exist)
  - ✅ Updated to use `QueryMetrics` table (800 records)
  - ✅ Fixed all column names and data types
  - ✅ Added server filtering
  - ✅ Added system database exclusion
  - **Status**: COMPLETE

---

## 🖥️ Server Filtering

- [x] **Add server filters to all dashboard panels**
  - ✅ Query Store (06-query-store.json)
  - ✅ Performance Analysis (05-performance-analysis.json)
  - ✅ Detailed Metrics (detailed-metrics.json) - Already had it
  - [ ] SQL Server Overview (sql-server-overview.json)
  - [ ] Table Browser (01-table-browser.json) - Need to verify
  - [ ] Code Browser (03-code-browser.json) - Need to verify
  - [ ] Table Details (02-table-details.json)
  - [ ] Audit Logging (07-audit-logging.json)
  - **Status**: 3 of 8 COMPLETE

- [x] **Show server name as column in multi-server views**
  - ✅ Query Store tables show ServerName
  - ✅ Performance Analysis shows ServerName
  - ✅ Detailed Metrics shows ServerName
  - **Status**: COMPLETE (for updated dashboards)

---

## 🎨 Branding

- [x] **Change "Powered by ArcTrade Technology" to "ArcTrade"**
  - ✅ Updated landing page header
  - ✅ Updated landing page footer
  - ✅ Fixed copyright to "ArcTrade" (capital T)
  - **Status**: COMPLETE

- [ ] **Add a panel for each** (clarification needed)
  - ❓ Unclear requirement - separate panel for what?
  - ❓ Need user clarification
  - **Status**: NEEDS CLARIFICATION

---

## 💡 Insights Dashboard

- [ ] **Create Insights tab with 24h prioritized takeaways**
  - ⏳ Create new dashboard: `08-insights.json`
  - ⏳ Design insight detection queries:
    - Top 5 slowest queries (24h)
    - Blocking incidents
    - Error log entries
    - Resource bottlenecks (CPU, Memory, IO)
    - Index fragmentation issues
    - Plan regressions
  - ⏳ Add scoring/prioritization logic
  - ⏳ Group by server
  - ⏳ Add markdown panels for action recommendations
  - **Status**: NOT STARTED

---

## 🔗 Object Code Hyperlinks

- [ ] **Make object code viewable by hyperlink**
  - ⏳ Identify all locations where object names appear:
    - Performance Analysis (procedure names)
    - Query Store (queries)
    - Code Browser (procedures, functions, views)
    - Table Details (table names)
  - ⏳ Add data links in Grafana panels:
    ```json
    {
      "dataLinks": [{
        "title": "View Code",
        "url": "/d/code-browser?var-DatabaseName=${__data.fields.DatabaseName}&var-ObjectName=${__data.fields.ObjectName}"
      }]
    }
    ```
  - ⏳ Update Code Browser to accept URL parameters
  - ⏳ Add code preview panel that auto-populates
  - **Status**: NOT STARTED

---

## 📊 Progress Summary

| Category | Complete | In Progress | Pending | Total |
|----------|----------|-------------|---------|-------|
| **Metrics & Stats** | 1 | 0 | 1 | 2 |
| **Organization** | 1 | 0 | 1 | 2 |
| **Search & Filtering** | 1 | 0 | 0 | 1 |
| **Database Exclusions** | 3/8 | 5/8 | 1 | 2 |
| **Query Store** | 1 | 0 | 0 | 1 |
| **Server Filtering** | 3/8 | 5/8 | 0 | 1 |
| **Branding** | 1 | 0 | 1 | 2 |
| **Insights Dashboard** | 0 | 0 | 1 | 1 |
| **Object Hyperlinks** | 0 | 0 | 1 | 1 |
| **TOTAL** | **8** | **0** | **6** | **14** |

**Overall Progress**: 8/14 complete (57%)

---

## 🚀 Next Steps (Priority Order)

1. ✅ ~~Fix Query Store data~~ - COMPLETE
2. ✅ ~~Add search to Performance Analysis~~ - COMPLETE
3. ✅ ~~Add time intervals to Detailed Metrics~~ - COMPLETE
4. 🔄 **Finish server filtering** (5 remaining dashboards)
5. 🔄 **Finish database exclusions** (5 remaining dashboards)
6. 🆕 **Create Insights dashboard** (new dashboard)
7. 🆕 **Add object code hyperlinks** (all dashboards)
8. 🆕 **Categorize dashboards** (Grafana folders)
9. 🆕 **Add configurable exclusion list**

---

## 📝 Notes

- **Grafana Restart Required**: Changes to docker-compose.yml (home page setting) require restart
- **Data Collection**: QueryMetrics table has 800 records, ProcedureMetrics has 268 records
- **System Databases**: Currently hardcoded exclusion list - should be configurable
- **Multi-Server Support**: All updated dashboards now support multi-server environments

---

**Last Updated**: 2025-10-29
**Updated By**: Claude Code
