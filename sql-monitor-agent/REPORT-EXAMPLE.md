# HTML Report - Visual Example

**Report:** `health_report_20251027_181816.html`
**Size:** 656.7 KB
**Databases:** 37 sections
**Total Queries:** 370 (37 databases × 10 queries each)

---

## What You'll See in the Report

### Slow Queries Section (Enhanced)

#### Before Change
```
Top 20 Slow Queries (by Total CPU)

Rank  Database         SQL Text                    Total CPU
----  --------------   -------------------------   -----------
1     DB_Production    SELECT * FROM Orders ...    5,234,567
2     DB_Production    UPDATE Inventory ...        4,987,654
3     DB_Production    DELETE FROM Logs ...        3,876,543
...
18    DB_Production    INSERT INTO Stats ...       1,234,567
19    DB_Analytics     SELECT SUM(Sales) ...         987,654
20    DB_Warehouse     UPDATE Products ...           876,543
```
❌ Problem: Only 2 queries from non-production databases

---

#### After Change (Current)
```
Top 10 Slow Queries per Database (by Total CPU)

📊 Database: DB_Analytics
Rank  Database         SQL Text                    Total CPU    Avg Duration  Executions
----  --------------   -------------------------   -----------  ------------  ----------
1     DB_Analytics     SELECT SUM(Sales) ...         987,654        234.56    4,567
2     DB_Analytics     SELECT AVG(Revenue) ...       876,543        198.23    3,456
3     DB_Analytics     UPDATE DailySummary ...       765,432        156.78    2,345
4     DB_Analytics     INSERT INTO Metrics ...       654,321        134.56    1,234
5     DB_Analytics     DELETE FROM TempData ...      543,210        112.34      987
6     DB_Analytics     SELECT COUNT(*) ...           432,109         98.76      765
7     DB_Analytics     UPDATE MonthlyStats ...       321,098         87.65      654
8     DB_Analytics     SELECT MAX(Value) ...         210,987         76.54      543
9     DB_Analytics     INSERT INTO History ...       109,876         65.43      432
10    DB_Analytics     DELETE FROM Cache ...          98,765         54.32      321

📊 Database: DB_Archive
Rank  Database         SQL Text                    Total CPU    Avg Duration  Executions
----  --------------   -------------------------   -----------  ------------  ----------
1     DB_Archive       SELECT * FROM Logs_2024 ...   765,432        345.67    2,345
2     DB_Archive       DELETE FROM Logs_2023 ...     654,321        298.45    1,876
...

📊 Database: DB_Production
Rank  Database         SQL Text                    Total CPU    Avg Duration  Executions
----  --------------   -------------------------   -----------  ------------  ----------
1     DB_Production    SELECT * FROM Orders ...    5,234,567        567.89    9,876
2     DB_Production    UPDATE Inventory ...        4,987,654        498.76    8,765
3     DB_Production    DELETE FROM Logs ...        3,876,543        387.65    7,654
...
10    DB_Production    INSERT INTO Audit ...       1,234,567        123.45    1,234

📊 Database: DB_Reporting
Rank  Database         SQL Text                    Total CPU    Avg Duration  Executions
----  --------------   -------------------------   -----------  ------------  ----------
1     DB_Reporting     SELECT Report_Data ...        876,543        234.56    3,456
...

📊 Database: DB_Warehouse
Rank  Database         SQL Text                    Total CPU    Avg Duration  Executions
----  --------------   -------------------------   -----------  ------------  ----------
1     DB_Warehouse     UPDATE Products ...           876,543        198.23    3,456
...
```
✅ Benefit: All databases represented with top 10 queries each

---

## Visual Enhancements

### 1. Database Section Headers
Each database group starts with a **highlighted header row**:

```
┌─────────────────────────────────────────────────────┐
│ 📊 Database: DB_Production                         │  ← Gray background, blue top border
├─────┬──────────┬─────────────┬──────────┬──────────┤
│ Rank│ Database │ SQL Text    │ Total CPU│ ...      │
└─────┴──────────┴─────────────┴──────────┴──────────┘
```

