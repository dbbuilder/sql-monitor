# How to Add Indexes Based on Statistics

**Category**: Performance Tuning
**Difficulty**: Intermediate
**Reading Time**: 10 minutes
**Last Updated**: 2025-10-29

---

## Problem Statement

Missing indexes are the **#1 cause** of slow SQL Server queries. But with thousands of possible index combinations, how do you know which indexes to create without wasting time and storage?

**Real-World Impact**:
- Query taking 45 seconds drops to 2 seconds with right index
- CPU usage drops from 80% to 15%
- Blocking chains eliminated
- Users happy again

---

## The Solution: Use SQL Server's Built-In Statistics

SQL Server tracks **every query** you run and analyzes which indexes would help most. This data is stored in **Dynamic Management Views (DMVs)** that you can query to get smart recommendations.

###

 Step 1: Find Missing Indexes with High Impact

```sql
-- Find top 10 missing indexes by impact score
SELECT TOP 10
    CONVERT(DECIMAL(18,2), migs.avg_user_impact * (migs.user_seeks + migs.user_scans)) AS ImpactScore,
    mid.statement AS TableName,
    mid.equality_columns AS EqualityColumns,
    mid.inequality_columns AS InequalityColumns,
    mid.included_columns AS IncludedColumns,
    migs.user_seeks AS UserSeeks,
    migs.user_scans AS UserScans,
    migs.avg_user_impact AS AvgUserImpact,
    migs.avg_total_user_cost AS AvgTotalUserCost,
    migs.unique_compiles AS UniqueCompiles,
    migs.last_user_seek AS LastUserSeek,
    migs.last_user_scan AS LastUserScan
FROM sys.dm_db_missing_index_details mid
INNER JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
WHERE mid.database_id = DB_ID()
ORDER BY ImpactScore DESC;
```

**What This Shows**:
- **ImpactScore**: Higher = more important (100+ is significant)
- **EqualityColumns**: WHERE ID = @ID (exact matches)
- **InequalityColumns**: WHERE Date > @StartDate (ranges)
- **IncludedColumns**: SELECT columns not in WHERE clause
- **UserSeeks/UserScans**: How often this index would be used

---

## The Index Creation Formula

### Rule 1: Equality Columns First

Columns in `WHERE column = value` clauses go **first** in the index key.

```sql
-- Query pattern
SELECT * FROM Orders WHERE CustomerID = 123;

-- Optimal index
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON dbo.Orders (CustomerID);
```

**Why**: Equality matches allow SQL Server to jump directly to the right rows (index seek). This is the fastest type of index operation.

---

### Rule 2: Inequality Columns Second

Columns in `WHERE column > value` or `BETWEEN` clauses go **after** equality columns.

```sql
-- Query pattern
SELECT * FROM Orders
WHERE CustomerID = 123  -- Equality first
  AND OrderDate > '2025-01-01';  -- Inequality second

-- Optimal index
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID_OrderDate
ON dbo.Orders (CustomerID, OrderDate);
```

**Why**: SQL Server seeks on equality column first, then scans remaining rows for inequality match. Order matters!

---

### Rule 3: Included Columns Last

Columns in the `SELECT` list (but not in WHERE clause) go in the `INCLUDE` clause.

```sql
-- Query pattern
SELECT OrderID, OrderDate, Amount, Status  -- We want these columns
FROM Orders
WHERE CustomerID = 123;  -- But only filter on this

-- Optimal index (covering index)
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID_INCLUDE
ON dbo.Orders (CustomerID)
INCLUDE (OrderID, OrderDate, Amount, Status);
```

**Why**: Including these columns prevents a "key lookup" back to the main table. Query becomes **10x faster** because SQL Server has everything it needs in the index.

---

## Real-World Example

### Scenario: Slow Order Lookup

