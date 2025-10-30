# Temp Tables vs Table Variables: When to Use Each

**Category**: Performance Tuning
**Difficulty**: Beginner to Intermediate
**Reading Time**: 12 minutes
**Last Updated**: 2025-10-29

---

## Problem Statement

You need temporary storage for intermediate query results. SQL Server gives you two options:
- **Temp Tables** (`#TempTable`)
- **Table Variables** (`@TableVariable`)

Choose wrong, and your stored procedure takes 10 minutes instead of 10 seconds. Choose right, and everything runs smoothly.

**Real-World Impact**:
- Report generation: 8 minutes → 45 seconds (correct choice)
- Data import: Timeout after 30 minutes → Completes in 3 minutes
- ETL process: Blocks other queries → Runs without interference

---

## The Key Difference

### Temp Tables (#TempTable)

**What they are**: Real tables stored in `tempdb` database

```sql
CREATE TABLE #MyTempTable (
    ID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Amount DECIMAL(10,2)
);

INSERT INTO #MyTempTable (ID, Name, Amount)
VALUES (1, 'Alice', 100.00), (2, 'Bob', 200.00);

SELECT * FROM #MyTempTable;

DROP TABLE #MyTempTable;  -- Clean up when done
```

**Characteristics**:
- ✅ Support **statistics** (SQL Server tracks row counts, data distribution)
- ✅ Support **explicit indexes** (you create them after table creation)
- ✅ Visible **across nested procedures** (if you call Proc B from Proc A, both see the temp table)
- ✅ Survive **transaction rollbacks** (data rolls back but table structure remains)
- ❌ More **overhead** (stored in tempdb, uses disk I/O)
- ❌ Require **explicit DROP** (or automatic cleanup at session end)

---

### Table Variables (@TableVariable)

**What they are**: Special variables that hold table data

```sql
DECLARE @MyTableVariable TABLE (
    ID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Amount DECIMAL(10,2)
);

INSERT INTO @MyTableVariable (ID, Name, Amount)
VALUES (1, 'Alice', 100.00), (2, 'Bob', 200.00);

SELECT * FROM @MyTableVariable;

-- No DROP needed - automatically cleaned up
```

**Characteristics**:
- ✅ **Faster for small datasets** (<100 rows, no statistics overhead)
- ✅ **Transaction-scoped** (rolled back automatically with transaction)
- ✅ **No explicit cleanup** (automatically destroyed at end of scope)
- ✅ **Minimal locking** (less contention in tempdb)
- ❌ **No statistics** (SQL Server assumes 1 row, terrible estimates for large datasets)
- ❌ **Limited index support** (only at declaration time)
- ❌ **Not visible** to nested procedures (scope is current procedure only)

---

## The Decision Matrix

### Use Temp Tables When:

1. **Row count > 1,000**
   - Statistics become critical for good query plans
   - Table variables assume 1 row, plan fails catastrophically

2. **Need explicit indexes**
   - Create index after inserting data
   - Different indexes for different query patterns

3. **Called from nested procedures**
   - Parent procedure creates #temp table
   - Child procedure uses it

4. **Complex queries with JOINs**
   - Statistics help optimizer choose correct JOIN order
   - Nested loop vs hash join vs merge join

5. **Recompile is expensive**
   - Large procedure with many statements
   - Temp table statistics improve overall plan

---

### Use Table Variables When:

1. **Row count < 100**
   - Statistics overhead not worth it
   - Simple query plans work fine

2. **Simple lookups only**
   - No complex JOINs
   - No aggregations
   - Basic INSERT/SELECT

3. **Transaction isolation needed**
   - Rollback must remove data
   - Temp tables survive rollback

4. **Avoiding tempdb contention**
   - High-concurrency environment
   - 1000+ procedures running simultaneously

5. **Short-lived data**
   - Created and destroyed within single statement batch
   - No cross-procedure sharing needed

---

## Performance Comparison

### Scenario 1: Small Dataset (50 rows)

