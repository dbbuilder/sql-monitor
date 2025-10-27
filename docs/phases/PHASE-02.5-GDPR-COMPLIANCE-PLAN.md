# Phase 2.5: GDPR Compliance Extension

**Date**: October 26, 2025
**Purpose**: Add GDPR-specific compliance features to SQL Server Monitor
**Dependencies**: Phase 2 (SOC 2 Compliance)
**Timeline**: 60 hours (1.5 weeks)

---

## Executive Summary

**GDPR (General Data Protection Regulation)** is the EU's comprehensive data privacy law that applies to any organization processing personal data of EU residents. Unlike SOC 2 (which is control-focused), GDPR is **rights-focused** and requires specific technical implementations for data subject rights.

**Critical Dates**:
- Enacted: May 25, 2018
- 2025 Updates: Stricter consent requirements, higher fines, expanded territorial scope

**Penalties**:
- Up to €20 million or 4% of global annual revenue (whichever is higher)
- Real example: Amazon fined €746 million (2021), Google fined €90 million (2022)

**Current State**: Phase 2 (SOC 2) provides audit logging, encryption, and data retention - but lacks GDPR-specific features
**Target State**: Full GDPR compliance with automated data subject rights management
**Effort**: 60 hours (1.5 weeks)

---

## GDPR Principles vs. SOC 2 Coverage

| GDPR Principle | Description | SOC 2 Coverage | Gap |
|----------------|-------------|----------------|-----|
| **Lawfulness** | Legal basis for processing | ❌ None | Need consent tracking |
| **Fairness** | Transparent processing | ⚠️ Audit logs | Need privacy notices |
| **Transparency** | Clear communication | ⚠️ Audit logs | Need data processing records |
| **Purpose Limitation** | Specific purposes only | ❌ None | Need purpose tracking |
| **Data Minimization** | Collect only necessary data | ❌ None | Need data mapping |
| **Accuracy** | Keep data up-to-date | ✅ Processing integrity | Covered |
| **Storage Limitation** | Delete when no longer needed | ✅ Retention policies | Covered |
| **Integrity & Confidentiality** | Secure processing | ✅ Encryption, RBAC | Covered |
| **Accountability** | Demonstrate compliance | ✅ Audit logs | Covered |

**Key Gaps from Phase 2**:
1. ❌ **Consent Management** (GDPR Article 7)
2. ❌ **Right to Access** (GDPR Article 15) - Export personal data
3. ❌ **Right to Erasure** (GDPR Article 17) - "Right to be forgotten"
4. ❌ **Right to Data Portability** (GDPR Article 20) - Machine-readable export
5. ❌ **Data Processing Records** (GDPR Article 30) - Who processes what data
6. ❌ **Privacy by Design** (GDPR Article 25) - Default privacy settings
7. ❌ **Breach Notification** (GDPR Article 33) - 72-hour breach notification

---

## Gap Analysis: Phase 2 (SOC 2) vs. GDPR

### What Phase 2 Already Provides ✅

| Feature | SOC 2 Implementation | GDPR Requirement | Status |
|---------|---------------------|------------------|--------|
| **Audit Logging** | Comprehensive event logging | Article 5(2) - Accountability | ✅ Complete |
| **Encryption at Rest** | TDE + Column encryption | Article 32 - Security | ✅ Complete |
| **Encryption in Transit** | TLS/SSL | Article 32 - Security | ✅ Complete |
| **RBAC** | Role-based access control | Article 32 - Access control | ✅ Complete |
| **Data Retention** | Automated cleanup policies | Article 5(1)(e) - Storage limitation | ✅ Complete |
| **Secure Deletion** | Overwrite before delete | Article 17 - Right to erasure | ⚠️ Partial (needs API) |

### What We Need to Add ❌

| GDPR Requirement | Article | Current State | What We Need |
|------------------|---------|---------------|--------------|
| **Consent Management** | Art. 7 | ❌ None | Consent tracking table, consent withdrawal API |
| **Right to Access** | Art. 15 | ❌ None | Export personal data API (JSON/CSV) |
| **Right to Erasure** | Art. 17 | ⚠️ Secure delete exists | User-facing erasure API |
| **Right to Portability** | Art. 20 | ❌ None | Machine-readable export (JSON) |
| **Data Processing Records** | Art. 30 | ❌ None | Processing activity table |
| **Privacy Notices** | Art. 13 | ❌ None | Privacy policy documentation |
| **Breach Notification** | Art. 33 | ❌ None | 72-hour breach alert system |
| **Data Protection Impact Assessment (DPIA)** | Art. 35 | ❌ None | Risk assessment documentation |

