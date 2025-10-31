# SQL Server Monitor - Development Roadmap

**Last Updated**: October 31, 2025
**Project Status**: Phase 2.1 (Query Analysis Features) - Critical Bug Fix In Progress
**Methodology**: Test-Driven Development (TDD) - Red-Green-Refactor

---

## 🚨 **CRITICAL: Remote Collection Bug Fix (CURRENT SESSION)**

### Status: 🔄 IN PROGRESS (2 of 8 procedures fixed)

**Date Started**: 2025-10-31
**Priority**: CRITICAL (blocks Phase 2 deployment)
**Context Document**: `SESSION-STATUS-2025-10-31.md`

### Problem Identified

Remote servers were collecting **sqltest's data** instead of their own data when calling procedures via linked server (execution context issue).

**Root Cause**: When remote server calls `EXEC [sqltest].[MonitoringDB].dbo.usp_CollectWaitStats @ServerID=5`, the procedure executes on sqltest and queries sqltest's DMVs, storing sqltest's data with ServerID=5 (WRONG!).

**User Insight**: "make sure they capture their own data not just the destination server's data because of the linked servers issues" ✅

### Solution: OPENQUERY Pattern

```sql
IF @LinkedServerName IS NULL
    -- LOCAL: Direct DMV query
ELSE
    -- REMOTE: OPENQUERY([SVWEB], 'SELECT * FROM sys.dm_os_wait_stats')
```

### Progress Tracker

| # | Procedure | Status | Test Results | Notes |
|---|-----------|--------|--------------|-------|
| 1 | `usp_CollectWaitStats` | ✅ **FIXED** | 112 vs 150 wait types (DIFFERENT ✅) | Lines 325-412 in database/32 |
| 2 | `usp_CollectBlockingEvents` | ✅ **FIXED** | Both executed successfully ✅ | ⚠️ Needs merge to file |
| 3 | `usp_CollectDeadlockEvents` | ❌ **NOT FIXED** | - | Extended Events (45 min) |
| 4 | `usp_CollectIndexFragmentation` | ❌ **NOT FIXED** | - | sys.dm_db_index_physical_stats (30 min) |
| 5 | `usp_CollectMissingIndexes` | ❌ **NOT FIXED** | - | Simple DMVs (20 min) |
| 6 | `usp_CollectUnusedIndexes` | ❌ **NOT FIXED** | - | Simple DMVs (20 min) |
| 7 | `usp_CollectQueryStoreStats` | ❌ **NOT FIXED** | - | Complex: database context (60 min) |
| 8 | `usp_CollectAllQueryAnalysisMetrics` | ❌ **NOT FIXED** | - | Master procedure (10 min) |

**Estimated Time Remaining**: 2-3 hours

### Infrastructure Complete ✅

- ✅ **LinkedServerName column** added to `dbo.Servers` table
- ✅ **Linked servers verified**: SVWEB, suncity.schoolvision.net
- ✅ **Trace Flag 1222** deployed to all 3 servers
- ✅ **Test methodology proven**: Compare local vs remote data (must be DIFFERENT)

### Documentation Created ✅

- ✅ `CRITICAL-REMOTE-COLLECTION-FIX.md` - 900+ line solution guide
- ✅ `REMOTE-COLLECTION-FIX-PROGRESS.md` - Test results and progress
- ✅ `SESSION-STATUS-2025-10-31.md` - Complete session context

### Next Session Action Items

**Priority 1**: Merge usp_CollectBlockingEvents to file (5 min)
**Priority 2**: Fix remaining 6 procedures with OPENQUERY pattern (2-3 hours)
**Priority 3**: Test all procedures (local vs remote verification) (30 min)
**Priority 4**: Delete incorrect historical data for ServerID=4, 5 (15 min)
**Priority 5**: Final documentation update (15 min)

---

## 📊 Overall Progress