**Temp Table**:
```sql
CREATE TABLE #SmallTemp (ID INT PRIMARY KEY, Name NVARCHAR(100));
INSERT INTO #SmallTemp SELECT TOP 50 CustomerID, CustomerName FROM Customers;
SELECT * FROM #SmallTemp WHERE ID = 25;
DROP TABLE #SmallTemp;

-- Execution time: 12 ms
-- Logical reads: 8 pages
-- Tempdb activity: 3 pages written
```

**Table Variable**:
```sql
DECLARE @SmallTable TABLE (ID INT PRIMARY KEY, Name NVARCHAR(100));
INSERT INTO @SmallTable SELECT TOP 50 CustomerID, CustomerName FROM Customers;
SELECT * FROM @SmallTable WHERE ID = 25;

-- Execution time: 3 ms (4x faster!)
-- Logical reads: 2 pages
-- Tempdb activity: 0 pages written
```

**Winner**: Table Variable (less overhead)

---

### Scenario 2: Medium Dataset (500 rows)

**Temp Table**:
```sql
CREATE TABLE #MediumTemp (ID INT, Name NVARCHAR(100), Amount DECIMAL(10,2));
INSERT INTO #MediumTemp SELECT TOP 500 CustomerID, CustomerName, TotalSpent FROM Customers;
CREATE INDEX IX_Amount ON #MediumTemp(Amount);  -- Explicit index
SELECT AVG(Amount) FROM #MediumTemp WHERE Amount > 1000;
DROP TABLE #MediumTemp;

-- Execution time: 45 ms
-- Logical reads: 25 pages
-- Plan: Index seek (statistics helped)
```

**Table Variable**:
```sql
DECLARE @MediumTable TABLE (
    ID INT,
    Name NVARCHAR(100),
    Amount DECIMAL(10,2),
    INDEX IX_Amount (Amount)  -- Index at declaration only
);
INSERT INTO @MediumTable SELECT TOP 500 CustomerID, CustomerName, TotalSpent FROM Customers;
SELECT AVG(Amount) FROM @MediumTable WHERE Amount > 1000;

-- Execution time: 52 ms
-- Logical reads: 30 pages
-- Plan: Table scan (no statistics, bad estimate)
```

**Winner**: Temp Table (statistics + explicit index)

---

### Scenario 3: Large Dataset (50,000 rows)

**Temp Table**:
```sql
CREATE TABLE #LargeTemp (ID INT, OrderDate DATE, Amount DECIMAL(10,2));
INSERT INTO #LargeTemp SELECT OrderID, OrderDate, Amount FROM Orders WHERE YEAR(OrderDate) = 2024;
CREATE INDEX IX_OrderDate ON #LargeTemp(OrderDate);
CREATE INDEX IX_Amount ON #LargeTemp(Amount);

SELECT OrderDate, SUM(Amount)
FROM #LargeTemp
WHERE OrderDate >= '2024-10-01'
GROUP BY OrderDate;

DROP TABLE #LargeTemp;

-- Execution time: 850 ms
-- Logical reads: 450 pages
-- Plan: Index seek + stream aggregate (good plan)
```

**Table Variable**:
```sql
DECLARE @LargeTable TABLE (
    ID INT,
    OrderDate DATE,
    Amount DECIMAL(10,2),
    INDEX IX_OrderDate (OrderDate),
    INDEX IX_Amount (Amount)
);
INSERT INTO @LargeTable SELECT OrderID, OrderDate, Amount FROM Orders WHERE YEAR(OrderDate) = 2024;

SELECT OrderDate, SUM(Amount)
FROM @LargeTable
WHERE OrderDate >= '2024-10-01'
GROUP BY OrderDate;

-- Execution time: 12,400 ms (14x slower!!!)
-- Logical reads: 8,500 pages
-- Plan: Table scan + hash aggregate (terrible plan, SQL Server thinks 1 row exists)
```

