# Identity Seed Pattern - Implementation Guide

**Implemented:** 2025-10-27
**Pattern:** System data < 1 billion, User data >= 1 billion

## Overview

The feedback system uses an identity seed pattern to safely separate system-seeded data from user-created customizations:

- **System data:** IDs 1 - 999,999,999 (< 1 billion)
- **User data:** IDs 1,000,000,000+ (>= 1 billion)

This allows **safe reseeding** without deleting user customizations:

```sql
-- Safe reseed - only deletes system data
DELETE FROM FeedbackRule WHERE FeedbackRuleID < 1000000000
DELETE FROM FeedbackMetadata WHERE MetadataID < 1000000000
```

## Implementation

### Table Creation (13_create_feedback_system.sql)

```sql
CREATE TABLE dbo.FeedbackRule
(
    FeedbackRuleID INT IDENTITY(1000000000,1) PRIMARY KEY,  -- User data starts at 1B
    ...
    IsSystemRule BIT NOT NULL DEFAULT 0,  -- 1 = seeded, 0 = user
    ...
)

CREATE TABLE dbo.FeedbackMetadata
(
    MetadataID INT IDENTITY(1000000000,1) PRIMARY KEY,  -- User data starts at 1B
    ...
    IsSystemMetadata BIT NOT NULL DEFAULT 0,  -- 1 = seeded, 0 = user
    ...
)
```

**Key Points:**
- `IDENTITY(1000000000,1)` - Identity starts at 1 billion
- When users INSERT without specifying ID, they get IDs >= 1B automatically
- `IsSystemRule/IsSystemMetadata` - Additional safety flag

### Seed Script Pattern (13b_seed_feedback_rules.sql)

```sql
-- STEP 1: Delete only system data (ID < 1B)
DELETE FROM dbo.FeedbackMetadata WHERE MetadataID < 1000000000
DELETE FROM dbo.FeedbackRule WHERE FeedbackRuleID < 1000000000
-- User data (ID >= 1B) is preserved

-- STEP 2: Insert system data with explicit IDs
SET IDENTITY_INSERT dbo.FeedbackMetadata ON

INSERT INTO dbo.FeedbackMetadata (MetadataID, ..., IsSystemMetadata)
VALUES
    (1, ..., 1),    -- Explicit ID = 1 (system data)
    (2, ..., 1),    -- Explicit ID = 2 (system data)
    ...
    (12, ..., 1)    -- Explicit ID = 12 (system data)

SET IDENTITY_INSERT dbo.FeedbackMetadata OFF

SET IDENTITY_INSERT dbo.FeedbackRule ON

INSERT INTO dbo.FeedbackRule (FeedbackRuleID, ..., IsSystemRule)
VALUES
    (100, ..., 1),  -- Result Set 1 rules: IDs 100-109
    (101, ..., 1),
    ...
    (110, ..., 1),  -- Result Set 2 rules: IDs 110-149
    (111, ..., 1),
    ...
    (200, ..., 1),  -- Result Set 4 rules: IDs 200-219
    ...
    (500, ..., 1)   -- Result Set 9 rules: IDs 500-519

SET IDENTITY_INSERT dbo.FeedbackRule OFF
```

### ID Allocation Strategy

**FeedbackMetadata (IDs 1-99):**
- 1-12: DBA_DailyHealthOverview result sets
- 13-99: Reserved for future procedures

**FeedbackRule (IDs 100-999,999,999):**
- 100-109: Result Set 1 (Report Header)
- 110-149: Result Set 2 (Current Health)
- 150-199: Reserved
- 200-219: Result Set 4 (Summary Statistics)
- 220-299: Reserved
- 300-319: Result Set 5 (Slow Queries)
- 320-399: Reserved
- 400-419: Result Set 7 (Missing Indexes)
- 420-499: Reserved
- 500-519: Result Set 9 (Database Sizes)
- 520-999: Reserved for additional result sets
- 1000-999,999,999: Reserved for future system rules

**User Data (IDs >= 1,000,000,000):**
- All user-created rules automatically get IDs >= 1B
- No collisions with system data possible

## Usage Examples

### Adding User-Created Rules

```sql
-- User adds custom rule (no explicit ID needed)
INSERT INTO DBATools.dbo.FeedbackRule
(ProcedureName, ResultSetNumber, MetricName, RangeFrom, RangeTo,
 Severity, FeedbackText, Recommendation, SortOrder)
VALUES
('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', 70, NULL,
 'CRITICAL', 'Extreme CPU pressure', 'Kill expensive queries', 6)

-- Identity auto-assigns FeedbackRuleID = 1,000,000,000 (first user rule)
```

### Viewing System vs User Data

```sql
-- View system-seeded rules
SELECT * FROM DBATools.dbo.FeedbackRule
WHERE FeedbackRuleID < 1000000000
  OR IsSystemRule = 1

-- View user-created rules
SELECT * FROM DBATools.dbo.FeedbackRule
WHERE FeedbackRuleID >= 1000000000
  OR IsSystemRule = 0

-- Count by type
SELECT
    CASE
        WHEN FeedbackRuleID < 1000000000 THEN 'System'
        ELSE 'User'
    END AS RuleType,
    COUNT(*) AS RuleCount
FROM DBATools.dbo.FeedbackRule
GROUP BY CASE WHEN FeedbackRuleID < 1000000000 THEN 'System' ELSE 'User' END
```

### Reseeding (Preserves User Data)

