# SQL Monitor Permissions Guide

## Overview

This document describes the **least-privilege permission model** for SQL Monitor and sql-monitor-agent. It addresses the common scenario of cross-database queries and provides secure alternatives to granting `db_owner` access.

**Last Updated**: 2025-10-28
**Phase**: 2.0 (SOC 2 Compliance)
**Security Control**: CC6.1 (Logical and Physical Access Controls)

---

## The Cross-Database Query Problem

### Your Scenario

You have a stored procedure in `produsage2` that queries tables in `prod`:

```sql
-- In database: produsage2
CREATE PROCEDURE dbo.usp_Example
AS
BEGIN
    SELECT * FROM prod.dbo.table1;  -- Cross-database query
END
```

### The Question

**Will EXECUTE-only permission work for cross-database queries?**

### The Answer

**No**, EXECUTE-only won't work for cross-database queries.

When a stored procedure in `produsage2` does `SELECT * FROM prod.dbo.table1`, the **caller needs SELECT permission on prod.dbo.table1** regardless of having EXECUTE permission on the stored procedure in `produsage2`.

### Why?

- **Ownership chaining** only works within a single database
- Cross-database queries break the ownership chain
- The login must have explicit permissions in **both databases**

---

## Recommended Permissions for SQL Monitor

Here's the **least-privilege model** for SQL Monitor:

### Permission Summary

| Database | Permission | Why |
|----------|-----------|-----|
| **MonitoringDB** | `EXECUTE on SCHEMA::dbo` | Run collection procedures |
| **Monitored DBs** (prod, produsage2) | `db_datareader` | Read tables for cross-database queries |
| **Server-level** | `VIEW SERVER STATE` | Access DMVs (sys.dm_*) |
| **Server-level** | `VIEW ANY DEFINITION` | Read metadata (sys.objects, etc.) |
| **Database-level** (optional) | `VIEW DATABASE STATE` | Query Store access |

### Why db_datareader is Appropriate

