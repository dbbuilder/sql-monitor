# SQL Server Monitor - Development Roadmap

**Last Updated**: October 27, 2025
**Project Status**: Phase 1.9 (Integration Phase) - Planning
**Methodology**: Test-Driven Development (TDD) - Red-Green-Refactor

---

## 🎯 Project Vision

Build a **self-hosted, enterprise-grade SQL Server monitoring solution** that:
- ✅ Eliminates cloud dependencies (runs entirely on-prem or any cloud)
- ✅ Provides **complete compliance** coverage (SOC 2, GDPR, PCI-DSS, HIPAA, FERPA)
- ✅ Delivers **killer features** that exceed commercial competitors
- ✅ Leverages **AI** for intelligent optimization and recommendations
- ✅ Costs **$0-$1,500/year** vs. **$27k-$37k for competitors**

---

## 📊 Overall Progress

| Phase | Status | Hours | Priority | Dependencies |
|-------|--------|-------|----------|--------------|
| **Phase 1: Database Foundation** | ✅ Complete | 40h | Critical | None |
| **Phase 1.25: Schema Browser** | ✅ Complete | 40h (4h actual) | High | Phase 1 |
| **Phase 1.9: sql-monitor-agent Integration** | 🔄 **IN PROGRESS** | 60h | **CRITICAL** | Phase 1, 1.25 |
| **Phase 2: SOC 2 Compliance** | 📋 Planned | 80h | High | Phase 1.9 |
| **Phase 2.5: GDPR Compliance** | 📋 Planned | 60h | High | Phase 2 |
| **Phase 2.6: PCI-DSS Compliance** | 📋 Planned | 48h | Medium | Phase 2, 2.5 |
| **Phase 2.7: HIPAA Compliance** | 📋 Planned | 40h | Medium | Phase 2, 2.5, 2.6 |
| **Phase 2.8: FERPA Compliance** | 📋 Planned | 24h | Low | Phase 2, 2.5, 2.6, 2.7 |
| **Phase 3: Killer Features** | 📋 Planned | 160h | High | Phase 1.9, 2 |
| **Phase 4: Code Editor & Rules Engine** | 📋 Planned | 120h | Medium | Phase 1.9, 2, 3 |
| **Phase 5: AI Layer** | 📋 Planned | 200h | Medium | Phase 1-4 |
| **TOTAL** | 🔄 In Progress | **872h** | — | — |

**Current Phase**: Phase 1.9 (sql-monitor-agent Integration) - **MUST COMPLETE BEFORE PHASE 2**

---

## 🚨 **PHASE 1.9: sql-monitor-agent Integration (CRITICAL)**

### Rationale

**sql-monitor-agent** is a proven, production-deployed lightweight monitoring system with superior schema design and feedback capabilities. Instead of building from scratch, we need to:
1. **Leverage** the 20+ tables and comprehensive DMV collection from sql-monitor-agent
2. **Unify** the database naming (configurable DBATools/MonitoringDB)
3. **Bridge** the two schemas using views and stored procedures
4. **Adopt** the feedback/ranges system for intelligent analysis
5. **Evaluate** sql-http-bridge as a lightweight API alternative

### Schema Comparison

| Feature | sql-monitor-agent (DBATools) | sql-monitor (MonitoringDB) | Decision |
|---------|------------------------------|----------------------------|----------|
| **Core Tables** | 5 (Run, DB, Workload, ErrorLog, LogEntry) | 2 (Servers, PerformanceMetrics) | **Adopt sql-monitor-agent schema** |
| **Enhanced Tables** | 17+ (Query Stats, IO, Memory, Backups, Indexes, Waits, etc.) | None | **Migrate all to MonitoringDB** |
| **Feedback System** | ✅ FeedbackRule, FeedbackMetadata, ranges/insights | ❌ None | **Adopt feedback system** |
| **Priority Levels** | ✅ P0-P3 modular collectors | ❌ None | **Adopt priority system** |
| **Config System** | ✅ ConfigSetting, fn_GetConfigBit | ❌ None | **Adopt config system** |
| **Database Filter** | ✅ vw_MonitoredDatabases | ❌ None | **Adopt filter system** |
| **Collection Method** | ✅ SQL Agent + modular SPs | ❌ Planned | **Use sql-monitor-agent approach** |
| **Partitioning** | ❌ None | ✅ Monthly partitions + columnstore | **Keep MonitoringDB partitioning** |
| **Multi-Server** | ❌ Single-server focus | ✅ Servers table | **Extend sql-monitor-agent for multi-server** |