```sql
-- Run 13b_seed_feedback_rules.sql
-- This will:
--   1. DELETE WHERE ID < 1000000000 (removes old system rules)
--   2. INSERT new system rules with explicit IDs 1-999
--   3. User rules (ID >= 1B) remain untouched
```

## Benefits

### 1. **Safe Reseeding**
- Reseed system data without affecting user customizations
- No need to export/import user data
- Idempotent seed script

### 2. **Clear Separation**
- IDs clearly identify data origin
- IsSystemRule flag provides additional safety
- Easy to audit what's system vs user

### 3. **No Collisions**
- System data: 1 - 999,999,999 (nearly 1 billion IDs)
- User data: 1,000,000,000 - 2,147,483,647 (1.1+ billion IDs)
- Impossible for user IDs to conflict with system IDs

### 4. **Future-Proof**
- Room for 999 million system rules (more than enough)
- Room for 1 billion user rules
- Can add more procedures/result sets without redesign

## Maintenance

### Adding New System Rules

When adding new system rules (new procedure or result set):

```sql
-- Step 1: Choose unused ID range
-- Example: Result Set 6 rules use IDs 600-619

-- Step 2: Update 13b_seed_feedback_rules.sql
SET IDENTITY_INSERT dbo.FeedbackRule ON

INSERT INTO dbo.FeedbackRule (FeedbackRuleID, ..., IsSystemRule)
VALUES
    (600, 'NewProcedure', 6, 'MetricName', ..., 1),
    (601, 'NewProcedure', 6, 'MetricName', ..., 1)

SET IDENTITY_INSERT dbo.FeedbackRule OFF

-- Step 3: Reseed all servers
-- User data preserved automatically
```

### Troubleshooting

**Problem:** User rule gets ID < 1B

**Cause:** Table was created without IDENTITY(1000000000,1)

**Fix:**
```sql
-- Recreate table with correct identity seed
-- Export user data first if any exists
```

**Problem:** Reseed deletes user data

**Cause:** Used wrong DELETE statement

**Fix:** Always use `WHERE ID < 1000000000`, never `WHERE ProcedureName = 'X'`

## Testing

```sql
-- Test 1: Verify identity seed
CREATE TABLE #TestIdentity (
    ID INT IDENTITY(1000000000,1) PRIMARY KEY
)
INSERT INTO #TestIdentity DEFAULT VALUES
SELECT ID FROM #TestIdentity  -- Should return 1,000,000,000
DROP TABLE #TestIdentity

-- Test 2: Verify system data range
SELECT
    MIN(FeedbackRuleID) AS MinID,
    MAX(FeedbackRuleID) AS MaxID
FROM DBATools.dbo.FeedbackRule
WHERE IsSystemRule = 1
-- Both should be < 1,000,000,000

-- Test 3: Verify user data range
INSERT INTO DBATools.dbo.FeedbackRule (...) VALUES (...)  -- No explicit ID
SELECT TOP 1 FeedbackRuleID
FROM DBATools.dbo.FeedbackRule
WHERE IsSystemRule = 0
ORDER BY FeedbackRuleID DESC
-- Should be >= 1,000,000,000

-- Test 4: Verify reseed safety
DECLARE @UserRulesBefore INT
SELECT @UserRulesBefore = COUNT(*) FROM DBATools.dbo.FeedbackRule WHERE FeedbackRuleID >= 1000000000

-- Run: 13b_seed_feedback_rules.sql

DECLARE @UserRulesAfter INT
SELECT @UserRulesAfter = COUNT(*) FROM DBATools.dbo.FeedbackRule WHERE FeedbackRuleID >= 1000000000

SELECT
    @UserRulesBefore AS Before,
    @UserRulesAfter AS After,
    CASE WHEN @UserRulesBefore = @UserRulesAfter THEN 'PASS' ELSE 'FAIL' END AS Result
```

## Best Practices

1. **Always use DELETE WHERE ID < 1000000000** when reseeding
2. **Always use SET IDENTITY_INSERT ON** when inserting system data
3. **Always set IsSystemRule = 1** for system data
4. **Never manually insert with ID >= 1000000000** (let identity auto-assign)
5. **Document ID ranges** when adding new system rules
6. **Test reseed** in non-production before deploying

## Migration from Old Pattern

If you have existing data without this pattern:

```sql
-- Step 1: Backup existing data
SELECT * INTO FeedbackRule_Backup FROM DBATools.dbo.FeedbackRule
SELECT * INTO FeedbackMetadata_Backup FROM DBATools.dbo.FeedbackMetadata

-- Step 2: Identify user-created data
SELECT * FROM FeedbackRule_Backup WHERE /* your criteria for user data */

-- Step 3: Drop and recreate tables with new pattern
-- (use 13_create_feedback_system.sql)

-- Step 4: Reseed system data
-- (use 13b_seed_feedback_rules.sql)

-- Step 5: Restore user data with adjusted IDs
SET IDENTITY_INSERT dbo.FeedbackRule ON
INSERT INTO dbo.FeedbackRule (FeedbackRuleID, ...)
SELECT
    FeedbackRuleID + 1000000000,  -- Shift to user range
    ...
FROM FeedbackRule_Backup
WHERE /* user data criteria */
SET IDENTITY_INSERT dbo.FeedbackRule OFF
```

## Summary

The identity seed pattern provides:
- ✅ Safe reseeding without data loss
- ✅ Clear separation of system vs user data
- ✅ No ID collisions possible
- ✅ Future-proof design
- ✅ Easy to maintain and audit

**Key Rule:** System data uses explicit IDs < 1B, User data gets auto-assigned IDs >= 1B.
