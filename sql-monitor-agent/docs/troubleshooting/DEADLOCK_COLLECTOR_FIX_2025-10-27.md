# Deadlock Collector Fix - October 27, 2025

## Issue

The `DBA_Collect_P2_DeadlockDetails` procedure was failing on every run with the following error:

```
INSERT failed because the following SET options have incorrect settings: 'QUOTED_IDENTIFIER'.
Verify that SET options are correct for use with indexed views and/or indexes on computed columns
and/or filtered indexes and/or query notifications and/or XML data type methods and/or spatial index operations.
```

**Error Number:** 1934
**Affected Servers:** sqltest.schoolvision.net, svweb, suncity.schoolvision.net
**Frequency:** Every collection run (every 5 minutes)

## Root Cause

The `PerfSnapshotDeadlocks` table contains an **XML column** (`DeadlockXML`). SQL Server requires specific SET options to be enabled at **procedure creation time** when working with:
- XML data type methods
- Indexed views
- Computed columns
- Filtered indexes
- Spatial index operations

Setting these options **inside** the procedure body has no effect - they must be set **before** the `CREATE PROCEDURE` statement.

## Solution

Modified `08_create_modular_collectors_P2_P3_FIXED.sql` to include required SET options before the procedure creation:

```sql
-- P2.13: Collect Enhanced Deadlock Analysis
-- Required SET options for XML column operations (must be set at procedure creation time)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
SET ANSI_WARNINGS ON
GO
SET CONCAT_NULL_YIELDS_NULL ON
GO
SET ARITHABORT ON
GO

CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_DeadlockDetails
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    -- procedure body...
END
```

## Deployment

Fixed and deployed to all three servers:

| Server | Deployment Time | Verification Status |
|--------|----------------|---------------------|
| sqltest.schoolvision.net,14333 | 2025-10-27 17:16 UTC | ✅ COMPLETE (IsError=0) |
| svweb,14333 | 2025-10-27 17:17 UTC | ✅ COMPLETE (IsError=0) |
| suncity.schoolvision.net,14333 | 2025-10-27 17:17 UTC | ✅ COMPLETE (IsError=0) |

## Verification

All servers now show successful collection:

**sqltest:**
```
DateTime_Occurred: 2025-10-27 17:16:18.523
ProcedureSection: COMPLETE
IsError: 0
```

**svweb:**
```
DateTime_Occurred: 2025-10-27 17:17:25.836
ProcedureSection: COMPLETE
IsError: 0
```

**suncity:**
```
DateTime_Occurred: 2025-10-27 17:17:27.397
ProcedureSection: COMPLETE
IsError: 0
```

## Impact

- **Before Fix:** 100% failure rate on deadlock collection
- **After Fix:** 100% success rate
- **Data Loss:** None (deadlocks were still being counted in PerfSnapshotRun via XEvent ring buffer, just not stored in PerfSnapshotDeadlocks table)
- **Performance:** No change - same lightweight DMV queries

## Related Files

- **Fixed Script:** `08_create_modular_collectors_P2_P3_FIXED.sql`
- **Affected Table:** `dbo.PerfSnapshotDeadlocks` (created in `05_create_enhanced_tables.sql`)
- **Affected Procedure:** `dbo.DBA_Collect_P2_DeadlockDetails`

## Prevention

When creating procedures that insert into tables with:
- XML columns
- Indexed views
- Computed columns (especially persisted)
- Filtered indexes
- Spatial indexes

**Always set these options BEFORE the CREATE PROCEDURE statement:**
```sql
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
SET ANSI_WARNINGS ON
GO
SET CONCAT_NULL_YIELDS_NULL ON
GO
SET ARITHABORT ON
GO
```

## Lessons Learned

1. SET options inside procedure body do NOT affect procedure creation context
2. SQL Server stores the SET options that were active during CREATE PROCEDURE
3. XML columns are particularly sensitive to QUOTED_IDENTIFIER setting
4. Error 1934 always indicates SET option mismatch at creation time, not runtime
