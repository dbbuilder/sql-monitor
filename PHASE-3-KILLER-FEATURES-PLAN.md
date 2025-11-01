# Phase 3: Killer Features - Implementation Plan

**Start Date**: 2025-11-01
**Estimated Duration**: 160 hours (20 days)
**Status**: 🔄 **PLANNING**

---

## Overview

Phase 3 builds on our rock-solid data collection foundation (Phase 2.1) to deliver the features that differentiate us from commercial solutions. These are the capabilities that users WANT and that commercial tools charge $5k-$15k/year to provide.

### Why These Features?

1. **Market Differentiation**: Beat Redgate, SolarWinds, Quest Software at $0 cost
2. **User Value**: Immediate, tangible value for DBAs and developers
3. **Technical Leverage**: Use our comprehensive data collection
4. **Monetization Potential**: These features justify premium pricing if commercialized

---

## Feature Roadmap (7 Components)

| # | Feature | Duration | Priority | Dependencies |
|---|---------|----------|----------|--------------|
| 1 | **SQL Server Health Score** | 16h | HIGH | Phase 2.1 complete ✅ |
| 2 | **Query Performance Advisor** | 32h | HIGH | Feature #1 |
| 3 | **Backup Verification Dashboard** | 16h | MEDIUM | Phase 2.1 complete ✅ |
| 4 | **Automated Index Maintenance** | 24h | HIGH | Phase 2.1 complete ✅ |
| 5 | **Capacity Planning** | 24h | MEDIUM | Phase 2.1 complete ✅ |
| 6 | **Security Vulnerability Scanner** | 24h | HIGH | None |
| 7 | **Cost Optimization Engine** | 24h | MEDIUM | Feature #2 |

**Total**: 160 hours

---

## Feature #1: SQL Server Health Score (16 hours)

### Objective

Provide a single, easy-to-understand number (0-100) that represents overall SQL Server health, with drill-down capability to see what's affecting the score.

### What Users Get

- **Single Health Score**: 0-100 (red/yellow/green)
- **Component Scores**: CPU, Memory, Disk I/O, Wait Stats, Blocking, Index Health
- **Trend Graph**: Health score over time (last 24h, 7d, 30d)
- **Top Issues**: What's dragging the score down right now
- **Historical Comparison**: "Better/worse than yesterday/last week"

### Technical Design

#### Database Tables

```sql
-- Table: dbo.ServerHealthScore
CREATE TABLE dbo.ServerHealthScore (
    HealthScoreID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL FOREIGN KEY REFERENCES dbo.Servers(ServerID),
    CalculationTime DATETIME2 NOT NULL,

    -- Overall score (0-100)
    OverallHealthScore DECIMAL(5,2) NOT NULL,

    -- Component scores (0-100 each)
    CPUHealthScore DECIMAL(5,2) NOT NULL,
    MemoryHealthScore DECIMAL(5,2) NOT NULL,
    DiskIOHealthScore DECIMAL(5,2) NOT NULL,
    WaitStatsHealthScore DECIMAL(5,2) NOT NULL,
    BlockingHealthScore DECIMAL(5,2) NOT NULL,
    IndexHealthScore DECIMAL(5,2) NOT NULL,
    QueryPerformanceHealthScore DECIMAL(5,2) NOT NULL,

    -- Issue counts
    CriticalIssueCount INT NOT NULL DEFAULT 0,
    WarningIssueCount INT NOT NULL DEFAULT 0,

    -- Top issue description
    TopIssueDescription NVARCHAR(500) NULL,
    TopIssueSeverity VARCHAR(20) NULL,

    INDEX IX_ServerHealthScore_ServerID_CalculationTime (ServerID, CalculationTime)
);

-- Table: dbo.HealthScoreIssues
CREATE TABLE dbo.HealthScoreIssues (
    IssueID BIGINT IDENTITY(1,1) PRIMARY KEY,
    HealthScoreID BIGINT NOT NULL FOREIGN KEY REFERENCES dbo.ServerHealthScore(HealthScoreID),

    IssueCategory VARCHAR(50) NOT NULL, -- 'CPU', 'Memory', 'DiskIO', etc.
    IssueSeverity VARCHAR(20) NOT NULL, -- 'Critical', 'Warning', 'Info'
    IssueDescription NVARCHAR(500) NOT NULL,
    ImpactOnScore DECIMAL(5,2) NOT NULL, -- How much this issue reduces the score

    RecommendedAction NVARCHAR(1000) NULL,

    INDEX IX_HealthScoreIssues_HealthScoreID (HealthScoreID)
);
```

#### Stored Procedure: usp_CalculateHealthScore

