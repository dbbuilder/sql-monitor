# SQL Server Monitoring System - Configuration Guide

**Last Updated:** October 27, 2025

---

## Overview

The monitoring system uses a centralized configuration table (`MonitoringConfig`) to manage all settings, including:
- Timezone preferences (UTC storage, Eastern reporting)
- Data retention policies
- Collection intervals and priorities
- Alert thresholds
- Top-N limits for various collectors

---

## Quick Start

### View Current Configuration
```sql
-- View all settings
EXEC DBATools.dbo.DBA_ViewConfig

-- View specific setting
EXEC DBATools.dbo.DBA_ViewConfig 'ReportingTimeZone'
```

### Update Configuration
```sql
-- Change retention from 30 to 60 days
EXEC DBATools.dbo.DBA_UpdateConfig 'RetentionDays', '60'

-- Change timezone to Pacific
EXEC DBATools.dbo.DBA_UpdateConfig 'ReportingTimeZone', 'Pacific Standard Time'

-- Adjust backup warning threshold
EXEC DBATools.dbo.DBA_UpdateConfig 'BackupWarningHours', '12'
```

### Reset to Defaults
```sql
-- Reset single setting
EXEC DBATools.dbo.DBA_ResetConfig 'RetentionDays'

-- Reset all settings
EXEC DBATools.dbo.DBA_ResetConfig @ResetAll = 1
```

---

## Timezone Configuration

### How It Works

**Storage:** All timestamps stored in **UTC** in the database
**Reporting:** Views with `_ET` suffix convert to configured timezone (default: Eastern)

### Available Timezones

Common SQL Server timezone names:
- `Eastern Standard Time` (Default - handles EST/EDT automatically)
- `Central Standard Time`
- `Mountain Standard Time`
- `Pacific Standard Time`
- `UTC` (No conversion)

**View all available timezones:**
```sql
SELECT name, current_utc_offset, is_currently_dst
FROM sys.time_zone_info
ORDER BY name
```

### Timezone Views

All reporting views have two versions:

**UTC Version (Original):**
- `vw_LatestSnapshotSummary` - Times in UTC
- `vw_BackupRiskAssessment` - Times in UTC
- `vw_IOLatencyHotspots` - Times in UTC

**Local Time Version (Eastern by default):**
- `vw_LatestSnapshotSummary_ET` - Times in configured timezone
- `vw_BackupRiskAssessment_ET` - Times in configured timezone
- `vw_IOLatencyHotspots_ET` - Times in configured timezone

**Example:**
```sql
-- View latest snapshot in Eastern Time
SELECT
    SnapshotLocalTime,    -- Displays in Eastern (default)
    TimeZoneAbbr,         -- Shows EST or EDT
    SnapshotUTC,          -- Original UTC time
    PageLifeExpectancy,
    MemoryPressureStatus  -- Uses config thresholds
FROM DBATools.dbo.vw_LatestSnapshotSummary_ET
```

### Manual Timezone Conversion

```sql
-- Convert UTC to Eastern Time
SELECT dbo.fn_ConvertToReportingTime('2025-10-27 12:00:00') AS EasternTime

-- Convert Eastern Time to UTC
SELECT dbo.fn_ConvertToUTC('2025-10-27 08:00:00') AS UTCTime
```

---

## Configuration Categories

### 1. Timezone & Reporting

| Key | Default | Description |
|-----|---------|-------------|
| `ReportingTimeZone` | `Eastern Standard Time` | Timezone for all reporting views |

**Example:**
```sql
-- Switch to Central Time
EXEC DBA_UpdateConfig 'ReportingTimeZone', 'Central Standard Time'
```

---

### 2. Data Retention

| Key | Default | Description |
|-----|---------|-------------|
| `RetentionDays` | `30` | Days to keep snapshot data before purging |
| `CollectionIntervalMinutes` | `5` | Snapshot collection frequency |