**Winner**: Temp Table (statistics critical for large datasets)

---

## Real-World Examples

### Example 1: ETL Process (Use Temp Table)

**Scenario**: Import 100,000 customer orders, validate, transform, load into production table.

```sql
CREATE PROCEDURE usp_ImportOrders
    @FileName NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    -- Create staging temp table
    CREATE TABLE #StagingOrders (
        OrderID INT,
        CustomerID INT,
        OrderDate DATE,
        Amount DECIMAL(10,2),
        Status NVARCHAR(50),
        IsValid BIT DEFAULT 1,
        ErrorMessage NVARCHAR(MAX)
    );

    -- Bulk load from file
    BULK INSERT #StagingOrders
    FROM @FileName
    WITH (FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', FIRSTROW = 2);

    -- Create indexes for validation queries
    CREATE INDEX IX_CustomerID ON #StagingOrders(CustomerID);
    CREATE INDEX IX_OrderDate ON #StagingOrders(OrderDate);

    -- Validate: Check if customers exist
    UPDATE s
    SET IsValid = 0, ErrorMessage = 'Customer not found'
    FROM #StagingOrders s
    LEFT JOIN Customers c ON s.CustomerID = c.CustomerID
    WHERE c.CustomerID IS NULL;

    -- Validate: Check date range
    UPDATE #StagingOrders
    SET IsValid = 0, ErrorMessage = 'Invalid order date'
    WHERE OrderDate > GETDATE() OR OrderDate < '2020-01-01';

    -- Load valid orders
    INSERT INTO Orders (OrderID, CustomerID, OrderDate, Amount, Status)
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM #StagingOrders
    WHERE IsValid = 1;

    -- Log errors
    INSERT INTO ErrorLog (OrderID, ErrorMessage, LoadDate)
    SELECT OrderID, ErrorMessage, GETDATE()
    FROM #StagingOrders
    WHERE IsValid = 0;

    DROP TABLE #StagingOrders;

    -- Return results
    SELECT
        (SELECT COUNT(*) FROM Orders WHERE LoadDate = CAST(GETDATE() AS DATE)) AS OrdersLoaded,
        (SELECT COUNT(*) FROM ErrorLog WHERE LoadDate = CAST(GETDATE() AS DATE)) AS ErrorsLogged;
END;
```

**Why Temp Table**:
- 100,000 rows (large dataset)
- Multiple complex queries (JOINs, UPDATEs)
- Need indexes for performance
- Statistics critical for query optimization

---

### Example 2: Simple Lookup List (Use Table Variable)

**Scenario**: Create temporary list of status codes for validation.

```sql
CREATE PROCEDURE usp_ValidateOrderStatus
    @OrderID INT,
    @NewStatus NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Create table variable with valid statuses
    DECLARE @ValidStatuses TABLE (
        StatusCode NVARCHAR(50) PRIMARY KEY,
        Description NVARCHAR(200)
    );

    -- Populate valid statuses (small, static list)
    INSERT INTO @ValidStatuses (StatusCode, Description) VALUES
        ('Pending', 'Order pending review'),
        ('Approved', 'Order approved for processing'),
        ('Shipped', 'Order shipped to customer'),
        ('Delivered', 'Order delivered successfully'),
        ('Cancelled', 'Order cancelled by customer');

    -- Validate new status
    IF NOT EXISTS (SELECT 1 FROM @ValidStatuses WHERE StatusCode = @NewStatus)
    BEGIN
        THROW 50001, 'Invalid status code', 1;
    END;

    -- Update order
    UPDATE Orders SET Status = @NewStatus WHERE OrderID = @OrderID;

    -- Return updated order
    SELECT * FROM Orders WHERE OrderID = @OrderID;
END;
```

**Why Table Variable**:
- Only 5 rows (tiny dataset)
- Simple lookup (no complex queries)
- Short-lived (created and destroyed in same procedure)
- No statistics needed

---

### Example 3: Report Generation (Use Temp Table)