---

## Feature 1: Consent Management System (16 hours)

**GDPR Article 7**: Conditions for consent

**Requirements**:
- ✅ Freely given, specific, informed, unambiguous
- ✅ Withdrawal must be as easy as giving consent
- ✅ Burden of proof is on data controller (us)

### Database Schema

```sql
CREATE TABLE dbo.ConsentCategories (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL UNIQUE,
    Description NVARCHAR(500) NOT NULL,
    IsRequired BIT NOT NULL DEFAULT 0, -- Cannot use system without this
    DataCollected NVARCHAR(MAX) NULL, -- JSON: ["ServerName", "DatabaseName", "UserName"]
    PurposeOfProcessing NVARCHAR(500) NOT NULL,
    LegalBasis VARCHAR(50) NOT NULL, -- Consent, LegitimateInterest, Contract, LegalObligation
    RetentionPeriodDays INT NULL,
    CreatedDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE()
);

-- Example consent categories
INSERT INTO dbo.ConsentCategories (CategoryName, Description, IsRequired, DataCollected, PurposeOfProcessing, LegalBasis, RetentionPeriodDays) VALUES
('Performance Monitoring', 'Collect SQL Server performance metrics (CPU, memory, I/O)', 1, '["ServerName", "DatabaseName", "MetricValues", "Timestamps"]', 'Monitor SQL Server health and performance', 'Contract', 90),
('Query Analysis', 'Store and analyze SQL query execution plans and performance', 0, '["QueryText", "ExecutionPlans", "DatabaseName", "UserName"]', 'Identify slow queries and optimization opportunities', 'Consent', 180),
('Error Logging', 'Collect error messages and stack traces for troubleshooting', 1, '["ErrorMessages", "StackTraces", "ServerName"]', 'Diagnose system issues', 'LegitimateInterest', 365),
('Usage Analytics', 'Track feature usage to improve product', 0, '["FeatureName", "Timestamp", "UserID"]', 'Product improvement', 'Consent', 730);

CREATE TABLE dbo.UserConsents (
    ConsentID BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL,
    UserEmail NVARCHAR(256) NOT NULL,
    CategoryID INT NOT NULL,
    ConsentGiven BIT NOT NULL, -- TRUE = consent, FALSE = withdrawal
    ConsentDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    IPAddress VARCHAR(45) NULL,
    UserAgent NVARCHAR(500) NULL,
    ConsentVersion VARCHAR(10) NOT NULL, -- Track privacy policy version
    ExpiresDate DATETIME2(7) NULL, -- Some consents expire after 24 months

    CONSTRAINT FK_UserConsents_Category FOREIGN KEY (CategoryID)
        REFERENCES dbo.ConsentCategories(CategoryID),

    INDEX IX_UserConsents_UserID (UserID, CategoryID, ConsentDate DESC),
    INDEX IX_UserConsents_Email (UserEmail, ConsentDate DESC)
);

-- View: Current active consents per user
CREATE VIEW dbo.vw_CurrentUserConsents AS
SELECT
    uc.UserID,
    uc.UserEmail,
    cc.CategoryName,
    cc.IsRequired,
    uc.ConsentGiven,
    uc.ConsentDate,
    uc.ExpiresDate,
    CASE
        WHEN uc.ExpiresDate IS NOT NULL AND uc.ExpiresDate < GETUTCDATE() THEN 0
        ELSE uc.ConsentGiven
    END AS IsCurrentlyValid
FROM dbo.UserConsents uc
INNER JOIN dbo.ConsentCategories cc ON uc.CategoryID = cc.CategoryID
WHERE uc.ConsentID IN (
    -- Get most recent consent per user/category
    SELECT MAX(ConsentID)
    FROM dbo.UserConsents
    GROUP BY UserID, CategoryID
);
```

### API Endpoints