**Example:**
```sql
-- Keep data for 90 days
EXEC DBA_UpdateConfig 'RetentionDays', '90'

-- Collect every 15 minutes instead of 5
EXEC DBA_UpdateConfig 'CollectionIntervalMinutes', '15'
```

---

### 3. Collection Priorities

| Key | Default | Description |
|-----|---------|-------------|
| `EnableP0Collection` | `1` | Enable P0 (Critical) - Query stats, I/O, Memory, Backups |
| `EnableP1Collection` | `1` | Enable P1 (High) - Indexes, Waits, TempDB, Plans |
| `EnableP2Collection` | `1` | Enable P2 (Medium) - Config, VLF, Deadlocks, Schedulers |
| `EnableP3Collection` | `0` | Enable P3 (Low) - Latches, Job history, Spinlocks |

**Example:**
```sql
-- Disable P2 to reduce storage
EXEC DBA_UpdateConfig 'EnableP2Collection', '0'

-- Enable P3 for advanced troubleshooting
EXEC DBA_UpdateConfig 'EnableP3Collection', '1'
```

**Note:** These settings are read by the master orchestrator:
```sql
EXEC DBA_CollectPerformanceSnapshot
    @IncludeP0 = dbo.fn_GetConfigBit('EnableP0Collection'),
    @IncludeP1 = dbo.fn_GetConfigBit('EnableP1Collection'),
    @IncludeP2 = dbo.fn_GetConfigBit('EnableP2Collection'),
    @IncludeP3 = dbo.fn_GetConfigBit('EnableP3Collection')
```

---

### 4. Collection Limits (Top-N)

| Key | Default | Description |
|-----|---------|-------------|
| `QueryStatsTopN` | `100` | Number of top queries to capture |
| `QueryPlansTopN` | `30` | Number of query plans to capture |
| `MissingIndexTopN` | `100` | Missing index recommendations to capture |
| `WaitStatsTopN` | `100` | Wait types to capture |

**Example:**
```sql
-- Capture top 200 queries instead of 100
EXEC DBA_UpdateConfig 'QueryStatsTopN', '200'

-- Reduce query plans to save storage
EXEC DBA_UpdateConfig 'QueryPlansTopN', '10'
```

---

### 5. Backup Alert Thresholds

| Key | Default | Description |
|-----|---------|-------------|
| `BackupWarningHours` | `24` | Hours since full backup = WARNING |
| `BackupCriticalHours` | `48` | Hours since full backup = CRITICAL |
| `LogBackupWarningMinutes` | `60` | Minutes since log backup = WARNING (FULL recovery) |

**Example:**
```sql
-- More aggressive backup alerting
EXEC DBA_UpdateConfig 'BackupWarningHours', '12'
EXEC DBA_UpdateConfig 'BackupCriticalHours', '24'
EXEC DBA_UpdateConfig 'LogBackupWarningMinutes', '30'
```

---

### 6. Memory Pressure Thresholds

| Key | Default | Description |
|-----|---------|-------------|
| `PageLifeExpectancyWarning` | `500` | PLE threshold for WARNING (seconds) |
| `PageLifeExpectancyCritical` | `300` | PLE threshold for CRITICAL (seconds) |
| `BufferCacheHitRatioWarning` | `95` | Buffer cache hit % for WARNING |
| `BufferCacheHitRatioCritical` | `90` | Buffer cache hit % for CRITICAL |

**Industry Standards:**
- PLE: > 300 seconds per 4GB buffer pool = healthy
- Buffer Cache Hit Ratio: > 95% = excellent, < 90% = problem

**Example:**
```sql
-- Adjust for server with 64GB RAM (higher PLE expected)
EXEC DBA_UpdateConfig 'PageLifeExpectancyWarning', '2000'
EXEC DBA_UpdateConfig 'PageLifeExpectancyCritical', '1000'
```

---

### 7. I/O Latency Thresholds