```sql
CREATE PROCEDURE dbo.usp_CalculateHealthScore
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OverallScore DECIMAL(5,2) = 100;
    DECLARE @CPUScore DECIMAL(5,2) = 100;
    DECLARE @MemoryScore DECIMAL(5,2) = 100;
    DECLARE @DiskIOScore DECIMAL(5,2) = 100;
    DECLARE @WaitStatsScore DECIMAL(5,2) = 100;
    DECLARE @BlockingScore DECIMAL(5,2) = 100;
    DECLARE @IndexScore DECIMAL(5,2) = 100;
    DECLARE @QueryScore DECIMAL(5,2) = 100;

    DECLARE @CriticalCount INT = 0;
    DECLARE @WarningCount INT = 0;
    DECLARE @TopIssue NVARCHAR(500);
    DECLARE @TopSeverity VARCHAR(20);

    DECLARE @HealthScoreID BIGINT;

    -- 1. CPU Health Score (based on last hour avg CPU)
    -- Score = 100 - (AvgCPU)
    -- If CPU > 80%, score is 20 or less (critical)
    -- If CPU > 60%, score is 40 or less (warning)
    SELECT @CPUScore = CASE
        WHEN AVG(CPUPercent) > 90 THEN 10
        WHEN AVG(CPUPercent) > 80 THEN 20
        WHEN AVG(CPUPercent) > 70 THEN 30
        WHEN AVG(CPUPercent) > 60 THEN 40
        ELSE 100 - AVG(CPUPercent)
    END
    FROM dbo.PerformanceMetrics
    WHERE ServerID = @ServerID
      AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
      AND MetricName = 'CPUPercent';

    SET @CPUScore = ISNULL(@CPUScore, 100);

    -- 2. Memory Health Score (based on PLE - Page Life Expectancy)
    -- PLE > 300 = 100, PLE < 100 = critical (20), PLE < 200 = warning (50)
    SELECT @MemoryScore = CASE
        WHEN AVG(MetricValue) < 100 THEN 20
        WHEN AVG(MetricValue) < 200 THEN 50
        WHEN AVG(MetricValue) < 300 THEN 70
        ELSE 100
    END
    FROM dbo.PerformanceMetrics
    WHERE ServerID = @ServerID
      AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
      AND MetricName = 'PageLifeExpectancy';

    SET @MemoryScore = ISNULL(@MemoryScore, 100);

    -- 3. Disk I/O Health Score (based on avg read/write latency)
    -- Latency < 10ms = 100, 10-20ms = 80, 20-50ms = 50, >50ms = 20
    SELECT @DiskIOScore = CASE
        WHEN AVG(MetricValue) > 100 THEN 10
        WHEN AVG(MetricValue) > 50 THEN 20
        WHEN AVG(MetricValue) > 20 THEN 50
        WHEN AVG(MetricValue) > 10 THEN 80
        ELSE 100
    END
    FROM dbo.PerformanceMetrics
    WHERE ServerID = @ServerID
      AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
      AND MetricName IN ('AvgDiskReadLatencyMs', 'AvgDiskWriteLatencyMs');

    SET @DiskIOScore = ISNULL(@DiskIOScore, 100);

    -- 4. Wait Stats Health Score (based on percentage of bad waits)
    -- < 10% bad waits = 100, 10-30% = 70, 30-50% = 40, >50% = 20
    WITH WaitCategories AS (
        SELECT
            CASE
                WHEN WaitType IN ('PAGEIOLATCH_SH', 'PAGEIOLATCH_EX', 'WRITELOG', 'IO_COMPLETION',
                                  'ASYNC_IO_COMPLETION', 'BACKUPIO') THEN 'IO'
                WHEN WaitType IN ('LCK_M_S', 'LCK_M_X', 'LCK_M_U', 'LCK_M_IX') THEN 'Locking'
                WHEN WaitType IN ('CXPACKET', 'CXCONSUMER') THEN 'Parallelism'
                WHEN WaitType LIKE 'PREEMPTIVE%' THEN 'Preemptive'
                ELSE 'Other'
            END AS WaitCategory,
            SUM(WaitTimeMs) AS TotalWaitMs
        FROM dbo.WaitStatsSnapshot
        WHERE ServerID = @ServerID
          AND SnapshotTime >= DATEADD(HOUR, -1, GETUTCDATE())
        GROUP BY CASE
            WHEN WaitType IN ('PAGEIOLATCH_SH', 'PAGEIOLATCH_EX', 'WRITELOG', 'IO_COMPLETION',
                              'ASYNC_IO_COMPLETION', 'BACKUPIO') THEN 'IO'
            WHEN WaitType IN ('LCK_M_S', 'LCK_M_X', 'LCK_M_U', 'LCK_M_IX') THEN 'Locking'
            WHEN WaitType IN ('CXPACKET', 'CXCONSUMER') THEN 'Parallelism'
            WHEN WaitType LIKE 'PREEMPTIVE%' THEN 'Preemptive'
            ELSE 'Other'
        END
    )
    SELECT @WaitStatsScore = CASE
        WHEN (SUM(CASE WHEN WaitCategory IN ('IO', 'Locking', 'Parallelism') THEN TotalWaitMs ELSE 0 END) * 100.0 / NULLIF(SUM(TotalWaitMs), 0)) > 50 THEN 20
        WHEN (SUM(CASE WHEN WaitCategory IN ('IO', 'Locking', 'Parallelism') THEN TotalWaitMs ELSE 0 END) * 100.0 / NULLIF(SUM(TotalWaitMs), 0)) > 30 THEN 40
        WHEN (SUM(CASE WHEN WaitCategory IN ('IO', 'Locking', 'Parallelism') THEN TotalWaitMs ELSE 0 END) * 100.0 / NULLIF(SUM(TotalWaitMs), 0)) > 10 THEN 70
        ELSE 100
    END
    FROM WaitCategories;

    SET @WaitStatsScore = ISNULL(@WaitStatsScore, 100);

    -- 5. Blocking Health Score (based on blocking events in last hour)
    -- 0 events = 100, 1-5 = 80, 5-20 = 50, >20 = 20
    SELECT @BlockingScore = CASE
        WHEN COUNT(*) > 50 THEN 10
        WHEN COUNT(*) > 20 THEN 20
        WHEN COUNT(*) > 5 THEN 50
        WHEN COUNT(*) > 0 THEN 80
        ELSE 100
    END
    FROM dbo.BlockingEvents
    WHERE ServerID = @ServerID
      AND EventTime >= DATEADD(HOUR, -1, GETUTCDATE());

    SET @BlockingScore = ISNULL(@BlockingScore, 100);

    -- 6. Index Health Score (based on fragmentation)
    -- < 10% avg fragmentation = 100, 10-30% = 70, 30-50% = 40, >50% = 20
    SELECT @IndexScore = CASE
        WHEN AVG(AvgFragmentationPercent) > 50 THEN 20
        WHEN AVG(AvgFragmentationPercent) > 30 THEN 40
        WHEN AVG(AvgFragmentationPercent) > 10 THEN 70
        ELSE 100
    END
    FROM dbo.IndexFragmentation
    WHERE ServerID = @ServerID
      AND CollectionTime >= DATEADD(DAY, -1, GETUTCDATE())
      AND PageCount > 1000; -- Only consider indexes with >1000 pages

    SET @IndexScore = ISNULL(@IndexScore, 100);

    -- 7. Query Performance Health Score (based on Query Store data)
    -- Average query duration < 100ms = 100, 100-500ms = 80, 500-1000ms = 50, >1000ms = 20
    SELECT @QueryScore = CASE
        WHEN AVG(AvgDurationMs) > 1000 THEN 20
        WHEN AVG(AvgDurationMs) > 500 THEN 50
        WHEN AVG(AvgDurationMs) > 100 THEN 80
        ELSE 100
    END
    FROM dbo.QueryStoreStats
    WHERE ServerID = @ServerID
      AND LastExecutionTime >= DATEADD(HOUR, -1, GETUTCDATE());

    SET @QueryScore = ISNULL(@QueryScore, 100);

    -- Calculate overall weighted score
    -- Weights: CPU(20%), Memory(20%), DiskIO(15%), WaitStats(15%), Blocking(10%), Index(10%), Query(10%)
    SET @OverallScore = (
        (@CPUScore * 0.20) +
        (@MemoryScore * 0.20) +
        (@DiskIOScore * 0.15) +
        (@WaitStatsScore * 0.15) +
        (@BlockingScore * 0.10) +
        (@IndexScore * 0.10) +
        (@QueryScore * 0.10)
    );

    -- Determine critical/warning counts and top issue
    SET @CriticalCount = (
        (CASE WHEN @CPUScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @MemoryScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @DiskIOScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @WaitStatsScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @BlockingScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @IndexScore < 30 THEN 1 ELSE 0 END) +
        (CASE WHEN @QueryScore < 30 THEN 1 ELSE 0 END)
    );

    SET @WarningCount = (
        (CASE WHEN @CPUScore >= 30 AND @CPUScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @MemoryScore >= 30 AND @MemoryScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @DiskIOScore >= 30 AND @DiskIOScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @WaitStatsScore >= 30 AND @WaitStatsScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @BlockingScore >= 30 AND @BlockingScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @IndexScore >= 30 AND @IndexScore < 60 THEN 1 ELSE 0 END) +
        (CASE WHEN @QueryScore >= 30 AND @QueryScore < 60 THEN 1 ELSE 0 END)
    );

    -- Find the component with the lowest score (top issue)
    SELECT TOP 1
        @TopIssue = Description,
        @TopSeverity = Severity
    FROM (
        SELECT @CPUScore AS Score, 'High CPU usage detected' AS Description,
               CASE WHEN @CPUScore < 30 THEN 'Critical' WHEN @CPUScore < 60 THEN 'Warning' ELSE 'Info' END AS Severity
        UNION ALL
        SELECT @MemoryScore, 'Low page life expectancy',
               CASE WHEN @MemoryScore < 30 THEN 'Critical' WHEN @MemoryScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @DiskIOScore, 'High disk I/O latency',
               CASE WHEN @DiskIOScore < 30 THEN 'Critical' WHEN @DiskIOScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @WaitStatsScore, 'Excessive wait statistics',
               CASE WHEN @WaitStatsScore < 30 THEN 'Critical' WHEN @WaitStatsScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @BlockingScore, 'Blocking events detected',
               CASE WHEN @BlockingScore < 30 THEN 'Critical' WHEN @BlockingScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @IndexScore, 'High index fragmentation',
               CASE WHEN @IndexScore < 30 THEN 'Critical' WHEN @IndexScore < 60 THEN 'Warning' ELSE 'Info' END
        UNION ALL
        SELECT @QueryScore, 'Slow query performance',
               CASE WHEN @QueryScore < 30 THEN 'Critical' WHEN @QueryScore < 60 THEN 'Warning' ELSE 'Info' END
    ) AS Issues
    WHERE Score < 100
    ORDER BY Score ASC;

    -- Insert health score record
    INSERT INTO dbo.ServerHealthScore (
        ServerID, CalculationTime,
        OverallHealthScore,
        CPUHealthScore, MemoryHealthScore, DiskIOHealthScore,
        WaitStatsHealthScore, BlockingHealthScore, IndexHealthScore, QueryPerformanceHealthScore,
        CriticalIssueCount, WarningIssueCount,
        TopIssueDescription, TopIssueSeverity
    )
    VALUES (
        @ServerID, GETUTCDATE(),
        @OverallScore,
        @CPUScore, @MemoryScore, @DiskIOScore,
        @WaitStatsScore, @BlockingScore, @IndexScore, @QueryScore,
        @CriticalCount, @WarningCount,
        @TopIssue, @TopSeverity
    );

    SET @HealthScoreID = SCOPE_IDENTITY();

    -- Insert detailed issues
    INSERT INTO dbo.HealthScoreIssues (HealthScoreID, IssueCategory, IssueSeverity, IssueDescription, ImpactOnScore, RecommendedAction)
    SELECT @HealthScoreID, Category, Severity, Description, Impact, Recommendation
    FROM (
        SELECT 'CPU' AS Category,
               CASE WHEN @CPUScore < 30 THEN 'Critical' WHEN @CPUScore < 60 THEN 'Warning' ELSE 'Info' END AS Severity,
               'High CPU usage: ' + CAST((100 - @CPUScore) AS VARCHAR) + '%' AS Description,
               (100 - @CPUScore) * 0.20 AS Impact,
               'Review top CPU-consuming queries and consider query optimization or hardware upgrades' AS Recommendation
        WHERE @CPUScore < 100

        UNION ALL

        SELECT 'Memory',
               CASE WHEN @MemoryScore < 30 THEN 'Critical' WHEN @MemoryScore < 60 THEN 'Warning' ELSE 'Info' END,
               'Low page life expectancy detected',
               (100 - @MemoryScore) * 0.20,
               'Consider adding more memory or reducing memory pressure by optimizing queries'
        WHERE @MemoryScore < 100

        UNION ALL

        SELECT 'DiskIO',
               CASE WHEN @DiskIOScore < 30 THEN 'Critical' WHEN @DiskIOScore < 60 THEN 'Warning' ELSE 'Info' END,
               'High disk I/O latency detected',
               (100 - @DiskIOScore) * 0.15,
               'Check disk subsystem performance, consider faster storage or indexing improvements'
        WHERE @DiskIOScore < 100

        UNION ALL

        SELECT 'WaitStats',
               CASE WHEN @WaitStatsScore < 30 THEN 'Critical' WHEN @WaitStatsScore < 60 THEN 'Warning' ELSE 'Info' END,
               'Excessive wait statistics detected',
               (100 - @WaitStatsScore) * 0.15,
               'Review wait statistics to identify bottlenecks (I/O, locking, or parallelism issues)'
        WHERE @WaitStatsScore < 100

        UNION ALL

        SELECT 'Blocking',
               CASE WHEN @BlockingScore < 30 THEN 'Critical' WHEN @BlockingScore < 60 THEN 'Warning' ELSE 'Info' END,
               'Blocking events detected in last hour',
               (100 - @BlockingScore) * 0.10,
               'Review blocking events and optimize queries to reduce lock duration'
        WHERE @BlockingScore < 100

        UNION ALL

        SELECT 'Index',
               CASE WHEN @IndexScore < 30 THEN 'Critical' WHEN @IndexScore < 60 THEN 'Warning' ELSE 'Info' END,
               'High index fragmentation detected',
               (100 - @IndexScore) * 0.10,
               'Schedule index maintenance to rebuild or reorganize fragmented indexes'
        WHERE @IndexScore < 100

        UNION ALL

        SELECT 'Query',
               CASE WHEN @QueryScore < 30 THEN 'Critical' WHEN @QueryScore < 60 THEN 'Warning' ELSE 'Info' END,
               'Slow query performance detected',
               (100 - @QueryScore) * 0.10,
               'Review Query Store for slow queries and optimize execution plans'
        WHERE @QueryScore < 100
    ) AS DetailedIssues;

    -- Return the health score
    SELECT
        @OverallScore AS OverallHealthScore,
        @CPUScore AS CPUHealthScore,
        @MemoryScore AS MemoryHealthScore,
        @DiskIOScore AS DiskIOHealthScore,
        @WaitStatsScore AS WaitStatsHealthScore,
        @BlockingScore AS BlockingHealthScore,
        @IndexScore AS IndexHealthScore,
        @QueryScore AS QueryPerformanceHealthScore,
        @CriticalCount AS CriticalIssueCount,
        @WarningCount AS WarningIssueCount,
        @TopIssue AS TopIssueDescription,
        @TopSeverity AS TopIssueSeverity;
END;
GO
```

