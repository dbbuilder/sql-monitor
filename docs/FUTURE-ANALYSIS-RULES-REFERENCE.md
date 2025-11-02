# Future T-SQL Analysis Rules Reference

**Purpose**: Document the 230+ additional rules from SQLenlight and other commercial tools that we are NOT implementing in Phase 3 Feature #7, but may consider for future phases.

**Date**: 2025-11-02
**Status**: Reference for Phase 4+

---

## Overview

Our Phase 3 Feature #7 implementation focuses on **~30 critical rules** that provide the most value for SQL Server monitoring and code analysis. This document catalogs the **230+ additional rules** from commercial tools (primarily SQLenlight) that we are explicitly NOT implementing yet, organized by priority for future consideration.

---

## SQLenlight Rules NOT Implemented (230+ rules)

SQLenlight has 260+ rules across 6 categories. We're implementing ~30 in Phase 3. Here are the remaining rules organized by potential value for future phases.

### Performance Rules - Deferred (P011-P080, ~70 rules)

#### High Priority for Phase 4 (Consider implementing)

**P011: NOLOCK Overuse Detection**
- **Description**: Detects excessive use of NOLOCK hint (dirty reads)
- **Why Deferred**: Requires understanding of transaction isolation requirements
- **Effort**: Low (regex pattern)
- **Value**: Medium (prevents data consistency issues)

**P012: Missing Query Store Hints**
- **Description**: Queries that would benefit from OPTION (USE HINT('QUERY_STORE'))
- **Why Deferred**: Requires Query Store integration and pattern analysis
- **Effort**: Medium
- **Value**: High (improves plan stability)

**P013: Excessive Sorting Detection**
- **Description**: Queries with ORDER BY on large result sets without indexes
- **Why Deferred**: Requires execution plan analysis
- **Effort**: High (plan XML parsing)
- **Value**: High (major performance impact)

**P014: Implicit Conversion in JOIN Conditions**
- **Description**: Detects data type mismatches in JOIN predicates
- **Why Deferred**: Requires schema metadata and type analysis
- **Effort**: Medium
- **Value**: High (prevents index usage)

**P015: Key Lookup Detection**
- **Description**: Identifies queries with excessive key lookups (missing covering indexes)
- **Why Deferred**: Requires execution plan analysis
- **Effort**: High
- **Value**: High (major I/O reduction opportunity)

**P016: Large Object Reads in SELECT List**
- **Description**: VARCHAR(MAX), NVARCHAR(MAX), VARBINARY(MAX) columns in SELECT when not needed
- **Why Deferred**: Requires schema metadata
- **Effort**: Medium
- **Value**: Medium (reduces memory grants and I/O)

**P017: Table Variable Misuse**
- **Description**: Large table variables (use temp tables instead for >100 rows)
- **Why Deferred**: Requires cardinality estimation understanding
- **Effort**: Low (pattern detection)
- **Value**: High (prevents bad cardinality estimates)

**P018: CTE Instead of Temp Table**
- **Description**: Recursive CTEs or CTEs used multiple times (temp table may perform better)
- **Why Deferred**: Requires CTE usage pattern analysis
- **Effort**: Medium
- **Value**: Medium (case-by-case optimization)

**P019: DISTINCT in JOIN Subquery**
- **Description**: DISTINCT used to mask data model issues (missing foreign keys)
- **Why Deferred**: Requires schema analysis
- **Effort**: Medium
- **Value**: Medium (identifies design problems)

**P020: TOP Without ORDER BY**
- **Description**: TOP N used without ORDER BY (non-deterministic results)
- **Why Deferred**: Low effort, good catch
- **Effort**: Low (regex pattern)
- **Value**: High (data integrity issue)

#### Medium Priority for Phase 5+

**P021-P040**: Query Hint Misuse Detection (20 rules)
- FORCESEEK without understanding
- MAXDOP hint hardcoded
- RECOMPILE on every execution
- FORCE ORDER preventing optimization
- OPTIMIZE FOR UNKNOWN misuse
- FORCESCAN on small tables
- KEEPFIXED PLAN inappropriate usage
- ENABLE_QUERY_OPTIMIZER_HOTFIXES
- DISABLE_OPTIMIZER_ROWGOAL
- And 11 other hint-specific rules

