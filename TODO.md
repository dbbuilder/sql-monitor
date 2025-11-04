# SQL Server Monitor - Development Roadmap

**Last Updated**: November 3, 2025
**Project Status**: Phase 3 Feature #7 (T-SQL Code Editor) - Week 1 Complete ✅
**Methodology**: Test-Driven Development (TDD) - Red-Green-Refactor

---

## 🔥 Phase 3 Feature #7: T-SQL Code Editor - IN PROGRESS

**Status**: Week 1 Complete - Week 2 Ready to Start
**Progress**: 20% (15 of 75 hours)
**Target Completion**: 2025-12-06 (60 hours remaining)

### ✅ Week 1 Complete (15 hours) - Nov 1-3, 2025

**Day 1: Plugin Scaffolding (3h)** ✅ COMPLETE
- Created Grafana app plugin structure
- Configured package.json, tsconfig.json, webpack.config.ts
- Set up 3 pages (Code Editor, Saved Scripts, Configuration)
- Added dependencies (Monaco, ag-Grid, React, TypeScript)

**Day 2: Backend API Integration (6h)** ✅ COMPLETE
- Created QueryExecutionModels.cs (338 lines) - Request/response DTOs
- Implemented CodeController endpoints (4 new endpoints):
  - POST /api/code/execute - Query execution with timeout
  - GET /api/code/servers - List monitored servers
  - GET /api/code/databases/{serverId} - List databases
  - GET /api/code/objects - Schema browser integration
- Added SqlConnection-based execution (not stored procedures)
- Implemented InfoMessage tracking for PRINT statements
- Added GetSchemaTable() for column metadata

**Day 3: Frontend API Integration (6h)** ✅ COMPLETE
- Updated SqlMonitorApiClient.ts (replaced 120 lines of mock code)
- Integrated with Grafana's getBackendSrv() API proxy
- Implemented executeQuery(), getServers(), getDatabases(), getSchemaObjects()
- Built Webpack configuration (standalone, no external dependencies)
- Fixed ES module compatibility (dirname polyfill)
- Fixed JSDoc syntax errors (regex patterns)
- Successfully built plugin in 61-75 seconds

### 🔧 Additional Work Completed (Nov 3, 2025)

**Infrastructure & Deployment**:
- ✅ Fixed AWS RDS Performance Insights dashboard (simplified IOPS/Throughput queries)
- ✅ Added BatchRequestsPerSec and Transactions/sec metrics to collection
- ✅ Fixed Insights dashboard datasource template variable
- ✅ Updated dashboard refresh mechanism (port 8888 workaround documented)
- ✅ Created SchoolVision deployment folder (deployment/clients/schoolvision/)
- ✅ Created ArcTrade deployment folder (deployment/clients/arctrade/)
- ✅ Genericized scripts to remove hardcoded credentials
- ✅ Updated Grafana datasource to use environment variables

**Security Improvements**:
- ✅ Extracted SchoolVision credentials to .env (gitignored)
- ✅ Extracted ArcTrade credentials to .env (gitignored)
- ✅ Made deployment scripts require explicit parameters (fail-safe)
- ✅ Created comprehensive deployment guides (README.md for each client)

**Git Commits**:
- ec3e858: Extract client deployments and genericize scripts
- 0aae506: Fix Insights dashboard datasource template variable error
- 414b987: Update dashboard refresh page with working solutions
- e514a10: Fix dashboard refresh button display in Grafana
- 0eb6fd0: Add Batch Requests/sec and Transactions/sec metrics

### 📋 Week 2: Code Analysis + IntelliSense + Snippets (26 hours)

**Day 4-5: Analysis Engine Foundation (8h)** 🔜 NEXT
- [ ] Create RuleBase interface and BaseRule class
- [ ] Create AnalysisEngine with analyze() method
- [ ] Implement rule management (enable/disable/configure)
- [ ] Add severity levels (Error, Warning, Info)
- [ ] Create rule testing framework

**Day 6-7: Implement 30 Analysis Rules (12h)**
- [ ] Performance Rules (P001-P010): 4h
  - SELECT *, Missing WHERE, Cursor usage, Non-SARGable, etc.
- [ ] Deprecated Rules (DP001-DP008): 2h
  - sp_executesql, OPENROWSET, fn_virtualfilestats, etc.
- [ ] Security Rules (S001-S005): 2h
  - Dynamic SQL injection, xp_cmdshell, TRUSTWORTHY, etc.
- [ ] Code Smell Rules (C001-C008): 2h
  - NOLOCK hints, @@IDENTITY, Nested cursors, etc.