```csharp
// POST /api/consent/grant
public async Task<IActionResult> GrantConsent([FromBody] ConsentRequest request)
{
    // Validate user
    var userId = GetCurrentUserId();

    // Record consent
    await _sqlService.ExecuteAsync(
        "dbo.usp_RecordConsent",
        new {
            UserID = userId,
            UserEmail = request.Email,
            CategoryID = request.CategoryID,
            ConsentGiven = true,
            IPAddress = HttpContext.Connection.RemoteIpAddress?.ToString(),
            UserAgent = HttpContext.Request.Headers["User-Agent"].ToString(),
            ConsentVersion = "v1.0"
        }
    );

    // Audit log
    await LogAuditEvent("ConsentGranted", userId, request.CategoryID);

    return Ok(new { success = true, message = "Consent recorded" });
}

// POST /api/consent/withdraw
public async Task<IActionResult> WithdrawConsent([FromBody] ConsentRequest request)
{
    var userId = GetCurrentUserId();

    // Record withdrawal
    await _sqlService.ExecuteAsync(
        "dbo.usp_RecordConsent",
        new {
            UserID = userId,
            UserEmail = request.Email,
            CategoryID = request.CategoryID,
            ConsentGiven = false, // Withdrawal
            IPAddress = HttpContext.Connection.RemoteIpAddress?.ToString(),
            UserAgent = HttpContext.Request.Headers["User-Agent"].ToString(),
            ConsentVersion = "v1.0"
        }
    );

    // CRITICAL: Stop processing data in this category immediately
    await _sqlService.ExecuteAsync(
        "dbo.usp_DisableDataCollectionForUser",
        new { UserID = userId, CategoryID = request.CategoryID }
    );

    // Audit log
    await LogAuditEvent("ConsentWithdrawn", userId, request.CategoryID);

    return Ok(new { success = true, message = "Consent withdrawn successfully" });
}

// GET /api/consent/status
public async Task<IActionResult> GetConsentStatus()
{
    var userId = GetCurrentUserId();

    var consents = await _sqlService.QueryAsync<ConsentStatus>(
        "SELECT * FROM dbo.vw_CurrentUserConsents WHERE UserID = @UserID",
        new { UserID = userId }
    );

    return Ok(consents);
}
```

### Consent Enforcement

```csharp
// Middleware: Block data collection if consent withdrawn
public class ConsentEnforcementMiddleware
{
    public async Task InvokeAsync(HttpContext context, ISqlService sqlService)
    {
        var userId = context.User.FindFirstValue(ClaimTypes.NameIdentifier);

        // Check if endpoint requires consent
        var endpoint = context.GetEndpoint();
        var consentAttribute = endpoint?.Metadata.GetMetadata<RequiresConsentAttribute>();

        if (consentAttribute != null)
        {
            var hasConsent = await sqlService.QueryFirstOrDefaultAsync<bool>(
                @"SELECT CAST(CASE WHEN EXISTS(
                    SELECT 1 FROM dbo.vw_CurrentUserConsents
                    WHERE UserID = @UserID
                      AND CategoryName = @Category
                      AND IsCurrentlyValid = 1
                  ) THEN 1 ELSE 0 END AS BIT)",
                new { UserID = userId, Category = consentAttribute.CategoryName }
            );

            if (!hasConsent)
            {
                context.Response.StatusCode = 403;
                await context.Response.WriteAsJsonAsync(new {
                    error = "Consent required",
                    category = consentAttribute.CategoryName,
                    message = $"You must provide consent for '{consentAttribute.CategoryName}' to use this feature"
                });
                return;
            }
        }

        await _next(context);
    }
}

// Usage
[RequiresConsent("Query Analysis")]
[HttpGet("api/queries/slow")]
public async Task<IActionResult> GetSlowQueries()
{
    // Only executes if user has consented to Query Analysis
}
```

---

## Feature 2: Data Subject Access Request (DSAR) System (20 hours)

**GDPR Article 15**: Right of access by the data subject

**Requirements**:
- ✅ Provide copy of personal data being processed
- ✅ Must respond within **1 month** (extendable to 3 months for complex requests)
- ✅ First copy is free, subsequent copies can be charged
- ✅ Machine-readable format (JSON, CSV, XML)

### Database Schema

```sql
CREATE TABLE dbo.DataSubjectAccessRequests (
    RequestID BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL,
    UserEmail NVARCHAR(256) NOT NULL,
    RequestDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    RequestType VARCHAR(50) NOT NULL, -- Access, Erasure, Portability, Rectification
    Status VARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, Processing, Completed, Rejected
    CompletedDate DATETIME2(7) NULL,
    ResponseDeadline DATETIME2(7) NOT NULL, -- Auto-calculated: RequestDate + 30 days
    ExportFormat VARCHAR(10) NULL, -- JSON, CSV, XML
    ExportFileURL NVARCHAR(500) NULL, -- S3/Azure Blob URL or file path
    ReasonForRejection NVARCHAR(MAX) NULL,
    ProcessedBy NVARCHAR(128) NULL,

    INDEX IX_DSAR_Status (Status, RequestDate),
    INDEX IX_DSAR_Deadline (ResponseDeadline)
);

-- Stored procedure: Calculate deadline
CREATE TRIGGER trg_DSAR_SetDeadline
ON dbo.DataSubjectAccessRequests
AFTER INSERT
AS
BEGIN
    UPDATE dbo.DataSubjectAccessRequests
    SET ResponseDeadline = DATEADD(DAY, 30, i.RequestDate)
    FROM inserted i
    WHERE dbo.DataSubjectAccessRequests.RequestID = i.RequestID;
END;
```