**P041-P060**: Advanced Index Usage Analysis (20 rules)
- Missing filtered index opportunities
- Index intersection detection (multi-index reads)
- Index union detection
- Redundant index usage
- Index with low selectivity
- Covering index opportunities
- Columnstore index candidates
- Partitioned index alignment
- Index rebuild vs reorganize heuristics
- And 11 other index-specific rules

**P061-P070**: Memory and Resource Rules (10 rules)
- Excessive memory grant requests
- Spill to tempdb detection
- Parallel plan overhead
- MAXDOP configuration issues
- Resource governor misconfigurations
- And 5 other resource-related rules

#### Low Priority (P071-P080, ~10 rules)
- Trace flag usage detection
- Compatibility level mismatches
- Legacy cardinality estimator usage
- Deprecated query hints
- Statistics maintenance hints
- And 5 other edge-case rules

---

### Design Rules - Deferred (D011-D060, ~50 rules)

#### High Priority for Phase 4

**D011: Missing Indexes on Foreign Keys**
- **Description**: Foreign key columns without supporting indexes
- **Why Deferred**: We'll implement this with our DMV integration (missing index DMVs)
- **Effort**: Medium (requires schema analysis)
- **Value**: Very High (common performance issue)

**D012: Clustered Index on GUID**
- **Description**: Clustered index on UNIQUEIDENTIFIER (page splits, fragmentation)
- **Why Deferred**: Requires index metadata analysis
- **Effort**: Low
- **Value**: High (prevents fragmentation issues)

**D013: Wide Clustered Index Key**
- **Description**: Clustered index with >3 columns or >100 bytes (bloats nonclustered indexes)
- **Why Deferred**: Requires index metadata
- **Effort**: Low
- **Value**: High (reduces storage and I/O)

**D014: Nullable Columns in Clustered Index**
- **Description**: Nullable columns in clustered index key (potential sorting issues)
- **Why Deferred**: Requires index metadata
- **Effort**: Low
- **Value**: Medium

**D015: Missing Unique Constraint**
- **Description**: Columns that should have unique constraint but don't
- **Why Deferred**: Requires data analysis (detect uniqueness)
- **Effort**: High
- **Value**: Medium (data integrity)

**D016: Over-Normalized Tables**
- **Description**: Excessive table joins (>7 tables) due to over-normalization
- **Why Deferred**: Requires query pattern analysis
- **Effort**: High
- **Value**: Medium (denormalization opportunities)

**D017: Under-Normalized Tables**
- **Description**: Repeating groups, multi-valued columns
- **Why Deferred**: Requires data pattern analysis
- **Effort**: Very High
- **Value**: High (data integrity and performance)

**D018: Inappropriate Data Types**
- **Description**: VARCHAR(8000) when VARCHAR(50) would suffice, INT for boolean flags
- **Why Deferred**: Requires data profiling
- **Effort**: High
- **Value**: Medium (storage optimization)

**D019: Missing CHECK Constraints**
- **Description**: Data validation in application code instead of database
- **Why Deferred**: Requires code analysis + data profiling
- **Effort**: Very High
- **Value**: Medium (data integrity)

**D020: Surrogate Key Without Natural Key**
- **Description**: IDENTITY column but no unique constraint on natural business key
- **Why Deferred**: Requires business logic understanding
- **Effort**: Very High (manual review needed)
- **Value**: Medium

#### Medium Priority for Phase 5+

**D021-D040**: Schema Design Patterns (20 rules)
- Soft delete anti-pattern (IsDeleted bit column)
- Audit columns in transactional tables
- EAV (Entity-Attribute-Value) anti-pattern detection
- Missing created/modified timestamps
- Lack of schema ownership (dbo overuse)
- Generic column names (Data1, Data2, etc.)
- Table-per-type inheritance issues
- Missing default constraints
- Inappropriate column ordering
- And 11 other schema design rules

**D041-D050**: Partitioning and Filegroups (10 rules)
- Partition function misalignment
- Partition scheme on wrong column
- Missing filegroup separation
- Partitioning on low-cardinality column
- And 6 other partitioning rules

#### Low Priority (D051-D060, ~10 rules)
- Column collation mismatches
- Computed column indexing opportunities
- Sparse column opportunities
- Compression opportunities
- And 6 other advanced design rules

---

### Deprecated Features - Deferred (DP009-DP050, ~42 rules)