- [ ] Design Rules (D001-D005): 1h
  - Wide tables, Missing clustered index, GUID fragmentation, etc.
- [ ] Naming Rules (N001-N005): 1h
  - Naming conventions, reserved words, etc.

**Day 8: IntelliSense + Code Formatting + Snippets (6h)** ⭐ UX ENHANCEMENT
- [ ] Schema-aware IntelliSense (table/column autocomplete): 4h
- [ ] SQL code formatter integration (sql-formatter): 1h
- [ ] T-SQL code snippets (SELECT, INSERT, UPDATE, etc.): 1h

### 📋 Week 3: Query Execution + Export + History (15 hours)

**Day 9-10: Query Execution Enhancement (6h)**
- [ ] Create ResultsPanel component with ag-Grid
- [ ] Add execution time tracking
- [ ] Implement query timeout (60 seconds)
- [ ] Add error message display
- [ ] Create ToolbarActions component
- [ ] Add server/database selection dropdowns

**Day 11: Results Export + Execution History (9h)** ⭐ UX ENHANCEMENT
- [ ] Export Results to CSV: 1h
- [ ] Export Results to JSON: 0.5h
- [ ] Export Results to Excel: 0.5h
- [ ] Implement Execution History (last 50 queries): 3h
  - localStorage-based history
  - Display query, timestamp, duration, server
  - Click to re-execute
- [ ] Add query statistics (rows affected, execution time): 1h
- [ ] Add MESSAGES panel (PRINT statements): 1h
- [ ] Add multi-resultset support: 2h

### 📋 Week 3-4: SolarWinds DPA Features (10 hours)

**Day 12-13: Response Time Percentiles (5h)**
- [ ] Add P50, P95, P99 columns to ProcedureStats table
- [ ] Update usp_CollectProcedureStats with percentile calculation
- [ ] Create PerformanceInsights component
- [ ] Display percentiles in dashboard
- [ ] Add variance warnings (P95/P50 > 5x)

**Day 14: Query Rewrite Suggestions (3h)**
- [ ] Implement 5-10 query rewrite rules
  - OR to UNION ALL conversion
  - NOT IN to NOT EXISTS conversion
  - Scalar subquery to JOIN conversion
  - etc.
- [ ] Add auto-fix hints with sample code
- [ ] Display in AnalysisPanel

**Day 15: Wait Time Categorization (2h)**
- [ ] Create fn_CategorizeWaitType function
- [ ] Deploy to MonitoringDB
- [ ] Update wait stats dashboards
- [ ] Add actionable recommendations

### 📋 Week 4: Polish + Script Management + Documentation (9 hours)

**Day 16: AnalysisPanel + Script Management (6h)** ⭐ UX ENHANCEMENT
- [ ] Create AnalysisPanel sidebar with badges (Error, Warning, Info): 2h
- [ ] Add clickable results (jump to line in editor)
- [ ] Display fix suggestions with code samples
- [ ] Implement Script Management: 4h
  - Save script to localStorage (with name, description)
  - Load saved script into editor
  - Delete saved script
  - Create SavedScriptsPage with grid
  - Add search/filter functionality

**Day 17: Documentation (3h)**
- [ ] User Guide (USER-GUIDE.md): 1.5h
  - Getting started
  - Features overview
  - Analysis rules reference
  - Keyboard shortcuts
  - Export/import workflows
- [ ] Developer Guide (DEVELOPER-GUIDE.md): 1h
  - Plugin architecture
  - Adding new analysis rules
  - Testing guidelines
  - Build/deployment
- [ ] Update project README.md: 0.5h

### 🎯 Success Metrics

**Current Progress**: 15/75 hours (20%) ✅

**Functionality** (3 of 11 complete):
- [x] Backend API endpoints for query execution
- [x] Backend models for request/response
- [x] Frontend API client integration
- [ ] Code editor with T-SQL syntax highlighting
- [ ] Real-time code analysis with 30+ rules
- [ ] Query execution with results grid
- [ ] Auto-fix suggestions for common issues
- [ ] Index recommendations based on monitoring data
- [ ] Response time percentiles display
- [ ] Query rewrite suggestions
- [ ] Wait time categorization

**Performance**:
- [x] Plugin builds in <75 seconds
- [x] API endpoints respond in <200ms (tested)
- [ ] Analysis completes in <2 seconds for 1000-line files
- [ ] Query execution timeout enforced (60 seconds)
- [ ] UI remains responsive during analysis

**Quality**:
- [ ] 80%+ unit test coverage
- [x] Zero TypeScript compilation errors ✅
- [x] No webpack build errors ✅
- [ ] No console errors in browser
- [ ] Works in Chrome, Firefox, Edge