### Integration Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   UNIFIED DATABASE LAYER                         │
│  (Configurable: DBATools [default] or MonitoringDB)            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CORE SCHEMA (from sql-monitor-agent)                          │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ PerfSnapshotRun (server-level metrics)                    │ │
│  │ PerfSnapshotDB (database-level stats)                     │ │
│  │ PerfSnapshotWorkload (active sessions/requests)           │ │
│  │ PerfSnapshotErrorLog (SQL Server error log)               │ │
│  │ LogEntry (diagnostic logging)                             │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ENHANCED SCHEMA (from sql-monitor-agent)                      │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ P0: QueryStats, IOStats, Memory, BackupHistory (critical) │ │
│  │ P1: IndexUsage, MissingIndexes, WaitStats, TempDB, Plans │ │
│  │ P2: ServerConfig, VLF, Deadlocks, Schedulers, Counters   │ │
│  │ P3: LatchStats, JobHistory, SpinlockStats                │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  FEEDBACK SYSTEM (from sql-monitor-agent)                      │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ FeedbackRule (ranges, severity, recommendations)          │ │
│  │ FeedbackMetadata (result set descriptions)                │ │
│  │ fn_GetMetricFeedback (intelligent analysis)               │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  MULTI-SERVER EXTENSION (from sql-monitor)                     │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ Servers (inventory of monitored instances)                │ │
│  │ ServerConfigs (server-specific settings)                  │ │
│  │ LinkedServerMappings (cross-server collection)            │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  MAPPING LAYER (compatibility views)                           │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ vw_PerformanceMetrics → PerfSnapshot* tables              │ │
│  │ vw_ServerMetrics → aggregated PerfSnapshotRun             │ │
│  │ vw_DatabaseMetrics → PerfSnapshotDB                       │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation Plan (60 hours)

#### Week 1: Database Configuration & Core Migration (24 hours)

**Day 1-2: Configurable Database Name (8h)**
- [ ] Create configuration system for database selection
- [ ] Add `@TargetDatabase` parameter to all stored procedures
- [ ] Default: `DBATools` (backwards compatible with sql-monitor-agent)
- [ ] Option: `MonitoringDB` (new enterprise solution)
- [ ] Create `fn_GetTargetDatabase()` function
- [ ] Update all `USE [DBATools]` to dynamic SQL or synonyms

**Day 3-4: Schema Unification (8h)**
- [ ] Create MonitoringDB with DBATools-compatible schema
- [ ] Add `Servers` table to DBATools for multi-server support
- [ ] Extend `PerfSnapshotRun` with `ServerID` foreign key
- [ ] Create migration script: DBATools (single-server) → MonitoringDB (multi-server)
- [ ] Add partitioning to existing PerfSnapshot* tables (monthly by SnapshotUTC)
- [ ] Add columnstore indexes for fast aggregation

**Day 5: Mapping Views (8h)**
- [ ] Create `vw_PerformanceMetrics` (maps to PerfSnapshotRun + detail tables)
- [ ] Create `vw_ServerSummary` (server-level aggregates)
- [ ] Create `vw_DatabaseSummary` (database-level aggregates)
- [ ] Create `vw_WorkloadHistory` (active workload trends)
- [ ] Test compatibility with existing sql-monitor API expectations

#### Week 2: Enhanced Tables & Feedback System (24 hours)

**Day 1-2: Enhanced Table Migration (8h)**
- [ ] Create all 17 enhanced tables in MonitoringDB
- [ ] Add ServerID foreign keys to all PerfSnapshot* tables
- [ ] Create indexes optimized for multi-server queries
- [ ] Add partitioning for high-volume tables (QueryStats, WaitStats)
- [ ] Test modular collectors (P0-P3) against MonitoringDB

**Day 3: Feedback System Migration (8h)**
- [ ] Create FeedbackRule and FeedbackMetadata tables in MonitoringDB
- [ ] Create `fn_GetMetricFeedback()` function
- [ ] Seed 50+ feedback rules (from sql-monitor-agent)
- [ ] Create `DBA_GetDailyOverview` with intelligent feedback
- [ ] Test feedback system with real metrics