#### High Priority for Phase 4

**DP009: RAISERROR Instead of THROW**
- **Description**: RAISERROR used instead of THROW (SQL Server 2012+)
- **Effort**: Low (regex pattern)
- **Value**: Medium (modern error handling)

**DP010: GOTO Statement Usage**
- **Description**: GOTO statements (poor code structure)
- **Effort**: Low
- **Value**: Low (code smell, not deprecated)

**DP011: String Concatenation with + for Large Strings**
- **Description**: Use CONCAT() or STRING_AGG() instead
- **Effort**: Low
- **Value**: Medium (prevents NULL propagation issues)

**DP012: ISNULL vs COALESCE**
- **Description**: ISNULL has limitations (type precedence, single replacement)
- **Effort**: Low
- **Value**: Low (prefer COALESCE but ISNULL not deprecated)

#### Medium Priority (DP013-DP040, ~28 rules)
- Old system functions (@@ROWCOUNT vs @@ROWCOUNT_BIG)
- EXECUTE vs sp_executesql
- SET ROWCOUNT instead of TOP
- Legacy date functions (DATEPART vs specific functions)
- @@ERROR instead of TRY/CATCH
- IDENTITY() function in SELECT INTO
- TEXTPTR, TEXTVALID functions
- BACKUP/RESTORE syntax changes
- Database compatibility level issues
- And 19 other deprecated feature rules

#### Low Priority (DP041-DP050, ~10 rules)
- Obscure deprecated features
- Undocumented system procedures
- Trace flags deprecated
- Extended stored procedures
- And 6 other rarely-used deprecated features

---

### Security Rules - Deferred (S006-S040, ~35 rules)

#### High Priority for Phase 4

**S006: Elevated Permissions in Stored Procedures**
- **Description**: Procedures using WITH EXECUTE AS OWNER without justification
- **Effort**: Low (regex pattern)
- **Value**: High (principle of least privilege)

**S007: Cross-Database Ownership Chaining**
- **Description**: Reliance on cross-database ownership chaining (security risk)
- **Effort**: Medium (requires database context analysis)
- **Value**: High (security vulnerability)

**S008: Hardcoded Connection Strings**
- **Description**: Connection strings in code (credentials exposure)
- **Effort**: Low (regex pattern)
- **Value**: Very High (credential leakage)

**S009: Weak Password Complexity**
- **Description**: CREATE LOGIN with simple passwords
- **Effort**: Medium (password strength rules)
- **Value**: High (brute force protection)

**S010: Public Role Permissions**
- **Description**: Permissions granted to public role
- **Effort**: Medium (requires permission analysis)
- **Value**: Very High (over-privileged access)

**S011: Guest User Enabled**
- **Description**: Guest user enabled in non-system databases
- **Effort**: Low (DMV query: sys.database_principals)
- **Value**: High (unauthorized access)

**S012: SQL Authentication with SA Account**
- **Description**: Code using SA account (should use principle-based accounts)
- **Effort**: Low (regex pattern)
- **Value**: Very High (audit trail, least privilege)

**S013: Unencrypted Communication**
- **Description**: Connection strings without Encrypt=True
- **Effort**: Low (regex pattern)
- **Value**: High (man-in-the-middle protection)

**S014: TrustServerCertificate=True in Production**
- **Description**: Disabling certificate validation in production
- **Effort**: Low (regex pattern)
- **Value**: Medium (certificate validation)

**S015: Orphaned Users**
- **Description**: Database users without corresponding logins
- **Effort**: Low (DMV query: sys.database_principals vs sys.server_principals)
- **Value**: Medium (cleanup, security hygiene)

#### Medium Priority for Phase 5+ (S016-S030, ~15 rules)
- Transparent Data Encryption (TDE) not enabled
- Always Encrypted not used for sensitive columns
- Row-level security opportunities
- Dynamic data masking opportunities
- Audit specification missing
- Missing certificate expiration monitoring
- Credential storage in tables
- Backup encryption not enabled
- And 7 other security rules

#### Low Priority (S031-S040, ~10 rules)
- Service account permissions
- Kerberos configuration issues
- Certificate key length requirements
- Linked server security
- And 6 other advanced security rules

---

### Naming Convention Rules - Deferred (N006-N030, ~25 rules)

#### High Priority for Phase 4