| Phase | Status | Hours | Priority | Dependencies |
|-------|--------|-------|----------|--------------|
| **Phase 1: Database Foundation** | ✅ Complete | 40h | Critical | None |
| **Phase 1.25: Schema Browser** | ✅ Complete | 4h actual | High | Phase 1 |
| **Phase 2.0: SOC 2 (Auth/Audit)** | ✅ Complete | 80h | Critical | Phase 1.25 |
| **Phase 2.1: Query Analysis Features** | 🔄 **IN PROGRESS** | 60h | **CRITICAL** | Phase 2.0 |
| **Phase 2.1.1: Remote Collection Fix** | 🔄 **IN PROGRESS** | 4h (2h spent) | **CRITICAL** | Phase 2.1 |
| **Phase 2.5: GDPR Compliance** | 📋 Planned | 60h | High | Phase 2.1 |
| **Phase 2.6: PCI-DSS Compliance** | 📋 Planned | 48h | Medium | Phase 2.1, 2.5 |
| **Phase 2.7: HIPAA Compliance** | 📋 Planned | 40h | Medium | Phase 2.1, 2.5, 2.6 |
| **Phase 2.8: FERPA Compliance** | 📋 Planned | 24h | Low | Phase 2.1, 2.5, 2.6, 2.7 |
| **Phase 3: Killer Features** | 📋 Planned | 160h | High | Phase 2.1 |
| **Phase 4: Code Editor & Rules Engine** | 📋 Planned | 120h | Medium | Phase 2.1, 3 |
| **Phase 5: AI Layer** | 📋 Planned | 200h | Medium | Phase 1-4 |
| **TOTAL** | 🔄 In Progress | **836h** | — | — |

**Current Phase**: Phase 2.1.1 - Remote Collection Bug Fix ← **FINISH THIS FIRST**

---

## 🎯 Project Vision

Build a **self-hosted, enterprise-grade SQL Server monitoring solution** that:
- ✅ Eliminates cloud dependencies (runs entirely on-prem or any cloud)
- ✅ Provides **complete compliance** coverage (SOC 2, GDPR, PCI-DSS, HIPAA, FERPA)
- ✅ Delivers **killer features** that exceed commercial competitors
- ✅ Leverages **AI** for intelligent optimization and recommendations
- ✅ Costs **$0-$1,500/year** vs. **$27k-$37k for competitors**

---

## 🚨 **PHASE 2.1.1: Remote Collection Bug Fix (CRITICAL)**

### Completion Checklist

#### Infrastructure (Complete ✅)
- [x] Add LinkedServerName column to dbo.Servers table
- [x] Populate LinkedServerName for all servers (NULL=local, value=remote)
- [x] Verify linked servers exist and are accessible
- [x] Deploy Trace Flag 1222 to all servers

#### Procedure Fixes (2 of 8 Complete)
- [x] **usp_CollectWaitStats** - FIXED and TESTED ✅
- [x] **usp_CollectBlockingEvents** - FIXED and TESTED ✅ (needs file merge)
- [ ] **usp_CollectDeadlockEvents** - Apply OPENQUERY pattern (45 min)
- [ ] **usp_CollectIndexFragmentation** - Apply OPENQUERY pattern (30 min)
- [ ] **usp_CollectMissingIndexes** - Apply OPENQUERY pattern (20 min)
- [ ] **usp_CollectUnusedIndexes** - Apply OPENQUERY pattern (20 min)
- [ ] **usp_CollectQueryStoreStats** - Apply OPENQUERY pattern (60 min, complex)
- [ ] **usp_CollectAllQueryAnalysisMetrics** - Update to call fixed procedures (10 min)

#### Testing (Partial)
- [x] Test usp_CollectWaitStats local (ServerID=1) vs remote (ServerID=5)
- [x] Verify data is DIFFERENT (proves fix working)
- [x] Test usp_CollectBlockingEvents local vs remote
- [ ] Test all 8 procedures local vs remote
- [ ] Verify all procedures collect different data for different servers

#### Data Cleanup
- [ ] Delete incorrect historical data for ServerID=4 (suncity)
- [ ] Delete incorrect historical data for ServerID=5 (svweb)
- [ ] Tables to clean: WaitStatsSnapshot, QueryStoreQueries, BlockingEvents, DeadlockEvents, etc.

#### Documentation
- [x] CRITICAL-REMOTE-COLLECTION-FIX.md (solution guide)
- [x] REMOTE-COLLECTION-FIX-PROGRESS.md (progress report)
- [x] SESSION-STATUS-2025-10-31.md (session context)
- [x] Update database/02-create-tables.sql with LinkedServerName
- [x] Update database/32-create-query-analysis-procedures.sql header
- [ ] Update header with final status (all procedures ✅)
- [ ] Create REMOTE-COLLECTION-FIX-COMPLETE.md (final summary)

#### Files Modified
- [x] database/02-create-tables.sql (LinkedServerName column)
- [x] database/32-create-query-analysis-procedures.sql (header + usp_CollectWaitStats)
- [ ] database/32-create-query-analysis-procedures.sql (merge usp_CollectBlockingEvents)
- [ ] database/32-create-query-analysis-procedures.sql (fix remaining 6 procedures)
- [ ] Git commit with all changes