---

## 📋 Next Steps (Immediate)

### 1. Deploy Plugin to Grafana Container (HIGH PRIORITY)

**Status**: Pending Docker/Azure deployment
**Estimated Time**: 2 hours

**Steps**:
1. Copy plugin to Grafana plugins directory:
   ```bash
   cp -r grafana-plugins/sqlmonitor-codeeditor-app /path/to/grafana/plugins/
   ```
2. Restart Grafana container
3. Enable plugin in Grafana UI
4. Test integration with backend API
5. Verify query execution works end-to-end

### 2. Start Week 2 Implementation (Analysis Engine)

**Status**: Ready to start
**Estimated Time**: 26 hours (5-6 days)

**First Task**: Create RuleBase interface
- Define IRule interface (analyze(), getSeverity(), getCategory())
- Create BaseRule abstract class
- Implement rule registration system
- Add unit tests

### 3. Test Integration End-to-End

**Status**: Pending plugin deployment
**Estimated Time**: 1 hour

**Test Scenarios**:
1. Open Code Editor page in Grafana
2. Select server and database
3. Write a simple SELECT query
4. Execute query and verify results display
5. Test error handling (syntax error, timeout)
6. Test PRINT statement capture (MESSAGES panel)

---

## 📊 Overall Progress

| Phase | Status | Hours | Priority | Dependencies |
|-------|--------|-------|----------|--------------|
| **Phase 1: Database Foundation** | ✅ Complete | 40h | Critical | None |
| **Phase 1.25: Schema Browser** | ✅ Complete | 4h | High | Phase 1 |
| **Phase 2.0: SOC 2 (Auth/Audit)** | ✅ Complete | 80h | Critical | Phase 1.25 |
| **Phase 2.1: Query Analysis** | ✅ Complete | 10h | Critical | Phase 2.0 |
| **Phase 3: Killer Features** | 🔄 **IN PROGRESS** | 135h / 160h | High | Phase 2.1 ✅ |
| **Phase 3 Feature #7** | 🔄 **CURRENT** | 15h / 75h | Critical | Phase 3 F#1-6 ✅ |
| **Phase 2.5: GDPR Compliance** | 📋 Planned | 60h est | High | Phase 3 |
| **Phase 2.6: PCI-DSS Compliance** | 📋 Planned | 48h | Medium | Phase 2.5 |
| **Phase 2.7: HIPAA Compliance** | 📋 Planned | 40h | Medium | Phase 2.6 |
| **Phase 2.8: FERPA Compliance** | 📋 Planned | 24h | Low | Phase 2.7 |
| **Phase 5: AI Layer** | 📋 Planned | 200h | Medium | Phase 3 |
| **TOTAL** | 🔄 In Progress | **730h** | — | — |

**Current Phase**: Phase 3 Feature #7 (T-SQL Code Editor) - Week 1 Complete ✅
**Next Milestone**: Complete Week 2 (Analysis Engine) → Week 3 (Query Execution) → Week 4 (Polish)

---

## 🎯 Project Vision

Build a **self-hosted, enterprise-grade SQL Server monitoring solution** that:
- ✅ Eliminates cloud dependencies (runs entirely on-prem or any cloud)
- 🔄 Provides **complete compliance** coverage (SOC 2 ✅, GDPR, PCI-DSS, HIPAA, FERPA)
- 🔄 Delivers **killer features** that exceed commercial competitors
- 📋 Leverages **AI** for intelligent optimization and recommendations
- ✅ Costs **$0-$1,500/year** vs. **$27k-$37k for competitors**

---

## 📊 Feature Parity Progression

| Phase | Feature Parity | Unique Features | Cost Savings (5yr, 10 servers) |
|-------|----------------|-----------------|-------------------------------|
| Phase 1.25 (Schema Browser) | 88% | 3 | $53,200 vs Redgate |
| Phase 2.0 (SOC 2) | 90% | 5 | $53,200 vs Redgate |
| Phase 2.1 (Query Analysis) | 95% ✅ | 8 | $53,200 vs Redgate |
| **Phase 3 Feature #7 (In Progress)** | **100%** 🎯 | **10** | **$53,200 vs Redgate** |
| Phase 3 (Complete) | **105%** 🎯 | **15** | **$203,350 vs Competitors** |
| Phase 2.5-2.8 (All Compliance) | 98% | 11 | $150,540 vs AWS RDS |
| Phase 5 (AI Layer) | 120% | 25 | $150,540 vs AWS RDS |