**Day 4: Configuration System (8h)**
- [ ] Create ConfigSetting table in MonitoringDB
- [ ] Create `fn_GetConfigBit()`, `fn_GetConfigValue()` functions
- [ ] Create `vw_MonitoredDatabases` (database filter system)
- [ ] Seed default configuration:
  - `EnableP0Collection = 1`
  - `EnableP1Collection = 1`
  - `EnableP2Collection = 0` (optional, performance-intensive)
  - `EnableP3Collection = 0` (optional, low priority)
  - `RetentionDays = 90`
  - `DatabaseFilter = ALL` (or comma-separated list)

#### Week 3: API Integration & Testing (12 hours)

**Day 1-2: Stored Procedure Updates (6h)**
- [ ] Update `DBA_CollectPerformanceSnapshot` to use configurable database
- [ ] Update all P0-P3 collectors to support ServerID parameter
- [ ] Create `usp_CollectMetrics_RemoteServer` (wraps DBA_CollectPerformanceSnapshot)
- [ ] Add server selection logic (if ServerID provided, filter by server)
- [ ] Create `usp_GetServerMetrics` (API endpoint, returns vw_PerformanceMetrics)
- [ ] Create `usp_GetDailyOverview` (API endpoint, returns feedback-enhanced report)

**Day 3: API Compatibility Layer (3h)**
- [ ] Create wrapper stored procedures for existing sql-monitor API
  - `usp_GetServers` → `SELECT * FROM Servers WHERE IsActive = 1`
  - `usp_GetMetricHistory` → `SELECT * FROM vw_PerformanceMetrics WHERE ...`
  - `usp_GetServerSummary` → `SELECT * FROM vw_ServerSummary WHERE ...`
- [ ] Test with existing ASP.NET Core API controllers
- [ ] Verify Grafana dashboards work with new views

**Day 4: Integration Testing (3h)**
- [ ] Test single-server mode (DBATools, no ServerID, backwards compatible)
- [ ] Test multi-server mode (MonitoringDB with Servers table)
- [ ] Test collection from multiple servers via linked servers
- [ ] Test feedback system with various metric ranges
- [ ] Performance test: collection overhead <3% CPU
- [ ] Performance test: dashboard queries <500ms

---

## 🔧 **sql-http-bridge Evaluation**

### Current State
- **Production-ready**: Python-based HTTP-to-sqlcmd bridge
- **Security-first**: Localhost-only (127.0.0.1:8080), SQL auth required per request
- **Least-privilege**: Execute-only permissions on allowlisted stored procedures
- **Audit logging**: All requests logged to `DBATools.dbo.Api_AccessLog`
- **Cross-platform**: Linux (systemd) and Windows (NSSM service)

### Comparison with ASP.NET Core API

| Feature | sql-http-bridge | ASP.NET Core API (current) | Recommendation |
|---------|-----------------|----------------------------|----------------|
| **Deployment** | Single Python file + systemd/NSSM | Docker container (API + dependencies) | **Bridge simpler for quick setups** |
| **Security** | SQL auth per request | JWT + MFA + session management | **API more enterprise-grade** |
| **Performance** | sqlcmd overhead per request | Connection pooling, async | **API faster at scale** |
| **Features** | Simple SP execution | Rich middleware, RBAC, audit | **API more feature-rich** |
| **Maintenance** | Minimal (Python + sqlcmd) | Complex (.NET, Docker, config) | **Bridge easier to maintain** |
| **Use Case** | Small deployments, air-gap, simplicity | Enterprise multi-server monitoring | **Both have value** |

### Recommendation: **Hybrid Approach**

1. **Keep sql-http-bridge for**:
   - Quick deployments (single server, no Docker)
   - Air-gap environments (no internet, minimal dependencies)
   - SQL-only shops (no .NET/Docker expertise)
   - Testing/development (fast iteration)

2. **Use ASP.NET Core API for**:
   - Enterprise multi-server deployments
   - Compliance requirements (SOC 2, GDPR, etc.)
   - Advanced features (MFA, RBAC, AI)
   - Grafana integration (needs consistent JSON API)

