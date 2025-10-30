# SOC 2 Compliance Implementation Plan

**Date**: October 26, 2025
**Purpose**: Enterprise-grade security and compliance for SQL Server Monitor

---

## Executive Summary

SOC 2 (Service Organization Control 2) compliance is **critical for enterprise adoption**. Organizations handling sensitive data require SOC 2 Type II certification from their monitoring solutions to ensure:

- **Security**: Data protection and access controls
- **Availability**: System reliability and uptime
- **Processing Integrity**: Accurate and timely data processing
- **Confidentiality**: Protection of sensitive information
- **Privacy**: Compliance with data privacy regulations (GDPR, CCPA)

**Current State**: Our SQL Server Monitor lacks formal SOC 2 compliance features
**Target State**: Full SOC 2 compliance with audit-ready evidence collection
**Effort**: 80 hours (2 weeks)

---

## SOC 2 Trust Service Criteria

### 1. Security (CC6)

**Requirements**:
- Access controls (authentication, authorization)
- Encryption at rest and in transit
- Audit logging of all access and changes
- Vulnerability management
- Incident response procedures

**Our Implementation**:
✅ Encryption in transit (SQL Server TLS)
⚠️ **Need to add**:
- Role-based access control (RBAC)
- Comprehensive audit logging
- Encryption at rest for sensitive data
- Security event monitoring

---

### 2. Availability (A1)

**Requirements**:
- System monitoring and alerting
- Backup and recovery procedures
- Capacity planning
- Incident management

**Our Implementation**:
✅ System monitoring (Performance metrics, alerts)
✅ SQL Agent jobs for automated tasks
⚠️ **Need to add**:
- Formal uptime SLA tracking
- Backup verification logging
- Disaster recovery testing records

---

### 3. Processing Integrity (PI1)

**Requirements**:
- Data validation and quality controls
- Error detection and correction
- Processing completeness checks
- Audit trails for data modifications

**Our Implementation**:
✅ Stored procedure-only pattern (data integrity)
✅ SQL Server constraints and foreign keys
⚠️ **Need to add**:
- Data validation logging
- Processing integrity checks
- Anomaly detection for data quality

---

### 4. Confidentiality (C1)

**Requirements**:
- Data classification
- Encryption of confidential data
- Secure disposal of data
- Access restrictions

**Our Implementation**:
⚠️ **Need to add**:
- Data classification labels
- Column-level encryption for sensitive fields
- Secure data deletion procedures
- Access audit logs

---

### 5. Privacy (P1)

**Requirements**:
- Privacy policy and notices
- Data subject rights (GDPR Article 15-22)
- Data retention and disposal
- Third-party management

**Our Implementation**:
✅ Configurable data retention (cleanup jobs)
⚠️ **Need to add**:
- Privacy policy documentation
- Data export capabilities (GDPR right to data portability)
- Right to erasure implementation

---

## Phase 1.5: SOC 2 Compliance Features

**Priority**: Insert between Phase 1 (Gap Closing) and Phase 2 (Killer Features)
**Rationale**: Enterprise customers require SOC 2 compliance before adoption

### Feature 1: Comprehensive Audit Logging (24 hours)

**What**: Log all access, changes, and security events

**Database Schema**:
```sql
CREATE TABLE dbo.AuditLog (
    AuditID BIGINT IDENTITY(1,1) PRIMARY KEY,
    EventTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    EventType VARCHAR(50) NOT NULL, -- Login, Logout, Query, Insert, Update, Delete, ConfigChange, etc.
    UserName NVARCHAR(128) NOT NULL,
    SessionID UNIQUEIDENTIFIER NULL,
    IPAddress VARCHAR(45) NULL,
    ApplicationName NVARCHAR(128) NULL,
    ObjectType VARCHAR(50) NULL, -- Server, Database, Table, Procedure, AlertRule, etc.
    ObjectName NVARCHAR(500) NULL,
    Action VARCHAR(50) NULL, -- CREATE, READ, UPDATE, DELETE, EXECUTE, etc.
    OldValue NVARCHAR(MAX) NULL, -- Before state (JSON)
    NewValue NVARCHAR(MAX) NULL, -- After state (JSON)
    Success BIT NOT NULL,
    ErrorMessage NVARCHAR(MAX) NULL,
    DurationMs INT NULL,

    -- Compliance fields
    DataClassification VARCHAR(20) NULL, -- Public, Internal, Confidential, Restricted
    ComplianceNotes NVARCHAR(MAX) NULL,

    -- Indexing for audit queries
    INDEX IX_AuditLog_EventTime (EventTime DESC),
    INDEX IX_AuditLog_UserName (UserName, EventTime DESC),
    INDEX IX_AuditLog_EventType (EventType, EventTime DESC)
);

-- Partition by month for performance
CREATE PARTITION FUNCTION PF_AuditLogByMonth (DATETIME2)
AS RANGE RIGHT FOR VALUES (
    '2025-01-01', '2025-02-01', '2025-03-01', -- ... monthly partitions
);
```