#### Stored Procedure: usp_GetHealthScoreHistory

```sql
CREATE PROCEDURE dbo.usp_GetHealthScoreHistory
    @ServerID INT,
    @StartTime DATETIME2 = NULL,
    @EndTime DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @StartTime IS NULL SET @StartTime = DATEADD(DAY, -7, GETUTCDATE());
    IF @EndTime IS NULL SET @EndTime = GETUTCDATE();

    SELECT
        hs.CalculationTime,
        hs.OverallHealthScore,
        hs.CPUHealthScore,
        hs.MemoryHealthScore,
        hs.DiskIOHealthScore,
        hs.WaitStatsHealthScore,
        hs.BlockingHealthScore,
        hs.IndexHealthScore,
        hs.QueryPerformanceHealthScore,
        hs.CriticalIssueCount,
        hs.WarningIssueCount,
        hs.TopIssueDescription,
        hs.TopIssueSeverity
    FROM dbo.ServerHealthScore hs
    WHERE hs.ServerID = @ServerID
      AND hs.CalculationTime >= @StartTime
      AND hs.CalculationTime <= @EndTime
    ORDER BY hs.CalculationTime DESC;
END;
GO
```

#### SQL Agent Job: Calculate Health Scores

```sql
-- Job to calculate health scores every 15 minutes
EXEC msdb.dbo.sp_add_job
    @job_name = 'Calculate Server Health Scores',
    @enabled = 1,
    @description = 'Calculates health scores for all monitored servers every 15 minutes';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = 'Calculate Server Health Scores',
    @step_name = 'Calculate Scores',
    @subsystem = 'TSQL',
    @database_name = 'MonitoringDB',
    @command = N'
        DECLARE @ServerID INT;
        DECLARE server_cursor CURSOR FOR
            SELECT ServerID FROM dbo.Servers WHERE IsActive = 1;

        OPEN server_cursor;
        FETCH NEXT FROM server_cursor INTO @ServerID;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC dbo.usp_CalculateHealthScore @ServerID = @ServerID;
            FETCH NEXT FROM server_cursor INTO @ServerID;
        END;

        CLOSE server_cursor;
        DEALLOCATE server_cursor;
    ';

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = 'Every 15 Minutes',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 15;

EXEC msdb.dbo.sp_attach_schedule
    @job_name = 'Calculate Server Health Scores',
    @schedule_name = 'Every 15 Minutes';

EXEC msdb.dbo.sp_add_jobserver
    @job_name = 'Calculate Server Health Scores',
    @server_name = N'(local)';
```