**N006: Table Plural Naming**
- **Description**: Inconsistent plural/singular table names (Orders vs Order)
- **Effort**: Low (regex pattern)
- **Value**: Low (consistency, not functional)
- **Note**: Highly subjective, make configurable

**N007: PascalCase vs snake_case Consistency**
- **Description**: Mixed naming conventions across objects
- **Effort**: Low
- **Value**: Low (consistency only)

**N008: Abbreviation Usage**
- **Description**: Inconsistent abbreviations (Qty vs Quantity, Num vs Number)
- **Effort**: Medium (dictionary-based)
- **Value**: Low

**N009: Prefix Overuse**
- **Description**: tbl_, usp_, fn_ prefixes (redundant with object type)
- **Effort**: Low
- **Value**: Low (personal preference)

**N010: Column Name Repeating Table Name**
- **Description**: Customer.CustomerName instead of Customer.Name
- **Effort**: Low
- **Value**: Low (verbosity)

#### Medium Priority (N011-N025, ~15 rules)
- ID column naming inconsistency
- Foreign key naming conventions
- Index naming standards
- Constraint naming standards
- Trigger naming standards
- View naming standards
- Synonym naming standards
- Schema naming standards
- And 7 other naming convention rules

#### Low Priority (N026-N030, ~5 rules)
- Unicode prefix (N prefix) usage
- Underscores in names
- Camel case detection
- Name length limits
- Reserved word usage in names

---

### Code Metrics - NOT Implementing (M001-M020, ~20 rules)

**These are all deferred to Phase 5+ due to complexity**:

**M001: Cyclomatic Complexity**
- **Description**: Measure of code complexity (branching, loops)
- **Effort**: Very High (requires control flow graph analysis)
- **Value**: Medium (identifies complex procedures)

**M002: Lines of Code per Procedure**
- **Description**: Procedures exceeding 300 lines (maintainability)
- **Effort**: Low (line count)
- **Value**: Low (arbitrary threshold)

**M003: Nesting Depth**
- **Description**: IF/WHILE nesting depth >4 levels
- **Effort**: Medium (requires parsing)
- **Value**: Medium (readability)

**M004: Parameter Count**
- **Description**: Procedures with >10 parameters
- **Effort**: Low (parameter count)
- **Value**: Low (design smell)

**M005: Comment Ratio**
- **Description**: Code-to-comment ratio
- **Effort**: Medium (comment detection)
- **Value**: Very Low (misleading metric)

**M006: Halstead Metrics**
- **Description**: Program difficulty, volume, effort
- **Effort**: Very High (AST analysis)
- **Value**: Low (academic metric)

**M007: Maintainability Index**
- **Description**: Composite metric (complexity + LOC + comments)
- **Effort**: Very High
- **Value**: Low (derived metric)

**M008-M020**: 13 other advanced code metrics
- Coupling between objects
- Depth of inheritance tree (for CLR procedures)
- Response for class
- Lack of cohesion
- Code duplication detection
- Test coverage estimation
- And 7 other metrics

**Why Deferred**: Code metrics require Abstract Syntax Tree (AST) parsing, control flow analysis, and significant computation. Low ROI for initial implementation.

---

## SolarWinds DPA-Specific Features Worth Borrowing

### High Priority Features (Implement in Phase 3 or 4)

#### 1. AI Query Assist - Automated Query Rewriting

**Feature**: Suggest optimized query rewrites based on pattern analysis

**Examples**:

**Anti-Pattern #1: OR in WHERE Clause**
```sql
-- Before (slow)
WHERE (Status = 'Active' OR Status = 'Pending')
  AND CreatedDate >= '2024-01-01'

-- Suggested Fix
WHERE Status IN ('Active', 'Pending')
  AND CreatedDate >= '2024-01-01'
```

**Anti-Pattern #2: Non-SARGable LIKE**
```sql
-- Before (index scan)
WHERE CustomerName LIKE '%Smith%'

-- Suggested Fix (if looking for starts-with)
WHERE CustomerName LIKE 'Smith%'

-- Alternative: Full-text search
-- Consider creating full-text index on CustomerName
```