| Key | Default | Description |
|-----|---------|-------------|
| `IOLatencyWarningMs` | `15` | Average I/O latency for WARNING |
| `IOLatencyCriticalMs` | `25` | Average I/O latency for CRITICAL |

**Industry Standards:**
- < 5ms = Excellent (SSD)
- 5-15ms = Good
- 15-25ms = Needs investigation
- \> 25ms = Critical problem

**Example:**
```sql
-- Tighter thresholds for SSD storage
EXEC DBA_UpdateConfig 'IOLatencyWarningMs', '10'
EXEC DBA_UpdateConfig 'IOLatencyCriticalMs', '15'

-- Relaxed thresholds for slower storage
EXEC DBA_UpdateConfig 'IOLatencyWarningMs', '20'
EXEC DBA_UpdateConfig 'IOLatencyCriticalMs', '30'
```

---

### 8. VLF Health Thresholds

| Key | Default | Description |
|-----|---------|-------------|
| `VLFCountWarning` | `1000` | VLF count for WARNING |
| `VLFCountCritical` | `10000` | VLF count for CRITICAL |

**Impact of High VLFs:**
- Slow database recovery on restart
- Slow transaction log backups
- Slow log truncation

**Example:**
```sql
-- More conservative VLF thresholds
EXEC DBA_UpdateConfig 'VLFCountWarning', '500'
EXEC DBA_UpdateConfig 'VLFCountCritical', '5000'
```

---

### 9. Blocking & CPU Pressure

| Key | Default | Description |
|-----|---------|-------------|
| `BlockingSessionsWarning` | `5` | Blocking sessions for WARNING |
| `BlockingSessionsCritical` | `10` | Blocking sessions for CRITICAL |
| `RunnableTasksWarning` | `2` | Runnable tasks/scheduler for WARNING |
| `RunnableTasksCritical` | `5` | Runnable tasks/scheduler for CRITICAL |

**Example:**
```sql
-- Lower blocking tolerance
EXEC DBA_UpdateConfig 'BlockingSessionsWarning', '3'
EXEC DBA_UpdateConfig 'BlockingSessionsCritical', '5'
```

---

### 10. Transaction Log Space

| Key | Default | Description |
|-----|---------|-------------|
| `LogSpaceUsedWarning` | `80` | Log space used % for WARNING |
| `LogSpaceUsedCritical` | `90` | Log space used % for CRITICAL |

**Example:**
```sql
-- Alert earlier on log space
EXEC DBA_UpdateConfig 'LogSpaceUsedWarning', '70'
EXEC DBA_UpdateConfig 'LogSpaceUsedCritical', '85'
```

---

## Using Configuration in Custom Queries

### Reading Config Values

```sql
-- Get string value
DECLARE @TimeZone NVARCHAR(500) = dbo.fn_GetConfigValue('ReportingTimeZone')
PRINT 'Timezone: ' + @TimeZone

-- Get integer value
DECLARE @RetentionDays INT = dbo.fn_GetConfigInt('RetentionDays')
PRINT 'Retention: ' + CAST(@RetentionDays AS VARCHAR(10)) + ' days'

-- Get bit/boolean value
DECLARE @EnableP2 BIT = dbo.fn_GetConfigBit('EnableP2Collection')
IF @EnableP2 = 1
    PRINT 'P2 collection enabled'
```

### Example: Dynamic Alert Query

```sql
-- Get databases with backup issues based on config thresholds
SELECT
    DatabaseName,
    LastFullBackupLocalTime,
    HoursSinceFullBackup,
    BackupRiskLevel
FROM DBATools.dbo.vw_BackupRiskAssessment_ET
WHERE BackupRiskLevel IN ('WARNING', 'CRITICAL')
ORDER BY
    CASE BackupRiskLevel
        WHEN 'CRITICAL' THEN 1
        WHEN 'WARNING' THEN 2
        ELSE 3
    END,
    HoursSinceFullBackup DESC
```

---

## Configuration Best Practices