**Audit Triggers** (automatic logging):
```sql
-- Example: Audit alert rule changes
CREATE TRIGGER trg_AlertRules_Audit
ON dbo.AlertRules
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    INSERT INTO dbo.AuditLog (EventType, UserName, ObjectType, ObjectName, Action, OldValue, NewValue, Success)
    SELECT
        'ConfigChange',
        SUSER_SNAME(),
        'AlertRule',
        COALESCE(i.RuleName, d.RuleName),
        CASE
            WHEN i.RuleID IS NOT NULL AND d.RuleID IS NULL THEN 'CREATE'
            WHEN i.RuleID IS NOT NULL AND d.RuleID IS NOT NULL THEN 'UPDATE'
            WHEN i.RuleID IS NULL AND d.RuleID IS NOT NULL THEN 'DELETE'
        END,
        (SELECT * FROM deleted d2 WHERE d2.RuleID = d.RuleID FOR JSON PATH),
        (SELECT * FROM inserted i2 WHERE i2.RuleID = i.RuleID FOR JSON PATH),
        1
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.RuleID = d.RuleID;
END;
```

**API Audit Middleware** (C#):
```csharp
public class AuditMiddleware
{
    public async Task InvokeAsync(HttpContext context, ISqlService sqlService)
    {
        var startTime = DateTime.UtcNow;
        var success = true;
        string errorMessage = null;

        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            success = false;
            errorMessage = ex.Message;
            throw;
        }
        finally
        {
            var duration = (DateTime.UtcNow - startTime).TotalMilliseconds;

            await sqlService.LogAuditEventAsync(new AuditLogEntry
            {
                EventType = "APIRequest",
                UserName = context.User.Identity?.Name ?? "Anonymous",
                IPAddress = context.Connection.RemoteIpAddress?.ToString(),
                ObjectType = "APIEndpoint",
                ObjectName = $"{context.Request.Method} {context.Request.Path}",
                Action = context.Request.Method,
                Success = success,
                ErrorMessage = errorMessage,
                DurationMs = (int)duration
            });
        }
    }
}
```

**Audit Queries** (for compliance reports):
```sql
-- All access to sensitive data in last 90 days
SELECT * FROM dbo.AuditLog
WHERE DataClassification IN ('Confidential', 'Restricted')
  AND EventTime >= DATEADD(DAY, -90, GETUTCDATE())
ORDER BY EventTime DESC;

-- Failed login attempts
SELECT * FROM dbo.AuditLog
WHERE EventType = 'Login'
  AND Success = 0
  AND EventTime >= DATEADD(DAY, -30, GETUTCDATE());

-- All configuration changes by user
SELECT * FROM dbo.AuditLog
WHERE EventType = 'ConfigChange'
  AND UserName = 'admin@company.com'
ORDER BY EventTime DESC;
```

---

### Feature 2: Role-Based Access Control (RBAC) (20 hours)

**What**: Granular permissions for different user roles

**Database Schema**:
```sql
CREATE TABLE dbo.Roles (
    RoleID INT IDENTITY(1,1) PRIMARY KEY,
    RoleName NVARCHAR(100) NOT NULL UNIQUE,
    Description NVARCHAR(500) NULL,
    IsBuiltIn BIT NOT NULL DEFAULT 0,
    CreatedDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE dbo.Permissions (
    PermissionID INT IDENTITY(1,1) PRIMARY KEY,
    PermissionName NVARCHAR(100) NOT NULL UNIQUE,
    Category VARCHAR(50) NOT NULL, -- Server, Alert, Maintenance, Audit, Admin
    Description NVARCHAR(500) NULL
);

CREATE TABLE dbo.RolePermissions (
    RoleID INT NOT NULL,
    PermissionID INT NOT NULL,
    CONSTRAINT PK_RolePermissions PRIMARY KEY (RoleID, PermissionID),
    CONSTRAINT FK_RolePermissions_Roles FOREIGN KEY (RoleID) REFERENCES dbo.Roles(RoleID) ON DELETE CASCADE,
    CONSTRAINT FK_RolePermissions_Permissions FOREIGN KEY (PermissionID) REFERENCES dbo.Permissions(PermissionID) ON DELETE CASCADE
);

CREATE TABLE dbo.UserRoles (
    UserID INT IDENTITY(1,1) NOT NULL,
    UserName NVARCHAR(128) NOT NULL,
    RoleID INT NOT NULL,
    GrantedBy NVARCHAR(128) NOT NULL,
    GrantedDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    ExpiresDate DATETIME2(7) NULL,
    CONSTRAINT PK_UserRoles PRIMARY KEY (UserID),
    CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (RoleID) REFERENCES dbo.Roles(RoleID)
);
```

**Built-In Roles**:
```sql
-- Insert built-in roles
INSERT INTO dbo.Roles (RoleName, Description, IsBuiltIn) VALUES
('Administrator', 'Full access to all features', 1),
('DBA', 'Database administration and maintenance', 1),
('Developer', 'Read access to metrics and alerts', 1),
('Auditor', 'Read-only access to audit logs', 1),
('Viewer', 'Read-only access to dashboards', 1);

-- Insert permissions
INSERT INTO dbo.Permissions (PermissionName, Category, Description) VALUES
('ViewMetrics', 'Server', 'View performance metrics'),
('ViewAlerts', 'Alert', 'View active alerts'),
('ManageAlerts', 'Alert', 'Create/modify alert rules'),
('PerformMaintenance', 'Maintenance', 'Run index maintenance and backups'),
('ViewAuditLog', 'Audit', 'View audit log entries'),
('ManageUsers', 'Admin', 'Manage user roles and permissions'),
('ConfigureSystem', 'Admin', 'Modify system configuration'),
('DeleteData', 'Admin', 'Delete metrics and historical data');
```

**Permission Checks** (API):
```csharp
[Authorize(Policy = "ManageAlerts")]
[HttpPost]
public async Task<IActionResult> CreateAlertRule([FromBody] AlertRuleRequest request)
{
    // Only users with ManageAlerts permission can execute this
}

// Policy registration in Program.cs
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("ManageAlerts", policy =>
        policy.RequireClaim("Permission", "ManageAlerts"));
});
```

---

### Feature 3: Encryption at Rest (16 hours)

**What**: Encrypt sensitive data stored in database

**Implementation**:

**Option 1: Transparent Data Encryption (TDE)** - Database-level
```sql
-- Enable TDE (SQL Server Enterprise Edition)
USE master;
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'ComplexPassword123!';
GO

CREATE CERTIFICATE MonitoringDB_Cert
WITH SUBJECT = 'MonitoringDB TDE Certificate';
GO

USE MonitoringDB;
GO

CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_256
ENCRYPTION BY SERVER CERTIFICATE MonitoringDB_Cert;
GO

ALTER DATABASE MonitoringDB
SET ENCRYPTION ON;
GO
```

**Option 2: Column-Level Encryption** - For specific sensitive fields
```sql
-- Encrypt sensitive configuration values
ALTER TABLE dbo.AlertRules
ADD EmailRecipientsEncrypted VARBINARY(MAX) NULL;

-- Encryption function
CREATE FUNCTION dbo.fn_EncryptValue(@PlainText NVARCHAR(MAX))
RETURNS VARBINARY(MAX)
AS
BEGIN
    DECLARE @Key VARBINARY(128);
    DECLARE @Encrypted VARBINARY(MAX);

    -- Get encryption key from master key
    SET @Key = CONVERT(VARBINARY(128), 'YourEncryptionKeyHere');

    -- Encrypt using AES_256
    SET @Encrypted = ENCRYPTBYKEY(KEY_GUID('MonitoringDB_SymmetricKey'), @PlainText);

    RETURN @Encrypted;
END;

-- Decryption function
CREATE FUNCTION dbo.fn_DecryptValue(@EncryptedValue VARBINARY(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN CONVERT(NVARCHAR(MAX), DECRYPTBYKEY(@EncryptedValue));
END;
```

---

### Feature 4: Data Retention and Secure Deletion (12 hours)

**What**: GDPR/CCPA-compliant data lifecycle management

**Database Schema**:
```sql
CREATE TABLE dbo.DataRetentionPolicies (
    PolicyID INT IDENTITY(1,1) PRIMARY KEY,
    TableName NVARCHAR(128) NOT NULL,
    RetentionDays INT NOT NULL,
    SecureDelete BIT NOT NULL DEFAULT 1, -- Overwrite before delete
    ComplianceReason NVARCHAR(500) NULL,
    IsEnabled BIT NOT NULL DEFAULT 1,
    CreatedDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE()
);

-- Default retention policies
INSERT INTO dbo.DataRetentionPolicies (TableName, RetentionDays, ComplianceReason) VALUES
('PerformanceMetrics', 90, 'Performance data retention per policy'),
('AuditLog', 2555, 'SOC 2 requires 7 years of audit log retention'),
('AlertHistory', 365, 'Alert history for trend analysis'),
('QueryMetrics', 180, 'Query performance history');
```

**Secure Delete Procedure**:
```sql
CREATE PROCEDURE dbo.usp_SecureDeleteData
    @TableName NVARCHAR(128),
    @CutoffDate DATETIME2(7)
AS
BEGIN
    -- Step 1: Overwrite sensitive data before deletion (GDPR right to erasure)
    DECLARE @SQL NVARCHAR(MAX);

    IF @TableName = 'AuditLog'
    BEGIN
        -- Overwrite IP addresses and user info
        UPDATE dbo.AuditLog
        SET IPAddress = 'REDACTED',
            UserName = 'DELETED_USER_' + CAST(AuditID AS VARCHAR(20)),
            OldValue = NULL,
            NewValue = NULL
        WHERE EventTime < @CutoffDate;
    END;

    -- Step 2: Delete overwritten records
    SET @SQL = N'DELETE FROM ' + QUOTENAME(@TableName) +
               N' WHERE EventTime < @CutoffDate';

    EXEC sp_executesql @SQL, N'@CutoffDate DATETIME2(7)', @CutoffDate;

    -- Step 3: Log deletion in audit log
    INSERT INTO dbo.AuditLog (EventType, UserName, ObjectType, ObjectName, Action, Success)
    VALUES ('DataDeletion', SUSER_SNAME(), 'Table', @TableName, 'SECURE_DELETE', 1);
END;
```

---

### Feature 5: Compliance Reporting (8 hours)

**What**: Pre-built compliance reports for SOC 2 audits

**Reports**:

**1. User Access Report**:
```sql
CREATE PROCEDURE dbo.usp_GetUserAccessReport
    @StartDate DATETIME2(7) = NULL,
    @EndDate DATETIME2(7) = NULL
AS
BEGIN
    IF @StartDate IS NULL SET @StartDate = DATEADD(DAY, -30, GETUTCDATE());
    IF @EndDate IS NULL SET @EndDate = GETUTCDATE();

    SELECT
        UserName,
        COUNT(*) AS TotalAccess,
        COUNT(DISTINCT CAST(EventTime AS DATE)) AS UniqueDays,
        SUM(CASE WHEN Success = 0 THEN 1 ELSE 0 END) AS FailedAttempts,
        MIN(EventTime) AS FirstAccess,
        MAX(EventTime) AS LastAccess
    FROM dbo.AuditLog
    WHERE EventTime BETWEEN @StartDate AND @EndDate
    GROUP BY UserName
    ORDER BY TotalAccess DESC;
END;
```

**2. Configuration Change Report**:
```sql
CREATE PROCEDURE dbo.usp_GetConfigurationChangeReport
    @StartDate DATETIME2(7) = NULL,
    @EndDate DATETIME2(7) = NULL
AS
BEGIN
    IF @StartDate IS NULL SET @StartDate = DATEADD(DAY, -90, GETUTCDATE());
    IF @EndDate IS NULL SET @EndDate = GETUTCDATE();

    SELECT
        EventTime,
        UserName,
        ObjectType,
        ObjectName,
        Action,
        OldValue,
        NewValue
    FROM dbo.AuditLog
    WHERE EventType = 'ConfigChange'
      AND EventTime BETWEEN @StartDate AND @EndDate
    ORDER BY EventTime DESC;
END;
```

**3. Data Access Report** (for GDPR compliance):
```sql
CREATE PROCEDURE dbo.usp_GetDataAccessReport
    @DataClassification VARCHAR(20) = 'Confidential',
    @StartDate DATETIME2(7) = NULL,
    @EndDate DATETIME2(7) = NULL
AS
BEGIN
    IF @StartDate IS NULL SET @StartDate = DATEADD(DAY, -30, GETUTCDATE());
    IF @EndDate IS NULL SET @EndDate = GETUTCDATE();

    SELECT
        EventTime,
        UserName,
        IPAddress,
        ObjectType,
        ObjectName,
        Action,
        DurationMs
    FROM dbo.AuditLog
    WHERE DataClassification = @DataClassification
      AND EventTime BETWEEN @StartDate AND @EndDate
    ORDER BY EventTime DESC;
END;
```

---

## Implementation Timeline (TDD Approach)

### Phase 1.5: SOC 2 Compliance (Total: 80 hours = 2 weeks)

**Week 1** (40 hours):
1. **Day 1-3**: Audit Logging (24 hours)
   - Write tests for AuditLog table
   - Write tests for audit triggers
   - Implement AuditLog schema
   - Implement audit triggers
   - Write tests for API audit middleware
   - Implement API audit middleware

2. **Day 4-5**: RBAC (16 hours)
   - Write tests for Roles/Permissions tables
   - Implement RBAC schema
   - Write tests for permission checks
   - Implement permission enforcement in API

**Week 2** (40 hours):
3. **Day 6-7**: Encryption (16 hours)
   - Write tests for TDE/column encryption
   - Implement encryption functions
   - Write tests for decryption
   - Implement secure key management

4. **Day 8-9**: Data Retention (12 hours)
   - Write tests for secure deletion
   - Implement retention policies
   - Write tests for GDPR right to erasure
   - Implement secure delete procedures

5. **Day 10**: Compliance Reporting (8 hours)
   - Write tests for compliance reports
   - Implement reporting procedures
   - Write tests for report accuracy
   - Integration testing

6. **Day 10 (cont)**: Documentation (8 hours)
   - SOC 2 compliance guide
   - Audit evidence collection procedures
   - Security policy documentation

---

## Competitive Advantage

### With SOC 2 Compliance Features

| Feature | Our Solution | Redgate | AWS RDS |
|---------|--------------|---------|---------|
| **Audit Logging** | ✅ Comprehensive | ⚠️ Limited | ✅ CloudTrail |
| **RBAC** | ✅ Granular | ⚠️ Basic | ✅ IAM |
| **Encryption at Rest** | ✅ TDE + Column | ⚠️ TDE only | ✅ TDE |
| **Data Retention** | ✅ GDPR-compliant | ❌ Manual | ⚠️ Basic |
| **Compliance Reports** | ✅ Pre-built | ❌ Manual | ⚠️ Custom queries |
| **Cost** | **$0-$1,500** | **$11,640** | **$27,000-$37,000** |

**Key Differentiator**: We'll be the **only open-source SQL Server monitoring solution with built-in SOC 2 compliance features**.

---

## Updated Roadmap

### Phase 1: Gap Closing ✅ COMPLETE
- Advanced alerting (4/5)
- Automated index maintenance (5/5)
- **Feature parity**: 92%

### Phase 1.5: SOC 2 Compliance ⏳ NEXT
- Audit logging
- RBAC
- Encryption
- Data retention
- Compliance reporting
- **Feature parity**: 95% (adds enterprise readiness)

### Phase 2: Killer Features
- Automated baseline + anomaly detection (alerting: 4/5 → 5/5)
- SQL Server health score
- Query performance impact analysis
- Multi-server query search
- **Feature parity**: 98%

---

## Summary

**Why SOC 2 Compliance Matters**:
1. **Enterprise Adoption**: Required by Fortune 500 companies
2. **Competitive Advantage**: Redgate lacks comprehensive compliance features
3. **Market Differentiation**: Only open-source solution with SOC 2 compliance
4. **Trust**: Demonstrates security commitment to potential customers

**Effort**: 80 hours (2 weeks)
**Impact**: Unlocks enterprise market, differentiates from competitors
**Recommendation**: Implement as Phase 1.5 before Phase 2 killer features
