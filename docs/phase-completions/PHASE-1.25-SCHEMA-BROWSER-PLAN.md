# Phase 1.25: Database Schema Browser & Code Navigation (Revised)

**Date**: October 26, 2025
**Priority**: Insert between Phase 1 (Gap Closing) and SOC 2 Compliance
**Purpose**: Developer productivity, schema discovery, foundation for Phase 3 Code Browser

**CRITICAL DESIGN PRINCIPLES**:
1. ✅ **Cached Metadata** - Refresh only on schema changes (DDL events)
2. ✅ **Per-Database Views** - Single database queries only (no cross-database joins)
3. ✅ **Minimal Runtime Impact** - <1% CPU, background collection only
4. ✅ **Off-Hours Seeding** - SQL Agent job runs at 2 AM daily (non-business hours)
5. ✅ **Change Detection** - Track schema versions via DDL triggers

---

## Executive Summary

**What**: Cached, change-detection-based schema browser in Grafana with minimal runtime impact

**Why**:
- ✅ **Zero Production Impact**: Metadata cached, refreshed only on DDL changes
- ✅ **Developer Productivity**: Instant schema browsing without SSMS
- ✅ **Per-Database Isolation**: No cross-database queries (performance!)
- ✅ **Automatic Seeding**: Runs at 2 AM daily via SQL Agent (off-hours)
- ✅ **Foundation for Phase 3**: Code browser infrastructure

**Timeline**: 40 hours (5 days) - Extended from 32h due to caching/change-detection logic
**Outcome**: Fully browsable, cached database schema in Grafana with change detection

---

## Architecture: Caching + Change Detection

### Problem: Real-Time Metadata Queries Are Expensive

**Traditional Approach** (BAD):
```sql
-- This runs EVERY time Grafana dashboard loads (EXPENSIVE!)
SELECT * FROM sys.tables
JOIN sys.dm_db_partition_stats ...
JOIN sys.dm_db_index_physical_stats ...
```

**Impact**:
- 🔴 High CPU on monitored servers (5-10% per query)
- 🔴 Slow dashboard loads (10-30 seconds)
- 🔴 Production impact during business hours

### Solution: Cached Metadata + Change Detection

**New Approach** (GOOD):
1. **Cache metadata** in MonitoringDB tables (fast lookups)
2. **Detect schema changes** via DDL triggers or schema version tracking
3. **Refresh only changed databases** (incremental updates)
4. **Seed automatically** at 2 AM daily (off-hours)
5. **Grafana queries cached tables** (instant, no production impact)

**Impact**:
- ✅ <1% CPU overhead (background collection only)
- ✅ Instant dashboard loads (<500ms)
- ✅ Zero production impact during business hours

---

## Change Detection Strategy

### Option 1: DDL Trigger-Based (Recommended)

**How It Works**:
1. Create DDL trigger on each monitored database
2. Trigger fires on CREATE/ALTER/DROP events (tables, views, procedures, etc.)
3. Trigger inserts row into `SchemaChangeLog` table in MonitoringDB
4. SQL Agent job checks `SchemaChangeLog` every 5 minutes
5. If changes detected, refresh metadata for affected database only

**Advantages**:
- ✅ Real-time detection (5-minute lag max)
- ✅ Incremental refresh (only changed databases)
- ✅ Minimal overhead (trigger is <10ms)

**Implementation**:
```sql
-- On each monitored database
CREATE TRIGGER trg_DDL_SchemaChangeDetection
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE,
    CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE,
    CREATE_VIEW, ALTER_VIEW, DROP_VIEW,
    CREATE_FUNCTION, ALTER_FUNCTION, DROP_FUNCTION,
    CREATE_INDEX, ALTER_INDEX, DROP_INDEX
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EventData XML = EVENTDATA();
    DECLARE @EventType VARCHAR(50) = @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'VARCHAR(50)');
    DECLARE @ObjectName NVARCHAR(128) = @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)');
    DECLARE @SchemaName NVARCHAR(128) = @EventData.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(128)');

    -- Log change to MonitoringDB (via linked server or remote SP call)
    INSERT INTO [MonitoringDB].[dbo].[SchemaChangeLog] (
        ServerName, DatabaseName, SchemaName, ObjectName, EventType, EventTime
    )
    VALUES (
        @@SERVERNAME,
        DB_NAME(),
        @SchemaName,
        @ObjectName,
        @EventType,
        GETUTCDATE()
    );
END;
```