**CSS Styling:**
- Background: Light gray (#e8e8e8)
- Top border: Blue 2px (#0078d4)
- Font: Bold
- Icon: 📊 for visual identification

### 2. Database Name Emphasis
Database names in the data rows are **bold** for easy scanning:

```
1  DB_Production  SELECT * FROM ...    ← Database name is bold
2  DB_Production  UPDATE ...
```

### 3. Grouped Presentation
Queries are **grouped by database**, making it easy to:
- Scan for specific database
- Compare query patterns within database
- Identify database-specific performance issues

---

## Benefits by Use Case

### Scenario 1: Multi-Tenant Application
**Databases:** 30+ tenant databases (DB_Tenant001, DB_Tenant002, ...)

**Before:**
- Only see queries from 2-3 largest tenants
- Small tenants' issues hidden

**After:**
- See top 10 queries from **every** tenant
- Easy to identify which tenants have problematic queries
- Fair representation regardless of database size

---

### Scenario 2: Microservices Architecture
**Databases:** Multiple service-specific databases

**Before:**
```
Top 20 Queries:
- 15 from UserService_DB
- 3 from OrderService_DB
- 2 from PaymentService_DB
- 0 from NotificationService_DB  ← Hidden!
- 0 from ReportService_DB        ← Hidden!
```

**After:**
```
📊 Database: NotificationService_DB
  Top 10 queries visible

📊 Database: OrderService_DB
  Top 10 queries visible

📊 Database: PaymentService_DB
  Top 10 queries visible

📊 Database: ReportService_DB
  Top 10 queries visible

📊 Database: UserService_DB
  Top 10 queries visible
```

---

### Scenario 3: Dev/Test/Prod Environments
**Databases:** Mix of environments on same server

**Before:**
- Production databases dominate
- Dev/Test issues invisible

**After:**
- Development databases: Top 10 visible
- Testing databases: Top 10 visible
- Production databases: Top 10 visible
- Can identify issues in any environment

---

## Report Statistics

### Current Report Analysis
```
Total Report Size:     656.7 KB
Total Databases:       37
Total Queries Shown:   370 (37 × 10)
Database Headers:      37 (one per database)
```

### Coverage Comparison
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Databases Shown | 1-3 | 37 | 12× more |
| Total Queries | 20 | 370 | 18.5× more |
| Report Size | 65 KB | 657 KB | 10× larger |
| Coverage | Partial | Complete | 100% |

---

## How to Read the Report

### 1. Navigate to Slow Queries Section
Scroll to **"Top 10 Slow Queries per Database"** section

### 2. Find Your Database
Look for the gray header bar with 📊 icon:
```
📊 Database: YourDatabaseName
```

### 3. Review Top Queries
Examine the 10 queries listed under your database:
- **Rank 1-3:** Critical - highest CPU consumers
- **Rank 4-7:** Important - moderate CPU usage
- **Rank 8-10:** Watch - lower but still notable

### 4. Analyze Patterns
Look for:
- **Missing indexes** - High Avg Reads
- **Long-running queries** - High Avg Duration
- **Frequent executions** - High Execution Count
- **Inefficient queries** - High CPU + High Duration

### 5. Compare Across Databases
Scroll through all database sections to:
- Identify databases with similar issues
- Find patterns (e.g., all analytics DBs have slow aggregations)
- Prioritize which databases need attention

---

## Example Analysis

### Database: DB_Analytics
```
📊 Database: DB_Analytics

Rank  SQL Text                      Total CPU    Avg Duration  Executions
----  ---------------------------   -----------  ------------  ----------
1     SELECT SUM(Sales) ...           987,654        234.56    4,567
2     SELECT AVG(Revenue) ...         876,543        198.23    3,456
3     UPDATE DailySummary ...         765,432        156.78    2,345
```

**Analysis:**
- ✅ Top query: Aggregation (SUM) - expected for analytics
- ⚠️ 4,567 executions - possibly running too frequently
- 💡 Recommendation: Consider caching or materialized view

---

### Database: DB_Production
```
📊 Database: DB_Production

Rank  SQL Text                      Total CPU    Avg Duration  Executions
----  ---------------------------   -----------  ------------  ----------
1     SELECT * FROM Orders ...      5,234,567        567.89    9,876
```

**Analysis:**
- ❌ SELECT * - retrieving all columns
- ❌ 567ms average duration - very slow
- ❌ 9,876 executions - high frequency
- 💡 Recommendation: Add specific columns, create covering index

---

## Summary

**What Changed:** Top 20 overall → Top 10 per database
**Visual Impact:** Database section headers with 📊 icons
**File Location:** `E:\Downloads\sql_monitor\reports\health_report_20251027_181816.html`
**Size:** 656.7 KB (still opens instantly in browser)
**Databases:** 37 sections
**Coverage:** 100% of databases on server

**Open the report to see:**
- ✅ Visual database grouping with headers
- ✅ Top 10 queries from **every** database
- ✅ Easy navigation and scanning
- ✅ Comprehensive performance insight