**Anti-Pattern #3: Subquery in SELECT List**
```sql
-- Before (executes subquery per row)
SELECT
    o.OrderID,
    o.CustomerID,
    (SELECT COUNT(*) FROM OrderDetails WHERE OrderID = o.OrderID) AS ItemCount
FROM Orders o

-- Suggested Fix (single scan with GROUP BY)
SELECT
    o.OrderID,
    o.CustomerID,
    ISNULL(od.ItemCount, 0) AS ItemCount
FROM Orders o
LEFT JOIN (
    SELECT OrderID, COUNT(*) AS ItemCount
    FROM OrderDetails
    GROUP BY OrderID
) od ON o.OrderID = od.OrderID
```

**Implementation Strategy**:
```typescript
class QueryRewriteRule implements AnalysisRule {
    ruleId = 'P050';
    severity = 'Warning';
    message = 'Query can be rewritten for better performance';

    detect(code: string): AnalysisResult[] {
        // Pattern matching for anti-patterns
    }

    suggest(match: AnalysisResult): FixSuggestion {
        return {
            ruleId: this.ruleId,
            description: 'Rewrite query using set-based approach',
            before: '-- Original inefficient query',
            after: '-- Optimized query',
            explanation: 'Reduces row-by-row processing',
            estimatedImpact: 'High (10x-100x faster)',
            autoFixAvailable: false  // Requires manual review
        };
    }
}
```

#### 2. Response Time Percentiles (P50, P95, P99)

**Feature**: Track percentile-based performance metrics (already planned)

**Schema Enhancement**:
```sql
ALTER TABLE dbo.ProcedureStats ADD
    P50_DurationMs BIGINT NULL,      -- Median (50th percentile)
    P95_DurationMs BIGINT NULL,      -- 95th percentile (outlier detection)
    P99_DurationMs BIGINT NULL,      -- 99th percentile (worst-case)
    P999_DurationMs BIGINT NULL;     -- 99.9th percentile (extreme outliers)

-- Collection query
SELECT
    database_id,
    object_id,
    AVG(avg_duration) AS AvgDurationMs,
    MAX(max_duration) AS MaxDurationMs,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_duration) AS P50_DurationMs,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY avg_duration) AS P95_DurationMs,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY avg_duration) AS P99_DurationMs,
    PERCENTILE_CONT(0.999) WITHIN GROUP (ORDER BY avg_duration) AS P999_DurationMs
FROM sys.dm_exec_procedure_stats
GROUP BY database_id, object_id;
```

**Grafana Dashboard Panel**:
```sql
-- Procedures with High P95/P50 Ratio (inconsistent performance)
SELECT
    s.ServerName,
    ps.DatabaseName,
    ps.ProcedureName,
    ps.P50_DurationMs AS [Median (ms)],
    ps.P95_DurationMs AS [95th Percentile (ms)],
    ps.P99_DurationMs AS [99th Percentile (ms)],
    CAST(ps.P95_DurationMs * 1.0 / NULLIF(ps.P50_DurationMs, 0) AS DECIMAL(5,2)) AS [P95/P50 Ratio],
    CASE
        WHEN ps.P95_DurationMs > ps.P50_DurationMs * 10 THEN 'High Variance (Investigate)'
        WHEN ps.P95_DurationMs > ps.P50_DurationMs * 5 THEN 'Moderate Variance'
        ELSE 'Stable Performance'
    END AS [Performance Consistency]
FROM dbo.ProcedureStats ps
INNER JOIN dbo.Servers s ON ps.ServerID = s.ServerID
WHERE ps.CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY [P95/P50 Ratio] DESC;
```

**Value**: Percentiles reveal outliers that averages hide. A P95 >> P50 indicates inconsistent performance (parameter sniffing, plan cache issues).

#### 3. Table Tuning Advisor (Per-Table Analysis)

**Feature**: Analyze table-level performance issues and recommendations