### Success Criteria

- [ ] All 8 procedures use OPENQUERY pattern for remote collection
- [ ] All procedures tested: local (ServerID=1) vs remote (ServerID=5)
- [ ] Data verification: Results are DIFFERENT for each server
- [ ] Incorrect historical data deleted
- [ ] All fixes committed to database/32 script file
- [ ] Documentation complete

---

## 📋 **PHASE 2.1: Query Analysis Features (CURRENT PHASE)**

### Status: 85% Complete (4 of 4 features deployed, bug discovered)

**Date Started**: 2025-10-30
**Date Target**: 2025-11-01 (completion after bug fix)
**Document**: `PHASE-2-QUERY-ANALYSIS-IMPLEMENTATION.md`

### Overview

Implemented 4 competitive features from analysis:
1. ✅ Query Store Integration
2. ✅ Real-time Blocking Detection
3. ✅ Deadlock Monitoring (Trace Flag 1222)
4. ✅ Wait Statistics Analysis

### Deliverables

#### Database Objects (Complete ✅)
- ✅ 11 new tables (QueryStoreQueries, BlockingEvents, WaitStatsSnapshot, etc.)
- ✅ 8 collection procedures (now fixing with OPENQUERY pattern)
- ✅ 4 analysis procedures (baseline, anomaly detection)
- ✅ Trace Flag 1222 configuration script

#### Features Deployed
- ✅ **Query Store Integration** - Captures query metadata, runtime stats, execution plans
- ✅ **Real-time Blocking Detection** - Tracks blocking chains with 5+ second threshold
- ✅ **Deadlock Monitoring** - TF 1222 enabled, captures deadlock graphs
- ✅ **Wait Statistics** - Snapshot-based wait analysis with delta calculation

#### Critical Issue Discovered
- ❌ **Remote Collection Bug** - Procedures collect wrong server's data via linked server
- 🔄 **Fix In Progress** - OPENQUERY pattern implementation (2 of 8 procedures fixed)

### Remaining Work

1. **Complete Remote Collection Fix** (2-3 hours)
   - Fix 6 remaining procedures with OPENQUERY pattern
   - Test all procedures local vs remote
   - Delete incorrect historical data

2. **Grafana Dashboards** (4 hours)
   - Query Store Performance dashboard
   - Blocking/Deadlock dashboard
   - Wait Statistics dashboard
   - Top Queries by metric dashboard

3. **Documentation** (2 hours)
   - User guide for Query Analysis features
   - Troubleshooting guide
   - Dashboard usage guide

**Total Remaining**: 8-10 hours

---

## ✅ **PHASE 2.0: SOC 2 Compliance (COMPLETE)**

### Status: 100% Complete ✅

**Completion Date**: 2025-10-29
**Document**: `docs/phases/PHASE-02-SOC2-COMPLIANCE-PLAN.md`

### Deliverables Completed

#### Authentication & Authorization
- ✅ JWT token authentication (8-hour expiration, 5-min clock skew)
- ✅ MFA support (TOTP with QR code generation)
- ✅ Backup codes (10 single-use codes)
- ✅ Password hashing (BCrypt with automatic salt)
- ✅ Session management (server-side tracking, auto-cleanup)

#### Database Schema
- ✅ Users, Roles, Permissions tables
- ✅ UserRoles, RolePermissions (many-to-many)
- ✅ UserSessions (active session tracking)
- ✅ UserMFA (TOTP secrets, backup codes)
- ✅ AuditLog (comprehensive audit trail)

#### API Endpoints
- ✅ POST /api/auth/register, /login
- ✅ POST /api/mfa/setup, /verify, /validate
- ✅ GET/DELETE /api/session

#### Middleware
- ✅ AuditMiddleware (logs all requests before auth)
- ✅ AuthorizationMiddleware (enforces permissions)
- ✅ [RequirePermission] attribute for declarative checks

#### Security Features
- ✅ Row-level security via @UserID parameter
- ✅ Permissions cached in IMemoryCache
- ✅ All passwords hashed with BCrypt
- ✅ MFA secrets stored encrypted

---

## ✅ **PHASE 1.25: Schema Browser (COMPLETE)**

### Status: 100% Complete ✅

