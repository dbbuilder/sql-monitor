# Database Filter System

## Overview

The monitoring system now includes a **centralized database filtering mechanism** that allows you to include/exclude specific databases from monitoring using configurable patterns.

---

## Key Benefits

1. **Prevents self-monitoring** - Excludes DBATools database by default
2. **Reduces overhead** - Focus monitoring on production databases only
3. **Flexible patterns** - Use wildcards (* and ?) to match multiple databases
4. **Centralized control** - One configuration affects all collectors
5. **Safe filtering** - Automatically excludes system databases and offline databases

---

## Architecture

### Components

1. **Configuration Table** (`MonitoringConfig`)
   - `DatabaseIncludeFilter` - Semicolon-separated list of patterns to include
   - `DatabaseExcludeFilter` - Semicolon-separated list of patterns to exclude

2. **Helper Functions**
   - `fn_DatabaseMatchesPattern` - Matches database name against wildcard pattern
   - `fn_ShouldMonitorDatabase` - Determines if database should be monitored

3. **Centralized View** (`vw_MonitoredDatabases`)
   - Returns only databases that should be monitored
   - Applies include/exclude filters
   - Filters for ONLINE state
   - Excludes system databases (master, tempdb, model, msdb)

4. **Updated Collectors**
   - All collectors now use `vw_MonitoredDatabases` instead of `sys.databases`
   - No more duplicate filtering logic in each collector

---

## Default Configuration

```sql
DatabaseIncludeFilter = '*'         -- Include all databases
DatabaseExcludeFilter = 'DBATools'  -- Exclude monitoring database itself
```

**Result**: Monitors all user databases except DBATools, system databases, and offline databases.

---

## Pattern Syntax

### Wildcards

| Pattern | Meaning | Example | Matches |
|---------|---------|---------|---------|
| `*` | Match any characters | `Prod*` | ProdDB, Production, Prod2024 |
| `?` | Match single character | `DB?` | DB1, DB2, DBX |
| Exact | Exact match | `MyDatabase` | Only MyDatabase |

### Multiple Patterns

Use semicolon (`;`) to separate multiple patterns:

```sql
-- Include multiple production databases
DatabaseIncludeFilter = 'Prod*;Production*;Live*'

-- Exclude test and dev databases
DatabaseExcludeFilter = 'Test*;Dev*;Staging*'
```

---

## Common Use Cases

### Use Case 1: Monitor Only Production Databases

```sql
-- Include only databases starting with "Prod" or "Production"
EXEC DBA_UpdateConfig 'DatabaseIncludeFilter', 'Prod*;Production*'

-- Exclude DBATools
EXEC DBA_UpdateConfig 'DatabaseExcludeFilter', 'DBATools'
```

**Result**: Only Prod*, Production* databases monitored

---

### Use Case 2: Exclude Test and Development Databases

```sql
-- Include all databases
EXEC DBA_UpdateConfig 'DatabaseIncludeFilter', '*'

-- Exclude test, dev, staging, and DBATools
EXEC DBA_UpdateConfig 'DatabaseExcludeFilter', 'Test*;Dev*;Staging*;DBATools'
```

**Result**: All databases except Test*, Dev*, Staging*, DBATools

---

### Use Case 3: Monitor Specific Databases Only

```sql
-- Include only specific databases
EXEC DBA_UpdateConfig 'DatabaseIncludeFilter', 'CustomerDB;OrderDB;InventoryDB'

-- Clear exclude filter
EXEC DBA_UpdateConfig 'DatabaseExcludeFilter', ''
```

**Result**: Only CustomerDB, OrderDB, InventoryDB monitored

---

### Use Case 4: Monitor Everything (Default)

```sql
-- Reset to default
EXEC DBA_ResetConfig 'DatabaseIncludeFilter'
EXEC DBA_ResetConfig 'DatabaseExcludeFilter'
```

**Result**: All user databases monitored except DBATools

---

## Testing Filters

### Check Current Configuration

```sql
EXEC DBA_TestDatabaseFilters
```

**Output**:
- Current filter configuration
- All databases with "Will Monitor" status
- List of databases that will be monitored

---

### Example Output

```
=== Current Database Filter Configuration ===

ConfigKey                   ConfigValue       ConfigDescription
--------------------------- ----------------- ----------------------------------------
DatabaseIncludeFilter       *                 Include all databases
DatabaseExcludeFilter       DBATools;Test*    Exclude DBATools and test databases

=== All Databases ===

database_id  name            state_desc  WillMonitor
------------ --------------- ----------- -----------
5            ProductionDB    ONLINE      YES
6            TestDB          ONLINE      NO
7            DevDB           ONLINE      NO
8            DBATools        ONLINE      NO
9            CustomerDB      ONLINE      YES

=== Databases That Will Be Monitored ===

database_id  database_name   state_desc  recovery_model_desc
------------ --------------- ----------- -------------------
5            ProductionDB    ONLINE      FULL
9            CustomerDB      ONLINE      FULL
```