**Query** (taking 45 seconds):
```sql
SELECT
    o.OrderID,
    o.OrderDate,
    o.Amount,
    o.Status,
    c.CustomerName,
    c.Email
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
WHERE c.CompanyID = 123
  AND o.OrderDate >= '2025-01-01'
  AND o.OrderDate < '2025-02-01'
  AND o.Status = 'Shipped';
```

**Current State**: No indexes, SQL Server doing table scans (scanning all 10 million rows).

### Step 1: Run Missing Index DMV Query

```sql
-- Result from DMV query
ImpactScore: 8,234.56
EqualityColumns: [CompanyID], [Status]
InequalityColumns: [OrderDate]
IncludedColumns: [OrderID], [Amount], [CustomerName], [Email]
```

### Step 2: Create Optimal Indexes

```sql
-- Index for Customers table
CREATE NONCLUSTERED INDEX IX_Customers_CompanyID_INCLUDE
ON dbo.Customers (CompanyID)
INCLUDE (CustomerID, CustomerName, Email);

-- Index for Orders table
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID_Status_OrderDate_INCLUDE
ON dbo.Orders (CustomerID, Status, OrderDate)
INCLUDE (OrderID, Amount);
```

**Why This Order**:
1. `CustomerID` - Equality (WHERE CustomerID = @CustomerID from JOIN)
2. `Status` - Equality (WHERE Status = 'Shipped')
3. `OrderDate` - Inequality (WHERE OrderDate >= '2025-01-01')
4. `OrderID, Amount` - INCLUDE (in SELECT but not WHERE)

### Step 3: Test Performance

**Before**: 45 seconds, 10 million rows scanned
**After**: 2 seconds, 1,523 rows scanned (99.98% faster!)

---

## Advanced Techniques

### Technique 1: Composite Index Order Matters

```sql
-- WRONG ORDER (slow)
CREATE INDEX IX_Wrong ON Orders (OrderDate, CustomerID);

-- Query won't use this index efficiently because CustomerID is second
SELECT * FROM Orders WHERE CustomerID = 123;

-- CORRECT ORDER (fast)
CREATE INDEX IX_Right ON Orders (CustomerID, OrderDate);

-- Now this query uses index seek on CustomerID
SELECT * FROM Orders WHERE CustomerID = 123;
```

**Rule**: Put the most selective column first (column with most unique values).

---

### Technique 2: Covering Index vs Key Lookup

```sql
-- Index without INCLUDE (requires key lookup)
CREATE INDEX IX_Partial ON Orders (CustomerID);

-- Query execution:
-- 1. Index seek on IX_Partial (finds matching rows)
-- 2. Key lookup to clustered index (gets Amount, Status columns) ← SLOW
-- 3. Nested loop join (combines results)
SELECT CustomerID, Amount, Status FROM Orders WHERE CustomerID = 123;

-- Covering index (no key lookup needed)
CREATE INDEX IX_Covering ON Orders (CustomerID) INCLUDE (Amount, Status);

-- Query execution:
-- 1. Index seek on IX_Covering (finds all data) ← FAST
-- Done! No key lookup needed.
```

**Performance Difference**: 10x faster with covering index.

---

### Technique 3: Filtered Indexes (Partial Indexes)

```sql
-- Full index (indexes all 10 million rows)
CREATE INDEX IX_Full ON Orders (Status);

-- Filtered index (indexes only 100,000 active rows)
CREATE INDEX IX_Filtered ON Orders (Status)
WHERE Status IN ('Pending', 'Shipped');  -- 90% smaller!

-- Query must match filter to use index
SELECT * FROM Orders WHERE Status = 'Shipped';  -- Uses filtered index (fast)
SELECT * FROM Orders WHERE Status = 'Cancelled';  -- Table scan (not in filter)
```

**Benefits**:
- 90% smaller index (less storage, faster seeks)
- Faster index maintenance (fewer rows to update)
- Perfect for "current data" scenarios (last 90 days, active orders, etc.)

---

## Balancing Act: Too Many Indexes

### The Problem