**Completion Date**: 2025-10-27
**Actual Time**: 4 hours (vs 40 hours planned)
**Document**: `docs/phases/PHASE-01.25-COMPLETE.md`

### Deliverables

- ✅ Schema metadata tables (ObjectCode, ObjectDependencies, ObjectParameters)
- ✅ Metadata caching system (615 objects cached in 250ms)
- ✅ Code Browser Grafana dashboard
- ✅ SSMS integration (search by name, view dependencies)
- ✅ Full-text search on code

---

## 📁 Phase Documentation

All phase plans are documented in **[docs/phases/](docs/phases/)** with detailed implementation guides.

### Completed Phases ✅

| Phase | Document | Status | Key Deliverables |
|-------|----------|--------|------------------|
| **1.0** | [PHASE-01-IMPLEMENTATION-COMPLETE.md](docs/phases/PHASE-01-IMPLEMENTATION-COMPLETE.md) | ✅ Complete | Database schema, stored procedures, SQL Agent jobs |
| **1.25** | [PHASE-01.25-COMPLETE.md](docs/phases/PHASE-01.25-COMPLETE.md) | ✅ Complete | Schema caching (4h vs 40h planned) |
| **2.0** | [PHASE-02-SOC2-COMPLIANCE-PLAN.md](docs/phases/PHASE-02-SOC2-COMPLIANCE-PLAN.md) | ✅ Complete | Auth, MFA, RBAC, Audit logging |

### Current Phase 🔄

| Phase | Document | Status | Key Deliverables |
|-------|----------|--------|------------------|
| **2.1** | PHASE-2-QUERY-ANALYSIS-IMPLEMENTATION.md | 🔄 85% | Query Store, Blocking, Deadlocks, Wait Stats |
| **2.1.1** | SESSION-STATUS-2025-10-31.md | 🔄 50% | OPENQUERY pattern fix (2 of 8 procedures) |

**Current Blocker**: Remote collection bug (2-3 hours to fix)

### Planned Phases 📋

| Phase | Document | Hours | Dependencies |
|-------|----------|-------|--------------|
| **2.5** | PHASE-02.5-GDPR-COMPLIANCE-PLAN.md | 60h | Phase 2.1 complete |
| **2.6** | PHASE-02.6-PCI-DSS-COMPLIANCE-PLAN.md | 48h | Phase 2.1, 2.5 |
| **2.7** | PHASE-02.7-HIPAA-COMPLIANCE-PLAN.md | 40h | Phase 2.1, 2.5, 2.6 |
| **2.8** | PHASE-02.8-FERPA-COMPLIANCE-PLAN.md | 24h | Phase 2.1, 2.5, 2.6, 2.7 |
| **3** | PHASE-03-KILLER-FEATURES-PLAN.md | 160h | Phase 2.1 |
| **4** | PHASE-04-CODE-EDITOR-PLAN.md | 120h | Phase 2.1, 3 |
| **5** | PHASE-05-AI-LAYER-PLAN.md | 200h | Phase 1-4 |

---

## 🚀 Implementation Path Forward

### Immediate: Fix Remote Collection Bug (2-3 hours)

**Priority**: CRITICAL (blocks Phase 2.1 completion)

**Action Items**:
1. Merge usp_CollectBlockingEvents to database/32 file (5 min)
2. Fix 6 remaining procedures with OPENQUERY pattern:
   - usp_CollectDeadlockEvents (45 min)
   - usp_CollectIndexFragmentation (30 min)
   - usp_CollectMissingIndexes (20 min)
   - usp_CollectUnusedIndexes (20 min)
   - usp_CollectQueryStoreStats (60 min, complex)
   - usp_CollectAllQueryAnalysisMetrics (10 min)
3. Test all procedures local vs remote (30 min)
4. Delete incorrect historical data (15 min)
5. Update documentation (15 min)

**Reference**: `SESSION-STATUS-2025-10-31.md` for complete context

### Short-term: Complete Phase 2.1 (8-10 hours)

**After bug fix is complete**:

1. **Grafana Dashboards** (4 hours)
   - Query Store Performance dashboard
   - Blocking/Deadlock dashboard
   - Wait Statistics dashboard
   - Top Queries dashboard

2. **Documentation** (2 hours)
   - Query Analysis user guide
   - Troubleshooting guide
   - Dashboard usage guide

3. **Deployment** (2 hours)
   - Deploy to production servers
   - Verify data collection on all 3 servers
   - Monitor for 24 hours

### Medium-term: Phase 2.5 GDPR (60 hours)