3. **Integration**:
   - [ ] Expose same stored procedures via both interfaces
   - [ ] Add sql-http-bridge to docker-compose as optional service
   - [ ] Document when to use each approach
   - [ ] Create `docker-compose.lightweight.yml` (sql-http-bridge only, no .NET)

---

## 📋 Phase 1.9 Deliverables

### Database Changes
- ✅ Configurable database name (DBATools default, MonitoringDB option)
- ✅ All sql-monitor-agent tables migrated to MonitoringDB
- ✅ Multi-server extensions (Servers table, ServerID foreign keys)
- ✅ Partitioning + columnstore on high-volume tables
- ✅ Feedback system (FeedbackRule, FeedbackMetadata, fn_GetMetricFeedback)
- ✅ Configuration system (ConfigSetting, fn_GetConfigBit, vw_MonitoredDatabases)

### Stored Procedures
- ✅ `DBA_CollectPerformanceSnapshot` (configurable database)
- ✅ All P0-P3 collectors (support ServerID)
- ✅ `usp_CollectMetrics_RemoteServer` (multi-server wrapper)
- ✅ `usp_GetServerMetrics` (API endpoint)
- ✅ `usp_GetDailyOverview` (feedback-enhanced report)
- ✅ API compatibility wrappers (usp_GetServers, usp_GetMetricHistory, etc.)

### Mapping Views
- ✅ `vw_PerformanceMetrics` (unified time-series view)
- ✅ `vw_ServerSummary` (server-level aggregates)
- ✅ `vw_DatabaseSummary` (database-level aggregates)
- ✅ `vw_WorkloadHistory` (active workload trends)

### Documentation
- ✅ Migration guide (DBATools → MonitoringDB)
- ✅ Configuration reference (all ConfigSetting options)
- ✅ Feedback system guide (how to add custom rules)
- ✅ API compatibility guide (sql-http-bridge vs ASP.NET Core)

### Testing
- ✅ Single-server mode (backwards compatible)
- ✅ Multi-server mode (enterprise deployment)
- ✅ Collection performance (<3% CPU overhead)
- ✅ Query performance (<500ms dashboard queries)
- ✅ Feedback system accuracy (50+ rules tested)

---

## 📁 Phase Documentation

All phase plans are documented in **[docs/phases/](docs/phases/)** with detailed implementation guides:

### ✅ Completed Phases

| Phase | Document | Status | Deliverables |
|-------|----------|--------|--------------|
| **1.0** | [PHASE-01-IMPLEMENTATION-COMPLETE.md](docs/phases/PHASE-01-IMPLEMENTATION-COMPLETE.md) | ✅ Done | Database schema, stored procedures, SQL Agent jobs |
| **1.25** | [PHASE-01.25-SCHEMA-BROWSER-PLAN.md](docs/phases/PHASE-01.25-SCHEMA-BROWSER-PLAN.md) | ✅ Done | Schema caching, metadata tables, Code Browser dashboard |
| | [PHASE-01.25-COMPLETE.md](docs/phases/PHASE-01.25-COMPLETE.md) | ✅ Done | Completion report (4 hours vs 40 planned) |

### 🔄 Current Phase

| Phase | Document | Status | Deliverables |
|-------|----------|--------|--------------|
| **1.9** | PHASE-01.9-INTEGRATION-PLAN.md (this file) | 🔄 **IN PROGRESS** | Unified schema, feedback system, multi-server support |

**Key Achievements (Planned)**:
- ✅ 20+ tables from sql-monitor-agent integrated
- ✅ Feedback system with 50+ intelligent rules
- ✅ Configurable database name (DBATools/MonitoringDB)
- ✅ Multi-server support via Servers table
- ✅ API compatibility layer (views + wrapper SPs)
- ✅ sql-http-bridge evaluation and integration path

---

### 📋 Planned Phases (After Phase 1.9)

#### Phase 2: Compliance Framework (252 hours total)

Complete enterprise compliance coverage across 5 major frameworks:

| Phase | Framework | Document | Hours | Market |
|-------|-----------|----------|-------|--------|
| **2.0** | **SOC 2** | [PHASE-02-SOC2-COMPLIANCE-PLAN.md](docs/phases/PHASE-02-SOC2-COMPLIANCE-PLAN.md) | 80h | All industries |
| **2.5** | **GDPR** | [PHASE-02.5-GDPR-COMPLIANCE-PLAN.md](docs/phases/PHASE-02.5-GDPR-COMPLIANCE-PLAN.md) | 60h | EU data processing |
| **2.6** | **PCI-DSS** | [PHASE-02.6-PCI-DSS-COMPLIANCE-PLAN.md](docs/phases/PHASE-02.6-PCI-DSS-COMPLIANCE-PLAN.md) | 48h | Payment processing |
| **2.7** | **HIPAA** | [PHASE-02.7-HIPAA-COMPLIANCE-PLAN.md](docs/phases/PHASE-02.7-HIPAA-COMPLIANCE-PLAN.md) | 40h | Healthcare |
| **2.8** | **FERPA** | [PHASE-02.8-FERPA-COMPLIANCE-PLAN.md](docs/phases/PHASE-02.8-FERPA-COMPLIANCE-PLAN.md) | 24h | Education |

---

#### Phase 3: Killer Features (160 hours)

**Document**: [PHASE-03-KILLER-FEATURES-PLAN.md](docs/phases/PHASE-03-KILLER-FEATURES-PLAN.md)

High-value features that provide competitive advantages:

| Feature | Impact | Hours | Competitive Edge |
|---------|--------|-------|------------------|
| **Automated Baseline + Anomaly Detection** | Very High | 48h | Match Redgate ML alerting |
| **SQL Server Health Score** | Very High | 40h | Unique in market |
| **Query Performance Impact Analysis** | Very High | 32h | Unique in market |
| **Multi-Server Query Search** | Medium | 24h | Unique for large estates |
| **Schema Change Tracking** | Medium-High | 16h | Free (vs Redgate paid) |

**Foundation**: Phase 1.9 feedback system provides baseline detection infrastructure

---

#### Phase 4: Code Editor & Rules Engine (120 hours)

**Document**: [PHASE-04-CODE-EDITOR-PLAN.md](docs/phases/PHASE-04-CODE-EDITOR-PLAN.md)

SQL code editor with intelligent rules engine:
- Monaco Editor integration (VS Code engine)
- 50+ rules across 8 categories
- IntelliSense (autocomplete from Phase 1.25 metadata)
- Query Store integration
- Foundation for Phase 5 AI

---

#### Phase 5: AI Layer (200 hours)

**Document**: [PHASE-05-AI-LAYER-PLAN.md](docs/phases/PHASE-05-AI-LAYER-PLAN.md)

AI-powered optimization using **Claude 3.7 Sonnet** (91% accuracy):
- 8 AI capability levels
- Text2SQL (natural language to SQL)
- Opt-in design (system/database/user levels)
- Cost: ~$5/month per developer

---

## 🎯 Updated Implementation Path

### Path 1: Integration-First (RECOMMENDED)

**Rationale**: Leverage proven sql-monitor-agent foundation before adding new features

1. **Phase 1.9** - Integration (60h) ← **START HERE**
2. Phase 2.0 - SOC 2 (80h)
3. Phase 3 - Killer Features (160h) ← Leverage feedback system from 1.9
4. Phase 4 - Code Editor (120h)
5. Phase 5 - AI Layer (200h)

**Total**: 620 hours (15.5 weeks)
**Market Impact**: Production-ready monitoring → Enterprise compliance → Market-leading features

---

## 📋 Implementation Principles

### 1. Test-Driven Development (TDD) - MANDATORY

- Write tests BEFORE implementation
- Red-Green-Refactor cycle
- Minimum 80% code coverage

### 2. Database-First Architecture

- All data access via stored procedures
- No dynamic SQL in application code

### 3. Material Design Aesthetic

- Minimalist color palette
- Roboto typography
- Grafana dashboards

### 4. Backwards Compatibility

- sql-monitor-agent must continue to work in single-server mode
- DBATools database remains default for existing deployments
- Migration to MonitoringDB is optional, not required

---

## 📊 Success Metrics

### Phase 1.9 Completion Criteria

- [ ] All sql-monitor-agent tables exist in MonitoringDB
- [ ] Feedback system operational with 50+ rules
- [ ] Single-server mode: collection works with DBATools (backwards compatible)
- [ ] Multi-server mode: collection works with MonitoringDB + Servers table
- [ ] API compatibility: existing controllers work with new views
- [ ] Grafana compatibility: existing dashboards work with new views
- [ ] Performance: collection <3% CPU, queries <500ms
- [ ] sql-http-bridge: evaluated, integration path documented