**Implementation**:
```sql
CREATE PROCEDURE dbo.usp_AnalyzeTablePerformance
    @ServerID INT,
    @DatabaseName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL
AS
BEGIN
    -- Combine multiple analyses per table
    SELECT
        t.DatabaseName,
        t.SchemaName,
        t.TableName,
        -- Fragmentation
        f.FragmentationPercent,
        f.PageCount,
        -- Statistics freshness
        si.LastUpdated AS StatisticsLastUpdated,
        DATEDIFF(DAY, si.LastUpdated, GETUTCDATE()) AS StatisticsDaysOld,
        si.ModificationCounter,
        CAST(si.ModificationCounter * 100.0 / NULLIF(si.RowCount_Value, 0) AS DECIMAL(5,2)) AS ModificationPercent,
        -- Missing indexes (from DMV)
        mi.MissingIndexCount,
        mi.EstimatedImpact,
        -- Table size
        ts.TotalSizeMB,
        ts.DataSizeMB,
        ts.IndexSizeMB,
        -- Recommendations
        CASE
            WHEN f.FragmentationPercent > 30 THEN 'REBUILD index on ' + t.TableName
            WHEN f.FragmentationPercent > 5 THEN 'REORGANIZE index on ' + t.TableName
            ELSE NULL
        END AS IndexMaintenanceRecommendation,
        CASE
            WHEN DATEDIFF(DAY, si.LastUpdated, GETUTCDATE()) > 7
                 OR (si.ModificationCounter * 100.0 / NULLIF(si.RowCount_Value, 0)) > 20
            THEN 'UPDATE STATISTICS on ' + t.TableName
            ELSE NULL
        END AS StatisticsRecommendation,
        CASE
            WHEN mi.MissingIndexCount > 0 THEN 'Consider ' + CAST(mi.MissingIndexCount AS VARCHAR) + ' missing index(es)'
            ELSE NULL
        END AS MissingIndexRecommendation
    FROM (
        -- Get distinct tables
        SELECT DISTINCT ServerID, DatabaseName, SchemaName, TableName
        FROM dbo.IndexFragmentation
        WHERE ServerID = @ServerID
          AND (@DatabaseName IS NULL OR DatabaseName = @DatabaseName)
          AND (@TableName IS NULL OR TableName = @TableName)
    ) t
    LEFT JOIN (
        -- Latest fragmentation
        SELECT ServerID, DatabaseName, SchemaName, TableName,
               MAX(FragmentationPercent) AS FragmentationPercent,
               SUM(PageCount) AS PageCount
        FROM dbo.IndexFragmentation
        WHERE CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
        GROUP BY ServerID, DatabaseName, SchemaName, TableName
    ) f ON t.ServerID = f.ServerID AND t.DatabaseName = f.DatabaseName
       AND t.SchemaName = f.SchemaName AND t.TableName = f.TableName
    LEFT JOIN (
        -- Latest statistics info
        SELECT ServerID, DatabaseName, SchemaName, TableName,
               MAX(LastUpdated) AS LastUpdated,
               SUM(ModificationCounter) AS ModificationCounter,
               SUM(RowCount_Value) AS RowCount_Value
        FROM dbo.StatisticsInfo
        WHERE CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
        GROUP BY ServerID, DatabaseName, SchemaName, TableName
    ) si ON t.ServerID = si.ServerID AND t.DatabaseName = si.DatabaseName
        AND t.SchemaName = si.SchemaName AND t.TableName = si.TableName
    LEFT JOIN (
        -- Missing indexes (would need to collect from sys.dm_db_missing_index_details)
        -- Placeholder for future implementation
        SELECT 1 AS ServerID, 'DB1' AS DatabaseName, 'dbo' AS SchemaName, 'Table1' AS TableName,
               0 AS MissingIndexCount, 0.0 AS EstimatedImpact
        WHERE 1=0
    ) mi ON t.ServerID = mi.ServerID AND t.DatabaseName = mi.DatabaseName
        AND t.SchemaName = mi.SchemaName AND t.TableName = mi.TableName
    LEFT JOIN (
        -- Table size (would need to collect from sys.dm_db_partition_stats)
        -- Placeholder for future implementation
        SELECT 1 AS ServerID, 'DB1' AS DatabaseName, 'dbo' AS SchemaName, 'Table1' AS TableName,
               0.0 AS TotalSizeMB, 0.0 AS DataSizeMB, 0.0 AS IndexSizeMB
        WHERE 1=0
    ) ts ON t.ServerID = ts.ServerID AND t.DatabaseName = ts.DatabaseName
        AND t.SchemaName = ts.SchemaName AND t.TableName = ts.TableName
    ORDER BY t.DatabaseName, t.SchemaName, t.TableName;
END;
GO
```