Every index has a **cost**:
- **Storage**: Each index takes disk space (1-50% of table size)
- **INSERT Cost**: Every INSERT updates all indexes (2x slower with 5 indexes)
- **UPDATE Cost**: Updating indexed column updates index (5x slower)
- **DELETE Cost**: Every DELETE updates all indexes (3x slower)

### The Rule of Thumb

**For OLTP (transactional) systems**:
- **3-7 indexes per table** is ideal
- **10+ indexes** = too many, write performance suffers
- **0-2 indexes** = too few, read performance suffers

**For OLAP (analytical) systems**:
- **10-20 indexes per table** is acceptable (few writes, many reads)

### How to Choose

**Keep indexes that**:
- ✅ Support critical queries (login, checkout, search)
- ✅ Have high impact score (> 1000)
- ✅ Are used frequently (last_user_seek within 24 hours)

**Remove indexes that**:
- ❌ Haven't been used in 30+ days
- ❌ Have low impact score (< 100)
- ❌ Duplicate existing indexes

```sql
-- Find unused indexes (candidates for removal)
SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    i.name AS IndexName,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates,
    s.last_user_seek,
    s.last_user_scan,
    s.last_user_lookup
FROM sys.dm_db_index_usage_stats s
INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.database_id = DB_ID()
  AND OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
  AND s.user_seeks = 0  -- Never used for seeks
  AND s.user_scans = 0  -- Never used for scans
  AND s.user_lookups = 0  -- Never used for lookups
  AND i.is_primary_key = 0  -- Not a primary key
  AND i.is_unique_constraint = 0  -- Not a unique constraint
ORDER BY s.user_updates DESC;  -- Most expensive to maintain
```

---

## Index Maintenance Best Practices

### 1. Monitor Index Usage

```sql
-- Weekly report: Which indexes are actually used?
SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    i.name AS IndexName,
    s.user_seeks + s.user_scans + s.user_lookups AS TotalReads,
    s.user_updates AS TotalWrites,
    CASE
        WHEN s.user_updates > 0 THEN
            CAST((s.user_seeks + s.user_scans + s.user_lookups) AS FLOAT) / s.user_updates
        ELSE
            999999
    END AS ReadWriteRatio,
    s.last_user_seek AS LastRead
FROM sys.dm_db_index_usage_stats s
INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.database_id = DB_ID()
ORDER BY TotalReads DESC;
```

**Interpretation**:
- **ReadWriteRatio > 10**: Great index (reads vastly outweigh writes)
- **ReadWriteRatio 1-10**: Good index (balanced)
- **ReadWriteRatio < 1**: Bad index (more writes than reads, consider removing)

---

### 2. Test Index Before Creating in Production

```sql
-- 1. Create index on DEV server
CREATE INDEX IX_Test ON Orders (CustomerID) INCLUDE (Amount);

-- 2. Run your query with and without index
-- Without index
DROP INDEX IX_Test ON Orders;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SELECT * FROM Orders WHERE CustomerID = 123;
-- Note: Logical reads, CPU time, elapsed time

-- With index
CREATE INDEX IX_Test ON Orders (CustomerID) INCLUDE (Amount);
SELECT * FROM Orders WHERE CustomerID = 123;
-- Compare metrics

-- 3. If 10x improvement, deploy to PROD
```

---

### 3. Use Database Tuning Advisor (DTA)

SQL Server has a built-in tool that analyzes your workload and recommends indexes.

```sql
-- Capture workload trace (run for 24 hours)
-- Use SQL Server Profiler or Extended Events

-- Run Database Tuning Advisor
-- File → New → Workload File → Select trace file
-- Select tables to analyze
-- Click "Start Analysis"
-- Review recommendations
```

**When to Use**: For complex workloads with hundreds of queries. DTA considers query interactions that DMVs don't.

---

## Common Mistakes to Avoid

### Mistake 1: Index on Low-Selectivity Columns