### Feature Parity vs Competitors (Updated)

| Phase | Feature Parity | Unique Features |
|-------|----------------|-----------------|
| Phase 1.9 (Current Target) | **92%** | **6** (feedback, ranges, P0-P3 collectors) |
| Phase 2 (Compliance) | 95% | 8 |
| Phase 3 (Killer Features) | 98% | 13 |
| Phase 4 (Code Editor) | 100% | 14 |
| Phase 5 (AI Layer) | 105% | 19 |

### Cost Comparison (5 Years, 10 Servers)

| Solution | Cost | Savings |
|----------|------|---------|
| **Our Solution** | **$1,500** | — |
| Redgate | $54,700 | **$53,200** |
| AWS RDS | $152,040 | **$150,540** |

---

## 🚀 Getting Started

### For Contributors

1. **Strategic Planning**: Review this file (TODO.md) for Phase 1.9 integration plan
2. **sql-monitor-agent**: Review `/sql-monitor-agent/` folder for existing schema
3. **Tactical Implementation**: Follow Week 1-3 plan above
4. **Follow TDD**: Write tests first, then implementation
5. **Review Guidelines**: See [CLAUDE.md](CLAUDE.md) for project-specific conventions

### For Users

**Current Capabilities** (Phase 1.25):
- Real-time performance monitoring
- Schema browser with caching
- SSMS integration
- Grafana dashboards

**Coming in Phase 1.9** (Integration):
- Unified monitoring with sql-monitor-agent's proven schema
- Intelligent feedback system with 50+ rules
- Multi-server support
- Configurable database (DBATools or MonitoringDB)

**Coming in Phase 2.0** (After Integration):
- SOC 2 compliance automation
- Comprehensive audit logging
- Role-based access control

---

## 📝 Phase 1.9 Migration Example

### Before (sql-monitor current state)

```sql
-- Simple, generic time-series
CREATE TABLE dbo.PerformanceMetrics (
    MetricID BIGINT IDENTITY(1,1),
    ServerID INT,
    CollectionTime DATETIME2,
    MetricCategory NVARCHAR(50),  -- "CPU", "Memory", etc.
    MetricName NVARCHAR(100),      -- "SignalWaitPct", "PageLifeExpectancy"
    MetricValue DECIMAL(18,4)
);

-- Query for CPU metrics
SELECT MetricValue
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'CPU' AND MetricName = 'SignalWaitPct';
```

### After (Phase 1.9 integrated)

```sql
-- Rich, structured schema from sql-monitor-agent
CREATE TABLE dbo.PerfSnapshotRun (
    PerfSnapshotRunID BIGINT IDENTITY(1,1),
    SnapshotUTC DATETIME2(3),
    ServerID INT,  -- NEW: multi-server support
    ServerName SYSNAME,
    SqlVersion NVARCHAR(200),
    CpuSignalWaitPct DECIMAL(9,4),  -- Typed column, not generic MetricValue
    TopWaitType NVARCHAR(120),
    TopWaitMsPerSec DECIMAL(18,4),
    SessionsCount INT,
    RequestsCount INT,
    BlockingSessionCount INT,
    DeadlockCountRecent INT,
    MemoryGrantWarningCount INT
);

-- Query with intelligent feedback
SELECT
    psr.CpuSignalWaitPct,
    f.Severity,
    f.FeedbackText,
    f.Recommendation
FROM dbo.PerfSnapshotRun psr
CROSS APPLY dbo.fn_GetMetricFeedback(
    'DBA_GetDailyOverview',
    1,  -- Result set #1
    'CpuSignalWaitPct',
    psr.CpuSignalWaitPct
) f
WHERE psr.ServerID = @ServerID
ORDER BY psr.SnapshotUTC DESC;

-- Example feedback:
-- CpuSignalWaitPct = 45.2%
-- Severity: WARNING
-- FeedbackText: "High CPU signal wait percentage indicates CPU pressure"
-- Recommendation: "Review query plans, consider adding indexes, check for parameter sniffing"
```

---

**Last Updated**: October 27, 2025
**Next Milestone**: Phase 1.9 - sql-monitor-agent Integration (60 hours)
**Project Status**: Phase 1.9 Planning Complete ✅ → Implementation Next