### 1. Start Conservative
- Use defaults for first 24-48 hours
- Observe actual metrics before adjusting
- Document why you changed from defaults

### 2. Environment-Specific Tuning

**Development/Test:**
```sql
EXEC DBA_UpdateConfig 'BackupWarningHours', '72'  -- Relaxed
EXEC DBA_UpdateConfig 'RetentionDays', '7'        -- Less storage
EXEC DBA_UpdateConfig 'EnableP3Collection', '0'   -- Minimal overhead
```

**Production:**
```sql
EXEC DBA_UpdateConfig 'BackupWarningHours', '12'  -- Strict
EXEC DBA_UpdateConfig 'RetentionDays', '60'       -- More history
EXEC DBA_UpdateConfig 'EnableP2Collection', '1'   -- Full visibility
```

### 3. Storage Considerations

**Reduce storage:**
```sql
EXEC DBA_UpdateConfig 'RetentionDays', '14'
EXEC DBA_UpdateConfig 'QueryStatsTopN', '50'
EXEC DBA_UpdateConfig 'QueryPlansTopN', '10'
EXEC DBA_UpdateConfig 'EnableP3Collection', '0'
```

**Maximize history:**
```sql
EXEC DBA_UpdateConfig 'RetentionDays', '90'
EXEC DBA_UpdateConfig 'QueryStatsTopN', '200'
EXEC DBA_UpdateConfig 'QueryPlansTopN', '50'
EXEC DBA_UpdateConfig 'EnableP3Collection', '1'
```

### 4. Alerting Integration

When building alerting logic, always use config functions:

```sql
-- Example: Email alert for memory pressure
IF EXISTS (
    SELECT 1
    FROM DBATools.dbo.PerfSnapshotMemory m
    INNER JOIN DBATools.dbo.PerfSnapshotRun r ON m.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
      AND m.PageLifeExpectancy < dbo.fn_GetConfigInt('PageLifeExpectancyCritical')
)
BEGIN
    -- Send alert
    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = 'DBA Alerts',
        @recipients = 'dba@company.com',
        @subject = 'CRITICAL: Memory Pressure Detected',
        @body = 'Page Life Expectancy below threshold'
END
```

---

## Audit Trail

All configuration changes are tracked:

```sql
-- View recent configuration changes
SELECT
    ConfigKey,
    ConfigValue,
    LastModified,
    ModifiedBy
FROM DBATools.dbo.MonitoringConfig
WHERE LastModified >= DATEADD(DAY, -7, SYSUTCDATETIME())
ORDER BY LastModified DESC
```

---

## Troubleshooting

### Timezone Conversion Not Working

**Check SQL Server version:**
```sql
SELECT @@VERSION
-- AT TIME ZONE requires SQL Server 2016+
```

**Verify timezone name:**
```sql
SELECT * FROM sys.time_zone_info WHERE name LIKE '%Eastern%'
```

### Configuration Not Taking Effect

**Verify active status:**
```sql
SELECT ConfigKey, ConfigValue, IsActive
FROM DBATools.dbo.MonitoringConfig
WHERE ConfigKey = 'YourKey'
```

**Check function return value:**
```sql
SELECT dbo.fn_GetConfigValue('YourKey') AS CurrentValue
```

---

## Summary

The configuration system provides:
✅ Centralized management of all settings
✅ Automatic timezone conversion (UTC storage → Eastern reporting)
✅ Dynamic alert thresholds
✅ Easy tuning without code changes
✅ Audit trail of configuration changes
✅ Defaults that can be reset

**Most Common Tasks:**
1. Change timezone: `EXEC DBA_UpdateConfig 'ReportingTimeZone', 'Pacific Standard Time'`
2. Adjust retention: `EXEC DBA_UpdateConfig 'RetentionDays', '60'`
3. Tune alerts: `EXEC DBA_UpdateConfig 'BackupWarningHours', '12'`
4. View config: `EXEC DBA_ViewConfig`

---

**End of Configuration Guide**
