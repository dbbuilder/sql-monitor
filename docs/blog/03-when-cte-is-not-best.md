# When CTE is NOT the Best Idea

**Category**: Performance Tuning
**Difficulty**: Intermediate
**Reading Time**: 10 minutes
**Last Updated**: 2025-10-29

---

## Problem Statement

CTEs (Common Table Expressions) are elegant and readable. They make complex queries easier to understand. But they can also **destroy performance** when used incorrectly.

**Real-World Impact**:
- Report query: 12 minutes → 15 seconds (switched from CTE to temp table)
- Dashboard load: Timeout → 3 seconds
- ETL process: 2 hours → 20 minutes

---

## What is a CTE?

**Common Table Expression**: A temporary named result set that exists only for the duration of a single query.

```sql
-- Basic CTE syntax
WITH SalesData AS (
    SELECT
        CustomerID,
        SUM(Amount) AS TotalSales
    FROM Orders
    WHERE YEAR(OrderDate) = 2024
    GROUP BY CustomerID
)
SELECT * FROM SalesData WHERE TotalSales > 10000;
```

**Benefits**:
- ✅ **Readable**: Breaks complex query into logical steps
- ✅ **Maintainable**: Easier to understand than nested subqueries
- ✅ **Recursive**: Supports hierarchical data (org charts, bill of materials)

**Limitations**:
- ❌ **No materialization**: Not stored, re-executed for each reference
- ❌ **No indexes**: Can't create index on CTE
- ❌ **No statistics**: SQL Server doesn't know row count or data distribution
- ❌ **Scope**: Exists only for single SELECT/INSERT/UPDATE/DELETE statement

---

## When CTEs Hurt Performance

### Problem 1: Multiple References = Multiple Executions

**The Trap**: Referencing a CTE multiple times executes it multiple times.

```sql
-- BAD: CTE executed 3 times!
WITH SalesData AS (
    SELECT CustomerID, SUM(Amount) AS Total
    FROM Orders
    WHERE Year = 2024  -- Scans 10 million rows
    GROUP BY CustomerID  -- Expensive aggregation
)
SELECT
    (SELECT AVG(Total) FROM SalesData) AS AvgSales,      -- Executes CTE (10M rows scanned)
    (SELECT MAX(Total) FROM SalesData) AS MaxSales,      -- Executes CTE again (10M rows)
    (SELECT MIN(Total) FROM SalesData) AS MinSales,      -- Executes CTE again (10M rows)
    (SELECT COUNT(*) FROM SalesData WHERE Total > 5000) AS HighValueCustomers  -- Executes CTE again!
FROM SalesData;  -- And one more time here!

-- Total: 30 million rows scanned (10M × 3 references)
-- Execution time: 45 seconds
```

**The Fix**: Use temp table (executed once, reused 4 times).

```sql
-- GOOD: Temp table executed once
SELECT CustomerID, SUM(Amount) AS Total
INTO #SalesData
FROM Orders
WHERE Year = 2024  -- Scans 10 million rows (once)
GROUP BY CustomerID;  -- Expensive aggregation (once)

CREATE INDEX IX_Total ON #SalesData(Total);  -- Index for fast queries

SELECT
    (SELECT AVG(Total) FROM #SalesData) AS AvgSales,      -- Uses temp table (instant)
    (SELECT MAX(Total) FROM #SalesData) AS MaxSales,      -- Uses temp table (instant)
    (SELECT MIN(Total) FROM #SalesData) AS MinSales,      -- Uses temp table (instant)
    (SELECT COUNT(*) FROM #SalesData WHERE Total > 5000) AS HighValueCustomers;  -- Index seek!

DROP TABLE #SalesData;

-- Total: 10 million rows scanned (once)
-- Execution time: 3 seconds (15x faster!)
```

---

### Problem 2: Large Result Sets Without Indexes

**The Trap**: CTEs can't have indexes, so large result sets cause table scans.

```sql
-- BAD: CTE with 50,000 rows, no index
WITH OrderDetails AS (
    SELECT
        o.OrderID,
        o.OrderDate,
        o.CustomerID,
        c.CustomerName,
        p.ProductID,
        p.ProductName,
        od.Quantity,
        od.UnitPrice
    FROM Orders o
    INNER JOIN Customers c ON o.CustomerID = c.CustomerID
    INNER JOIN OrderDetails od ON o.OrderID = od.OrderID
    INNER JOIN Products p ON od.ProductID = p.ProductID
    WHERE YEAR(o.OrderDate) = 2024
)
SELECT
    ProductName,
    SUM(Quantity) AS TotalQuantity,
    SUM(Quantity * UnitPrice) AS TotalRevenue
FROM OrderDetails  -- Table scan on 50,000 rows (no index)
WHERE CustomerName LIKE 'A%'  -- String filter on 50,000 rows
GROUP BY ProductName
ORDER BY TotalRevenue DESC;

-- Execution time: 8 seconds
```