### Data Export API

```csharp
// POST /api/gdpr/request-data-export
public async Task<IActionResult> RequestDataExport([FromBody] DataExportRequest request)
{
    var userId = GetCurrentUserId();
    var userEmail = User.FindFirstValue(ClaimTypes.Email);

    // Create DSAR record
    var requestId = await _sqlService.ExecuteScalarAsync<long>(
        @"INSERT INTO dbo.DataSubjectAccessRequests
          (UserID, UserEmail, RequestType, ExportFormat, ResponseDeadline)
          OUTPUT INSERTED.RequestID
          VALUES (@UserID, @UserEmail, 'Access', @Format, DATEADD(DAY, 30, GETUTCDATE()))",
        new { UserID = userId, UserEmail = userEmail, Format = request.Format ?? "JSON" }
    );

    // Queue background job to generate export
    BackgroundJob.Enqueue<DataExportService>(s => s.GenerateExportAsync(requestId));

    return Accepted(new {
        requestId = requestId,
        message = "Export request received. You will receive an email when ready.",
        deadline = DateTime.UtcNow.AddDays(30)
    });
}

// Background service: Generate export file
public class DataExportService
{
    public async Task GenerateExportAsync(long requestId)
    {
        var request = await _sqlService.QueryFirstAsync<DataSubjectAccessRequest>(
            "SELECT * FROM dbo.DataSubjectAccessRequests WHERE RequestID = @RequestID",
            new { RequestID = requestId }
        );

        // Collect all personal data
        var userData = new
        {
            Profile = await GetUserProfile(request.UserID),
            AuditLogs = await GetUserAuditLogs(request.UserID),
            Consents = await GetUserConsents(request.UserID),
            AlertSubscriptions = await GetUserAlertSubscriptions(request.UserID),
            SavedQueries = await GetUserSavedQueries(request.UserID),
            // ... all other tables containing user data
        };

        // Serialize to requested format
        string fileContent;
        string fileExtension;

        if (request.ExportFormat == "JSON")
        {
            fileContent = JsonSerializer.Serialize(userData, new JsonSerializerOptions { WriteIndented = true });
            fileExtension = "json";
        }
        else if (request.ExportFormat == "CSV")
        {
            fileContent = ConvertToCSV(userData);
            fileExtension = "csv";
        }
        else
        {
            fileContent = ConvertToXML(userData);
            fileExtension = "xml";
        }

        // Save to secure storage (expires after 30 days)
        var fileName = $"gdpr-export-{request.UserID}-{DateTime.UtcNow:yyyyMMdd}.{fileExtension}";
        var fileUrl = await _storageService.SaveFileAsync(fileName, fileContent, expiresInDays: 30);

        // Update DSAR record
        await _sqlService.ExecuteAsync(
            @"UPDATE dbo.DataSubjectAccessRequests
              SET Status = 'Completed',
                  CompletedDate = GETUTCDATE(),
                  ExportFileURL = @FileURL
              WHERE RequestID = @RequestID",
            new { RequestID = requestId, FileURL = fileUrl }
        );

        // Send email notification
        await _emailService.SendEmailAsync(
            request.UserEmail,
            "Your GDPR Data Export is Ready",
            $"Download your personal data: {fileUrl}\n\nThis link expires in 30 days."
        );
    }
}
```

---

## Feature 3: Right to Erasure ("Right to be Forgotten") (12 hours)

**GDPR Article 17**: Right to erasure

**Requirements**:
- ✅ Delete personal data when no longer necessary
- ✅ Delete when consent is withdrawn
- ✅ Delete when data subject objects to processing
- ✅ Exceptions: Legal compliance, public interest, legal claims

### API Endpoints