**Current Status**: **95% feature parity** with $53,200 cost savings ✅
**Next Milestone**: **100% feature parity** (T-SQL Code Editor complete)

---

## ✅ Completed Phases

### **Phase 1.0: Database Foundation** ✅
**Completion Date**: 2025-10-15
**Document**: `docs/phases/PHASE-01-IMPLEMENTATION-COMPLETE.md`

### **Phase 1.25: Schema Browser** ✅
**Completion Date**: 2025-10-27
**Actual Time**: 4 hours (vs 40 hours planned)
**Document**: `docs/phases/PHASE-01.25-COMPLETE.md`

### **Phase 2.0: SOC 2 Compliance** ✅
**Completion Date**: 2025-10-29
**Document**: `docs/phases/PHASE-02-SOC2-COMPLIANCE-PLAN.md`

### **Phase 2.1: Query Analysis Features** ✅
**Completion Date**: 2025-11-01
**Actual Time**: 10 hours (2 sessions)
**Document**: `FINAL-REMOTE-COLLECTION-COMPLETE.md`

---

## 🚀 Deployment Infrastructure (New - Nov 3, 2025)

### Client Deployment Folders

**Purpose**: Secure, client-specific deployment configurations with password management

**Structure**:
```
deployment/clients/
├── schoolvision/
│   ├── .env                     # Actual credentials (gitignored)
│   ├── .env.template            # Safe template (committed)
│   ├── Setup-SchoolVisionMonitoring.ps1
│   ├── README.md
│   └── logs/
└── arctrade/
    ├── .env                     # Actual credentials (gitignored)
    ├── .env.template            # Safe template (committed)
    ├── Setup-ArcTradeMonitoring.ps1
    ├── README.md
    └── logs/
```

**SchoolVision Servers**:
- Primary: sqltest.schoolvision.net:14333
- Remote 1: svweb:14333
- Remote 2: suncity.schoolvision.net:14333

**ArcTrade Servers**:
- Primary: 003p_New at 10.10.2.196:1433
- Remote 1: 001p_New at 10.10.2.210:1433
- Remote 2: 002p_New at 10.10.2.201:1433

**Features**:
- ✅ Automated password reset on all servers
- ✅ MonitoringDB creation and deployment
- ✅ Linked server configuration
- ✅ SQL Agent job setup (5-minute collection)
- ✅ Server registration
- ✅ Comprehensive logging

---

## 📋 Implementation Principles

### 1. Test-Driven Development (TDD) - MANDATORY
- Write tests BEFORE implementation
- Red-Green-Refactor cycle
- Minimum 80% code coverage

### 2. Database-First Architecture
- All data access via stored procedures
- No dynamic SQL in application code
- **Exception**: OPENQUERY pattern for remote collection

### 3. Security Best Practices
- No hardcoded credentials in code
- Environment variables for configuration
- Client-specific .env files (gitignored)
- Generic scripts require explicit parameters

### 4. Documentation
- Comprehensive README for each deployment
- User guides and troubleshooting steps
- Code comments and inline documentation

---

## 🎯 Quick Reference

### Current Status
- **Phase 3 Feature #7**: 20% complete (15 of 75 hours)
- **Week 1**: ✅ COMPLETE (Plugin scaffolding, API integration, build system)
- **Week 2**: Ready to start (Analysis engine, 30 rules, IntelliSense)
- **Deployment Infrastructure**: ✅ COMPLETE (SchoolVision + ArcTrade)

### Key Documents
- **PHASE-3-FEATURE-7-IMPLEMENTATION-PLAN.md** - Complete implementation plan
- **PHASE-3-FEATURE-7-PLUGIN-ARCHITECTURE.md** - Technical architecture
- **PHASE-3-FEATURE-7-NICE-TO-HAVES.md** - UX enhancements guide
- **deployment/clients/schoolvision/README.md** - SchoolVision deployment guide
- **deployment/clients/arctrade/README.md** - ArcTrade deployment guide

### Recent Commits (Nov 3, 2025)
- ec3e858: Extract client deployments and genericize scripts
- 0aae506: Fix Insights dashboard datasource template variable error
- 414b987: Update dashboard refresh page with working solutions
- e514a10: Fix dashboard refresh button display in Grafana
- 0eb6fd0: Add Batch Requests/sec and Transactions/sec metrics

---

**Last Updated**: November 3, 2025 14:00 UTC
**Next Milestone**: Deploy plugin to Grafana → Start Week 2 (Analysis Engine)
**Project Status**: Phase 3 Feature #7 - Week 1 Complete ✅ (20% done)
**Recommendation**: Deploy plugin first, then start analysis engine implementation