**The Fix**: Use temp table with indexes.

```sql
-- GOOD: Temp table with indexes
SELECT
    o.OrderID,
    o.OrderDate,
    o.CustomerID,
    c.CustomerName,
    p.ProductID,
    p.ProductName,
    od.Quantity,
    od.UnitPrice
INTO #OrderDetails
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
INNER JOIN OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN Products p ON od.ProductID = p.ProductID
WHERE YEAR(o.OrderDate) = 2024;

-- Create index on filter column
CREATE INDEX IX_CustomerName ON #OrderDetails(CustomerName) INCLUDE (ProductName, Quantity, UnitPrice);

SELECT
    ProductName,
    SUM(Quantity) AS TotalQuantity,
    SUM(Quantity * UnitPrice) AS TotalRevenue
FROM #OrderDetails
WHERE CustomerName LIKE 'A%'  -- Index seek! (not table scan)
GROUP BY ProductName
ORDER BY TotalRevenue DESC;

DROP TABLE #OrderDetails;

-- Execution time: 1 second (8x faster!)
```

---

### Problem 3: Recursive CTEs Without Proper Termination

**The Trap**: Infinite loops cause query timeouts.

```sql
-- BAD: Recursive CTE with no termination (infinite loop)
WITH EmployeeHierarchy AS (
    -- Anchor: Top-level employees
    SELECT EmployeeID, ManagerID, EmployeeName, 1 AS Level
    FROM Employees
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive: All employees
    SELECT e.EmployeeID, e.ManagerID, e.EmployeeName, eh.Level + 1
    FROM Employees e
    INNER JOIN EmployeeHierarchy eh ON e.ManagerID = eh.EmployeeID
    -- Missing termination condition!
)
SELECT * FROM EmployeeHierarchy;

-- Error after 100 recursions (default MAXRECURSION)
-- Or infinite loop if MAXRECURSION = 0
```

**The Fix**: Add termination condition and reasonable MAXRECURSION.

```sql
-- GOOD: Recursive CTE with termination
WITH EmployeeHierarchy AS (
    -- Anchor
    SELECT EmployeeID, ManagerID, EmployeeName, 1 AS Level
    FROM Employees
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive with level limit
    SELECT e.EmployeeID, e.ManagerID, e.EmployeeName, eh.Level + 1
    FROM Employees e
    INNER JOIN EmployeeHierarchy eh ON e.ManagerID = eh.EmployeeID
    WHERE eh.Level < 10  -- Termination: Max 10 levels deep
)
SELECT * FROM EmployeeHierarchy
OPTION (MAXRECURSION 20);  -- Safety: Stop after 20 recursions

-- Execution time: 50 ms
```

---

## When CTEs Are Great

### Use Case 1: Single Reference, Small Result Set

```sql
-- GOOD: CTE referenced once, 100 rows
WITH TopCustomers AS (
    SELECT TOP 100 CustomerID, CustomerName, TotalSpent
    FROM Customers
    ORDER BY TotalSpent DESC
)
SELECT
    tc.CustomerName,
    COUNT(o.OrderID) AS OrderCount,
    SUM(o.Amount) AS TotalRevenue
FROM TopCustomers tc
INNER JOIN Orders o ON tc.CustomerID = o.CustomerID
GROUP BY tc.CustomerName;

-- Perfect use case:
-- ✅ Single reference (CTE only used once)
-- ✅ Small result set (100 rows)
-- ✅ Simple aggregation
```

---

### Use Case 2: Readability Is Critical (Maintenance)

```sql
-- GOOD: CTE makes complex query understandable
WITH MonthlyRevenue AS (
    SELECT
        YEAR(OrderDate) AS Year,
        MONTH(OrderDate) AS Month,
        SUM(Amount) AS Revenue
    FROM Orders
    GROUP BY YEAR(OrderDate), MONTH(OrderDate)
),
QuarterlyRevenue AS (
    SELECT
        Year,
        CEILING(Month / 3.0) AS Quarter,
        SUM(Revenue) AS QuarterRevenue
    FROM MonthlyRevenue
    GROUP BY Year, CEILING(Month / 3.0)
)
SELECT
    Year,
    Quarter,
    QuarterRevenue,
    LAG(QuarterRevenue, 1) OVER (ORDER BY Year, Quarter) AS PreviousQuarterRevenue,
    QuarterRevenue - LAG(QuarterRevenue, 1) OVER (ORDER BY Year, Quarter) AS Growth
FROM QuarterlyRevenue
ORDER BY Year, Quarter;

-- Benefits:
-- ✅ Each CTE has clear purpose (monthly → quarterly → growth)
-- ✅ Easy to debug (test each CTE independently)
-- ✅ Easy to maintain (add new calculations)
```