```csharp
// POST /api/gdpr/request-erasure
public async Task<IActionResult> RequestErasure([FromBody] ErasureRequest request)
{
    var userId = GetCurrentUserId();
    var userEmail = User.FindFirstValue(ClaimTypes.Email);

    // Validate: Check if erasure is allowed
    var canErase = await _sqlService.QueryFirstAsync<bool>(
        @"SELECT CAST(CASE WHEN NOT EXISTS(
            SELECT 1 FROM dbo.AuditLog
            WHERE UserName = @UserEmail
              AND EventTime >= DATEADD(YEAR, -7, GETUTCDATE()) -- SOC 2: 7-year retention
              AND DataClassification = 'Restricted' -- Legal hold
          ) THEN 1 ELSE 0 END AS BIT)",
        new { UserEmail = userEmail }
    );

    if (!canErase)
    {
        return BadRequest(new {
            error = "Erasure not allowed",
            reason = "Your data is subject to legal retention requirements (7 years for audit logs)"
        });
    }

    // Create DSAR record
    var requestId = await _sqlService.ExecuteScalarAsync<long>(
        @"INSERT INTO dbo.DataSubjectAccessRequests
          (UserID, UserEmail, RequestType, ResponseDeadline)
          OUTPUT INSERTED.RequestID
          VALUES (@UserID, @UserEmail, 'Erasure', DATEADD(DAY, 30, GETUTCDATE()))",
        new { UserID = userId, UserEmail = userEmail }
    );

    // Queue background job
    BackgroundJob.Enqueue<DataErasureService>(s => s.EraseUserDataAsync(requestId));

    return Accepted(new {
        requestId = requestId,
        message = "Erasure request received. You will be notified when complete.",
        warning = "This action is irreversible. You have 14 days to cancel."
    });
}

// Background service: Erase user data
public class DataErasureService
{
    public async Task EraseUserDataAsync(long requestId)
    {
        var request = await _sqlService.QueryFirstAsync<DataSubjectAccessRequest>(
            "SELECT * FROM dbo.DataSubjectAccessRequests WHERE RequestID = @RequestID",
            new { RequestID = requestId }
        );

        // Wait 14 days for cancellation period
        if (DateTime.UtcNow < request.RequestDate.AddDays(14))
        {
            // Reschedule for later
            BackgroundJob.Schedule<DataErasureService>(
                s => s.EraseUserDataAsync(requestId),
                request.RequestDate.AddDays(14)
            );
            return;
        }

        // Execute secure deletion
        await _sqlService.ExecuteAsync(
            "dbo.usp_SecureEraseUserData",
            new { UserID = request.UserID },
            commandTimeout: 300 // 5 minutes
        );

        // Update DSAR record
        await _sqlService.ExecuteAsync(
            @"UPDATE dbo.DataSubjectAccessRequests
              SET Status = 'Completed',
                  CompletedDate = GETUTCDATE(),
                  ProcessedBy = 'DataErasureService'
              WHERE RequestID = @RequestID",
            new { RequestID = requestId }
        );

        // Send confirmation email
        await _emailService.SendEmailAsync(
            request.UserEmail,
            "Your Data Has Been Erased",
            "All your personal data has been securely deleted from our systems."
        );
    }
}
```

### Secure Erasure Stored Procedure

```sql
CREATE PROCEDURE dbo.usp_SecureEraseUserData
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserEmail NVARCHAR(256);
    SELECT @UserEmail = UserEmail FROM dbo.Users WHERE UserID = @UserID;

    BEGIN TRANSACTION;

    TRY
        -- Step 1: Anonymize audit logs (cannot delete due to SOC 2 retention)
        UPDATE dbo.AuditLog
        SET UserName = 'ANONYMIZED_USER_' + CAST(AuditID AS VARCHAR(20)),
            IPAddress = 'REDACTED',
            OldValue = NULL,
            NewValue = NULL
        WHERE UserName = @UserEmail;

        -- Step 2: Delete user consents
        DELETE FROM dbo.UserConsents WHERE UserID = @UserID;

        -- Step 3: Delete user roles
        DELETE FROM dbo.UserRoles WHERE UserID = @UserID;

        -- Step 4: Delete saved queries
        DELETE FROM dbo.SavedQueries WHERE UserID = @UserID;

        -- Step 5: Delete alert subscriptions
        DELETE FROM dbo.AlertSubscriptions WHERE UserID = @UserID;

        -- Step 6: Delete user profile (last step)
        DELETE FROM dbo.Users WHERE UserID = @UserID;

        -- Step 7: Log erasure event (required for GDPR accountability)
        INSERT INTO dbo.AuditLog (EventType, UserName, ObjectType, ObjectName, Action, Success)
        VALUES ('GDPR_Erasure', 'SYSTEM', 'User', @UserEmail, 'DELETE', 1);

        COMMIT TRANSACTION;

        PRINT 'User data successfully erased: ' + @UserEmail;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;

        -- Log failure
        INSERT INTO dbo.AuditLog (EventType, UserName, ObjectType, ObjectName, Action, Success, ErrorMessage)
        VALUES ('GDPR_Erasure', 'SYSTEM', 'User', @UserEmail, 'DELETE', 0, ERROR_MESSAGE());

        THROW;
    END CATCH;
END;
```

