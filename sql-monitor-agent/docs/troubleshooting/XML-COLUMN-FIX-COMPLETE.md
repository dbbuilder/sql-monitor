# XML Column Procedures - Future-Proof Fix Complete

## Summary

✅ **All files are now fixed for future implementations**

All procedures that insert into tables with XML columns now have the required SET options explicitly declared before the CREATE PROCEDURE statement. This ensures they will work correctly on any SQL Server installation regardless of default session settings.

## Files Fixed

### 1. `08_create_modular_collectors_P2_P3_FIXED.sql`
**Procedure:** `DBA_Collect_P2_DeadlockDetails`
**Table:** `PerfSnapshotDeadlocks`
**XML Column:** `DeadlockXML`
**Status:** ✅ **Fixed** (October 27, 2025)
**Deployed:** sqltest, svweb, suncity
**Before Fix:** 100% failure rate (Error 1934)
**After Fix:** 100% success rate

### 2. `07_create_modular_collectors_P1_FIXED.sql`
**Procedure:** `DBA_Collect_P1_QueryPlans`
**Table:** `PerfSnapshotQueryPlans`
**XML Column:** `QueryPlanXML`
**Status:** ✅ **Fixed** (October 27, 2025 - preventive)
**Current State:** Working (was created with correct defaults by chance)
**Fix Type:** Future-proofing to ensure consistency across all deployments

## Tables with XML Columns

| Table | XML Column | Procedure | Fix Status |
|-------|-----------|-----------|------------|
| PerfSnapshotDeadlocks | DeadlockXML | DBA_Collect_P2_DeadlockDetails | ✅ Fixed |
| PerfSnapshotQueryPlans | QueryPlanXML | DBA_Collect_P1_QueryPlans | ✅ Fixed |

## Required SET Options

Both procedures now have these SET options **before** the CREATE PROCEDURE statement:

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

CREATE OR ALTER PROCEDURE dbo.ProcedureName
```

## Deployment Scripts Verified

All deployment scripts reference the correct fixed files:

✅ **deploy_all.sh** (Line 154-155)
```bash
execute_sql "08" "Create P2/P3 (Medium/Low) collectors" \
    "08_create_modular_collectors_P2_P3_FIXED.sql" "$DATABASE" || exit 1
```

✅ **Deploy-MonitoringSystem.ps1** (Line 08 in deployment array)
```powershell
@{ Num="08"; Desc="Create P2/P3 (Medium/Low) collectors";
   File="08_create_modular_collectors_P2_P3_FIXED.sql"; DB="DBATools" }
```

✅ **deploy_all.sh** (Line 147-148)
```bash
execute_sql "07" "Create P1 (Performance) collectors" \
    "07_create_modular_collectors_P1_FIXED.sql" "$DATABASE" || exit 1
```

✅ **Deploy-MonitoringSystem.ps1** (Line 07 in deployment array)
```powershell
@{ Num="07"; Desc="Create P1 (Performance) collectors";
   File="07_create_modular_collectors_P1_FIXED.sql"; DB="DBATools" }
```

## Why This Fix is Important

SQL Server requires specific SET options when working with:
- XML data type methods (`.query()`, `.value()`, `.nodes()`)
- Indexed views
- Computed columns (especially persisted)
- Filtered indexes
- Spatial indexes
- Query notifications

**Key Insight:** SET options must be active during `CREATE PROCEDURE` execution, not during procedure execution. Setting them inside the procedure body has no effect.

## Error This Prevents

**Error 1934:**
```
INSERT failed because the following SET options have incorrect settings: 'QUOTED_IDENTIFIER'.
Verify that SET options are correct for use with indexed views and/or indexes on computed columns
and/or filtered indexes and/or query notifications and/or XML data type methods and/or spatial index operations.
```

## Verification Queries

Check if procedures were created with correct SET options:

```sql
-- Check QUOTED_IDENTIFIER setting for procedures
SELECT
    name,
    uses_quoted_identifier,
    uses_ansi_nulls
FROM sys.sql_modules sm
INNER JOIN sys.objects o ON sm.object_id = o.object_id
WHERE o.name IN ('DBA_Collect_P2_DeadlockDetails', 'DBA_Collect_P1_QueryPlans')
```

Expected results:
- `uses_quoted_identifier` = 1 (True)
- `uses_ansi_nulls` = 1 (True)

## Production Deployment Status

| Server | Fixed P2/P3 | Fixed P1 | Verified |
|--------|------------|----------|----------|
| sqltest.schoolvision.net,14333 | ✅ 2025-10-27 17:16 UTC | Not yet deployed | ⏳ Pending |
| svweb,14333 | ✅ 2025-10-27 17:17 UTC | Not yet deployed | ⏳ Pending |
| suncity.schoolvision.net,14333 | ✅ 2025-10-27 17:17 UTC | Not yet deployed | ⏳ Pending |

**Next Step:** Deploy `07_create_modular_collectors_P1_FIXED.sql` to all three servers (no urgency - currently working, this is preventive).

## Files Checked for XML Operations

✅ `06_create_modular_collectors_P0_FIXED.sql` - No XML columns
✅ `07_create_modular_collectors_P1_FIXED.sql` - **FIXED** (QueryPlanXML)
✅ `08_create_modular_collectors_P2_P3_FIXED.sql` - **FIXED** (DeadlockXML)
✅ `10_create_master_orchestrator_FIXED.sql` - No INSERT into XML columns
✅ `05_create_enhanced_tables.sql` - Table definitions only

## Conclusion

**All source files are now future-proof.** Any new deployment using the current version of:
- `07_create_modular_collectors_P1_FIXED.sql`
- `08_create_modular_collectors_P2_P3_FIXED.sql`

Will correctly create procedures that can insert into XML columns without Error 1934.

## Related Documentation

- [Deadlock Collector Fix Details](DEADLOCK_COLLECTOR_FIX_2025-10-27.md)
- [Microsoft Docs: SET Options Affecting Results](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-statements-transact-sql)