---

### Use Case 3: Hierarchical Data (Recursive CTEs)

```sql
-- GOOD: Recursive CTE for org chart
WITH OrgChart AS (
    -- Anchor: CEO
    SELECT
        EmployeeID,
        EmployeeName,
        ManagerID,
        Title,
        CAST(EmployeeName AS NVARCHAR(MAX)) AS HierarchyPath,
        1 AS Level
    FROM Employees
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive: Direct reports
    SELECT
        e.EmployeeID,
        e.EmployeeName,
        e.ManagerID,
        e.Title,
        CAST(oc.HierarchyPath + ' > ' + e.EmployeeName AS NVARCHAR(MAX)),
        oc.Level + 1
    FROM Employees e
    INNER JOIN OrgChart oc ON e.ManagerID = oc.EmployeeID
    WHERE oc.Level < 20  -- Reasonable depth limit
)
SELECT
    REPLICATE('  ', Level - 1) + EmployeeName AS EmployeeName,
    Title,
    HierarchyPath,
    Level
FROM OrgChart
ORDER BY HierarchyPath
OPTION (MAXRECURSION 50);

-- Perfect use case:
-- ✅ Recursive data (manager-employee hierarchy)
-- ✅ Termination condition (level limit)
-- ✅ Clear hierarchy visualization
```

---

## Performance Comparison Table

| Scenario | CTE | Temp Table | Winner | Reason |
|----------|-----|------------|--------|--------|
| **Single reference, <1000 rows** | 50 ms | 60 ms | CTE | No overhead |
| **Multiple references, <1000 rows** | 200 ms | 70 ms | Temp Table | CTE executed 3× |
| **Single reference, 50,000 rows** | 2 sec | 800 ms | Temp Table | CTE no index |
| **Multiple references, 50,000 rows** | 12 sec | 1 sec | Temp Table | 12× faster |
| **Recursive, 500 rows** | 80 ms | N/A | CTE | Only option |

---

## Real-World Example: Dashboard Report

### Scenario: Executive Dashboard (5 Metrics from Same Data)

**BAD: CTE Referenced 5 Times**

```sql
WITH SalesData AS (
    SELECT
        s.SaleID,
        s.SaleDate,
        s.CustomerID,
        s.ProductID,
        s.Quantity,
        s.UnitPrice,
        s.Quantity * s.UnitPrice AS TotalAmount,
        c.Region,
        p.Category
    FROM Sales s
    INNER JOIN Customers c ON s.CustomerID = c.CustomerID
    INNER JOIN Products p ON s.ProductID = p.ProductID
    WHERE s.SaleDate >= DATEADD(MONTH, -1, GETDATE())  -- Last month
)
SELECT
    -- Metric 1: Total Revenue
    (SELECT SUM(TotalAmount) FROM SalesData) AS TotalRevenue,

    -- Metric 2: Total Sales
    (SELECT COUNT(*) FROM SalesData) AS TotalSales,

    -- Metric 3: Avg Sale Amount
    (SELECT AVG(TotalAmount) FROM SalesData) AS AvgSaleAmount,

    -- Metric 4: Top Region
    (SELECT TOP 1 Region FROM SalesData GROUP BY Region ORDER BY SUM(TotalAmount) DESC) AS TopRegion,

    -- Metric 5: Top Category
    (SELECT TOP 1 Category FROM SalesData GROUP BY Category ORDER BY SUM(TotalAmount) DESC) AS TopCategory;

-- CTE executed 5 times = 5× data scan
-- Execution time: 25 seconds
```

**GOOD: Temp Table Referenced 5 Times**

```sql
-- Execute once, reuse 5 times
SELECT
    s.SaleID,
    s.SaleDate,
    s.CustomerID,
    s.ProductID,
    s.Quantity,
    s.UnitPrice,
    s.Quantity * s.UnitPrice AS TotalAmount,
    c.Region,
    p.Category
INTO #SalesData
FROM Sales s
INNER JOIN Customers c ON s.CustomerID = c.CustomerID
INNER JOIN Products p ON s.ProductID = p.ProductID
WHERE s.SaleDate >= DATEADD(MONTH, -1, GETDATE());

-- Create indexes for fast aggregation
CREATE INDEX IX_TotalAmount ON #SalesData(TotalAmount);
CREATE INDEX IX_Region ON #SalesData(Region) INCLUDE (TotalAmount);
CREATE INDEX IX_Category ON #SalesData(Category) INCLUDE (TotalAmount);

SELECT
    -- Metric 1: Total Revenue (index scan)
    (SELECT SUM(TotalAmount) FROM #SalesData) AS TotalRevenue,

    -- Metric 2: Total Sales (index scan)
    (SELECT COUNT(*) FROM #SalesData) AS TotalSales,

    -- Metric 3: Avg Sale Amount (index scan)
    (SELECT AVG(TotalAmount) FROM #SalesData) AS AvgSaleAmount,

    -- Metric 4: Top Region (index seek)
    (SELECT TOP 1 Region FROM #SalesData GROUP BY Region ORDER BY SUM(TotalAmount) DESC) AS TopRegion,

    -- Metric 5: Top Category (index seek)
    (SELECT TOP 1 Category FROM #SalesData GROUP BY Category ORDER BY SUM(TotalAmount) DESC) AS TopCategory;

DROP TABLE #SalesData;

-- Temp table executed once, indexed queries
-- Execution time: 3 seconds (8× faster!)
```