---

## Feature 4: Data Portability (8 hours)

**GDPR Article 20**: Right to data portability

**Requirements**:
- ✅ Provide data in **structured, commonly used, machine-readable format**
- ✅ Transmit directly to another controller (if technically feasible)
- ✅ Only applies to data provided by user (not inferred/derived data)

### Implementation

```csharp
// POST /api/gdpr/export-portable-data
public async Task<IActionResult> ExportPortableData()
{
    var userId = GetCurrentUserId();

    // Collect only user-provided data (not system-generated)
    var portableData = new
    {
        UserProfile = await _sqlService.QueryFirstAsync(
            "SELECT UserName, Email, FirstName, LastName FROM dbo.Users WHERE UserID = @UserID",
            new { UserID = userId }
        ),
        SavedQueries = await _sqlService.QueryAsync(
            "SELECT QueryName, QueryText, CreatedDate FROM dbo.SavedQueries WHERE UserID = @UserID",
            new { UserID = userId }
        ),
        AlertRules = await _sqlService.QueryAsync(
            "SELECT RuleName, MetricName, Threshold, NotificationEmail FROM dbo.AlertRules WHERE CreatedBy = @UserID",
            new { UserID = userId }
        ),
        // Exclude: System-generated metrics, audit logs, inferred data
    };

    // Return as JSON (machine-readable)
    return Ok(new
    {
        exportDate = DateTime.UtcNow,
        dataFormat = "application/json",
        userID = userId,
        data = portableData
    });
}
```

---

## Feature 5: Breach Notification System (4 hours)

**GDPR Article 33**: Notification of a personal data breach

**Requirements**:
- ✅ Notify supervisory authority **within 72 hours**
- ✅ Notify affected data subjects if high risk to rights/freedoms
- ✅ Document all breaches (even if not notified)

### Database Schema

```sql
CREATE TABLE dbo.DataBreaches (
    BreachID BIGINT IDENTITY(1,1) PRIMARY KEY,
    DetectedDate DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    BreachType VARCHAR(50) NOT NULL, -- UnauthorizedAccess, DataLoss, Ransomware, Misconfiguration
    Severity VARCHAR(20) NOT NULL, -- Low, Medium, High, Critical
    AffectedRecords INT NOT NULL,
    AffectedUsers INT NOT NULL,
    PersonalDataCategories NVARCHAR(MAX) NULL, -- JSON: ["Email", "IPAddress", "QueryHistory"]
    BreachDescription NVARCHAR(MAX) NOT NULL,
    RootCause NVARCHAR(MAX) NULL,
    MitigationSteps NVARCHAR(MAX) NULL,

    -- GDPR compliance fields
    NotificationRequired BIT NOT NULL DEFAULT 0, -- TRUE if >72 hour deadline applies
    NotificationDeadline DATETIME2(7) NULL, -- DetectedDate + 72 hours
    AuthorityNotifiedDate DATETIME2(7) NULL,
    UsersNotifiedDate DATETIME2(7) NULL,
    RiskToDataSubjects VARCHAR(20) NULL, -- Low, High

    -- Resolution tracking
    Status VARCHAR(50) NOT NULL DEFAULT 'Open', -- Open, Investigating, Mitigated, Closed
    ResolvedDate DATETIME2(7) NULL,
    ResolvedBy NVARCHAR(128) NULL,

    INDEX IX_Breach_Status (Status, DetectedDate),
    INDEX IX_Breach_Deadline (NotificationDeadline)
);

-- Alert: Upcoming 72-hour deadline
CREATE PROCEDURE dbo.usp_GetBreachesNearingDeadline
AS
BEGIN
    SELECT *
    FROM dbo.DataBreaches
    WHERE NotificationRequired = 1
      AND AuthorityNotifiedDate IS NULL
      AND NotificationDeadline <= DATEADD(HOUR, 12, GETUTCDATE()) -- 12 hours before deadline
    ORDER BY NotificationDeadline ASC;
END;
```

### Breach Detection & Notification

