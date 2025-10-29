# Phase 1.9: sql-monitor-agent Integration - Technical Design Document

**Author**: SQL Server Monitor Team
**Date**: October 27, 2025
**Status**: Design Phase - NOT YET IMPLEMENTED
**Estimated Effort**: 60 hours (3 weeks)
**Risk Level**: HIGH (Major architectural change)

---

## Executive Summary

This document provides detailed technical specifications for integrating the proven **sql-monitor-agent** (DBATools database) with the enterprise **sql-monitor** solution (MonitoringDB). The integration leverages sql-monitor-agent's superior schema design (20+ tables, feedback system, P0-P3 collectors) while maintaining backwards compatibility and enabling multi-server monitoring.

**Critical Design Decisions**:
1. **Deployment-time database selection** (not runtime configurable)
2. **Synonym-based abstraction** for cross-database references
3. **View-based mapping layer** for API compatibility (WIDE schema → TALL schema)
4. **Nullable ServerID** for backwards compatibility
5. **Dual naming convention** (DBA_* for core, usp_* for API)
6. **Selective partitioning** (MonitoringDB only, not DBATools)

---

## Table of Contents

1. [Schema Transformation Design](#1-schema-transformation-design)
2. [Configurable Database Implementation](#2-configurable-database-implementation)
3. [Data Migration Strategy](#3-data-migration-strategy)
4. [API Compatibility Layer](#4-api-compatibility-layer)
5. [Naming Convention Policy](#5-naming-convention-policy)
6. [Test Plan](#6-test-plan)
7. [Partitioning Strategy](#7-partitioning-strategy)
8. [Rollback Procedures](#8-rollback-procedures)
9. [Implementation Sequence](#9-implementation-sequence)
10. [Risk Assessment](#10-risk-assessment)

---

## 1. Schema Transformation Design

### 1.1 The Challenge

**sql-monitor-agent schema** (WIDE - typed columns):
```sql
CREATE TABLE dbo.PerfSnapshotRun (
    PerfSnapshotRunID BIGINT IDENTITY(1,1),
    SnapshotUTC DATETIME2(3),
    ServerID INT NULL,  -- NEW: for multi-server
    ServerName SYSNAME,
    CpuSignalWaitPct DECIMAL(9,4),      -- Typed metric
    TopWaitType NVARCHAR(120),          -- Typed metric
    TopWaitMsPerSec DECIMAL(18,4),      -- Typed metric
    SessionsCount INT,                   -- Typed metric
    RequestsCount INT,                   -- Typed metric
    BlockingSessionCount INT,            -- Typed metric
    DeadlockCountRecent INT,             -- Typed metric
    MemoryGrantWarningCount INT          -- Typed metric
);
-- ONE row contains MANY metrics (typed columns)
```

**sql-monitor schema** (TALL - generic rows):
```sql
CREATE TABLE dbo.PerformanceMetrics (
    MetricID BIGINT IDENTITY(1,1),
    ServerID INT,
    CollectionTime DATETIME2,
    MetricCategory NVARCHAR(50),   -- "CPU", "Waits", "Memory", etc.
    MetricName NVARCHAR(100),      -- "CpuSignalWaitPct", "SessionsCount", etc.
    MetricValue DECIMAL(18,4)      -- Generic value
);
-- ONE row contains ONE metric (generic key-value)
```

**Transformation Required**: WIDE (many columns, one row) → TALL (one column, many rows)

### 1.2 Solution: CROSS APPLY Unpivoting

**View Definition**:
```sql
CREATE VIEW dbo.vw_PerformanceMetrics AS
SELECT
    -- Generate unique MetricID for each unpivoted row
    CAST(
        (PerfSnapshotRunID * 1000) + MetricOrdinal
        AS BIGINT
    ) AS MetricID,

    ISNULL(ServerID, 0) AS ServerID,  -- NULL → 0 for backwards compat
    SnapshotUTC AS CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue
FROM dbo.PerfSnapshotRun
CROSS APPLY (
    VALUES
        -- Server metrics
        (1, 'Server', 'SessionsCount', CAST(SessionsCount AS DECIMAL(18,4))),
        (2, 'Server', 'RequestsCount', CAST(RequestsCount AS DECIMAL(18,4))),
        (3, 'Server', 'BlockingSessionCount', CAST(BlockingSessionCount AS DECIMAL(18,4))),

        -- CPU metrics
        (4, 'CPU', 'CpuSignalWaitPct', CpuSignalWaitPct),

        -- Wait metrics
        (5, 'Waits', 'TopWaitMsPerSec', TopWaitMsPerSec),

        -- Memory metrics
        (6, 'Memory', 'DeadlockCountRecent', CAST(DeadlockCountRecent AS DECIMAL(18,4))),
        (7, 'Memory', 'MemoryGrantWarningCount', CAST(MemoryGrantWarningCount AS DECIMAL(18,4)))
) AS Metrics(MetricOrdinal, MetricCategory, MetricName, MetricValue);
```

**Key Design Points**:
1. **MetricID generation**: `(PerfSnapshotRunID * 1000) + MetricOrdinal`
   - Ensures uniqueness across unpivoted rows
   - Example: RunID 5, Metric 3 → MetricID 5003

2. **ServerID handling**: `ISNULL(ServerID, 0)`
   - NULL ServerID → 0 (local server, backwards compatible)
   - Matches expected API contract (NOT NULL ServerID)

3. **MetricOrdinal**: Fixed ordinal per metric type
   - Enables consistent MetricID generation
   - Allows filtering: `WHERE MetricOrdinal = 4` for CPU metrics only

### 1.3 Enhanced Tables Unpivoting

**Similar pattern for PerfSnapshotQueryStats**:
```sql
CREATE VIEW dbo.vw_PerformanceMetrics_QueryStats AS
SELECT
    CAST(
        (PerfSnapshotQueryStatsID * 1000) + MetricOrdinal
        AS BIGINT
    ) AS MetricID,

    psr.ServerID,
    psr.SnapshotUTC AS CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue
FROM dbo.PerfSnapshotQueryStats pqs
INNER JOIN dbo.PerfSnapshotRun psr
    ON pqs.PerfSnapshotRunID = psr.PerfSnapshotRunID
CROSS APPLY (
    VALUES
        (1, 'Query', 'ExecutionCount', CAST(ExecutionCount AS DECIMAL(18,4))),
        (2, 'Query', 'TotalCpuMs', CAST(TotalCpuMs AS DECIMAL(18,4))),
        (3, 'Query', 'AvgCpuMs', AvgCpuMs),
        (4, 'Query', 'TotalLogicalReads', CAST(TotalLogicalReads AS DECIMAL(18,4))),
        (5, 'Query', 'AvgLogicalReads', AvgLogicalReads),
        (6, 'Query', 'TotalElapsedMs', CAST(TotalElapsedMs AS DECIMAL(18,4))),
        (7, 'Query', 'AvgElapsedMs', AvgElapsedMs)
) AS Metrics(MetricOrdinal, MetricCategory, MetricName, MetricValue);
```

**Unified view combining all sources**:
```sql
CREATE VIEW dbo.vw_PerformanceMetrics_Unified AS
-- Base metrics from PerfSnapshotRun
SELECT * FROM dbo.vw_PerformanceMetrics
UNION ALL
-- Query metrics from PerfSnapshotQueryStats
SELECT * FROM dbo.vw_PerformanceMetrics_QueryStats
UNION ALL
-- IO metrics from PerfSnapshotIOStats
SELECT * FROM dbo.vw_PerformanceMetrics_IOStats
UNION ALL
-- Memory metrics from PerfSnapshotMemory
SELECT * FROM dbo.vw_PerformanceMetrics_Memory
-- ... etc for all enhanced tables
;
```

### 1.4 Reverse Transformation (TALL → WIDE)

**Not needed in Phase 1.9**, but for future reference:

```sql
-- If we need to reconstruct PerfSnapshotRun from PerformanceMetrics
SELECT
    ServerID,
    CollectionTime,
    MAX(CASE WHEN MetricName = 'CpuSignalWaitPct' THEN MetricValue END) AS CpuSignalWaitPct,
    MAX(CASE WHEN MetricName = 'SessionsCount' THEN MetricValue END) AS SessionsCount,
    -- ... PIVOT all metrics
FROM dbo.PerformanceMetrics
WHERE CollectionTime BETWEEN @StartTime AND @EndTime
GROUP BY ServerID, CollectionTime;
```

### 1.5 Performance Considerations

**Concern**: Unpivoting creates 7+ rows per PerfSnapshotRun row. Query performance?

**Mitigation**:
1. **Indexed views** (if query patterns justify it)
2. **Filtered indexes** on common MetricCategory values
3. **Columnstore index** on base PerfSnapshotRun table
4. **Partition elimination** (when partitioned by SnapshotUTC)

**Benchmark Target**: vw_PerformanceMetrics queries < 500ms for 90 days of data

---

## 2. Configurable Database Implementation

### 2.1 The Challenge

SQL Server doesn't support runtime database switching:
```sql
DECLARE @TargetDB SYSNAME = 'DBATools';
USE @TargetDB;  -- ❌ ERROR: Must be a constant
```

### 2.2 Options Analysis

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Dynamic SQL everywhere** | Flexible | Maintenance nightmare, SQL injection risk, can't use in views | ❌ Rejected |
| **Synonyms** | Clean, performant, works in views/functions | Deployment-time decision (not runtime) | ✅ **CHOSEN** |
| **Linked server to self** | Runtime switchable | Weird, adds latency, complex security | ❌ Rejected |
| **Two separate codebases** | Simple | Defeats integration purpose | ❌ Rejected |

### 2.3 Solution: Deployment-Time Configuration with Synonyms

**Design Decision**: Database selection is a **deployment-time** decision, not runtime.

**Two Deployment Modes**:

#### Mode 1: Single-Server (DBATools) - Backwards Compatible

**Target audience**: Existing sql-monitor-agent users, simple deployments

**Database**: `DBATools`

**Schema**:
- All PerfSnapshot* tables live in DBATools
- `Servers` table also in DBATools (added for multi-server support)
- No synonyms needed (everything in one database)

**Collection**:
```sql
-- Runs on local SQL Server instance
EXEC DBA_CollectPerformanceSnapshot @Debug = 0;
-- ServerID defaults to NULL (local server)
```

**Use case**: Small shops, single SQL Server, no Docker/containers

---

#### Mode 2: Multi-Server (MonitoringDB) - Enterprise

**Target audience**: Enterprise deployments, multi-server monitoring

**Databases**:
- `MonitoringDB` (centralized monitoring database)
- `DBATools` (optional, if sql-monitor-agent is still deployed on individual servers)

**Schema**:
- All PerfSnapshot* tables live in MonitoringDB
- `Servers` table in MonitoringDB (inventory)
- Synonyms in MonitoringDB pointing to... wait, no synonyms needed if everything is in MonitoringDB!

**Collection**:
```sql
-- Centralized collection via linked servers
DECLARE @ServerID INT = 1;  -- SQL-PROD-01
EXEC usp_CollectMetrics_RemoteServer @ServerID = @ServerID;
```

**Use case**: Large enterprises, 10+ SQL Servers, Docker deployment

---

### 2.4 Migration Path: DBATools → MonitoringDB

**When ready to migrate from single-server to multi-server**:

```sql
-- Step 1: Create MonitoringDB with full schema
:r database/01-create-database.sql  -- Creates MonitoringDB
:r database/02-create-tables.sql    -- Creates Servers table
:r database/20-create-dbatools-tables.sql  -- NEW: Creates all PerfSnapshot* tables

-- Step 2: Migrate data from DBATools → MonitoringDB
INSERT INTO MonitoringDB.dbo.Servers (ServerName, Environment, IsActive)
VALUES (@@SERVERNAME, 'Production', 1);

DECLARE @LocalServerID INT = SCOPE_IDENTITY();

-- Migrate historical PerfSnapshotRun data
INSERT INTO MonitoringDB.dbo.PerfSnapshotRun (
    SnapshotUTC, ServerID, ServerName, SqlVersion, CpuSignalWaitPct, ...
)
SELECT
    SnapshotUTC, @LocalServerID, ServerName, SqlVersion, CpuSignalWaitPct, ...
FROM DBATools.dbo.PerfSnapshotRun;

-- Repeat for all PerfSnapshot* tables

-- Step 3: Update SQL Agent job to use MonitoringDB
-- (or keep DBATools and use linked server for remote collection)

-- Step 4: Configure API to point to MonitoringDB
-- Update appsettings.json: "MonitoringDB" instead of "DBATools"
```

### 2.5 Configuration File Approach

**appsettings.json**:
```json
{
  "ConnectionStrings": {
    "MonitoringDB": "Server=172.31.208.1,14333;Database=DBATools;...",
    "DeploymentMode": "SingleServer"  // or "MultiServer"
  }
}
```

**Or for multi-server**:
```json
{
  "ConnectionStrings": {
    "MonitoringDB": "Server=monitoring-db-server;Database=MonitoringDB;...",
    "DeploymentMode": "MultiServer"
  }
}
```

### 2.6 No Synonyms Needed (Simpler!)

**Revised decision**: Since we're choosing deployment-time configuration, **all tables live in one database per deployment mode**:

- **Single-Server Mode**: Everything in `DBATools`
- **Multi-Server Mode**: Everything in `MonitoringDB`

No cross-database queries needed = no synonyms needed!

---

## 3. Data Migration Strategy

### 3.1 Scenario: Existing PerformanceMetrics Data

**User has**: Existing `MonitoringDB.dbo.PerformanceMetrics` table with historical data (Phase 1.0 schema)

**Challenge**: Can we transform generic PerformanceMetrics → typed PerfSnapshotRun?

### 3.2 Assessment: Partial Migration Possible

**PerformanceMetrics → PerfSnapshotRun mapping**:

| PerformanceMetrics | PerfSnapshotRun | Possible? |
|--------------------|-----------------|-----------|
| MetricCategory='CPU', MetricName='CpuSignalWaitPct' | CpuSignalWaitPct DECIMAL(9,4) | ✅ Yes |
| MetricCategory='Server', MetricName='SessionsCount' | SessionsCount INT | ✅ Yes |
| MetricCategory='Waits', MetricName='TopWaitMsPerSec' | TopWaitMsPerSec DECIMAL(18,4) | ✅ Yes |
| ... | ServerName SYSNAME | ❌ **No** - not in PerformanceMetrics |
| ... | TopWaitType NVARCHAR(120) | ❌ **No** - not in PerformanceMetrics |

**Verdict**: **Partial migration only** - can populate numeric metrics, but missing descriptive fields (ServerName, TopWaitType, etc.)

### 3.3 Solution: Dual-Table Coexistence

**Strategy**: Keep both tables, union them in views

**Implementation**:
```sql
-- Rename existing table (preserve historical data)
EXEC sp_rename 'dbo.PerformanceMetrics', 'PerformanceMetrics_Legacy';

-- Create new PerfSnapshotRun table (Phase 1.9 schema)
-- ... (from sql-monitor-agent)

-- Create unified view
CREATE VIEW dbo.vw_PerformanceMetrics AS
-- Historical data (before Phase 1.9 cutover)
SELECT
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue
FROM dbo.PerformanceMetrics_Legacy
WHERE CollectionTime < '2025-10-27 00:00:00'  -- Cutover timestamp

UNION ALL

-- New data (after Phase 1.9 cutover, unpivoted from PerfSnapshotRun)
SELECT
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue
FROM dbo.vw_PerfSnapshotRun_Unpivoted
WHERE CollectionTime >= '2025-10-27 00:00:00';
```

**Benefits**:
- ✅ No data loss
- ✅ Seamless historical queries
- ✅ Grafana dashboards continue to work
- ✅ API unchanged (queries vw_PerformanceMetrics)

**Tradeoff**: Two schemas to maintain until legacy data expires (90 days retention)

### 3.4 Cutover Plan

**Pre-Cutover** (Current State):
```
MonitoringDB
├── PerformanceMetrics (legacy, active collection)
└── Servers
```

**Cutover Day**:
```sql
-- 1. Stop collection
EXEC msdb.dbo.sp_stop_job @job_name = 'SQL Monitor - Collect Metrics';

-- 2. Rename legacy table
EXEC sp_rename 'dbo.PerformanceMetrics', 'PerformanceMetrics_Legacy';

-- 3. Deploy Phase 1.9 schema
:r database/20-create-dbatools-tables.sql  -- Creates all PerfSnapshot* tables

-- 4. Deploy Phase 1.9 views
:r database/21-create-mapping-views.sql    -- Creates vw_PerformanceMetrics

-- 5. Deploy Phase 1.9 stored procedures
:r database/22-create-collection-procedures.sql

-- 6. Update SQL Agent job
-- (point to new DBA_CollectPerformanceSnapshot procedure)

-- 7. Resume collection
EXEC msdb.dbo.sp_start_job @job_name = 'SQL Monitor - Collect Metrics';
```

**Post-Cutover** (New State):
```
MonitoringDB
├── PerformanceMetrics_Legacy (read-only, historical data)
├── PerfSnapshotRun (active collection)
├── PerfSnapshotDB
├── PerfSnapshotWorkload
├── ... (all 20+ tables)
├── vw_PerformanceMetrics (unified view: legacy + new)
└── Servers
```

### 3.5 Cleanup (After 90 Days)

```sql
-- After retention period expires, legacy data can be archived/dropped
-- 1. Verify all queries use vw_PerformanceMetrics (not direct table)
-- 2. Export legacy data for archival
SELECT * INTO PerformanceMetrics_Archive_2025
FROM PerformanceMetrics_Legacy;

-- 3. Drop legacy table
DROP TABLE dbo.PerformanceMetrics_Legacy;

-- 4. Simplify view (remove UNION, only new data)
ALTER VIEW dbo.vw_PerformanceMetrics AS
SELECT MetricID, ServerID, CollectionTime, MetricCategory, MetricName, MetricValue
FROM dbo.vw_PerfSnapshotRun_Unpivoted;
```

---

## 4. API Compatibility Layer

### 4.1 Current API Contract

**Endpoint**: `GET /api/metrics/{serverId}?start=2025-10-26&end=2025-10-27`

**Expected Response**:
```json
[
  {
    "serverId": 1,
    "collectionTime": "2025-10-27T10:00:00Z",
    "metricCategory": "CPU",
    "metricName": "CpuSignalWaitPct",
    "metricValue": 45.2
  },
  {
    "serverId": 1,
    "collectionTime": "2025-10-27T10:00:00Z",
    "metricCategory": "Server",
    "metricName": "SessionsCount",
    "metricValue": 127
  }
]
```

**C# Model**:
```csharp
public class MetricModel
{
    public int ServerID { get; set; }
    public DateTime CollectionTime { get; set; }
    public string MetricCategory { get; set; }
    public string MetricName { get; set; }
    public decimal? MetricValue { get; set; }
}
```

### 4.2 Phase 1.9 Compatibility: No Changes Needed!

**Stored Procedure** (unchanged):
```sql
CREATE PROCEDURE dbo.usp_GetMetricHistory
    @ServerID INT,
    @StartTime DATETIME2,
    @EndTime DATETIME2
AS
BEGIN
    SELECT
        ServerID,
        CollectionTime,
        MetricCategory,
        MetricName,
        MetricValue
    FROM dbo.vw_PerformanceMetrics  -- NEW: view instead of table
    WHERE ServerID = @ServerID
      AND CollectionTime BETWEEN @StartTime AND @EndTime
    ORDER BY CollectionTime, MetricCategory, MetricName;
END
```

**API Controller** (unchanged):
```csharp
[HttpGet("servers/{serverId}/metrics")]
public async Task<IEnumerable<MetricModel>> GetMetricHistoryAsync(
    int serverId,
    DateTime start,
    DateTime end)
{
    using var connection = _connectionFactory.CreateConnection();
    return await connection.QueryAsync<MetricModel>(
        "dbo.usp_GetMetricHistory",
        new { ServerID = serverId, StartTime = start, EndTime = end },
        commandType: CommandType.StoredProcedure
    );
}
```

**Result**: ✅ **Zero API changes required** - compatibility through views!

### 4.3 New Rich API Endpoints (Optional, Phase 1.9+)

**For clients that want typed, rich data**:

**New Model**:
```csharp
public class PerfSnapshotRunModel
{
    public long PerfSnapshotRunID { get; set; }
    public DateTime SnapshotUTC { get; set; }
    public int? ServerID { get; set; }
    public string ServerName { get; set; }
    public string SqlVersion { get; set; }
    public decimal? CpuSignalWaitPct { get; set; }
    public string TopWaitType { get; set; }
    public decimal? TopWaitMsPerSec { get; set; }
    public int? SessionsCount { get; set; }
    public int? RequestsCount { get; set; }
    public int? BlockingSessionCount { get; set; }
    public int? DeadlockCountRecent { get; set; }
    public int? MemoryGrantWarningCount { get; set; }
}
```

**New Endpoint**:
```csharp
[HttpGet("servers/{serverId}/snapshots")]
public async Task<IEnumerable<PerfSnapshotRunModel>> GetSnapshotsAsync(
    int serverId,
    DateTime start,
    DateTime end)
{
    using var connection = _connectionFactory.CreateConnection();
    return await connection.QueryAsync<PerfSnapshotRunModel>(
        "dbo.usp_GetPerfSnapshots",
        new { ServerID = serverId, StartTime = start, EndTime = end },
        commandType: CommandType.StoredProcedure
    );
}
```

**Stored Procedure**:
```sql
CREATE PROCEDURE dbo.usp_GetPerfSnapshots
    @ServerID INT,
    @StartTime DATETIME2,
    @EndTime DATETIME2
AS
BEGIN
    SELECT
        PerfSnapshotRunID,
        SnapshotUTC,
        ServerID,
        ServerName,
        SqlVersion,
        CpuSignalWaitPct,
        TopWaitType,
        TopWaitMsPerSec,
        SessionsCount,
        RequestsCount,
        BlockingSessionCount,
        DeadlockCountRecent,
        MemoryGrantWarningCount
    FROM dbo.PerfSnapshotRun
    WHERE (ServerID = @ServerID OR (@ServerID IS NULL AND ServerID IS NULL))
      AND SnapshotUTC BETWEEN @StartTime AND @EndTime
    ORDER BY SnapshotUTC DESC;
END
```

**Benefits**:
- Typed data (better performance, no unpivoting overhead)
- Richer information (ServerName, TopWaitType, SqlVersion)
- Backwards compatible (old endpoint still works)

---

## 5. Naming Convention Policy

### 5.1 The Conflict

- **sql-monitor-agent**: `DBA_CollectPerformanceSnapshot`, `DBA_Collect_P0_QueryStats`
- **sql-monitor**: `usp_GetServers`, `usp_GetMetricHistory`

### 5.2 Solution: Dual Naming with Clear Ownership

**Core Collection Procedures** (owned by sql-monitor-agent, internal use):
- Prefix: `DBA_`
- Examples: `DBA_CollectPerformanceSnapshot`, `DBA_Collect_P0_QueryStats`
- Audience: SQL Agent jobs, internal orchestration
- Stability: Core logic, rarely changed

**API-Facing Procedures** (owned by sql-monitor, external contract):
- Prefix: `usp_`
- Examples: `usp_GetServers`, `usp_GetMetricHistory`, `usp_CollectMetrics`
- Audience: ASP.NET Core API, Grafana, external clients
- Stability: Public contract, backwards compatible

**Wrapper Pattern** (for integration):
```sql
-- API wrapper that calls core DBA_ procedure
CREATE PROCEDURE dbo.usp_CollectMetrics
    @ServerID INT = NULL,
    @Debug BIT = 0
AS
BEGIN
    -- Thin wrapper, delegates to core collector
    EXEC DBA_CollectPerformanceSnapshot
        @Debug = @Debug;

    -- Could add API-specific logic here (logging, notifications, etc.)
END
```

### 5.3 Naming Matrix

| Component | Prefix | Owner | Examples | Audience |
|-----------|--------|-------|----------|----------|
| **Core collection** | `DBA_` | sql-monitor-agent | `DBA_CollectPerformanceSnapshot` | SQL Agent jobs |
| **Modular collectors** | `DBA_Collect_P[0-3]_` | sql-monitor-agent | `DBA_Collect_P0_QueryStats` | Orchestrator SP |
| **Reporting/feedback** | `DBA_Get` | sql-monitor-agent | `DBA_GetDailyOverview` | Manual execution |
| **API endpoints** | `usp_Get*` | sql-monitor | `usp_GetMetricHistory` | ASP.NET API |
| **API actions** | `usp_[Verb]*` | sql-monitor | `usp_CollectMetrics`, `usp_AddServer` | ASP.NET API |
| **Mapping views** | `vw_*` | Phase 1.9 integration | `vw_PerformanceMetrics` | API, Grafana |
| **Config functions** | `fn_GetConfig*` | sql-monitor-agent | `fn_GetConfigBit` | All SPs |
| **Helper functions** | `fn_*` | sql-monitor-agent | `fn_GetMetricFeedback` | Reporting |

### 5.4 Migration of Existing Names

**No renaming of sql-monitor-agent procedures** - maintains backwards compatibility.

**New Phase 1.9 procedures** use `usp_` prefix:
- `usp_CollectMetrics` (wrapper for DBA_CollectPerformanceSnapshot)
- `usp_GetPerfSnapshots` (new rich endpoint)
- `usp_GetDailyOverview` (wrapper for DBA_GetDailyOverview with API formatting)

---

## 6. Test Plan

### 6.1 Test Categories

1. **Unit Tests** (stored procedures, functions)
2. **Integration Tests** (database + API)
3. **Performance Tests** (collection overhead, query speed)
4. **Compatibility Tests** (backwards compatibility, API contract)
5. **Migration Tests** (DBATools → MonitoringDB)

### 6.2 Unit Tests (20 test cases)

#### Category 1: Schema Transformation

**Test 1.1: vw_PerformanceMetrics unpivots correctly**
```sql
-- Setup
INSERT INTO PerfSnapshotRun (SnapshotUTC, ServerID, ServerName, SqlVersion, CpuSignalWaitPct, SessionsCount)
VALUES ('2025-10-27 10:00:00', 1, 'SQL-TEST', '16.0.4095.4', 45.2, 127);

-- Execute
SELECT MetricCategory, MetricName, MetricValue
FROM vw_PerformanceMetrics
WHERE ServerID = 1;

-- Assert
-- Expected: 7 rows (one per metric in PerfSnapshotRun)
-- Row 1: MetricCategory='CPU', MetricName='CpuSignalWaitPct', MetricValue=45.2
-- Row 2: MetricCategory='Server', MetricName='SessionsCount', MetricValue=127
-- ... etc
```

**Test 1.2: MetricID is unique across unpivoted rows**
```sql
-- Execute
SELECT MetricID, COUNT(*) AS DuplicateCount
FROM vw_PerformanceMetrics
GROUP BY MetricID
HAVING COUNT(*) > 1;

-- Assert
-- Expected: 0 rows (no duplicates)
```

**Test 1.3: NULL ServerID → 0 transformation**
```sql
-- Setup
INSERT INTO PerfSnapshotRun (SnapshotUTC, ServerID, ServerName, ...)
VALUES ('2025-10-27 10:00:00', NULL, @@SERVERNAME, ...);

-- Execute
SELECT DISTINCT ServerID FROM vw_PerformanceMetrics;

-- Assert
-- Expected: ServerID = 0 (not NULL)
```

#### Category 2: Data Migration

**Test 2.1: Legacy data accessible via unified view**
```sql
-- Setup
INSERT INTO PerformanceMetrics_Legacy (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
VALUES (1, '2025-10-25 10:00:00', 'CPU', 'CpuSignalWaitPct', 50.0);

INSERT INTO PerfSnapshotRun (SnapshotUTC, ServerID, CpuSignalWaitPct, ...)
VALUES ('2025-10-27 10:00:00', 1, 45.2, ...);

-- Execute
SELECT COUNT(*) FROM vw_PerformanceMetrics WHERE ServerID = 1;

-- Assert
-- Expected: 8+ rows (1 from legacy + 7+ from new schema)
```

**Test 2.2: Cutover date respected**
```sql
-- Execute
SELECT MIN(CollectionTime) AS OldestNew, MAX(CollectionTime) AS NewestOld
FROM vw_PerformanceMetrics;

-- Assert
-- No overlap: NewestOld < '2025-10-27', OldestNew >= '2025-10-27'
```

#### Category 3: API Compatibility

**Test 3.1: usp_GetMetricHistory returns expected schema**
```sql
-- Execute
EXEC usp_GetMetricHistory
    @ServerID = 1,
    @StartTime = '2025-10-27 00:00:00',
    @EndTime = '2025-10-27 23:59:59';

-- Assert
-- Columns: ServerID, CollectionTime, MetricCategory, MetricName, MetricValue
-- All columns NOT NULL (except MetricValue)
```

**Test 3.2: Filtering by MetricCategory works**
```sql
-- Execute
SELECT DISTINCT MetricCategory
FROM vw_PerformanceMetrics
WHERE MetricName = 'CpuSignalWaitPct';

-- Assert
-- Expected: Only 'CPU' category
```

#### Category 4: Multi-Server Support

**Test 4.1: ServerID foreign key constraint**
```sql
-- Execute (should fail)
INSERT INTO PerfSnapshotRun (ServerID, SnapshotUTC, ...)
VALUES (999, GETUTCDATE(), ...);

-- Assert
-- Expected: FK constraint violation (ServerID 999 doesn't exist in Servers table)
```

**Test 4.2: NULL ServerID allowed (backwards compat)**
```sql
-- Execute (should succeed)
INSERT INTO PerfSnapshotRun (ServerID, SnapshotUTC, ...)
VALUES (NULL, GETUTCDATE(), ...);

-- Assert
-- Expected: Success, 1 row inserted
```

**Test 4.3: Collection for specific server**
```sql
-- Setup
INSERT INTO Servers (ServerName, Environment) VALUES ('SQL-PROD-01', 'Production');
DECLARE @ServerID INT = SCOPE_IDENTITY();

-- Execute
EXEC usp_CollectMetrics @ServerID = @ServerID;

-- Assert
SELECT ServerID FROM PerfSnapshotRun WHERE PerfSnapshotRunID = SCOPE_IDENTITY();
-- Expected: ServerID = @ServerID
```

#### Category 5: Feedback System

**Test 5.1: fn_GetMetricFeedback returns correct severity**
```sql
-- Execute
SELECT Severity, FeedbackText
FROM dbo.fn_GetMetricFeedback('DBA_GetDailyOverview', 1, 'CpuSignalWaitPct', 45.2);

-- Assert
-- Expected: Severity='WARNING' (45.2% is high CPU)
-- FeedbackText contains 'CPU pressure' or similar
```

**Test 5.2: Feedback rules cover expected range**
```sql
-- Execute
SELECT COUNT(*) AS RuleCount
FROM FeedbackRule
WHERE ProcedureName = 'DBA_GetDailyOverview'
  AND MetricName = 'CpuSignalWaitPct'
  AND IsActive = 1;

-- Assert
-- Expected: >= 3 rules (INFO, WARNING, CRITICAL ranges)
```

#### Category 6: Configuration System

**Test 6.1: fn_GetConfigBit returns defaults**
```sql
-- Execute
SELECT dbo.fn_GetConfigBit('EnableP0Collection') AS P0Enabled,
       dbo.fn_GetConfigBit('EnableP3Collection') AS P3Enabled;

-- Assert
-- Expected: P0Enabled=1, P3Enabled=0 (default priorities)
```

**Test 6.2: vw_MonitoredDatabases filters correctly**
```sql
-- Setup
UPDATE ConfigSetting SET ConfigValue = 'master,msdb' WHERE ConfigKey = 'DatabaseFilter';

-- Execute
SELECT DatabaseName FROM vw_MonitoredDatabases;

-- Assert
-- Expected: Only 'master' and 'msdb', not 'tempdb' or user databases
```

#### Category 7: Modular Collectors (P0-P3)

**Test 7.1: P0 collectors run successfully**
```sql
-- Execute
DECLARE @RunID BIGINT;
INSERT INTO PerfSnapshotRun (SnapshotUTC, ServerName, SqlVersion)
VALUES (GETUTCDATE(), @@SERVERNAME, @@VERSION);
SET @RunID = SCOPE_IDENTITY();

EXEC DBA_Collect_P0_QueryStats @RunID, @Debug = 1;

-- Assert
SELECT COUNT(*) FROM PerfSnapshotQueryStats WHERE PerfSnapshotRunID = @RunID;
-- Expected: > 0 (at least some queries collected)
```

**Test 7.2: P3 collectors skipped when disabled**
```sql
-- Setup
UPDATE ConfigSetting SET ConfigValue = '0' WHERE ConfigKey = 'EnableP3Collection';

-- Execute
EXEC DBA_CollectPerformanceSnapshot @Debug = 1;

-- Assert
SELECT COUNT(*) FROM LogEntry
WHERE ProcedureName = 'DBA_CollectPerformanceSnapshot'
  AND ProcedureSection LIKE '%P3%';
-- Expected: 0 (P3 section not executed)
```

### 6.3 Integration Tests (5 test cases)

**Test I-1: End-to-end collection and retrieval**
```bash
# 1. Trigger collection
curl -X POST http://localhost:9000/api/collect

# 2. Wait for completion
sleep 5

# 3. Retrieve metrics
curl http://localhost:9000/api/servers/1/metrics?start=2025-10-27T00:00:00&end=2025-10-27T23:59:59

# Assert: HTTP 200, JSON array with metrics
```

**Test I-2: Grafana dashboard query**
```sql
-- Execute in Grafana SQL datasource
SELECT
    CollectionTime AS "time",
    MetricValue AS "value",
    MetricName AS "metric"
FROM vw_PerformanceMetrics
WHERE ServerID = $serverId
  AND MetricCategory = 'CPU'
  AND $__timeFilter(CollectionTime)
ORDER BY CollectionTime;

-- Assert: Grafana renders time-series chart successfully
```

**Test I-3: Multi-server collection via linked server**
```sql
-- On monitoring server (MonitoringDB)
DECLARE @ServerID INT = 1;  -- SQL-PROD-01
EXEC usp_CollectMetrics_RemoteServer @ServerID = @ServerID;

-- Assert: PerfSnapshotRun has new row with ServerID = 1
```

**Test I-4: SQL Agent job execution**
```bash
# Trigger job manually
sqlcmd -S localhost -Q "EXEC msdb.dbo.sp_start_job @job_name = 'SQL Monitor - Collect Metrics'"

# Wait for completion
sleep 10

# Check job history
sqlcmd -S localhost -Q "SELECT TOP 1 run_status FROM msdb.dbo.sysjobhistory WHERE job_id = ... ORDER BY run_date DESC, run_time DESC"

# Assert: run_status = 1 (success)
```

**Test I-5: API backward compatibility (Phase 1.0 client)**
```csharp
// Old client code (Phase 1.0)
var client = new HttpClient();
var response = await client.GetAsync("http://localhost:9000/api/servers/1/metrics?start=2025-10-27");
var metrics = await response.Content.ReadAsAsync<List<MetricModel>>();

// Assert
Assert.NotEmpty(metrics);
Assert.All(metrics, m => {
    Assert.NotNull(m.MetricCategory);
    Assert.NotNull(m.MetricName);
});
```

### 6.4 Performance Tests (5 test cases)

**Test P-1: Collection overhead < 3% CPU**
```sql
-- Baseline (no collection)
-- Measure CPU: SELECT * FROM sys.dm_os_performance_counters WHERE counter_name = 'Processor Time'
-- Baseline: X%

-- Execute collection
EXEC DBA_CollectPerformanceSnapshot;

-- Measure CPU again
-- Expected: < Baseline + 3%
```

**Test P-2: vw_PerformanceMetrics query < 500ms (90 days)**
```sql
SET STATISTICS TIME ON;

SELECT MetricCategory, MetricName, AVG(MetricValue) AS AvgValue
FROM vw_PerformanceMetrics
WHERE ServerID = 1
  AND CollectionTime >= DATEADD(DAY, -90, GETUTCDATE())
GROUP BY MetricCategory, MetricName;

-- Assert: Execution time < 500ms
```

**Test P-3: Columnstore index effectiveness**
```sql
-- Check rowgroup compression
SELECT
    object_name(object_id) AS TableName,
    state_desc,
    total_rows,
    deleted_rows,
    size_in_bytes / 1024.0 / 1024.0 AS SizeMB
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID('dbo.PerfSnapshotRun');

-- Assert: Most rowgroups in COMPRESSED state, high compression ratio
```

**Test P-4: Partition elimination working**
```sql
-- Query single month
SET STATISTICS IO ON;

SELECT COUNT(*)
FROM PerfSnapshotRun
WHERE SnapshotUTC >= '2025-10-01' AND SnapshotUTC < '2025-11-01';

-- Assert: Logical reads only from October partition (not all partitions)
```

**Test P-5: Concurrent collection (multi-server)**
```bash
# Simulate 10 servers collecting simultaneously
for i in {1..10}; do
    sqlcmd -S localhost -Q "EXEC usp_CollectMetrics_RemoteServer @ServerID = $i" &
done
wait

# Assert: No deadlocks, all 10 collections successful
```

### 6.5 Compatibility Tests (3 test cases)

**Test C-1: Single-server mode (DBATools only)**
```sql
-- Verify sql-monitor-agent works without MonitoringDB
-- 1. No Servers table dependency
-- 2. ServerID defaults to NULL
-- 3. Collection succeeds

USE DBATools;
EXEC DBA_CollectPerformanceSnapshot @Debug = 1;

SELECT ServerID FROM PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC;
-- Expected: ServerID IS NULL (backwards compatible)
```

**Test C-2: Phase 1.0 API client still works**
```csharp
// Client expects old PerformanceMetrics shape
public class MetricModel {
    public int ServerID { get; set; }
    public DateTime CollectionTime { get; set; }
    public string MetricCategory { get; set; }
    public string MetricName { get; set; }
    public decimal? MetricValue { get; set; }
}

// Call API
var metrics = await api.GetMetricHistoryAsync(serverId: 1, start, end);

// Assert: Correct shape returned (view handles transformation)
Assert.All(metrics, m => Assert.NotNull(m.MetricCategory));
```

**Test C-3: Grafana dashboards (Phase 1.0) still work**
```bash
# Import existing Grafana dashboard JSON
curl -X POST http://localhost:9001/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @dashboards/01-instance-health.json

# Verify panels render without errors
# Assert: No "column not found" errors, charts display data
```

### 6.6 Migration Tests (2 test cases)

**Test M-1: DBATools → MonitoringDB data migration**
```sql
-- 1. Create test data in DBATools
USE DBATools;
EXEC DBA_CollectPerformanceSnapshot;  -- Run 10 times to get historical data

-- 2. Run migration script
:r scripts/migrate-dbatools-to-monitoringdb.sql

-- 3. Verify data in MonitoringDB
USE MonitoringDB;
SELECT COUNT(*) AS MigratedRows FROM PerfSnapshotRun;

-- Assert: MigratedRows = 10
```

**Test M-2: Rollback migration**
```sql
-- 1. Backup MonitoringDB
BACKUP DATABASE MonitoringDB TO DISK = 'test_backup.bak';

-- 2. Run migration (simulate partial failure)
-- ... migration fails midway

-- 3. Rollback
RESTORE DATABASE MonitoringDB FROM DISK = 'test_backup.bak' WITH REPLACE;

-- 4. Verify DBATools unchanged
USE DBATools;
SELECT COUNT(*) FROM PerfSnapshotRun;
-- Assert: Original data intact
```

---

## 7. Partitioning Strategy

### 7.1 Partitioning Decision Matrix

| Table | Deployment Mode | Partition? | Rationale |
|-------|-----------------|------------|-----------|
| **PerfSnapshotRun** | DBATools (single-server) | ❌ No | Small data volume (<100K rows/month) |
| **PerfSnapshotRun** | MonitoringDB (multi-server) | ✅ Yes | Large volume (10 servers × 100K = 1M rows/month) |
| **PerfSnapshotQueryStats** | DBATools | ❌ No | Optional collector (P0), manageable size |
| **PerfSnapshotQueryStats** | MonitoringDB | ✅ Yes | High volume (1000s of queries × 10 servers) |
| **PerfSnapshotWaitStats** | Both | ✅ Yes | Always high volume (100+ wait types per snapshot) |
| **PerformanceMetrics_Legacy** | MonitoringDB | ❌ No | Read-only, will be dropped after 90 days |

### 7.2 Partition Strategy: Monthly Range Partitioning

**Partition Function**:
```sql
CREATE PARTITION FUNCTION PF_MonitoringByMonth (DATETIME2)
AS RANGE RIGHT FOR VALUES (
    '2025-01-01',
    '2025-02-01',
    '2025-03-01',
    '2025-04-01',
    '2025-05-01',
    '2025-06-01',
    '2025-07-01',
    '2025-08-01',
    '2025-09-01',
    '2025-10-01',
    '2025-11-01',
    '2025-12-01',
    '2026-01-01'
);
```

**Partition Scheme**:
```sql
CREATE PARTITION SCHEME PS_MonitoringByMonth
AS PARTITION PF_MonitoringByMonth
ALL TO ([PRIMARY]);
-- Or map to multiple filegroups for I/O parallelism
```

**Table Creation with Partitioning**:
```sql
CREATE TABLE dbo.PerfSnapshotRun (
    PerfSnapshotRunID BIGINT IDENTITY(1,1) NOT NULL,
    SnapshotUTC DATETIME2(3) NOT NULL,
    ServerID INT NULL,
    -- ... other columns

    CONSTRAINT PK_PerfSnapshotRun PRIMARY KEY CLUSTERED (SnapshotUTC, PerfSnapshotRunID)
) ON PS_MonitoringByMonth(SnapshotUTC);
```

**Key Design Points**:
1. **Partition key**: `SnapshotUTC` (natural time-series partitioning)
2. **Range**: RANGE RIGHT (partition boundary belongs to right partition)
3. **Clustered key**: `(SnapshotUTC, PerfSnapshotRunID)` - partition key MUST be first
4. **Why not ServerID?** - Most queries filter by time, not server (time > server in WHERE clause)

### 7.3 Sliding Window Maintenance

**Monthly Job: Add Next Month Partition**
```sql
-- Runs on 1st of each month
DECLARE @NextMonth DATE = DATEADD(MONTH, 1, DATEADD(MONTH, DATEDIFF(MONTH, 0, GETUTCDATE()), 0));

ALTER PARTITION SCHEME PS_MonitoringByMonth
NEXT USED [PRIMARY];

ALTER PARTITION FUNCTION PF_MonitoringByMonth()
SPLIT RANGE (@NextMonth);
```

**Monthly Job: Drop Old Partition (90-day retention)**
```sql
-- Drop data older than 90 days
DECLARE @OldestMonth DATE = DATEADD(MONTH, -3, DATEADD(MONTH, DATEDIFF(MONTH, 0, GETUTCDATE()), 0));

-- Switch out old partition to staging table
ALTER TABLE PerfSnapshotRun
SWITCH PARTITION $PARTITION.PF_MonitoringByMonth(@OldestMonth)
TO PerfSnapshotRun_Archive;

-- Merge partition boundary (remove from function)
ALTER PARTITION FUNCTION PF_MonitoringByMonth()
MERGE RANGE (@OldestMonth);

-- Archive or drop staging table
-- (Backup to blob storage, then DROP TABLE PerfSnapshotRun_Archive)
```

### 7.4 When to Add Partitioning (DBATools Migration)

**Trigger**: When data volume exceeds **10 million rows**

**Migration Process** (add partitioning to existing table):
```sql
-- 1. Create partition function and scheme (as above)

-- 2. Create new partitioned table with same schema
CREATE TABLE dbo.PerfSnapshotRun_Partitioned (
    -- Same schema as PerfSnapshotRun
) ON PS_MonitoringByMonth(SnapshotUTC);

-- 3. Copy data in batches (partition-aware)
INSERT INTO PerfSnapshotRun_Partitioned
SELECT * FROM PerfSnapshotRun
WHERE SnapshotUTC >= '2025-01-01' AND SnapshotUTC < '2025-02-01';
-- Repeat for each month

-- 4. Drop old table, rename new
DROP TABLE PerfSnapshotRun;
EXEC sp_rename 'PerfSnapshotRun_Partitioned', 'PerfSnapshotRun';

-- 5. Recreate indexes, foreign keys, etc.
```

---

## 8. Rollback Procedures

### 8.1 Risk Scenarios

| Scenario | Likelihood | Impact | Rollback Complexity |
|----------|-----------|--------|---------------------|
| **View definition error** | Medium | High (API breaks) | Low (fix view) |
| **Data migration failure** | Low | Critical (data loss) | High (restore backup) |
| **Performance regression** | Medium | Medium (slow queries) | Medium (revert schema) |
| **API compatibility break** | Low | Critical (clients fail) | High (revert + redeploy) |
| **Partition corruption** | Very Low | Critical (data inaccessible) | High (restore backup) |

### 8.2 Pre-Cutover Checklist

**Before deploying Phase 1.9**:
- [ ] Full database backup (MonitoringDB + DBATools)
- [ ] Export existing PerformanceMetrics data to CSV
- [ ] Document current API response format (save sample JSON)
- [ ] Baseline performance metrics (query execution times)
- [ ] Git tag: `pre-phase-1.9-cutover`
- [ ] Grafana dashboard export (all dashboards to JSON)
- [ ] SQL Agent job backup (script out all jobs)

### 8.3 Rollback Procedure: View Definition Error

**Symptom**: API returns errors, Grafana panels show "column not found"

**Rollback** (5 minutes):
```sql
-- 1. Drop broken view
DROP VIEW dbo.vw_PerformanceMetrics;

-- 2. Recreate pointing to legacy table (Phase 1.0 schema)
CREATE VIEW dbo.vw_PerformanceMetrics AS
SELECT MetricID, ServerID, CollectionTime, MetricCategory, MetricName, MetricValue
FROM dbo.PerformanceMetrics_Legacy;

-- 3. Stop Phase 1.9 collection
EXEC msdb.dbo.sp_stop_job @job_name = 'SQL Monitor - Collect Metrics';

-- 4. Revert SQL Agent job to Phase 1.0 collection procedure
-- (manually edit job step to call old procedure)

-- 5. Resume collection
EXEC msdb.dbo.sp_start_job @job_name = 'SQL Monitor - Collect Metrics';
```

**Validation**:
```bash
# Test API
curl http://localhost:9000/api/servers/1/metrics

# Expected: HTTP 200, JSON with Phase 1.0 schema
```

### 8.4 Rollback Procedure: Data Migration Failure

**Symptom**: Migration script fails, MonitoringDB in inconsistent state

**Rollback** (30 minutes):
```sql
-- 1. Stop all collection jobs
EXEC msdb.dbo.sp_stop_job @job_name = 'SQL Monitor - Collect Metrics';

-- 2. Restore MonitoringDB from pre-cutover backup
USE master;
ALTER DATABASE MonitoringDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE MonitoringDB FROM DISK = 'D:\Backups\MonitoringDB_PrePhase19.bak' WITH REPLACE;
ALTER DATABASE MonitoringDB SET MULTI_USER;

-- 3. Verify data integrity
USE MonitoringDB;
DBCC CHECKDB;

-- 4. Test queries
SELECT TOP 100 * FROM PerformanceMetrics ORDER BY CollectionTime DESC;

-- 5. Resume collection (Phase 1.0 procedure)
EXEC msdb.dbo.sp_start_job @job_name = 'SQL Monitor - Collect Metrics';
```

**Validation**:
```sql
-- Check row counts match pre-cutover baseline
SELECT 'PerformanceMetrics' AS TableName, COUNT(*) AS RowCount FROM PerformanceMetrics
UNION ALL
SELECT 'Servers', COUNT(*) FROM Servers;

-- Compare with documented baseline
```

### 8.5 Rollback Procedure: Performance Regression

**Symptom**: Queries take >500ms (vs <200ms baseline), Grafana dashboards timeout

**Diagnosis**:
```sql
-- Identify slow queries
SELECT
    qt.text AS QueryText,
    qs.execution_count,
    qs.total_elapsed_time / 1000.0 / qs.execution_count AS AvgDurationMs
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qt.text LIKE '%vw_PerformanceMetrics%'
ORDER BY qs.total_elapsed_time DESC;
```

**Rollback Options**:

**Option A: Add Indexes** (if view unpivoting is slow)
```sql
-- Add filtered indexes on base table
CREATE NONCLUSTERED INDEX IX_PerfSnapshotRun_ServerID_Time
ON dbo.PerfSnapshotRun(ServerID, SnapshotUTC)
INCLUDE (CpuSignalWaitPct, SessionsCount, RequestsCount);
```

**Option B: Materialized View** (if unpivoting overhead unacceptable)
```sql
-- Create indexed view (pre-computed unpivot)
CREATE VIEW dbo.vw_PerformanceMetrics_Indexed
WITH SCHEMABINDING
AS
SELECT
    CAST((PerfSnapshotRunID * 1000) + MetricOrdinal AS BIGINT) AS MetricID,
    ISNULL(ServerID, 0) AS ServerID,
    SnapshotUTC AS CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue
FROM dbo.PerfSnapshotRun
CROSS APPLY (...);

-- Add clustered index (materializes the view)
CREATE UNIQUE CLUSTERED INDEX IX_vw_PerformanceMetrics_Indexed
ON dbo.vw_PerformanceMetrics_Indexed(MetricID);
```

**Option C: Full Rollback** (if performance unrecoverable)
```sql
-- Revert to Phase 1.0 PerformanceMetrics table (direct storage, no unpivoting)
-- (Use procedures from Rollback 8.4)
```

### 8.6 Rollback Procedure: API Compatibility Break

**Symptom**: Clients report errors, API returns unexpected JSON shape

**Rollback** (15 minutes):
```bash
# 1. Git revert
cd /mnt/d/dev2/sql-monitor/api
git revert HEAD  # Revert last commit (Phase 1.9 changes)
git push

# 2. Rebuild API
dotnet build

# 3. Redeploy container
docker-compose down
docker-compose up --build -d

# 4. Verify API contract
curl http://localhost:9000/api/servers/1/metrics | jq .

# Expected: Phase 1.0 JSON shape
```

**Database Rollback** (if needed):
```sql
-- Revert view to point to legacy table
-- (Same as Rollback 8.3)
```

### 8.7 Rollback Decision Matrix

| Time Since Cutover | Rollback Complexity | Recommended Action |
|--------------------|---------------------|-------------------|
| **< 1 hour** | Low | Full rollback (restore backup) |
| **1-24 hours** | Medium | Selective rollback (views only, keep data) |
| **1-7 days** | High | Fix forward (patch issues, don't rollback) |
| **> 7 days** | Very High | Fix forward only (too much new data to lose) |

---

## 9. Implementation Sequence

### 9.1 Week 1: Database Configuration & Core Migration (24 hours)

#### Day 1 (8 hours): Configurable Database Preparation

**Tasks**:
1. ✅ Create `database/20-create-dbatools-tables.sql` (all PerfSnapshot* tables)
2. ✅ Add `ServerID INT NULL` column to all PerfSnapshot* tables
3. ✅ Add foreign key: `FOREIGN KEY (ServerID) REFERENCES Servers(ServerID)`
4. ✅ Create `Servers` table in DBATools (for backwards compat)
5. ✅ Test: Deploy to DBATools, verify schema
6. ✅ Test: Deploy to MonitoringDB, verify schema

**Deliverable**: SQL scripts that work in both DBATools and MonitoringDB

#### Day 2 (8 hours): Schema Unification

**Tasks**:
1. ✅ Create `database/21-create-mapping-views.sql`
2. ✅ Implement `vw_PerformanceMetrics` (unpivot PerfSnapshotRun)
3. ✅ Implement `vw_PerformanceMetrics_QueryStats` (unpivot PerfSnapshotQueryStats)
4. ✅ Implement `vw_PerformanceMetrics_IOStats`, `_Memory`, `_WaitStats`, etc.
5. ✅ Implement `vw_PerformanceMetrics_Unified` (UNION ALL of above)
6. ✅ Test: Query views, verify unpivoting logic
7. ✅ Benchmark: Query performance < 500ms for 90 days

**Deliverable**: Mapping views that transform WIDE → TALL schema

#### Day 3 (8 hours): Data Migration Strategy

**Tasks**:
1. ✅ Rename `PerformanceMetrics` → `PerformanceMetrics_Legacy`
2. ✅ Update `vw_PerformanceMetrics` to UNION legacy + new data
3. ✅ Create `scripts/migrate-dbatools-to-monitoringdb.sql`
4. ✅ Test: Migrate sample DBATools data → MonitoringDB
5. ✅ Test: Queries work against unified view (legacy + new)
6. ✅ Document cutover procedure

**Deliverable**: Migration scripts + unified view

### 9.2 Week 2: Enhanced Tables & Feedback System (24 hours)

#### Day 4 (8 hours): Enhanced Tables Migration

**Tasks**:
1. ✅ Create all 17 enhanced tables in MonitoringDB (from sql-monitor-agent)
2. ✅ Add `ServerID` foreign keys to all tables
3. ✅ Create indexes optimized for multi-server queries
4. ✅ Test: Insert sample data, verify constraints
5. ✅ Test: Modular collectors (P0-P3) work with new schema
6. ✅ Benchmark: Collection overhead < 3% CPU

**Deliverable**: Enhanced tables deployed, tested

#### Day 5 (8 hours): Feedback System Migration

**Tasks**:
1. ✅ Create `FeedbackRule` and `FeedbackMetadata` tables
2. ✅ Create `fn_GetMetricFeedback()` function
3. ✅ Seed 50+ feedback rules (copy from sql-monitor-agent)
4. ✅ Create `DBA_GetDailyOverview` procedure (with feedback)
5. ✅ Test: Query feedback for various metric values
6. ✅ Test: Severity ranges (INFO, WARNING, CRITICAL)

**Deliverable**: Feedback system operational

#### Day 6 (8 hours): Configuration System

**Tasks**:
1. ✅ Create `ConfigSetting` table
2. ✅ Create `fn_GetConfigBit()`, `fn_GetConfigValue()` functions
3. ✅ Create `vw_MonitoredDatabases` view (database filter)
4. ✅ Seed default configuration (P0=1, P1=1, P2=0, P3=0, Retention=90)
5. ✅ Update `DBA_CollectPerformanceSnapshot` to use config
6. ✅ Test: Collection respects config (P0/P1 run, P2/P3 skip)

**Deliverable**: Configuration system integrated

### 9.3 Week 3: API Integration & Testing (12 hours)

#### Day 7 (6 hours): Stored Procedure Updates

**Tasks**:
1. ✅ Update `DBA_CollectPerformanceSnapshot` to support `@ServerID`
2. ✅ Update all P0-P3 collectors to support `@ServerID`
3. ✅ Create `usp_CollectMetrics` (wrapper for DBA_CollectPerformanceSnapshot)
4. ✅ Create `usp_GetMetricHistory` (queries vw_PerformanceMetrics)
5. ✅ Create `usp_GetPerfSnapshots` (rich endpoint, direct PerfSnapshotRun query)
6. ✅ Create `usp_GetDailyOverview` (wrapper for DBA_GetDailyOverview)
7. ✅ Test: All SPs execute successfully

**Deliverable**: API-facing stored procedures

#### Day 8 (3 hours): API Compatibility Layer

**Tasks**:
1. ✅ Test existing API controllers with new views
2. ✅ Verify JSON response matches Phase 1.0 contract
3. ✅ Create new API endpoint: `/api/servers/{id}/snapshots` (rich data)
4. ✅ Test Grafana dashboards (no changes needed)
5. ✅ Document migration guide for Grafana queries (optional optimizations)

**Deliverable**: API compatibility verified, new rich endpoint added

#### Day 9 (3 hours): Integration Testing

**Tasks**:
1. ✅ Run all 20+ unit tests
2. ✅ Run 5 integration tests (end-to-end collection + retrieval)
3. ✅ Run 5 performance tests (collection overhead, query speed)
4. ✅ Run 3 compatibility tests (single-server, API backward compat, Grafana)
5. ✅ Run 2 migration tests (DBATools → MonitoringDB, rollback)
6. ✅ Document test results

**Deliverable**: Test report, all tests passing

---

## 10. Risk Assessment

### 10.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **View unpivoting too slow** | Medium | High | Indexed views, columnstore indexes, partition elimination |
| **API compatibility break** | Low | Critical | Comprehensive test suite, backward compat views |
| **Data migration failure** | Low | Critical | Full backup before cutover, rollback procedures |
| **Foreign key violations** | Medium | Medium | NULL ServerID allowed (backwards compat) |
| **Partition corruption** | Very Low | Critical | Tested partition scripts, backup before partition ops |

### 10.2 Organizational Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Existing sql-monitor-agent users resist change** | Medium | Medium | Backwards compatible single-server mode |
| **Lack of testing resources** | High | High | Automated test suite (20+ tests) |
| **Documentation outdated** | High | Medium | Update all docs in Phase 1.9 PR |
| **Knowledge transfer gap** | Medium | High | Technical design doc (this document!) |

### 10.3 Risk Mitigation Checklist

**Before Implementation**:
- [ ] Stakeholder review of technical design
- [ ] Test environment setup (isolated from production)
- [ ] Backup strategy documented
- [ ] Rollback procedures tested

**During Implementation**:
- [ ] Daily standup to track progress
- [ ] Test-driven development (write tests first)
- [ ] Code review for all schema changes
- [ ] Performance benchmarks after each major component

**After Implementation**:
- [ ] Full test suite execution (all 30+ tests)
- [ ] Performance benchmarks vs baseline
- [ ] Documentation update
- [ ] User acceptance testing (UAT)

---

## Conclusion

This technical design document provides a comprehensive blueprint for Phase 1.9 integration. Key takeaways:

1. **Schema transformation** solved via CROSS APPLY unpivoting
2. **Configurable database** simplified to deployment-time decision (no synonyms needed)
3. **Data migration** handled via dual-table coexistence (legacy + new)
4. **API compatibility** maintained through mapping views (zero API changes)
5. **Naming convention** clarified (DBA_* for core, usp_* for API)
6. **Test plan** comprehensive (30+ tests across 6 categories)
7. **Partitioning** selective (MonitoringDB only, monthly ranges)
8. **Rollback** procedures defined for all failure scenarios

**Next Steps**:
1. Review and approve this design document
2. Begin Week 1 implementation (database configuration)
3. Execute test-driven development (write tests first!)
4. Track progress via TodoWrite tool

**Success Criteria**:
- All 30+ tests passing
- Collection overhead < 3% CPU
- Query performance < 500ms
- Zero API contract changes
- Backwards compatible single-server mode works

---

**Document Status**: ✅ **Design Complete - Ready for Review**
**Implementation Start**: Upon approval
**Estimated Completion**: 3 weeks from start date