**Scenario**: Monthly sales report aggregating data from multiple sources.

```sql
CREATE PROCEDURE usp_MonthlySalesReport
    @Year INT,
    @Month INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Temp table for sales data
    CREATE TABLE #SalesData (
        SaleID INT,
        SaleDate DATE,
        CustomerID INT,
        ProductID INT,
        Quantity INT,
        UnitPrice DECIMAL(10,2),
        TotalAmount DECIMAL(10,2),
        Region NVARCHAR(50)
    );

    -- Populate from multiple sources
    INSERT INTO #SalesData
    SELECT
        s.SaleID,
        s.SaleDate,
        s.CustomerID,
        s.ProductID,
        s.Quantity,
        s.UnitPrice,
        s.Quantity * s.UnitPrice AS TotalAmount,
        c.Region
    FROM Sales s
    INNER JOIN Customers c ON s.CustomerID = c.CustomerID
    WHERE YEAR(s.SaleDate) = @Year AND MONTH(s.SaleDate) = @Month;

    -- Add missing regions from another table
    INSERT INTO #SalesData
    SELECT
        os.OrderID,
        os.OrderDate,
        os.CustomerID,
        os.ProductID,
        os.Quantity,
        os.Price,
        os.Quantity * os.Price,
        r.RegionName
    FROM OnlineSales os
    INNER JOIN Regions r ON os.RegionID = r.RegionID
    WHERE YEAR(os.OrderDate) = @Year AND MONTH(os.OrderDate) = @Month;

    -- Create indexes for aggregation queries
    CREATE INDEX IX_Region ON #SalesData(Region);
    CREATE INDEX IX_ProductID ON #SalesData(ProductID);
    CREATE INDEX IX_CustomerID ON #SalesData(CustomerID);

    -- Report 1: Sales by region
    SELECT
        Region,
        COUNT(*) AS TotalSales,
        SUM(TotalAmount) AS Revenue,
        AVG(TotalAmount) AS AvgSaleAmount
    FROM #SalesData
    GROUP BY Region
    ORDER BY Revenue DESC;

    -- Report 2: Top 10 customers
    SELECT TOP 10
        CustomerID,
        c.CustomerName,
        COUNT(*) AS PurchaseCount,
        SUM(TotalAmount) AS TotalSpent
    FROM #SalesData s
    INNER JOIN Customers c ON s.CustomerID = c.CustomerID
    GROUP BY CustomerID, c.CustomerName
    ORDER BY TotalSpent DESC;

    -- Report 3: Top 10 products
    SELECT TOP 10
        ProductID,
        p.ProductName,
        SUM(Quantity) AS TotalQuantitySold,
        SUM(TotalAmount) AS Revenue
    FROM #SalesData s
    INNER JOIN Products p ON s.ProductID = p.ProductID
    GROUP BY ProductID, p.ProductName
    ORDER BY Revenue DESC;

    DROP TABLE #SalesData;
END;
```

**Why Temp Table**:
- 10,000+ rows (medium-large dataset)
- Multiple complex queries (aggregations, JOINs, GROUP BY)
- Multiple indexes needed for different queries
- Statistics critical for query optimizer

---

## Advanced Techniques

### Technique 1: Hybrid Approach (Best of Both)

Use table variable for initial filter, then temp table for heavy lifting.