**db_datareader is READ-ONLY** and perfect for monitoring because:
- ✅ No INSERT/UPDATE/DELETE permissions
- ✅ No EXECUTE permissions (can't run stored procedures)
- ✅ Can read DMVs and system views
- ✅ Supports cross-database queries
- ✅ Industry standard for monitoring tools (SQL Sentry, SolarWinds, Redgate)

---

## Complete Permission Script

### 1. Create Dedicated Login

```sql
-- =============================================
-- SQL Monitor Collector Login (Least Privilege)
-- =============================================

USE [master];
GO

-- Create dedicated login
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'sql_monitor_collector')
BEGIN
    CREATE LOGIN [sql_monitor_collector]
    WITH PASSWORD = 'YourSecurePassword!',
    CHECK_POLICY = OFF;

    PRINT 'Login sql_monitor_collector created successfully';
END
ELSE
BEGIN
    PRINT 'Login sql_monitor_collector already exists';
END
GO
```

### 2. Grant Server-Level Permissions

```sql
-- Grant server-level permissions for DMV access
USE [master];
GO

GRANT VIEW SERVER STATE TO [sql_monitor_collector];
GRANT VIEW ANY DEFINITION TO [sql_monitor_collector];

PRINT 'Server-level permissions granted:';
PRINT '  - VIEW SERVER STATE (DMV access)';
PRINT '  - VIEW ANY DEFINITION (metadata access)';
GO
```

### 3. MonitoringDB Permissions (EXECUTE-only)

```sql
-- Setup MonitoringDB permissions (EXECUTE-only)
USE [MonitoringDB];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'sql_monitor_collector')
BEGIN
    CREATE USER [sql_monitor_collector] FOR LOGIN [sql_monitor_collector];
    PRINT 'User sql_monitor_collector created in MonitoringDB';
END
GO

-- Grant EXECUTE on all stored procedures
GRANT EXECUTE ON SCHEMA::dbo TO [sql_monitor_collector];

PRINT 'MonitoringDB permissions granted:';
PRINT '  - EXECUTE ON SCHEMA::dbo (run all stored procedures)';
GO
```

### 4. Monitored Database Permissions (READ-ONLY)

Repeat for each monitored database: `prod`, `produsage2`, etc.

```sql
-- =============================================
-- Monitored Database: prod
-- =============================================
USE [prod];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'sql_monitor_collector')
BEGIN
    CREATE USER [sql_monitor_collector] FOR LOGIN [sql_monitor_collector];
    PRINT 'User sql_monitor_collector created in [prod]';
END
GO

-- Read-only access for cross-database queries
ALTER ROLE db_datareader ADD MEMBER [sql_monitor_collector];

-- Query Store access (optional)
GRANT VIEW DATABASE STATE TO [sql_monitor_collector];

PRINT '[prod] permissions granted:';
PRINT '  - db_datareader (read all tables/views)';
PRINT '  - VIEW DATABASE STATE (Query Store access)';
GO

-- =============================================
-- Monitored Database: produsage2
-- =============================================
USE [produsage2];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'sql_monitor_collector')
BEGIN
    CREATE USER [sql_monitor_collector] FOR LOGIN [sql_monitor_collector];
    PRINT 'User sql_monitor_collector created in [produsage2]';
END
GO

ALTER ROLE db_datareader ADD MEMBER [sql_monitor_collector];
GRANT VIEW DATABASE STATE TO [sql_monitor_collector];

PRINT '[produsage2] permissions granted:';
PRINT '  - db_datareader (read all tables/views)';
PRINT '  - VIEW DATABASE STATE (Query Store access)';
GO
```

---

## Alternative: Granular Permissions

If you want to restrict access to specific tables only (not recommended for monitoring):

```sql
USE [prod];
GO

CREATE USER [sql_monitor_collector] FOR LOGIN [sql_monitor_collector];

-- Grant SELECT on specific tables only
GRANT SELECT ON dbo.table1 TO [sql_monitor_collector];
GRANT SELECT ON dbo.table2 TO [sql_monitor_collector];
GRANT SELECT ON dbo.table3 TO [sql_monitor_collector];

-- Grant VIEW on specific views
GRANT SELECT ON dbo.view1 TO [sql_monitor_collector];

-- DMV access (system views)
GRANT VIEW DATABASE STATE TO [sql_monitor_collector];
GO
```

**Warning**: This approach requires maintenance every time a new table is added to monitoring.

---

## Migration Script: From db_owner to Least Privilege

If you currently have `db_owner` access and want to migrate to least-privilege:

```sql
-- =============================================
-- Migrate from db_owner to Least Privilege
-- =============================================

-- Example: Migrate arctradeprodrunner login

USE [prod];
GO

-- Remove db_owner (dangerous)
ALTER ROLE db_owner DROP MEMBER [arctradeprodrunner];
PRINT 'Removed db_owner role from [arctradeprodrunner] in [prod]';

-- Add db_datareader (read-only)
ALTER ROLE db_datareader ADD MEMBER [arctradeprodrunner];
PRINT 'Added db_datareader role to [arctradeprodrunner] in [prod]';

-- Add Query Store access
GRANT VIEW DATABASE STATE TO [arctradeprodrunner];
PRINT 'Granted VIEW DATABASE STATE to [arctradeprodrunner] in [prod]';
GO

-- Repeat for other databases
USE [produsage2];
GO

ALTER ROLE db_owner DROP MEMBER [arctradeprodrunner];
ALTER ROLE db_datareader ADD MEMBER [arctradeprodrunner];
GRANT VIEW DATABASE STATE TO [arctradeprodrunner];

PRINT 'Migration complete for [produsage2]';
GO
```

---

## Verification Script

Verify permissions after setup:

```sql
-- =============================================
-- Verify SQL Monitor Permissions
-- =============================================

-- 1. Check server-level permissions
USE [master];
GO

SELECT
    'Server-Level' AS PermissionType,
    pr.name AS LoginName,
    pe.permission_name AS Permission,
    pe.state_desc AS State
FROM sys.server_principals pr
INNER JOIN sys.server_permissions pe ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name = 'sql_monitor_collector'
ORDER BY pe.permission_name;

-- 2. Check MonitoringDB permissions
USE [MonitoringDB];
GO

SELECT
    'MonitoringDB' AS Database,
    dp.name AS UserName,
    pe.permission_name AS Permission,
    pe.state_desc AS State,
    SCHEMA_NAME(pe.major_id) AS SchemaName
FROM sys.database_principals dp
LEFT JOIN sys.database_permissions pe ON dp.principal_id = pe.grantee_principal_id
WHERE dp.name = 'sql_monitor_collector'
ORDER BY pe.permission_name;

-- 3. Check monitored database permissions
USE [prod];
GO

SELECT
    'prod' AS Database,
    dp.name AS UserName,
    r.name AS RoleMembership
FROM sys.database_principals dp
LEFT JOIN sys.database_role_members rm ON dp.principal_id = rm.member_principal_id
LEFT JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
WHERE dp.name = 'sql_monitor_collector';

-- 4. Test DMV access
SELECT
    'DMV Access Test' AS Test,
    COUNT(*) AS RowCount,
    'sys.dm_os_performance_counters' AS ViewName
FROM sys.dm_os_performance_counters;
```

---

## Security Best Practices

### 1. Use Dedicated Login
- ✅ **Do**: Create `sql_monitor_collector` dedicated to monitoring
- ❌ **Don't**: Use `sa`, `dbo`, or application logins

### 2. Least Privilege
- ✅ **Do**: Grant only `db_datareader` on monitored databases
- ❌ **Don't**: Grant `db_owner`, `db_ddladmin`, or write permissions

### 3. Password Security
- ✅ **Do**: Use strong passwords (16+ characters, mixed case, symbols)
- ✅ **Do**: Store passwords in Azure Key Vault or .env files (not in code)
- ❌ **Don't**: Use default passwords or commit passwords to git

### 4. Regular Audits
- ✅ **Do**: Review permissions quarterly
- ✅ **Do**: Monitor login activity via AuditLog table
- ✅ **Do**: Revoke permissions when monitoring is disabled

### 5. Connection Strings
```bash
# Development (.env file)
DB_CONNECTION_STRING="Server=localhost;Database=MonitoringDB;User Id=sql_monitor_collector;Password=SecurePass123!;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30"

# Production (Azure Key Vault)
DB_CONNECTION_STRING="@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/MonitoringDBConnectionString)"
```

---

## Permissions by Component

### SQL Monitor API
- **MonitoringDB**: EXECUTE on stored procedures
- **Monitored DBs**: db_datareader (for dashboards, queries)
- **Server**: VIEW SERVER STATE, VIEW ANY DEFINITION

### sql-monitor-agent (DBATools)
- **DBATools**: EXECUTE on collection procedures
- **Monitored DBs**: db_datareader (for cross-database collection)
- **Server**: VIEW SERVER STATE (for DMV collection)

### Grafana Datasource
- **MonitoringDB**: SELECT on metric tables (`PerformanceMetrics`, `WaitStatistics`, etc.)
- **No permissions needed on monitored databases** (data already collected)

---

## Troubleshooting

### Error: "The server principal 'sql_monitor_collector' is not able to access the database under the current security context"

**Cause**: Login exists but user not created in database.

**Fix**:
```sql
USE [YourDatabase];
CREATE USER [sql_monitor_collector] FOR LOGIN [sql_monitor_collector];
```

### Error: "SELECT permission denied on object 'table1'"

**Cause**: Missing db_datareader or explicit SELECT permission.

**Fix**:
```sql
USE [YourDatabase];
ALTER ROLE db_datareader ADD MEMBER [sql_monitor_collector];
```

### Error: "VIEW SERVER STATE permission denied"

**Cause**: Missing server-level permission for DMV access.

**Fix**:
```sql
USE [master];
GRANT VIEW SERVER STATE TO [sql_monitor_collector];
```

---

## References

- [SQL Server Database-Level Roles](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/database-level-roles)
- [Server-Level Permissions](https://learn.microsoft.com/en-us/sql/relational-databases/security/permissions-database-engine)
- [Ownership Chains](https://learn.microsoft.com/en-us/sql/relational-databases/security/ownership-chains)
- [DMV Permissions](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-requests-transact-sql#permissions)

---

## Template: Full Deployment Script

```sql
-- =============================================
-- SQL Monitor Permissions - Full Deployment
-- =============================================
-- Replace variables:
-- @LoginName: sql_monitor_collector
-- @Password: YourSecurePassword!
-- @MonitoringDB: MonitoringDB
-- @MonitoredDBs: prod, produsage2, produsage3
-- =============================================

USE [master];
GO

-- 1. Create login
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'sql_monitor_collector')
    CREATE LOGIN [sql_monitor_collector] WITH PASSWORD = 'YourSecurePassword!', CHECK_POLICY = OFF;

-- 2. Server permissions
GRANT VIEW SERVER STATE TO [sql_monitor_collector];
GRANT VIEW ANY DEFINITION TO [sql_monitor_collector];

-- 3. MonitoringDB
USE [MonitoringDB];
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'sql_monitor_collector')
    CREATE USER [sql_monitor_collector] FOR LOGIN [sql_monitor_collector];
GRANT EXECUTE ON SCHEMA::dbo TO [sql_monitor_collector];

-- 4. Monitored databases (repeat for each)
USE [prod];
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'sql_monitor_collector')
    CREATE USER [sql_monitor_collector] FOR LOGIN [sql_monitor_collector];
ALTER ROLE db_datareader ADD MEMBER [sql_monitor_collector];
GRANT VIEW DATABASE STATE TO [sql_monitor_collector];

USE [produsage2];
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'sql_monitor_collector')
    CREATE USER [sql_monitor_collector] FOR LOGIN [sql_monitor_collector];
ALTER ROLE db_datareader ADD MEMBER [sql_monitor_collector];
GRANT VIEW DATABASE STATE TO [sql_monitor_collector];

PRINT 'SQL Monitor permissions setup complete';
GO
```

---

## Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2025-10-28 | 1.0 | Initial version - least privilege model for cross-database queries |

---

**Status**: Production-Ready
**Security Level**: Least Privilege
**Compliance**: SOC 2 Type II (CC6.1)