### Grafana Dashboard

**Dashboard Name**: `08-server-health-score.json`

**Panels**:
1. **Main Health Score Gauge** - Large gauge showing 0-100 with color bands (red/yellow/green)
2. **Component Scores** - 7 mini-gauges for each component
3. **Health Trend** - Line graph showing health score over time
4. **Top Issues Table** - Table showing current issues with severity and recommendations
5. **Comparison Panel** - Compare health score to yesterday/last week

### Implementation Tasks (16 hours)

| Task | Duration | Description |
|------|----------|-------------|
| 1. Create database tables | 1h | ServerHealthScore, HealthScoreIssues tables |
| 2. Create usp_CalculateHealthScore | 4h | Complex scoring logic with all 7 components |
| 3. Create usp_GetHealthScoreHistory | 1h | Retrieve historical scores |
| 4. Create SQL Agent job | 1h | Schedule health score calculation every 15 minutes |
| 5. Test scoring algorithm | 2h | Verify scores make sense with real data |
| 6. Create Grafana dashboard | 4h | Build beautiful health score dashboard |
| 7. Documentation | 2h | User guide for interpreting health scores |
| 8. Unit tests | 1h | Test edge cases and scoring logic |

**Total**: 16 hours

---

## Feature #2: Query Performance Advisor (32 hours)