**After Phase 2.1 complete**:

- Data subject rights (access, deletion, portability)
- Consent management
- Data retention policies
- Privacy impact assessments
- EU-specific compliance

### Long-term: Phases 2.6-2.8, 3, 4, 5 (592 hours)

Complete compliance frameworks and competitive features.

---

## 📊 Success Metrics

### Phase 2.1.1 (Remote Collection Fix)

- [ ] All 8 procedures collect correct server data
- [ ] Test results show DIFFERENT data for local vs remote
- [ ] Incorrect historical data deleted
- [ ] All fixes committed to scripts
- [ ] Documentation complete

### Phase 2.1 (Query Analysis Features)

- [ ] Remote collection bug fixed ✅
- [ ] 4 Grafana dashboards deployed
- [ ] Data collection verified on all 3 servers
- [ ] User documentation complete
- [ ] 24-hour monitoring shows no errors

### Feature Parity vs Competitors

| Phase | Feature Parity | Unique Features | Cost Savings (5yr, 10 servers) |
|-------|----------------|-----------------|-------------------------------|
| Phase 1.25 (Schema Browser) | 88% | 3 | $53,200 vs Redgate |
| Phase 2.0 (SOC 2) | 90% | 5 | $53,200 vs Redgate |
| **Phase 2.1 (Query Analysis)** | **95%** | **9** | **$53,200 vs Redgate** |
| Phase 2.5-2.8 (All Compliance) | 98% | 11 | $150,540 vs AWS RDS |
| Phase 3 (Killer Features) | 100% | 16 | $150,540 vs AWS RDS |
| Phase 4 (Code Editor) | 105% | 18 | $150,540 vs AWS RDS |
| Phase 5 (AI Layer) | 110% | 23 | $150,540 vs AWS RDS |

---

## 📋 Implementation Principles

### 1. Test-Driven Development (TDD) - MANDATORY

- Write tests BEFORE implementation
- Red-Green-Refactor cycle
- Minimum 80% code coverage

### 2. Database-First Architecture

- All data access via stored procedures
- No dynamic SQL in application code
- Exception: OPENQUERY pattern for remote collection (uses dynamic SQL by necessity)

### 3. Backwards Compatibility

- LinkedServerName column added with ALTER TABLE IF NOT EXISTS
- Local collection still works (LinkedServerName=NULL)
- Remote collection enhanced with OPENQUERY

### 4. Data Verification

- Always test local vs remote collection
- Data must be DIFFERENT for different servers
- If data is IDENTICAL → bug still exists

---

## 🎯 Quick Reference

### Current Session Status
**File**: `SESSION-STATUS-2025-10-31.md`
**Status**: Remote collection bug - 2 of 8 procedures fixed
**Next**: Fix remaining 6 procedures (2-3 hours)

### Key Documents
- **CRITICAL-REMOTE-COLLECTION-FIX.md** - Complete solution guide (900+ lines)
- **REMOTE-COLLECTION-FIX-PROGRESS.md** - Progress report with test results
- **PHASE-2-QUERY-ANALYSIS-IMPLEMENTATION.md** - Phase 2.1 implementation guide
- **COMPETITIVE-FEATURE-ANALYSIS.md** - Market analysis of 13 features

### Database Changes This Session
- `database/02-create-tables.sql` - Added LinkedServerName column
- `database/32-create-query-analysis-procedures.sql` - Fixed usp_CollectWaitStats
- Live database - Fixed usp_CollectWaitStats, usp_CollectBlockingEvents

### Test Results
- Local (ServerID=1): 112 wait types, 19.2B ms
- Remote (ServerID=5): 150 wait types, 73.6B ms
- **Verification**: DIFFERENT ✅ (proves fix working)

---

## 🚀 Getting Started (Next Session)

1. **Read SESSION-STATUS-2025-10-31.md** - Complete context
2. **Reference CRITICAL-REMOTE-COLLECTION-FIX.md** - OPENQUERY pattern details
3. **Start with usp_CollectMissingIndexes** - Simplest remaining procedure
4. **Use usp_CollectWaitStats as template** - Lines 325-412 in database/32
5. **Test each procedure after fixing** - Local vs remote comparison
6. **Update header comment** - Mark each procedure as ✅ when complete

---

**Last Updated**: October 31, 2025 17:30 UTC
**Next Milestone**: Complete Remote Collection Fix (2-3 hours)
**Project Status**: Phase 2.1.1 - Critical Bug Fix In Progress (50% complete)
