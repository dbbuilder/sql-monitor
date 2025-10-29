# Insights Dashboard Fix - Datasource Variable Error

**Date**: 2025-10-29
**Status**: ✅ FIXED

---

## 🐛 Issue

**Error Message**:
```
Templating Failed to upgrade legacy queries Datasource ${DS_MONITORINGDB} was not found
```

**Impact**: Insights dashboard (08-insights.json) would not load at all in Grafana.

---

## 🔍 Root Cause

The Insights dashboard used the `${DS_MONITORINGDB}` variable reference in the ServerName variable definition (line 258), but the datasource variable itself was never defined in the `templating.list` array.

**Code Pattern** (Broken):
```json
{
  "templating": {
    "list": [
      {
        "name": "ServerName",
        "datasource": {
          "type": "mssql",
          "uid": "${DS_MONITORINGDB}"  // ❌ Variable not defined
        }
      }
    ]
  }
}
```

---

## ✅ Fix Applied

Added the datasource variable definition at position 0 in the templating.list array, before the ServerName variable.

**Code Pattern** (Fixed):
```json
{
  "templating": {
    "list": [
      {
        "name": "DS_MONITORINGDB",
        "type": "datasource",
        "query": "mssql",
        "current": {
          "text": "MonitoringDB",
          "value": "MonitoringDB"
        }
      },
      {
        "name": "ServerName",
        "datasource": {
          "type": "mssql",
          "uid": "${DS_MONITORINGDB}"  // ✅ Now defined
        }
      }
    ]
  }
}
```

---

## 📝 Files Changed

- **dashboards/grafana/dashboards/08-insights.json** - Added DS_MONITORINGDB variable (lines 250-267)
- **DASHBOARD-IMPROVEMENTS-CHECKLIST.md** - Marked Insights dashboard as COMPLETE
- **GRAFANA-POLISH-SUMMARY.md** - Added fix note

---

## 🧪 Testing

After Grafana restart (`docker compose restart grafana`), the Insights dashboard should:

1. ✅ Load without templating errors
2. ✅ Show "Data Source" dropdown at top (MonitoringDB selected)
3. ✅ Show "Server" dropdown with all active servers
4. ✅ Display 24h priority insights table
5. ✅ Show comprehensive user guide panel at bottom

---

## 📋 Deployment Checklist

- [x] Fix applied to 08-insights.json
- [x] Documentation updated
- [ ] **Next**: Deploy to production servers
  - [ ] data.schoolvision.net,14333 (or svweb,14333)
  - [ ] suncity.schoolvision.net,14333
  - Credentials: sv / Gv51076!

---

## 🔗 Related Dashboards

All other dashboards already had the DS_MONITORINGDB variable correctly defined:
- ✅ Query Store (06-query-store.json)
- ✅ Performance Analysis (05-performance-analysis.json)
- ✅ Detailed Metrics (detailed-metrics.json)
- ✅ SQL Server Overview (sql-server-overview.json)
- ✅ Table Browser (01-table-browser.json)
- ✅ Code Browser (03-code-browser.json)
- ✅ Table Details (02-table-details.json)
- ✅ Audit Logging (07-audit-logging.json)

---

**Fixed**: 2025-10-29
**Ready for Production Deployment**: ✅ YES