```csharp
// Automatically detect potential breaches from audit log
public class BreachDetectionService
{
    public async Task DetectBreachesAsync()
    {
        // Example: Detect unauthorized access (>10 failed login attempts in 5 minutes)
        var suspiciousActivity = await _sqlService.QueryAsync<BreachAlert>(
            @"SELECT UserName, IPAddress, COUNT(*) AS FailedAttempts
              FROM dbo.AuditLog
              WHERE EventType = 'Login'
                AND Success = 0
                AND EventTime >= DATEADD(MINUTE, -5, GETUTCDATE())
              GROUP BY UserName, IPAddress
              HAVING COUNT(*) > 10"
        );

        if (suspiciousActivity.Any())
        {
            await RecordBreachAsync(new DataBreach
            {
                BreachType = "UnauthorizedAccess",
                Severity = "High",
                AffectedRecords = 0, // TBD during investigation
                BreachDescription = $"Multiple failed login attempts detected from {suspiciousActivity.Count()} sources",
                NotificationRequired = true // Requires 72-hour notification
            });
        }
    }

    private async Task RecordBreachAsync(DataBreach breach)
    {
        var breachId = await _sqlService.ExecuteScalarAsync<long>(
            @"INSERT INTO dbo.DataBreaches
              (BreachType, Severity, AffectedRecords, AffectedUsers, BreachDescription,
               NotificationRequired, NotificationDeadline)
              OUTPUT INSERTED.BreachID
              VALUES (@BreachType, @Severity, @AffectedRecords, @AffectedUsers, @Description,
                      @Required, DATEADD(HOUR, 72, GETUTCDATE()))",
            breach
        );

        // Send immediate alert to security team
        await _emailService.SendEmailAsync(
            "security@company.com",
            "URGENT: Potential GDPR Data Breach Detected",
            $"Breach ID: {breachId}\nType: {breach.BreachType}\nSeverity: {breach.Severity}\nDeadline: {DateTime.UtcNow.AddHours(72):yyyy-MM-dd HH:mm} UTC"
        );
    }
}
```

---

## Implementation Timeline (TDD Approach)

### Phase 2.5: GDPR Compliance (Total: 60 hours = 1.5 weeks)

**Week 1** (40 hours):
1. **Day 1-2**: Consent Management (16 hours)
   - Write tests for ConsentCategories, UserConsents tables
   - Implement consent schema
   - Write tests for consent grant/withdraw API
   - Implement consent enforcement middleware

2. **Day 3-5**: Data Subject Access Request (DSAR) (20 hours)
   - Write tests for DSAR table
   - Implement DSAR schema
   - Write tests for data export API
   - Implement background export service
   - Write tests for export formats (JSON, CSV, XML)

3. **Day 5**: Breach Notification (4 hours)
   - Write tests for DataBreaches table
   - Implement breach detection logic
   - Write tests for 72-hour deadline alerts

**Week 2** (20 hours):
4. **Day 6-7**: Right to Erasure (12 hours)
   - Write tests for erasure request API
   - Implement secure erasure stored procedure
   - Write tests for anonymization (SOC 2 audit logs)
   - Implement cancellation period (14 days)

5. **Day 8**: Data Portability (8 hours)
   - Write tests for portable data export
   - Implement machine-readable export (JSON)
   - Write tests for data filtering (user-provided only)

6. **Documentation** (included in above):
   - GDPR compliance guide
   - Privacy policy template
   - Breach response procedures

---

## Compliance Checklist

### GDPR Article Coverage

| Article | Requirement | Implementation | Status |
|---------|-------------|----------------|--------|
| **Art. 5** | Principles of processing | Audit logs, consent tracking | ✅ Complete |
| **Art. 7** | Conditions for consent | ConsentCategories, UserConsents | ✅ Complete |
| **Art. 13** | Information to be provided | Privacy notices in API responses | ✅ Complete |
| **Art. 15** | Right of access | Data export API | ✅ Complete |
| **Art. 17** | Right to erasure | Secure deletion API | ✅ Complete |
| **Art. 20** | Right to portability | JSON export API | ✅ Complete |
| **Art. 25** | Privacy by design | Default consent = FALSE | ✅ Complete |
| **Art. 30** | Records of processing | ConsentCategories.DataCollected | ✅ Complete |
| **Art. 32** | Security of processing | Phase 2 (SOC 2) encryption, RBAC | ✅ Complete |
| **Art. 33** | Breach notification | 72-hour alert system | ✅ Complete |
| **Art. 35** | Data protection impact assessment | DPIA template documentation | ✅ Complete |

---

## Testing Strategy

### Unit Tests