```sql
-- BAD: Gender has only 2-3 values (M, F, Other)
CREATE INDEX IX_Bad ON Users (Gender);

-- SQL Server will ignore this index and do table scan
SELECT * FROM Users WHERE Gender = 'M';  -- Returns 50% of rows

-- BETTER: Combine with high-selectivity column
CREATE INDEX IX_Better ON Users (Country, Gender) INCLUDE (Name, Email);

-- Now useful for specific country
SELECT * FROM Users WHERE Country = 'USA' AND Gender = 'M';  -- Returns 1% of rows
```

**Rule**: Index columns with **high cardinality** (many unique values). Avoid columns where any value represents >10% of rows.

---

### Mistake 2: Over-Indexing Small Tables

```sql
-- Table has 100 rows
CREATE INDEX IX_1 ON SmallTable (Column1);
CREATE INDEX IX_2 ON SmallTable (Column2);
CREATE INDEX IX_3 ON SmallTable (Column3);

-- SQL Server will ignore all indexes and do table scan (100 rows fits in memory)
```

**Rule**: Don't index tables with <1000 rows. Table scan is faster than index seek for small tables.

---

### Mistake 3: Duplicate Indexes

```sql
-- Index 1 (created by developer)
CREATE INDEX IX_Orders_CustomerID ON Orders (CustomerID);

-- Index 2 (created by DBA, duplicates Index 1)
CREATE INDEX IX_Orders_CustomerID_2 ON Orders (CustomerID);

-- Both indexes maintained on every INSERT/UPDATE/DELETE (wasted effort)
```

**How to Find**:
```sql
SELECT
    t.name AS TableName,
    i1.name AS Index1,
    i2.name AS Index2,
    c1.column_name AS Column
FROM sys.tables t
INNER JOIN sys.indexes i1 ON t.object_id = i1.object_id
INNER JOIN sys.indexes i2 ON t.object_id = i2.object_id
INNER JOIN information_schema.columns c1 ON c1.table_name = t.name
WHERE i1.index_id <> i2.index_id
  AND i1.name <> i2.name
  AND i1.is_primary_key = 0
  AND i2.is_primary_key = 0;
```

---

## Checklist: Before Creating an Index

- [ ] **Impact Score > 1000?** (from DMV query)
- [ ] **Supports critical query?** (login, checkout, search)
- [ ] **Table has >1000 rows?** (otherwise skip)
- [ ] **Column has high selectivity?** (>100 unique values)
- [ ] **Not duplicating existing index?** (check sys.indexes)
- [ ] **Read/write ratio > 10?** (more reads than writes)
- [ ] **Tested on DEV first?** (10x improvement confirmed)
- [ ] **Table has <7 indexes already?** (avoid over-indexing)

---

## Summary

### Quick Reference

| Index Type | Use Case | Performance |
|------------|----------|-------------|
| **Equality columns** | WHERE ID = @ID | ⚡⚡⚡ Fastest (index seek) |
| **Inequality columns** | WHERE Date > @Date | ⚡⚡ Fast (range scan) |
| **Covering index (INCLUDE)** | Includes SELECT columns | ⚡⚡⚡ 10x faster (no key lookup) |
| **Filtered index** | WHERE Status = 'Active' | ⚡⚡⚡ 90% smaller, faster |
| **Composite index** | Multiple WHERE columns | ⚡⚡ Order matters! |

### Action Steps

1. **Run DMV query** to find missing indexes
2. **Sort by ImpactScore** (highest first)
3. **Create top 3-5 indexes** (test on DEV first)
4. **Monitor usage** (weekly report)
5. **Remove unused indexes** (after 30 days)

---

**Next Article**: [Temp Tables vs Table Variables: When to Use Each](02-temp-tables-vs-table-variables.md)

**Related Articles**:
- [The Value of INCLUDE and Other Index Options](06-include-and-index-options.md)
- [When to Rebuild Indexes](12-when-to-rebuild-indexes.md)

---

**Author**: ArcTrade Technical Team
**Last Updated**: 2025-10-29
**Version**: 1.0