---

## Advanced Technique: Materialized CTE (SQL Server 2022+)

SQL Server 2022 introduces **materialized CTEs** with the `MATERIALIZE` hint.

```sql
-- SQL Server 2022+: Force CTE materialization
WITH SalesData AS MATERIALIZED (
    SELECT CustomerID, SUM(Amount) AS Total
    FROM Orders
    WHERE Year = 2024
    GROUP BY CustomerID
)
SELECT
    (SELECT AVG(Total) FROM SalesData) AS AvgSales,
    (SELECT MAX(Total) FROM SalesData) AS MaxSales,
    (SELECT MIN(Total) FROM SalesData) AS MinSales;

-- CTE materialized once, reused 3 times
-- Similar performance to temp table
```

**Note**: Only available in SQL Server 2022+. For older versions, use temp table.

---

## Decision Tree

```
┌─────────────────────────────────────┐
│ Will CTE be referenced > 1 time?    │
└────────┬────────────────────────────┘
         │
    ┌────┴────┐
    │ YES   NO│
    │         │
    ▼         ▼
┌──────────┐  ┌─────────────────────┐
│TEMP      │  │ Result set > 1000?  │
│TABLE     │  └──────┬──────────────┘
└──────────┘         │
                ┌────┴────┐
                │ YES   NO│
                │         │
                ▼         ▼
           ┌──────────┐  ┌─────────┐
           │TEMP      │  │CTE      │
           │TABLE     │  │(simple) │
           └──────────┘  └─────────┘
```

---

## Common Mistakes to Avoid

### Mistake 1: Nested CTEs That Reference Each Other Multiple Times

```sql
-- BAD: CTE1 referenced by CTE2 and main query
WITH CTE1 AS (
    SELECT CustomerID, SUM(Amount) AS Total
    FROM Orders
    GROUP BY CustomerID  -- Expensive aggregation
),
CTE2 AS (
    SELECT CustomerID, Total, Total * 0.1 AS Commission
    FROM CTE1  -- References CTE1 (execution 1)
)
SELECT
    cte1.CustomerID,
    cte1.Total,
    cte2.Commission,
    cte1.Total + cte2.Commission AS GrandTotal  -- References CTE1 again (execution 2)
FROM CTE1 cte1
INNER JOIN CTE2 cte2 ON cte1.CustomerID = cte2.CustomerID;

-- CTE1 executed twice!
```

---

### Mistake 2: Using CTE Instead of Derived Table for Single Use

```sql
-- BAD: CTE for single simple use
WITH SimpleFilter AS (
    SELECT * FROM Customers WHERE Region = 'USA'
)
SELECT * FROM SimpleFilter WHERE TotalSpent > 1000;

-- BETTER: Derived table (no CTE overhead)
SELECT * FROM (
    SELECT * FROM Customers WHERE Region = 'USA'
) AS SimpleFilter
WHERE TotalSpent > 1000;

-- Or even better: Single query
SELECT * FROM Customers
WHERE Region = 'USA' AND TotalSpent > 1000;
```

---

## Summary

### When to Use CTE

✅ **Single reference** (CTE used only once)
✅ **Small result set** (<1,000 rows)
✅ **Readability critical** (maintenance priority)
✅ **Recursive queries** (hierarchies, graphs)
✅ **SQL Server 2022+** with MATERIALIZE hint

### When to Use Temp Table

✅ **Multiple references** (CTE would execute 2+ times)
✅ **Large result set** (>1,000 rows)
✅ **Need indexes** (performance critical)
✅ **Complex transformations** (multi-step ETL)
✅ **Cross-procedure sharing** (nested stored procedures)

---

**Next Article**: [Error Handling and Logging Best Practices](04-error-handling-logging.md)

**Related Articles**:
- [Temp Tables vs Table Variables](02-temp-tables-vs-table-variables.md)
- [How to Manage Mammoth Tables Effectively](11-manage-mammoth-tables.md)

---

**Author**: ArcTrade Technical Team
**Last Updated**: 2025-10-29
**Version**: 1.0