### Objective

Provide AI-powered query optimization recommendations based on actual execution patterns, resource consumption, and execution plans.

### What Users Get

- **Slow Query Identification** - Automatically identify the worst-performing queries
- **Optimization Recommendations** - Specific suggestions for each slow query
- **Missing Index Suggestions** - Tied to actual query execution
- **Plan Regression Detection** - Alert when execution plans change and performance degrades
- **Before/After Comparisons** - Show expected improvement from implementing recommendations

### Technical Design

#### Database Tables

```sql
-- Table: dbo.QueryPerformanceRecommendations
CREATE TABLE dbo.QueryPerformanceRecommendations (
    RecommendationID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL FOREIGN KEY REFERENCES dbo.Servers(ServerID),
    DatabaseName NVARCHAR(128) NOT NULL,

    -- Query identification
    QueryHash BINARY(8) NOT NULL,
    QueryText NVARCHAR(MAX) NOT NULL,

    -- Performance metrics
    AvgDurationMs DECIMAL(18,2) NOT NULL,
    AvgCPUTimeMs DECIMAL(18,2) NOT NULL,
    AvgLogicalReads BIGINT NOT NULL,
    TotalExecutionCount BIGINT NOT NULL,

    -- Recommendation
    RecommendationType VARCHAR(50) NOT NULL, -- 'MissingIndex', 'StatisticsUpdate', 'PlanRegression', 'Rewrite', 'Parameterization'
    RecommendationSeverity VARCHAR(20) NOT NULL, -- 'Critical', 'High', 'Medium', 'Low'
    RecommendationText NVARCHAR(MAX) NOT NULL,
    EstimatedImprovementPercent DECIMAL(5,2) NULL,

    -- Implementation
    ImplementationScript NVARCHAR(MAX) NULL, -- SQL to implement the recommendation
    IsImplemented BIT NOT NULL DEFAULT 0,
    ImplementedDate DATETIME2 NULL,

    DetectionTime DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    INDEX IX_QueryPerformanceRecommendations_ServerID_Severity (ServerID, RecommendationSeverity, DetectionTime)
);

-- Table: dbo.QueryPlanRegressions
CREATE TABLE dbo.QueryPlanRegressions (
    RegressionID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL FOREIGN KEY REFERENCES dbo.Servers(ServerID),
    DatabaseName NVARCHAR(128) NOT NULL,

    QueryHash BINARY(8) NOT NULL,
    QueryText NVARCHAR(MAX) NOT NULL,

    -- Old plan (good performance)
    OldPlanHandle VARBINARY(64) NULL,
    OldAvgDurationMs DECIMAL(18,2) NOT NULL,
    OldAvgCPUTimeMs DECIMAL(18,2) NOT NULL,
    OldPlanCreatedTime DATETIME2 NULL,

    -- New plan (degraded performance)
    NewPlanHandle VARBINARY(64) NULL,
    NewAvgDurationMs DECIMAL(18,2) NOT NULL,
    NewAvgCPUTimeMs DECIMAL(18,2) NOT NULL,
    NewPlanCreatedTime DATETIME2 NULL,

    -- Regression metrics
    DurationIncreasePct DECIMAL(5,2) NOT NULL,
    CPUIncreasePct DECIMAL(5,2) NOT NULL,

    DetectionTime DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    IsResolved BIT NOT NULL DEFAULT 0,

    INDEX IX_QueryPlanRegressions_ServerID_DetectionTime (ServerID, DetectionTime)
);
```

