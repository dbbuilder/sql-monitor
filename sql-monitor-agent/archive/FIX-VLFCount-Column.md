# VLFCount Column Fix

**Date:** October 27, 2025
**Issue:** Invalid column name 'VLFCount' in P2 collector
**Status:** FIXED ✅

---

## Problem

Deployment failed at **step 6** (P2/P3 collectors) with this error:

```
Msg 207, Level 16, State 1, Procedure DBA_Collect_P2_VLFCounts, Line 27
Invalid column name 'VLFCount'.
```

**Root Cause:** The `DBA_Collect_P2_VLFCounts` procedure tries to update `dbo.PerfSnapshotDB.VLFCount`, but that column didn't exist in the table definition.

**Line 82 of 08_create_modular_collectors_P2_P3_FIXED.sql:**
```sql
UPDATE dbo.PerfSnapshotDB SET VLFCount = @VLFCount
WHERE PerfSnapshotRunID = @PerfSnapshotRunID AND DatabaseName = @DatabaseName
```

---

## Solution

Added `VLFCount` column to `PerfSnapshotDB` table in script `01_create_DBATools_and_tables.sql`:

### 1. Updated table creation (line 67)
```sql
CREATE TABLE dbo.PerfSnapshotDB
(
    PerfSnapshotDBID    BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    PerfSnapshotRunID   BIGINT               NOT NULL,
    DatabaseID          INT                  NOT NULL,
    DatabaseName        SYSNAME              NOT NULL,
    StateDesc           NVARCHAR(60)         NOT NULL,
    RecoveryModelDesc   NVARCHAR(60)         NOT NULL,
    IsReadOnly          BIT                  NOT NULL,
    TotalDataMB         DECIMAL(18,2)        NULL,
    TotalLogMB          DECIMAL(18,2)        NULL,
    LogReuseWaitDesc    NVARCHAR(120)        NULL,
    FileCount           INT                  NULL,
    CompatLevel         INT                  NULL,
    VLFCount            INT                  NULL,  -- NEW COLUMN
    CONSTRAINT FK_PerfSnapshotDB_Run
        FOREIGN KEY (PerfSnapshotRunID)
        REFERENCES dbo.PerfSnapshotRun(PerfSnapshotRunID)
)
```

### 2. Added ALTER TABLE for existing databases (lines 75-81)
```sql
-- Add VLFCount column if it doesn't exist (for existing databases)
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.PerfSnapshotDB')
               AND name = 'VLFCount')
BEGIN
    ALTER TABLE dbo.PerfSnapshotDB ADD VLFCount INT NULL
    PRINT 'Added VLFCount column to PerfSnapshotDB'
END
```

---

## What is VLFCount?

**VLF = Virtual Log File**

- SQL Server divides transaction logs into Virtual Log Files (VLFs)
- Too many VLFs causes performance problems:
  - Slow transaction log backups
  - Slow database recovery
  - Slow log truncation
- **P2 collector** (`DBA_Collect_P2_VLFCounts`) captures VLF counts for each database
- **Config thresholds:**
  - `VLFCountWarning`: 1000 VLFs
  - `VLFCountCritical`: 10000 VLFs

---

## Files Modified

✅ **01_create_DBATools_and_tables.sql**
- Added `VLFCount INT NULL` column to CREATE TABLE
- Added ALTER TABLE for existing databases

---

## For Existing Deployments

If you already deployed and have the `DBATools` database, run this manually:

```sql
USE DBATools
GO

-- Add missing column
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.PerfSnapshotDB')
               AND name = 'VLFCount')
BEGIN
    ALTER TABLE dbo.PerfSnapshotDB ADD VLFCount INT NULL
    PRINT 'Added VLFCount column to PerfSnapshotDB'
END
GO

-- Verify column exists
SELECT name, system_type_id, is_nullable
FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.PerfSnapshotDB')
AND name = 'VLFCount'
GO
```

Expected output:
```
name      system_type_id  is_nullable
--------  --------------  -----------
VLFCount  56              1
```

---

## Verification

After deployment completes, verify VLF collection works:

```sql
-- Run test collection
EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1

-- Check VLF counts were captured
SELECT
    DatabaseName,
    VLFCount,
    RecoveryModelDesc,
    TotalLogMB
FROM DBATools.dbo.PerfSnapshotDB
WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
ORDER BY VLFCount DESC
```

---

## Next Steps

1. **Re-run deployment** with fixed scripts
2. **Verify VLF data collection** using queries above
3. **Monitor VLF counts** using config thresholds:
   ```sql
   SELECT
       DatabaseName,
       VLFCount,
       CASE
           WHEN VLFCount > dbo.fn_GetConfigInt('VLFCountCritical') THEN 'CRITICAL'
           WHEN VLFCount > dbo.fn_GetConfigInt('VLFCountWarning') THEN 'WARNING'
           ELSE 'OK'
       END AS VLFStatus
   FROM DBATools.dbo.PerfSnapshotDB
   WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM DBATools.dbo.PerfSnapshotRun)
   ORDER BY VLFCount DESC
   ```

---

**Fix completed. Ready for deployment.**