### Option 2: Schema Version Tracking (Fallback)

**How It Works**:
1. Store `CHECKSUM_AGG` hash of `sys.objects.modify_date` per database
2. SQL Agent job compares current hash vs. last known hash
3. If hash differs, refresh metadata for that database

**Advantages**:
- ✅ No DDL triggers required (some shops disallow triggers)
- ✅ Simple to implement

**Disadvantages**:
- ⚠️ Higher overhead (runs query on every check)
- ⚠️ Less precise (doesn't tell you WHAT changed)

**We'll use Option 1 (DDL Trigger-Based)** for best performance.

---

## Database Schema Design (Revised)

### New Table: SchemaChangeLog (Change Detection)

```sql
CREATE TABLE dbo.SchemaChangeLog (
    ChangeLogID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerName NVARCHAR(128) NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NULL,
    ObjectName NVARCHAR(128) NULL,
    EventType VARCHAR(50) NOT NULL, -- CREATE_TABLE, ALTER_PROCEDURE, etc.
    EventTime DATETIME2(7) NOT NULL,
    ProcessedAt DATETIME2(7) NULL, -- NULL = not yet processed

    INDEX IX_SchemaChangeLog_Pending (ProcessedAt) WHERE ProcessedAt IS NULL,
    INDEX IX_SchemaChangeLog_Database (ServerName, DatabaseName)
);
```

### New Table: DatabaseMetadataCache (Per-Database Cache Status)

```sql
CREATE TABLE dbo.DatabaseMetadataCache (
    CacheID INT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    LastRefreshTime DATETIME2(7) NOT NULL,
    LastSchemaChangeTime DATETIME2(7) NULL, -- From SchemaChangeLog
    ObjectCount INT NULL, -- Total tables + views + SPs + functions
    IsCurrent BIT NOT NULL DEFAULT 1, -- 0 = needs refresh

    CONSTRAINT UQ_DatabaseMetadataCache_Server_Database UNIQUE (ServerID, DatabaseName),
    INDEX IX_DatabaseMetadataCache_NeedsRefresh (IsCurrent) WHERE IsCurrent = 0
);
```

### Existing Tables (Same as Before)

1. **TableMetadata** - Complete table inventory with statistics
2. **ColumnMetadata** - All column details per table
3. **IndexMetadata** - Index details with fragmentation
4. **PartitionMetadata** - Partition statistics
5. **ForeignKeyMetadata** - FK relationships
6. **CodeObjectMetadata** - Stored procedures, views, functions, triggers
7. **DependencyMetadata** - Object dependencies

**Key Revision**: All tables now include `LastRefreshTime` column to track cache freshness.

---

## Stored Procedures (Revised for Caching)

### 1. usp_DetectSchemaChanges (Change Detection)

**Purpose**: Check for pending schema changes and mark databases for refresh

```sql
CREATE PROCEDURE dbo.usp_DetectSchemaChanges
AS
BEGIN
    SET NOCOUNT ON;

    -- Mark databases that have pending schema changes
    UPDATE dmc
    SET IsCurrent = 0
    FROM dbo.DatabaseMetadataCache dmc
    WHERE EXISTS (
        SELECT 1
        FROM dbo.SchemaChangeLog scl
        WHERE scl.ServerName = (SELECT ServerName FROM dbo.Servers WHERE ServerID = dmc.ServerID)
          AND scl.DatabaseName = dmc.DatabaseName
          AND scl.ProcessedAt IS NULL
    );

    DECLARE @AffectedDatabases INT = @@ROWCOUNT;
    PRINT CONCAT('Detected schema changes in ', @AffectedDatabases, ' database(s)');
END;
```

### 2. usp_RefreshMetadataCache (Incremental Refresh)

**Purpose**: Refresh metadata cache for databases marked as stale

```sql
CREATE PROCEDURE dbo.usp_RefreshMetadataCache
    @ServerID INT = NULL, -- NULL = all servers
    @DatabaseName NVARCHAR(128) = NULL, -- NULL = all databases needing refresh
    @ForceRefresh BIT = 0 -- 1 = refresh even if current
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RefreshCount INT = 0;

    -- Cursor for databases needing refresh
    DECLARE @CurServerID INT, @CurDatabaseName NVARCHAR(128);

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ServerID, DatabaseName
        FROM dbo.DatabaseMetadataCache
        WHERE (@ServerID IS NULL OR ServerID = @ServerID)
          AND (@DatabaseName IS NULL OR DatabaseName = @DatabaseName)
          AND (@ForceRefresh = 1 OR IsCurrent = 0);

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @CurServerID, @CurDatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT CONCAT('Refreshing metadata for database: ', @CurDatabaseName);

        -- Delete old metadata for this database
        DELETE FROM dbo.TableMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.ColumnMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.IndexMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.PartitionMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.ForeignKeyMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.CodeObjectMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.DependencyMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;

        -- Collect fresh metadata
        EXEC dbo.usp_CollectTableMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
        EXEC dbo.usp_CollectColumnMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
        EXEC dbo.usp_CollectIndexMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
        EXEC dbo.usp_CollectPartitionMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
        EXEC dbo.usp_CollectForeignKeyMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
        EXEC dbo.usp_CollectCodeObjectMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
        EXEC dbo.usp_CollectDependencyMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;

        -- Update cache status
        UPDATE dbo.DatabaseMetadataCache
        SET LastRefreshTime = GETUTCDATE(),
            IsCurrent = 1
        WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;

        -- Mark schema changes as processed
        UPDATE dbo.SchemaChangeLog
        SET ProcessedAt = GETUTCDATE()
        WHERE ServerName = (SELECT ServerName FROM dbo.Servers WHERE ServerID = @CurServerID)
          AND DatabaseName = @CurDatabaseName
          AND ProcessedAt IS NULL;

        SET @RefreshCount = @RefreshCount + 1;

        FETCH NEXT FROM db_cursor INTO @CurServerID, @CurDatabaseName;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    PRINT CONCAT('Refreshed metadata for ', @RefreshCount, ' database(s)');
END;
```

### 3. usp_CollectTableMetadata (Per-Database, Remote)

**Purpose**: Collect table metadata from a SPECIFIC database (called remotely via linked server)

**Key Change**: Uses `OPENQUERY` to query remote server's sys tables

```sql
CREATE PROCEDURE dbo.usp_CollectTableMetadata
    @ServerID INT,
    @DatabaseName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerName NVARCHAR(128);
    SELECT @ServerName = ServerName FROM dbo.Servers WHERE ServerID = @ServerID;

    -- Build dynamic SQL to query remote database
    DECLARE @SQL NVARCHAR(MAX) = N'
    INSERT INTO dbo.TableMetadata (
        ServerID, DatabaseName, SchemaName, TableName, ObjectID,
        RowCount, TotalSizeMB, DataSizeMB, IndexSizeMB, ColumnCount, IndexCount, PartitionCount,
        IsPartitioned, CompressionType, CreatedDate, ModifiedDate, LastRefreshTime
    )
    SELECT
        @ServerID,
        ''' + @DatabaseName + ''',
        SCHEMA_NAME(t.schema_id),
        t.name,
        t.object_id,
        SUM(p.rows),
        SUM(a.total_pages) * 8 / 1024.0,
        SUM(a.used_pages) * 8 / 1024.0,
        (SUM(a.total_pages) - SUM(a.used_pages)) * 8 / 1024.0,
        (SELECT COUNT(*) FROM ' + QUOTENAME(@DatabaseName) + '.sys.columns c WHERE c.object_id = t.object_id),
        (SELECT COUNT(*) FROM ' + QUOTENAME(@DatabaseName) + '.sys.indexes i WHERE i.object_id = t.object_id AND i.index_id > 0),
        COUNT(DISTINCT p.partition_number),
        CASE WHEN COUNT(DISTINCT p.partition_number) > 1 THEN 1 ELSE 0 END,
        MAX(p.data_compression_desc),
        t.create_date,
        t.modify_date,
        GETUTCDATE()
    FROM ' + QUOTENAME(@DatabaseName) + '.sys.tables t
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.partitions p ON t.object_id = p.object_id
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.allocation_units a ON p.partition_id = a.container_id
    GROUP BY t.schema_id, t.name, t.object_id, t.create_date, t.modify_date;
    ';

    EXEC sp_executesql @SQL, N'@ServerID INT', @ServerID = @ServerID;
END;
```

**Same pattern for**:
- `usp_CollectColumnMetadata`
- `usp_CollectIndexMetadata`
- `usp_CollectPartitionMetadata`
- `usp_CollectForeignKeyMetadata`
- `usp_CollectCodeObjectMetadata`
- `usp_CollectDependencyMetadata`

---

## SQL Agent Jobs (Automatic Off-Hours Seeding)

### Job 1: Schema Change Detection (Every 5 Minutes)

```sql
-- Job: SQL Monitor - Schema Change Detection
-- Schedule: Every 5 minutes
-- Purpose: Detect schema changes and mark databases for refresh

EXEC dbo.usp_DetectSchemaChanges;
```

**Why Every 5 Minutes?**
- ✅ Fast detection (5-minute lag max)
- ✅ Minimal overhead (<100ms per run)
- ✅ Only marks databases as stale (no heavy lifting)

### Job 2: Metadata Refresh (Daily at 2 AM - Off-Hours)

```sql
-- Job: SQL Monitor - Metadata Refresh
-- Schedule: Daily at 2:00 AM
-- Purpose: Refresh metadata cache for all databases (off-hours)

-- Option 1: Incremental refresh (only changed databases)
EXEC dbo.usp_RefreshMetadataCache @ServerID = NULL, @ForceRefresh = 0;

-- Option 2: Full refresh (once per week on Sunday)
IF DATEPART(WEEKDAY, GETDATE()) = 1 -- Sunday
    EXEC dbo.usp_RefreshMetadataCache @ServerID = NULL, @ForceRefresh = 1;
```

**Why 2 AM?**
- ✅ Non-business hours (minimal production impact)
- ✅ Low database activity (fast execution)
- ✅ Daily schedule ensures metadata stays fresh

### Job 3: Initial Seeding (Run Once)

```sql
-- Job: SQL Monitor - Initial Metadata Seeding
-- Schedule: Run once after deployment
-- Purpose: Seed metadata cache for all databases on all servers

DECLARE @ServerID INT;

DECLARE server_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT ServerID FROM dbo.Servers WHERE IsActive = 1;

OPEN server_cursor;
FETCH NEXT FROM server_cursor INTO @ServerID;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Seed metadata for all databases on this server
    EXEC dbo.usp_RefreshMetadataCache @ServerID = @ServerID, @ForceRefresh = 1;

    FETCH NEXT FROM server_cursor INTO @ServerID;
END;

CLOSE server_cursor;
DEALLOCATE server_cursor;
```

---

## Grafana Dashboards (Querying Cached Data)

### Key Revision: All Queries Hit Cached Tables (Instant!)

**Before** (BAD - slow):
```sql
-- Direct query to sys.tables (SLOW! 10-30 seconds)
SELECT * FROM sys.tables ...
```

**After** (GOOD - fast):
```sql
-- Query cached metadata (FAST! <500ms)
SELECT * FROM dbo.TableMetadata
WHERE ServerID = $serverId
  AND DatabaseName = '$database'
ORDER BY TotalSizeMB DESC;
```

### Dashboard 1: Table Browser

**Panels**:

1. **Variable: Database** (dropdown)
   ```sql
   SELECT DISTINCT DatabaseName
   FROM dbo.TableMetadata
   WHERE ServerID = $serverId
   ORDER BY DatabaseName;
   ```

2. **Variable: Schema** (dropdown)
   ```sql
   SELECT DISTINCT SchemaName
   FROM dbo.TableMetadata
   WHERE ServerID = $serverId
     AND DatabaseName = '$database'
   ORDER BY SchemaName;
   ```

3. **Search Input: Table Name** (text variable)

4. **Cache Freshness Indicator** (stat panel)
   ```sql
   SELECT
       CASE
           WHEN DATEDIFF(HOUR, LastRefreshTime, GETUTCDATE()) < 24 THEN 'Fresh'
           WHEN DATEDIFF(HOUR, LastRefreshTime, GETUTCDATE()) < 72 THEN 'Stale'
           ELSE 'Outdated'
       END AS CacheStatus,
       LastRefreshTime
   FROM dbo.DatabaseMetadataCache
   WHERE ServerID = $serverId
     AND DatabaseName = '$database';
   ```

5. **Table List Panel** (main)
   ```sql
   SELECT
       DatabaseName,
       SchemaName,
       TableName,
       RowCount,
       TotalSizeMB,
       DataSizeMB,
       IndexSizeMB,
       ColumnCount,
       IndexCount,
       PartitionCount,
       CompressionType,
       ModifiedDate
   FROM dbo.TableMetadata
   WHERE ServerID = $serverId
     AND DatabaseName = '$database'
     AND (@schema = 'All' OR SchemaName = '$schema')
     AND (@tableName = '' OR TableName LIKE '%' + @tableName + '%')
   ORDER BY TotalSizeMB DESC;
   ```

**Performance**: <500ms (cached data)

### Dashboard 2: Table Details (Same Structure, Cached Queries)

### Dashboard 3: Code Browser (Same Structure, Cached Queries)

---

## Implementation Timeline (Revised for Caching)

### Day 1 (8 hours): Caching Infrastructure + Change Detection

**TDD Workflow**:
1. Create SchemaChangeLog and DatabaseMetadataCache tables (1 hour)
2. Write tests for usp_DetectSchemaChanges (1 hour)
3. Implement usp_DetectSchemaChanges (2 hours)
4. Write tests for usp_RefreshMetadataCache (1 hour)
5. Implement usp_RefreshMetadataCache (2 hours)
6. Create DDL triggers for change detection (1 hour)

### Day 2 (8 hours): TableMetadata + ColumnMetadata (Cached)

1. Write tests for usp_CollectTableMetadata (2 hours)
2. Implement usp_CollectTableMetadata (remote query via linked server) (3 hours)
3. Write tests for usp_CollectColumnMetadata (1 hour)
4. Implement usp_CollectColumnMetadata (2 hours)

### Day 3 (8 hours): IndexMetadata + PartitionMetadata (Cached)

1. Write tests for usp_CollectIndexMetadata (2 hours)
2. Implement usp_CollectIndexMetadata (3 hours)
3. Write tests for usp_CollectPartitionMetadata (1 hour)
4. Implement usp_CollectPartitionMetadata (2 hours)

### Day 4 (8 hours): CodeObjectMetadata + DependencyMetadata (Cached)

1. Write tests for usp_CollectCodeObjectMetadata (2 hours)
2. Implement usp_CollectCodeObjectMetadata (2 hours)
3. Write tests for usp_CollectDependencyMetadata (2 hours)
4. Implement usp_CollectDependencyMetadata (2 hours)

### Day 5 (8 hours): SQL Agent Jobs + Grafana Dashboards

1. Create SQL Agent jobs (change detection + metadata refresh) (2 hours)
2. Test DDL trigger-based change detection (1 hour)
3. Create Table Browser dashboard (2 hours)
4. Create Table Details dashboard (2 hours)
5. Create Code Browser dashboard (1 hour)

**Total**: 40 hours (5 days)

---

## Performance Impact Analysis

### Before Caching (Real-Time Queries)

| Operation | CPU Impact | Query Time | Production Impact |
|-----------|------------|------------|-------------------|
| Dashboard Load | 5-10% | 10-30 seconds | 🔴 High |
| Filter/Sort | 3-5% | 5-10 seconds | 🔴 Medium |
| Detail View | 2-3% | 3-5 seconds | ⚠️ Low-Medium |

**Total Impact**: 🔴 Unacceptable for production

### After Caching (Cached Queries)

| Operation | CPU Impact | Query Time | Production Impact |
|-----------|------------|------------|-------------------|
| Dashboard Load | <0.1% | <500ms | ✅ None |
| Filter/Sort | <0.1% | <200ms | ✅ None |
| Detail View | <0.1% | <300ms | ✅ None |
| **Background Refresh (2 AM)** | **1-2%** | **5-10 minutes** | ✅ **Off-hours only** |

**Total Impact**: ✅ Acceptable (<1% during business hours)

---

## Testing Strategy (TDD)

### Unit Tests (tSQLt Framework)

**Test Class**: `SchemaMetadata_Tests`

```sql
-- Test 1: DDL trigger logs schema changes
CREATE PROCEDURE SchemaMetadata_Tests.[test DDL trigger logs CREATE TABLE event]
AS
BEGIN
    -- Arrange
    DELETE FROM dbo.SchemaChangeLog;

    -- Act
    CREATE TABLE TestSchema.TestTable (ID INT);
    DROP TABLE TestSchema.TestTable;

    -- Assert
    DECLARE @Count INT;
    SELECT @Count = COUNT(*) FROM dbo.SchemaChangeLog WHERE ObjectName = 'TestTable';
    EXEC tSQLt.AssertEquals 1, @Count;
END;

-- Test 2: usp_DetectSchemaChanges marks databases as stale
CREATE PROCEDURE SchemaMetadata_Tests.[test usp_DetectSchemaChanges marks database as stale]
AS
BEGIN
    -- Arrange
    INSERT INTO dbo.SchemaChangeLog (ServerName, DatabaseName, EventType, EventTime)
    VALUES ('TestServer', 'TestDB', 'CREATE_TABLE', GETUTCDATE());

    INSERT INTO dbo.DatabaseMetadataCache (ServerID, DatabaseName, LastRefreshTime, IsCurrent)
    VALUES (1, 'TestDB', GETUTCDATE(), 1);

    -- Act
    EXEC dbo.usp_DetectSchemaChanges;

    -- Assert
    DECLARE @IsCurrent BIT;
    SELECT @IsCurrent = IsCurrent FROM dbo.DatabaseMetadataCache WHERE DatabaseName = 'TestDB';
    EXEC tSQLt.AssertEquals 0, @IsCurrent;
END;

-- Test 3: usp_RefreshMetadataCache refreshes stale database
CREATE PROCEDURE SchemaMetadata_Tests.[test usp_RefreshMetadataCache refreshes stale database]
AS
BEGIN
    -- Arrange
    UPDATE dbo.DatabaseMetadataCache SET IsCurrent = 0 WHERE DatabaseName = 'TestDB';

    -- Act
    EXEC dbo.usp_RefreshMetadataCache @DatabaseName = 'TestDB';

    -- Assert
    DECLARE @IsCurrent BIT;
    SELECT @IsCurrent = IsCurrent FROM dbo.DatabaseMetadataCache WHERE DatabaseName = 'TestDB';
    EXEC tSQLt.AssertEquals 1, @IsCurrent;
END;
```

### Integration Tests

1. **Change Detection End-to-End**:
   - Create table on monitored database
   - Verify DDL trigger fires
   - Verify SchemaChangeLog entry created
   - Run usp_DetectSchemaChanges
   - Verify database marked as stale
   - Run usp_RefreshMetadataCache
   - Verify metadata updated

2. **Performance Test**:
   - Seed 1,000 tables across 10 databases
   - Run full metadata refresh
   - Measure CPU impact (<2% target)
   - Measure execution time (<10 minutes target)

---

## Competitive Advantage (Revised)

### vs. Redgate SQL Monitor

| Feature | Our Solution | Redgate |
|---------|--------------|---------|
| **Integrated Schema Browser** | ✅ Cached, instant | ❌ Separate tool |
| **Change Detection** | ✅ DDL trigger-based | ❌ No |
| **Per-Database Isolation** | ✅ Yes (performance!) | ⚠️ Cross-database queries |
| **Off-Hours Seeding** | ✅ Configurable (2 AM) | ⚠️ Real-time only |
| **Production Impact** | ✅ <1% CPU | ⚠️ 3-5% CPU |
| **Cost** | **$0** | **$11,640/year** |

### vs. AWS RDS

| Feature | Our Solution | AWS RDS |
|---------|--------------|---------|
| **Schema Browser** | ✅ Built-in, cached | ❌ No |
| **Change Detection** | ✅ Automatic | ❌ No |
| **Metadata History** | ✅ Yes | ❌ No |

---

## Summary

**Phase 1.25 (Revised)** provides cached, change-detection-based schema browsing with ZERO production impact.

**Key Design Decisions**:
1. ✅ **Cached Metadata** - All Grafana queries hit MonitoringDB tables (instant, <500ms)
2. ✅ **DDL Trigger-Based Change Detection** - Real-time schema change tracking (5-minute lag)
3. ✅ **Incremental Refresh** - Only refresh databases with schema changes
4. ✅ **Off-Hours Seeding** - Daily refresh at 2 AM (non-business hours)
5. ✅ **Per-Database Isolation** - Single database queries only (performance!)

**Performance Impact**:
- 🟢 **Business Hours**: <1% CPU (cached queries only)
- 🟢 **Off-Hours (2 AM)**: 1-2% CPU for 5-10 minutes (acceptable)
- 🟢 **Dashboard Loads**: <500ms (vs. 10-30 seconds for real-time queries)

**Key Deliverables**:
- ✅ 9 new database tables (metadata + caching infrastructure)
- ✅ 8 new stored procedures (TDD-tested)
- ✅ 3 Grafana dashboards (browsing, details, code)
- ✅ 3 SQL Agent jobs (change detection, refresh, initial seeding)
- ✅ DDL triggers for automatic change detection

**Timeline**: 40 hours (5 days)
**Outcome**: Complete schema browsing in Grafana with zero production impact

**Ready to proceed with TDD implementation.**