**Grafana Dashboard**: "15-table-tuning-advisor.json"
- Panel 1: Tables Requiring Attention (stat)
- Panel 2: Top 20 Fragmented Tables (table)
- Panel 3: Tables with Outdated Statistics (table)
- Panel 4: Missing Index Opportunities (table)
- Panel 5: Largest Tables (bar chart)

#### 4. Wait Time Breakdown (Detailed Categorization)

**Feature**: Categorize wait types into actionable buckets

**Implementation**:
```sql
CREATE FUNCTION dbo.fn_CategorizeWaitType (@WaitType NVARCHAR(60))
RETURNS VARCHAR(50)
AS
BEGIN
    RETURN CASE
        -- CPU waits
        WHEN @WaitType IN ('SOS_SCHEDULER_YIELD', 'THREADPOOL', 'RESOURCE_SEMAPHORE')
            THEN 'CPU Pressure'

        -- I/O waits
        WHEN @WaitType LIKE 'PAGEIOLATCH%' OR @WaitType LIKE 'WRITELOG%' OR @WaitType = 'IO_COMPLETION'
            THEN 'I/O Contention'

        -- Locking waits
        WHEN @WaitType LIKE 'LCK%' OR @WaitType = 'LOCK_M_SCH_S' OR @WaitType = 'LOCK_M_SCH_M'
            THEN 'Blocking/Locking'

        -- Memory waits
        WHEN @WaitType LIKE 'RESOURCE_SEMAPHORE%' OR @WaitType LIKE 'CMEMTHREAD%'
            THEN 'Memory Pressure'

        -- Network waits
        WHEN @WaitType LIKE 'ASYNC_NETWORK_IO%' OR @WaitType = 'NETWORK_IO'
            THEN 'Network Latency'

        -- Parallelism waits
        WHEN @WaitType LIKE 'CXPACKET%' OR @WaitType = 'CXCONSUMER' OR @WaitType = 'EXCHANGE'
            THEN 'Parallelism'

        -- Compilation waits
        WHEN @WaitType LIKE 'COMPILE%' OR @WaitType = 'SQLCLR_QUANTUM_PUNISHMENT'
            THEN 'Compilation/Recompilation'

        -- AlwaysOn waits
        WHEN @WaitType LIKE 'HADR%'
            THEN 'AlwaysOn Availability Groups'

        -- Backup waits
        WHEN @WaitType LIKE 'BACKUP%'
            THEN 'Backup Operations'

        -- Benign waits (filter out)
        WHEN @WaitType IN ('BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'CHECKPOINT_QUEUE',
                           'DIRTY_PAGE_POLL', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
                           'REQUEST_FOR_DEADLOCK_SEARCH', 'SLEEP_TASK', 'SQLTRACE_BUFFER_FLUSH',
                           'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'WAITFOR', 'XE_DISPATCHER_WAIT',
                           'XE_TIMER_EVENT')
            THEN 'Benign (Ignore)'

        ELSE 'Other'
    END;
END;
GO

-- Use in query
SELECT
    s.ServerName,
    dbo.fn_CategorizeWaitType(ws.WaitType) AS WaitCategory,
    SUM(ws.WaitTimeSec) AS TotalWaitTimeSec,
    COUNT(*) AS WaitCount,
    AVG(ws.WaitTimeSec) AS AvgWaitTimeSec
FROM dbo.WaitStatistics ws
INNER JOIN dbo.Servers s ON ws.ServerID = s.ServerID
WHERE ws.CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
  AND dbo.fn_CategorizeWaitType(ws.WaitType) <> 'Benign (Ignore)'
GROUP BY s.ServerName, dbo.fn_CategorizeWaitType(ws.WaitType)
ORDER BY TotalWaitTimeSec DESC;
```

**Grafana Pie Chart**: Wait Time by Category
- Shows: CPU Pressure (35%), I/O Contention (40%), Blocking (15%), Other (10%)
- Click to drill down to specific wait types in category

#### 5. Anomaly Detection with Baseline Learning