#### Stored Procedure: usp_AnalyzeQueryPerformance

```sql
CREATE PROCEDURE dbo.usp_AnalyzeQueryPerformance
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Find top 50 slowest queries from Query Store
    -- Analyze each for optimization opportunities

    -- 1. Queries with missing indexes
    INSERT INTO dbo.QueryPerformanceRecommendations (
        ServerID, DatabaseName, QueryHash, QueryText,
        AvgDurationMs, AvgCPUTimeMs, AvgLogicalReads, TotalExecutionCount,
        RecommendationType, RecommendationSeverity, RecommendationText,
        EstimatedImprovementPercent, ImplementationScript
    )
    SELECT
        qs.ServerID,
        qs.DatabaseName,
        qs.QueryHash,
        qs.QueryText,
        qs.AvgDurationMs,
        qs.AvgCPUTimeMs,
        qs.AvgLogicalReads,
        qs.TotalExecutionCount,
        'MissingIndex' AS RecommendationType,
        CASE
            WHEN mi.AvgUserImpactPercent > 90 THEN 'Critical'
            WHEN mi.AvgUserImpactPercent > 70 THEN 'High'
            WHEN mi.AvgUserImpactPercent > 50 THEN 'Medium'
            ELSE 'Low'
        END AS RecommendationSeverity,
        'Create missing index on ' + mi.DatabaseName + '.' + mi.SchemaName + '.' + mi.TableName +
        ' (' + mi.EqualityColumns + ') INCLUDE (' + mi.IncludeColumns + ') - Expected improvement: ' +
        CAST(mi.AvgUserImpactPercent AS VARCHAR) + '%' AS RecommendationText,
        mi.AvgUserImpactPercent AS EstimatedImprovementPercent,
        'CREATE NONCLUSTERED INDEX IX_' + mi.TableName + '_' + REPLACE(mi.EqualityColumns, ',', '_') +
        ' ON ' + mi.DatabaseName + '.' + mi.SchemaName + '.' + mi.TableName +
        ' (' + mi.EqualityColumns + ') INCLUDE (' + mi.IncludeColumns + ');' AS ImplementationScript
    FROM dbo.QueryStoreStats qs
    INNER JOIN dbo.MissingIndexRecommendations mi
        ON qs.ServerID = mi.ServerID
        AND qs.DatabaseName = mi.DatabaseName
    WHERE qs.ServerID = @ServerID
      AND qs.AvgDurationMs > 100 -- Only queries slower than 100ms
      AND qs.TotalExecutionCount > 10 -- Only queries executed more than 10 times
      AND mi.AvgUserImpactPercent > 50
      AND NOT EXISTS (
          SELECT 1 FROM dbo.QueryPerformanceRecommendations qpr
          WHERE qpr.ServerID = qs.ServerID
            AND qpr.QueryHash = qs.QueryHash
            AND qpr.RecommendationType = 'MissingIndex'
            AND qpr.DetectionTime >= DATEADD(DAY, -7, GETUTCDATE())
      );

    -- 2. Queries with high logical reads (potential missing indexes or poor query design)
    INSERT INTO dbo.QueryPerformanceRecommendations (
        ServerID, DatabaseName, QueryHash, QueryText,
        AvgDurationMs, AvgCPUTimeMs, AvgLogicalReads, TotalExecutionCount,
        RecommendationType, RecommendationSeverity, RecommendationText,
        EstimatedImprovementPercent, ImplementationScript
    )
    SELECT TOP 10
        qs.ServerID,
        qs.DatabaseName,
        qs.QueryHash,
        qs.QueryText,
        qs.AvgDurationMs,
        qs.AvgCPUTimeMs,
        qs.AvgLogicalReads,
        qs.TotalExecutionCount,
        'HighLogicalReads' AS RecommendationType,
        CASE
            WHEN qs.AvgLogicalReads > 100000 THEN 'Critical'
            WHEN qs.AvgLogicalReads > 50000 THEN 'High'
            ELSE 'Medium'
        END AS RecommendationSeverity,
        'Query has excessive logical reads (' + CAST(qs.AvgLogicalReads AS VARCHAR) + ' per execution). ' +
        'Review execution plan for table scans and missing indexes.' AS RecommendationText,
        NULL AS EstimatedImprovementPercent,
        '-- Review execution plan for: ' + CHAR(13) + CHAR(10) + qs.QueryText AS ImplementationScript
    FROM dbo.QueryStoreStats qs
    WHERE qs.ServerID = @ServerID
      AND qs.AvgLogicalReads > 10000
      AND NOT EXISTS (
          SELECT 1 FROM dbo.QueryPerformanceRecommendations qpr
          WHERE qpr.ServerID = qs.ServerID
            AND qpr.QueryHash = qs.QueryHash
            AND qpr.RecommendationType = 'HighLogicalReads'
            AND qpr.DetectionTime >= DATEADD(DAY, -7, GETUTCDATE())
      )
    ORDER BY qs.AvgLogicalReads DESC;

    -- 3. Detect plan regressions
    WITH CurrentPlans AS (
        SELECT
            ServerID,
            DatabaseName,
            QueryHash,
            QueryText,
            PlanHandle,
            AvgDurationMs,
            AvgCPUTimeMs,
            LastExecutionTime,
            ROW_NUMBER() OVER (PARTITION BY ServerID, QueryHash ORDER BY LastExecutionTime DESC) AS rn
        FROM dbo.QueryStoreStats
        WHERE ServerID = @ServerID
    ),
    PreviousPlans AS (
        SELECT
            ServerID,
            DatabaseName,
            QueryHash,
            PlanHandle,
            AvgDurationMs,
            AvgCPUTimeMs,
            LastExecutionTime,
            ROW_NUMBER() OVER (PARTITION BY ServerID, QueryHash ORDER BY LastExecutionTime DESC) AS rn
        FROM dbo.QueryStoreStats
        WHERE ServerID = @ServerID
          AND LastExecutionTime < DATEADD(DAY, -1, GETUTCDATE())
    )
    INSERT INTO dbo.QueryPlanRegressions (
        ServerID, DatabaseName, QueryHash, QueryText,
        OldPlanHandle, OldAvgDurationMs, OldAvgCPUTimeMs, OldPlanCreatedTime,
        NewPlanHandle, NewAvgDurationMs, NewAvgCPUTimeMs, NewPlanCreatedTime,
        DurationIncreasePct, CPUIncreasePct
    )
    SELECT
        c.ServerID,
        c.DatabaseName,
        c.QueryHash,
        c.QueryText,
        p.PlanHandle AS OldPlanHandle,
        p.AvgDurationMs AS OldAvgDurationMs,
        p.AvgCPUTimeMs AS OldAvgCPUTimeMs,
        p.LastExecutionTime AS OldPlanCreatedTime,
        c.PlanHandle AS NewPlanHandle,
        c.AvgDurationMs AS NewAvgDurationMs,
        c.AvgCPUTimeMs AS NewAvgCPUTimeMs,
        c.LastExecutionTime AS NewPlanCreatedTime,
        ((c.AvgDurationMs - p.AvgDurationMs) * 100.0 / NULLIF(p.AvgDurationMs, 0)) AS DurationIncreasePct,
        ((c.AvgCPUTimeMs - p.AvgCPUTimeMs) * 100.0 / NULLIF(p.AvgCPUTimeMs, 0)) AS CPUIncreasePct
    FROM CurrentPlans c
    INNER JOIN PreviousPlans p
        ON c.ServerID = p.ServerID
        AND c.QueryHash = p.QueryHash
        AND p.rn = 1
    WHERE c.rn = 1
      AND c.PlanHandle <> p.PlanHandle
      AND c.AvgDurationMs > p.AvgDurationMs * 1.5 -- 50% slower
      AND NOT EXISTS (
          SELECT 1 FROM dbo.QueryPlanRegressions qpr
          WHERE qpr.ServerID = c.ServerID
            AND qpr.QueryHash = c.QueryHash
            AND qpr.IsResolved = 0
      );

    -- Return summary
    SELECT
        COUNT(*) AS TotalRecommendations,
        SUM(CASE WHEN RecommendationSeverity = 'Critical' THEN 1 ELSE 0 END) AS CriticalCount,
        SUM(CASE WHEN RecommendationSeverity = 'High' THEN 1 ELSE 0 END) AS HighCount,
        SUM(CASE WHEN RecommendationSeverity = 'Medium' THEN 1 ELSE 0 END) AS MediumCount,
        SUM(CASE WHEN RecommendationSeverity = 'Low' THEN 1 ELSE 0 END) AS LowCount
    FROM dbo.QueryPerformanceRecommendations
    WHERE ServerID = @ServerID
      AND IsImplemented = 0
      AND DetectionTime >= DATEADD(DAY, -7, GETUTCDATE());
END;
GO
```

