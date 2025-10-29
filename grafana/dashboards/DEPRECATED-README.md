# DEPRECATED DASHBOARD LOCATION

⚠️ **This directory is deprecated and should not be used.**

## New Location

All Grafana dashboards have been moved to:
```
/mnt/d/dev2/sql-monitor/dashboards/grafana/dashboards/
```

## Migration Complete

The following dashboards were migrated on 2025-10-28:
- ✅ sql-server-overview.json → Unified location
- ✅ detailed-metrics.json → Unified location
- ✅ 05-performance-analysis.json → Unified location

## Why the Change?

To consolidate all Grafana-related configuration into a single location:
```
dashboards/grafana/
├── provisioning/
│   ├── datasources/     # Datasource configs
│   └── dashboards/      # Provisioning configs
└── dashboards/          # Dashboard JSON files (UNIFIED)
```

## TODO: Cleanup

This directory can be safely removed after verifying all dashboards work in the new location.

```bash
# Verify dashboards are working in Grafana first!
# Then remove this directory:
rm -rf /mnt/d/dev2/sql-monitor/grafana/
```