**Feature**: Learn normal patterns, alert on deviations (we already have this in Feature #5 Predictive Analytics)

**Enhancement**: Add anomaly severity scoring

```sql
ALTER TABLE dbo.PredictiveAlerts ADD
    AnomalySeverityScore DECIMAL(5,2) NULL,  -- 0-100 score
    BaselineDeviation DECIMAL(18,6) NULL;    -- How many std deviations from baseline

-- Calculate anomaly severity
UPDATE dbo.PredictiveAlerts
SET
    AnomalySeverityScore = CASE
        WHEN ABS(BaselineDeviation) >= 5.0 THEN 100.0  -- Extreme (5+ std dev)
        WHEN ABS(BaselineDeviation) >= 3.0 THEN 80.0   -- Severe (3-5 std dev)
        WHEN ABS(BaselineDeviation) >= 2.0 THEN 60.0   -- Moderate (2-3 std dev)
        WHEN ABS(BaselineDeviation) >= 1.5 THEN 40.0   -- Minor (1.5-2 std dev)
        ELSE 20.0                                       -- Low (<1.5 std dev)
    END
WHERE AlertTime >= DATEADD(HOUR, -24, GETUTCDATE());
```

---

## Priority Matrix for Phase 4+ Implementation

| Rule Category | Rules Count | Effort | Value | Priority | Estimated Hours |
|---------------|-------------|--------|-------|----------|-----------------|
| **Performance - High Priority** | 10 | Medium | High | **P1** | 20 hours |
| **Design - Missing Index Analysis** | 5 | Medium | Very High | **P1** | 15 hours |
| **Security - Access Control** | 10 | Low | Very High | **P1** | 10 hours |
| **SolarWinds - Query Rewriting** | 15 | High | High | **P1** | 30 hours |
| **SolarWinds - Percentiles** | 1 | Low | High | **P1** | 5 hours |
| **SolarWinds - Table Tuning** | 1 | Medium | High | **P2** | 10 hours |
| **SolarWinds - Wait Categorization** | 1 | Low | Medium | **P2** | 5 hours |
| **Performance - Query Hints** | 20 | Medium | Medium | **P2** | 30 hours |
| **Performance - Advanced Index** | 20 | High | High | **P2** | 40 hours |
| **Design - Schema Patterns** | 20 | Medium | Medium | **P3** | 30 hours |
| **Deprecated - All Remaining** | 42 | Low | Low | **P3** | 20 hours |
| **Naming - All** | 25 | Low | Very Low | **P4** | 10 hours |
| **Code Metrics - All** | 20 | Very High | Low | **P5** | 80 hours |
| **Total Deferred** | **210** | | | | **305 hours** |

**Phase 4 Target** (100 hours): P1 rules (80 hours) + P2 Table Tuning + Wait Categorization (20 hours)
**Phase 5 Target** (100 hours): P2 remaining + P3 selected rules
**Phase 6+**: P4 and P5 if customer demand exists

---

## Recommendations for Feature #7 (Phase 3)

### Must Include from SolarWinds DPA

1. **Response Time Percentiles** - Essential for performance analysis
   - Add P50, P95, P99 columns to ProcedureStats
   - Minimal effort (5 hours)
   - High value

2. **Query Rewrite Suggestions** - High-value differentiator
   - Implement 5-10 most common anti-patterns
   - Medium effort (15 hours within Phase 3 scope)
   - Very high value

3. **Wait Time Categorization** - Actionable insights
   - Add fn_CategorizeWaitType function
   - Enhance wait statistics dashboard
   - Low effort (5 hours)
   - Medium-high value

### Defer to Phase 4

1. **Advanced Query Rewriting** - 15+ additional patterns
2. **Table Tuning Advisor** - Per-table comprehensive analysis
3. **Missing Index DMV Collection** - Integrate with our index recommendations
4. **High-priority performance rules** (P011-P020)
5. **High-priority security rules** (S006-S015)

---

## Conclusion

This document catalogs **230+ additional T-SQL analysis rules** that we are explicitly NOT implementing in Phase 3 Feature #7. From SolarWinds DPA, we should incorporate:

**Include in Phase 3** (~25 hours):
- ✅ Response time percentiles (P50, P95, P99)
- ✅ Query rewrite suggestions (5-10 patterns)
- ✅ Wait time categorization

**Defer to Phase 4** (~305 hours total backlog):
- Advanced query rewriting (15+ patterns)
- Table tuning advisor
- 10 high-priority performance rules
- 10 high-priority security rules
- Missing index DMV integration

**Total Addressable Market**: 260+ rules (SQLenlight baseline) + SolarWinds DPA features = Competitive with $40k/year commercial tool stack at $0 cost.

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02
**Status**: Complete - Reference for Phase 4+ Planning