### Implementation Tasks (32 hours)

| Task | Duration | Description |
|------|----------|-------------|
| 1. Create database tables | 2h | QueryPerformanceRecommendations, QueryPlanRegressions |
| 2. Create usp_AnalyzeQueryPerformance | 8h | Complex analysis logic for multiple recommendation types |
| 3. Create usp_GetRecommendations | 2h | Retrieve recommendations with filtering |
| 4. Create usp_ImplementRecommendation | 3h | Track implementation and measure results |
| 5. Create SQL Agent job | 1h | Schedule analysis every hour |
| 6. Test recommendation engine | 4h | Verify recommendations are accurate |
| 7. Create Grafana dashboard | 8h | Build query performance advisor dashboard |
| 8. Documentation | 3h | User guide for query optimization |
| 9. Unit tests | 1h | Test recommendation generation |

**Total**: 32 hours

---

## Feature #3: Backup Verification Dashboard (16 hours)

*... (continuing with Features 3-7) ...*

---

## Implementation Strategy

### Phase 3.1: Foundation (Week 1)
- Feature #1: SQL Server Health Score (16h)
- Feature #6: Security Vulnerability Scanner (24h)

### Phase 3.2: Query Optimization (Week 2)
- Feature #2: Query Performance Advisor (32h)
- Feature #4: Automated Index Maintenance (8h of 24h)

### Phase 3.3: Capacity & Backup (Week 3)
- Feature #3: Backup Verification Dashboard (16h)
- Feature #4: Automated Index Maintenance (16h remaining)

### Phase 3.4: Advanced Features (Week 4)
- Feature #5: Capacity Planning (24h)
- Feature #7: Cost Optimization Engine (24h)

---

## Success Metrics

For each feature, we'll track:

1. **Adoption**: % of users using the feature
2. **Value**: Issues identified and resolved
3. **Performance**: Feature execution time and resource usage
4. **Accuracy**: False positive rate for recommendations

---

## Next Steps

1. ✅ Create this comprehensive plan
2. 🔄 Start with Feature #1: SQL Server Health Score (16h)
3. ⏳ Create database tables for health scoring
4. ⏳ Implement usp_CalculateHealthScore procedure
5. ⏳ Build Grafana dashboard

**Let's begin with Feature #1!**