```sql
CREATE PROCEDURE usp_ProcessLargeDataset
AS
BEGIN
    -- Step 1: Quick filter with table variable (100 rows)
    DECLARE @QuickFilter TABLE (CustomerID INT PRIMARY KEY);

    INSERT INTO @QuickFilter
    SELECT DISTINCT CustomerID
    FROM Orders
    WHERE OrderDate >= DATEADD(DAY, -7, GETDATE())
      AND Status = 'Pending';

    -- Step 2: Use temp table for heavy processing (10,000 rows)
    CREATE TABLE #ProcessingTable (
        CustomerID INT,
        OrderID INT,
        Amount DECIMAL(10,2),
        Priority INT
    );

    INSERT INTO #ProcessingTable
    SELECT o.CustomerID, o.OrderID, o.Amount, c.PriorityLevel
    FROM Orders o
    INNER JOIN @QuickFilter qf ON o.CustomerID = qf.CustomerID  -- Fast join (100 rows)
    INNER JOIN Customers c ON o.CustomerID = c.CustomerID;

    CREATE INDEX IX_Priority ON #ProcessingTable(Priority, Amount);

    -- Process data...
    SELECT Priority, COUNT(*), SUM(Amount)
    FROM #ProcessingTable
    GROUP BY Priority;

    DROP TABLE #ProcessingTable;
END;
```

---

### Technique 2: Table Variable with Trace Flag 2453 (SQL Server 2019+)

Forces SQL Server to create statistics on table variables.

```sql
-- Enable trace flag (session-level)
OPTION (QUERYTRACEON 2453);

DECLARE @LargeTableVar TABLE (
    ID INT,
    Name NVARCHAR(100),
    Amount DECIMAL(10,2)
);

INSERT INTO @LargeTableVar
SELECT TOP 10000 CustomerID, CustomerName, TotalSpent
FROM Customers;

-- Query with statistics (better plan)
SELECT AVG(Amount)
FROM @LargeTableVar
WHERE Amount > 1000
OPTION (QUERYTRACEON 2453);  -- Creates statistics on the fly
```

**When to use**: SQL Server 2019+ only, when table variable must be used (e.g., function return type).

---

### Technique 3: Global Temp Tables (##GlobalTemp)

Shared across multiple sessions.

```sql
-- Session 1: Create global temp table
CREATE TABLE ##SharedData (
    ID INT,
    Name NVARCHAR(100)
);

INSERT INTO ##SharedData VALUES (1, 'Alice'), (2, 'Bob');

-- Session 2: Access global temp table (different connection!)
SELECT * FROM ##SharedData;  -- Works!

-- Session 1: Drop when done
DROP TABLE ##SharedData;
```

**When to use**:
- Multi-session ETL processes
- Parallel data loading
- Shared cache between connections

**Warning**: Security risk (any user can access), use with caution.

---

## Common Mistakes to Avoid

### Mistake 1: Using Table Variable for Large Datasets

```sql
-- BAD: 50,000 rows in table variable
DECLARE @BigTable TABLE (ID INT, Amount DECIMAL(10,2));

INSERT INTO @BigTable
SELECT OrderID, Amount FROM Orders WHERE YEAR(OrderDate) = 2024;  -- 50,000 rows

SELECT SUM(Amount) FROM @BigTable WHERE Amount > 1000;
-- SQL Server thinks 1 row exists
-- Uses nested loop join (expects 1 row, gets 50,000)
-- Query takes 30 seconds instead of 2 seconds
```

**Fix**: Use temp table for > 1,000 rows.

---

### Mistake 2: Not Creating Indexes on Temp Tables

```sql
-- BAD: No index on 10,000 row temp table
CREATE TABLE #NoIndex (CustomerID INT, Amount DECIMAL(10,2));

INSERT INTO #NoIndex
SELECT CustomerID, Amount FROM Orders WHERE YEAR(OrderDate) = 2024;

SELECT CustomerID, SUM(Amount)
FROM #NoIndex
GROUP BY CustomerID;
-- Table scan on 10,000 rows (slow)
```

**Fix**: Create index before querying.

```sql
-- GOOD: Index on temp table
CREATE TABLE #WithIndex (CustomerID INT, Amount DECIMAL(10,2));

INSERT INTO #WithIndex
SELECT CustomerID, Amount FROM Orders WHERE YEAR(OrderDate) = 2024;

CREATE INDEX IX_CustomerID ON #WithIndex(CustomerID);  -- Add index!

SELECT CustomerID, SUM(Amount)
FROM #WithIndex
GROUP BY CustomerID;
-- Index scan (fast)
```