---

## Using the View in Queries

### Query Monitored Databases

```sql
SELECT * FROM dbo.vw_MonitoredDatabases
```

**Returns**: Only databases that pass all filters (ONLINE, not system, not excluded)

---

### Check Specific Database

```sql
SELECT dbo.fn_ShouldMonitorDatabase('MyDatabase') AS ShouldMonitor
-- Returns: 1 (yes) or 0 (no)
```

---

## How Filtering Works

### Filter Logic Flow

1. **Start with sys.databases**
2. **Filter for ONLINE state** (exclude OFFLINE, RESTORING, RECOVERING, etc.)
3. **Filter for user databases** (exclude master, tempdb, model, msdb)
4. **Apply include filter**
   - Check if database name matches any include pattern
   - If no match, database is excluded
5. **Apply exclude filter** (only if included)
   - Check if database name matches any exclude pattern
   - If match, database is excluded
6. **Result**: Database passes all filters and will be monitored

---

## Impact on Collectors

### Before (Old Approach)

Each collector had duplicate filtering logic:

```sql
-- Backup collector
FROM sys.databases d
WHERE d.database_id > 4
  AND d.state_desc = 'ONLINE'

-- VLF collector
FROM sys.databases d
WHERE d.database_id > 4
  AND d.state_desc = 'ONLINE'

-- Orchestrator
FROM sys.databases d
WHERE d.database_id > 4
```

**Problems**:
- Duplicate code in 4+ places
- Inconsistent filtering
- Can't easily exclude specific databases
- Risk of missing filters (caused hang on offline databases)

---

### After (New Approach)

All collectors use centralized view:

```sql
-- All collectors now use this
FROM dbo.vw_MonitoredDatabases md
```

**Benefits**:
- Single source of truth
- Consistent filtering across all collectors
- Easy to add/remove databases from monitoring
- Centralized configuration

---

## Files Modified

### New File

- **13b_create_database_filter_view.sql** - Database filter system

### Modified Files

1. **06_create_modular_collectors_P0_FIXED.sql**
   - Backup history collector now uses `vw_MonitoredDatabases`

2. **08_create_modular_collectors_P2_P3_FIXED.sql**
   - VLF collector now uses `vw_MonitoredDatabases`

3. **10_create_master_orchestrator_FIXED.sql**
   - Database stats collection now uses `vw_MonitoredDatabases`

4. **Deploy-MonitoringSystem.ps1**
   - Added step 4: Database filter view deployment

---

## Performance Impact

### Minimal Overhead

- View is simple and efficient
- No additional table scans
- Filter logic runs once per collection
- Negligible performance impact (< 1ms)

### Reduced Overhead

- Excludes unnecessary databases from monitoring
- Reduces data collection volume
- Less storage usage
- Faster queries (fewer databases to process)

---

## Troubleshooting

### Problem: Databases Not Being Monitored

**Check configuration**:
```sql
EXEC DBA_TestDatabaseFilters
```

**Common causes**:
- Database excluded by pattern
- Database is OFFLINE or RESTORING
- Database name doesn't match include filter

**Fix**:
```sql
-- Check if database matches include pattern
SELECT dbo.fn_DatabaseMatchesPattern('MyDatabase', 'Prod*')  -- 1 = match, 0 = no match

-- Check if database should be monitored
SELECT dbo.fn_ShouldMonitorDatabase('MyDatabase')  -- 1 = yes, 0 = no

-- Adjust filters
EXEC DBA_UpdateConfig 'DatabaseIncludeFilter', '*'
EXEC DBA_UpdateConfig 'DatabaseExcludeFilter', 'DBATools'
```

---

### Problem: Too Many Databases Being Monitored

**Narrow the filter**:
```sql
-- Include only production databases
EXEC DBA_UpdateConfig 'DatabaseIncludeFilter', 'Prod*;Production*'
```

---

### Problem: Need to Monitor Specific Databases

**Use exact names**:
```sql
EXEC DBA_UpdateConfig 'DatabaseIncludeFilter', 'DB1;DB2;DB3;ProductionDB'
EXEC DBA_UpdateConfig 'DatabaseExcludeFilter', ''
```

---

## Summary

**The database filter system provides**:
- Centralized control over which databases are monitored
- Flexible wildcard pattern matching
- Prevention of self-monitoring (DBATools excluded by default)
- Consistent filtering across all collectors
- Easy testing and troubleshooting

**To use it**:
1. Configure include/exclude patterns via `DBA_UpdateConfig`
2. Test with `EXEC DBA_TestDatabaseFilters`
3. All collectors automatically respect the filters
4. Adjust as needed for your environment

**Default behavior**: Monitors all user databases except DBATools, system databases, and offline databases.