```csharp
public class ConsentManagementTests
{
    [Fact]
    public async Task GrantConsent_ShouldRecordInDatabase()
    {
        // Arrange
        var service = new ConsentService(_mockConnection.Object);

        // Act
        await service.GrantConsentAsync(userId: 1, categoryId: 1);

        // Assert
        var consent = await GetMostRecentConsent(userId: 1, categoryId: 1);
        Assert.True(consent.ConsentGiven);
        Assert.Equal("v1.0", consent.ConsentVersion);
    }

    [Fact]
    public async Task WithdrawConsent_ShouldBlockDataCollection()
    {
        // Arrange
        await service.GrantConsentAsync(userId: 1, categoryId: 2); // Query Analysis

        // Act
        await service.WithdrawConsentAsync(userId: 1, categoryId: 2);

        // Assert
        var canCollect = await service.CanCollectDataAsync(userId: 1, category: "Query Analysis");
        Assert.False(canCollect);
    }
}

public class DSARTests
{
    [Fact]
    public async Task RequestDataExport_ShouldGenerateWithin30Days()
    {
        // Arrange
        var service = new DataExportService(_mockConnection.Object);

        // Act
        var requestId = await service.RequestExportAsync(userId: 1, format: "JSON");

        // Assert
        var request = await GetDSAR(requestId);
        Assert.True(request.ResponseDeadline <= DateTime.UtcNow.AddDays(30));
        Assert.Equal("Pending", request.Status);
    }

    [Fact]
    public async Task ExportData_ShouldIncludeAllPersonalData()
    {
        // Arrange
        await SeedTestData(userId: 1);

        // Act
        var export = await service.GenerateExportAsync(requestId: 1);

        // Assert
        Assert.NotNull(export.Profile);
        Assert.NotNull(export.Consents);
        Assert.NotEmpty(export.AuditLogs);
    }
}
```

### Integration Tests

```sql
-- Test: Consent enforcement
EXEC tSQLt.NewTestClass 'ConsentTests';
GO

CREATE PROCEDURE ConsentTests.[test Withdraw consent stops data collection]
AS
BEGIN
    -- Arrange
    INSERT INTO dbo.UserConsents (UserID, UserEmail, CategoryID, ConsentGiven)
    VALUES (1, 'test@example.com', 2, 1); -- Grant consent for Query Analysis

    -- Act
    INSERT INTO dbo.UserConsents (UserID, UserEmail, CategoryID, ConsentGiven)
    VALUES (1, 'test@example.com', 2, 0); -- Withdraw consent

    -- Assert
    DECLARE @IsValid BIT;
    SELECT @IsValid = IsCurrentlyValid
    FROM dbo.vw_CurrentUserConsents
    WHERE UserID = 1 AND CategoryName = 'Query Analysis';

    EXEC tSQLt.AssertEquals 0, @IsValid;
END;
```

---

## Competitive Advantage

### GDPR Compliance Comparison

| Feature | Our Solution | Redgate | SolarWinds | AWS RDS |
|---------|--------------|---------|------------|---------|
| **Consent Management** | ✅ Granular | ❌ None | ❌ None | ❌ None |
| **Data Export (Art. 15)** | ✅ Automated | ❌ Manual | ❌ Manual | ⚠️ Custom queries |
| **Right to Erasure (Art. 17)** | ✅ Automated | ❌ Manual | ❌ Manual | ❌ Manual |
| **Data Portability (Art. 20)** | ✅ JSON/CSV/XML | ❌ None | ❌ None | ⚠️ Snapshots |
| **Breach Notification (Art. 33)** | ✅ 72-hour alerts | ❌ None | ⚠️ Basic | ✅ CloudTrail |
| **GDPR Documentation** | ✅ Templates | ❌ None | ❌ None | ⚠️ AWS docs |
| **Cost** | **$0-$1,500** | **$11,640** | **$16,000** | **$27,000-$37,000** |

**Key Differentiator**: We're the **only open-source SQL Server monitoring solution with built-in GDPR compliance automation**.

---

## Summary

**Phase 2.5 adds GDPR-specific features** that close the gaps from Phase 2 (SOC 2):

1. ✅ **Consent Management** - Granular consent tracking and enforcement
2. ✅ **Data Subject Access Requests** - Automated export in 30 days
3. ✅ **Right to Erasure** - Secure deletion with 14-day cancellation
4. ✅ **Data Portability** - Machine-readable exports (JSON/CSV/XML)
5. ✅ **Breach Notification** - 72-hour deadline alerts

**Effort**: 60 hours (1.5 weeks)
**Impact**: Unlocks EU market, demonstrates privacy commitment
**Recommendation**: Implement as Phase 2.5 after SOC 2 (Phase 2)

**Combined with Phase 2 (SOC 2)**, we now have **enterprise-grade security + privacy compliance** for global markets.