---

### Mistake 3: Forgetting to DROP Temp Tables

```sql
-- BAD: Temp table not dropped
CREATE PROCEDURE usp_ProcessData
AS
BEGIN
    CREATE TABLE #MyTemp (ID INT);
    -- ... processing ...
    -- Missing: DROP TABLE #MyTemp
END;

-- Call procedure 1000 times
-- Tempdb fills up with 1000 temp tables
-- Out of disk space!
```

**Fix**: Always DROP temp tables explicitly.

```sql
CREATE PROCEDURE usp_ProcessData
AS
BEGIN
    CREATE TABLE #MyTemp (ID INT);

    BEGIN TRY
        -- ... processing ...
    END TRY
    BEGIN CATCH
        IF OBJECT_ID('tempdb..#MyTemp') IS NOT NULL
            DROP TABLE #MyTemp;
        THROW;
    END CATCH;

    DROP TABLE #MyTemp;  -- Clean up
END;
```

---

## Performance Tuning Tips

### Tip 1: Use TRUNCATE Instead of DELETE

```sql
-- Slow (row-by-row deletion, logged)
DELETE FROM #MyTemp;

-- Fast (deallocation, minimally logged)
TRUNCATE TABLE #MyTemp;
```

---

### Tip 2: Batch Inserts for Better Performance

```sql
-- Slow (1 million individual INSERTs)
DECLARE @i INT = 1;
WHILE @i <= 1000000
BEGIN
    INSERT INTO #MyTemp (ID) VALUES (@i);
    SET @i = @i + 1;
END;

-- Fast (single batch INSERT)
INSERT INTO #MyTemp (ID)
SELECT TOP 1000000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
```

---

### Tip 3: Monitor Tempdb Usage

```sql
-- Check tempdb space used by temp tables
SELECT
    t.name AS TempTableName,
    SUM(a.total_pages) * 8 / 1024.0 AS SizeMB
FROM tempdb.sys.tables t
INNER JOIN tempdb.sys.partitions p ON t.object_id = p.object_id
INNER JOIN tempdb.sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name LIKE '#%'
GROUP BY t.name
ORDER BY SizeMB DESC;
```

---

## Decision Tree Flowchart

```
┌─────────────────────────────────┐
│ How many rows?                  │
└────────┬────────────────────────┘
         │
    ┌────┴────┐
    │ < 100?  │
    └────┬────┘
         │
    ┌────┴────────────────┐
    │ YES               NO│
    │                     │
    ▼                     ▼
┌────────────┐      ┌──────────────┐
│TABLE       │      │ > 1000?      │
│VARIABLE    │      └──────┬───────┘
└────────────┘             │
                      ┌────┴────┐
                      │YES    NO│
                      │         │
                      ▼         ▼
                 ┌────────┐ ┌────────────┐
                 │TEMP    │ │Test both!  │
                 │TABLE   │ │(100-1000)  │
                 └────────┘ └────────────┘
```

---

## Summary

### Quick Reference

| Feature | Temp Table (#) | Table Variable (@) |
|---------|----------------|-------------------|
| **Size** | Best for > 1,000 rows | Best for < 100 rows |
| **Statistics** | ✅ Yes | ❌ No |
| **Indexes** | ✅ Explicit | ⚠️ Declaration only |
| **Scope** | Session | Batch/Procedure |
| **Transactions** | Survives rollback | Rolled back |
| **Nested procs** | ✅ Visible | ❌ Not visible |
| **Performance** | Better for large | Better for small |

---

**Next Article**: [When CTE is NOT the Best Idea](03-when-cte-is-not-best.md)

**Related Articles**:
- [How to Optimize UPSERT Operations](09-optimize-upsert-operations.md)
- [Error Handling and Logging Best Practices](04-error-handling-logging.md)

---

**Author**: EXAMPLE_CLIENT Technical Team
**Last Updated**: 2025-10-29
**Version**: 1.0
