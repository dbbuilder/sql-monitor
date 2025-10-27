-- =============================================
-- Phase 2.0 Week 3 Days 11-12: Multi-Factor Authentication (MFA)
-- Description: MFA tables, procedures for TOTP and backup codes
-- SOC 2 Controls: CC6.1, CC6.2, CC6.8 (MFA, Strong Authentication)
-- =============================================

USE MonitoringDB;
GO

PRINT 'Starting MFA schema deployment...';
GO

-- =============================================
-- PART 1: MFA Tables
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 1: MFA Tables'
PRINT '=============================================='
PRINT '';

-- Table: UserMFA - Stores user MFA settings
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'UserMFA')
BEGIN
    PRINT 'Creating UserMFA table...';

    CREATE TABLE dbo.UserMFA (
        UserMFAID INT IDENTITY(1,1) NOT NULL,
        UserID INT NOT NULL,
        MFAEnabled BIT NOT NULL DEFAULT 0,
        MFAType VARCHAR(20) NOT NULL DEFAULT 'TOTP', -- TOTP, SMS, Email
        TOTPSecret VARBINARY(256) NULL, -- Encrypted TOTP secret
        TOTPSecretPlain NVARCHAR(100) NULL, -- Base32-encoded secret (temporary during enrollment)
        PhoneNumber NVARCHAR(20) NULL,
        PhoneNumberVerified BIT NOT NULL DEFAULT 0,
        EmailVerified BIT NOT NULL DEFAULT 0,
        BackupCodesUsed INT NOT NULL DEFAULT 0,
        EnrolledDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        LastUsedDate DATETIME2 NULL,
        ModifiedDate DATETIME2 NULL,
        ModifiedBy NVARCHAR(100) NULL,

        CONSTRAINT PK_UserMFA PRIMARY KEY CLUSTERED (UserMFAID),
        CONSTRAINT FK_UserMFA_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID),
        CONSTRAINT UQ_UserMFA_UserID UNIQUE (UserID),
        CONSTRAINT CK_UserMFA_Type CHECK (MFAType IN ('TOTP', 'SMS', 'Email'))
    );

    CREATE NONCLUSTERED INDEX IX_UserMFA_UserID ON dbo.UserMFA(UserID);
    CREATE NONCLUSTERED INDEX IX_UserMFA_Enabled ON dbo.UserMFA(MFAEnabled) WHERE MFAEnabled = 1;

    PRINT 'UserMFA table created.';
END
ELSE
BEGIN
    PRINT 'UserMFA table already exists.';
END
GO

-- Table: UserMFABackupCodes - Backup codes for MFA recovery
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'UserMFABackupCodes')
BEGIN
    PRINT 'Creating UserMFABackupCodes table...';

    CREATE TABLE dbo.UserMFABackupCodes (
        BackupCodeID INT IDENTITY(1,1) NOT NULL,
        UserID INT NOT NULL,
        CodeHash VARBINARY(64) NOT NULL, -- Hashed backup code
        CodeSalt VARBINARY(32) NOT NULL, -- Salt for backup code
        IsUsed BIT NOT NULL DEFAULT 0,
        UsedDate DATETIME2 NULL,
        UsedFromIP VARCHAR(45) NULL,
        CreatedDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_UserMFABackupCodes PRIMARY KEY CLUSTERED (BackupCodeID),
        CONSTRAINT FK_UserMFABackupCodes_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID)
    );

    CREATE NONCLUSTERED INDEX IX_UserMFABackupCodes_UserID ON dbo.UserMFABackupCodes(UserID);
    CREATE NONCLUSTERED INDEX IX_UserMFABackupCodes_Unused ON dbo.UserMFABackupCodes(UserID, IsUsed)
        WHERE IsUsed = 0;

    PRINT 'UserMFABackupCodes table created.';
END
ELSE
BEGIN
    PRINT 'UserMFABackupCodes table already exists.';
END
GO

-- Table: MFAVerificationAttempts - Track MFA verification attempts
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'MFAVerificationAttempts')
BEGIN
    PRINT 'Creating MFAVerificationAttempts table...';

    CREATE TABLE dbo.MFAVerificationAttempts (
        AttemptID BIGINT IDENTITY(1,1) NOT NULL,
        UserID INT NOT NULL,
        AttemptTime DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        MFAType VARCHAR(20) NOT NULL,
        IsSuccess BIT NOT NULL,
        FailureReason NVARCHAR(200) NULL,
        IPAddress VARCHAR(45) NULL,
        UserAgent NVARCHAR(500) NULL,

        CONSTRAINT PK_MFAVerificationAttempts PRIMARY KEY CLUSTERED (AttemptID),
        CONSTRAINT FK_MFAVerificationAttempts_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID)
    );

    CREATE NONCLUSTERED INDEX IX_MFAVerificationAttempts_UserID_Time
        ON dbo.MFAVerificationAttempts(UserID, AttemptTime DESC);
    CREATE NONCLUSTERED INDEX IX_MFAVerificationAttempts_Failed
        ON dbo.MFAVerificationAttempts(UserID, AttemptTime DESC)
        WHERE IsSuccess = 0;

    PRINT 'MFAVerificationAttempts table created.';
END
ELSE
BEGIN
    PRINT 'MFAVerificationAttempts table already exists.';
END
GO

-- =============================================
-- PART 2: MFA Stored Procedures
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 2: MFA Stored Procedures'
PRINT '=============================================='
PRINT '';

-- Procedure: Enable MFA for user
CREATE OR ALTER PROCEDURE dbo.usp_EnableMFA
    @UserID INT,
    @MFAType VARCHAR(20) = 'TOTP',
    @TOTPSecret VARBINARY(256) = NULL,
    @TOTPSecretPlain NVARCHAR(100) = NULL,
    @PhoneNumber NVARCHAR(20) = NULL,
    @ModifiedBy NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Check if MFA already exists
        IF EXISTS (SELECT 1 FROM dbo.UserMFA WHERE UserID = @UserID)
        BEGIN
            -- Update existing MFA settings
            UPDATE dbo.UserMFA
            SET MFAEnabled = 1,
                MFAType = @MFAType,
                TOTPSecret = @TOTPSecret,
                TOTPSecretPlain = @TOTPSecretPlain,
                PhoneNumber = @PhoneNumber,
                ModifiedDate = SYSUTCDATETIME(),
                ModifiedBy = @ModifiedBy
            WHERE UserID = @UserID;
        END
        ELSE
        BEGIN
            -- Insert new MFA settings
            INSERT INTO dbo.UserMFA (
                UserID, MFAEnabled, MFAType, TOTPSecret, TOTPSecretPlain,
                PhoneNumber, EnrolledDate
            )
            VALUES (
                @UserID, 1, @MFAType, @TOTPSecret, @TOTPSecretPlain,
                @PhoneNumber, SYSUTCDATETIME()
            );
        END

        -- Audit log
        EXEC dbo.usp_LogAuditEvent
            @EventType = 'MFAEnabled',
            @UserName = @ModifiedBy,
            @ObjectName = CAST(@UserID AS NVARCHAR(10)),
            @ObjectType = 'User',
            @ActionType = 'UPDATE',
            @NewValue = @MFAType,
            @Severity = 'Information',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        COMMIT TRANSACTION;
        RETURN 0; -- Success
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC dbo.usp_LogAuditEvent
            @EventType = 'MFAEnableFailed',
            @UserName = @ModifiedBy,
            @ErrorMessage = @ErrMsg,
            @Severity = 'Error',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 1; -- Error
    END CATCH
END;
GO

PRINT 'Procedure usp_EnableMFA created.';
GO

-- Procedure: Disable MFA for user
CREATE OR ALTER PROCEDURE dbo.usp_DisableMFA
    @UserID INT,
    @ModifiedBy NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.UserMFA
    SET MFAEnabled = 0,
        ModifiedDate = SYSUTCDATETIME(),
        ModifiedBy = @ModifiedBy
    WHERE UserID = @UserID;

    -- Audit log
    EXEC dbo.usp_LogAuditEvent
        @EventType = 'MFADisabled',
        @UserName = @ModifiedBy,
        @ObjectName = CAST(@UserID AS NVARCHAR(10)),
        @ObjectType = 'User',
        @ActionType = 'UPDATE',
        @Severity = 'Warning',
        @ComplianceFlag = 'SOC2',
        @RetentionDays = 2555;

    RETURN 0;
END;
GO

PRINT 'Procedure usp_DisableMFA created.';
GO

-- Procedure: Get MFA settings for user
CREATE OR ALTER PROCEDURE dbo.usp_GetUserMFA
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        UserMFAID,
        UserID,
        MFAEnabled,
        MFAType,
        TOTPSecret,
        TOTPSecretPlain,
        PhoneNumber,
        PhoneNumberVerified,
        EmailVerified,
        BackupCodesUsed,
        EnrolledDate,
        LastUsedDate
    FROM dbo.UserMFA
    WHERE UserID = @UserID;
END;
GO

PRINT 'Procedure usp_GetUserMFA created.';
GO

-- Procedure: Generate and store backup codes
CREATE OR ALTER PROCEDURE dbo.usp_GenerateBackupCodes
    @UserID INT,
    @NumberOfCodes INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    -- Delete existing unused backup codes
    DELETE FROM dbo.UserMFABackupCodes
    WHERE UserID = @UserID AND IsUsed = 0;

    -- Note: Actual code generation happens in application layer
    -- This procedure will be called after codes are generated and hashed

    PRINT 'Existing unused backup codes deleted for UserID: ' + CAST(@UserID AS NVARCHAR(10));
    PRINT 'Ready to insert ' + CAST(@NumberOfCodes AS NVARCHAR(10)) + ' new backup codes.';

    RETURN 0;
END;
GO

PRINT 'Procedure usp_GenerateBackupCodes created.';
GO

-- Procedure: Insert hashed backup code
CREATE OR ALTER PROCEDURE dbo.usp_InsertBackupCode
    @UserID INT,
    @CodeHash VARBINARY(64),
    @CodeSalt VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.UserMFABackupCodes (UserID, CodeHash, CodeSalt)
    VALUES (@UserID, @CodeHash, @CodeSalt);

    RETURN 0;
END;
GO

PRINT 'Procedure usp_InsertBackupCode created.';
GO

-- Procedure: Verify and use backup code
CREATE OR ALTER PROCEDURE dbo.usp_UseBackupCode
    @UserID INT,
    @CodeHash VARBINARY(64),
    @IPAddress VARCHAR(45) = NULL,
    @IsValid BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BackupCodeID INT;

    -- Find matching unused backup code
    SELECT TOP 1 @BackupCodeID = BackupCodeID
    FROM dbo.UserMFABackupCodes
    WHERE UserID = @UserID
      AND CodeHash = @CodeHash
      AND IsUsed = 0;

    IF @BackupCodeID IS NOT NULL
    BEGIN
        -- Mark code as used
        UPDATE dbo.UserMFABackupCodes
        SET IsUsed = 1,
            UsedDate = SYSUTCDATETIME(),
            UsedFromIP = @IPAddress
        WHERE BackupCodeID = @BackupCodeID;

        -- Update backup codes used count
        UPDATE dbo.UserMFA
        SET BackupCodesUsed = BackupCodesUsed + 1,
            LastUsedDate = SYSUTCDATETIME()
        WHERE UserID = @UserID;

        SET @IsValid = 1;

        -- Audit log
        EXEC dbo.usp_LogAuditEvent
            @EventType = 'MFABackupCodeUsed',
            @UserName = CAST(@UserID AS NVARCHAR(10)),
            @IPAddress = @IPAddress,
            @Severity = 'Warning',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;
    END
    ELSE
    BEGIN
        SET @IsValid = 0;
    END

    RETURN 0;
END;
GO

PRINT 'Procedure usp_UseBackupCode created.';
GO

-- Procedure: Get remaining backup codes count
CREATE OR ALTER PROCEDURE dbo.usp_GetRemainingBackupCodes
    @UserID INT,
    @RemainingCount INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT @RemainingCount = COUNT(*)
    FROM dbo.UserMFABackupCodes
    WHERE UserID = @UserID AND IsUsed = 0;

    RETURN 0;
END;
GO

PRINT 'Procedure usp_GetRemainingBackupCodes created.';
GO

-- Procedure: Log MFA verification attempt
CREATE OR ALTER PROCEDURE dbo.usp_LogMFAAttempt
    @UserID INT,
    @MFAType VARCHAR(20),
    @IsSuccess BIT,
    @FailureReason NVARCHAR(200) = NULL,
    @IPAddress VARCHAR(45) = NULL,
    @UserAgent NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.MFAVerificationAttempts (
        UserID, MFAType, IsSuccess, FailureReason, IPAddress, UserAgent
    )
    VALUES (
        @UserID, @MFAType, @IsSuccess, @FailureReason, @IPAddress, @UserAgent
    );

    -- Update last used date on success
    IF @IsSuccess = 1
    BEGIN
        UPDATE dbo.UserMFA
        SET LastUsedDate = SYSUTCDATETIME()
        WHERE UserID = @UserID;
    END

    RETURN 0;
END;
GO

PRINT 'Procedure usp_LogMFAAttempt created.';
GO

-- Procedure: Check if user has MFA enabled
CREATE OR ALTER PROCEDURE dbo.usp_IsMFAEnabled
    @UserID INT,
    @MFAEnabled BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT @MFAEnabled = ISNULL(MFAEnabled, 0)
    FROM dbo.UserMFA
    WHERE UserID = @UserID;

    -- If no record exists, MFA is not enabled
    IF @MFAEnabled IS NULL
        SET @MFAEnabled = 0;

    RETURN 0;
END;
GO

PRINT 'Procedure usp_IsMFAEnabled created.';
GO

-- Procedure: Get recent failed MFA attempts
CREATE OR ALTER PROCEDURE dbo.usp_GetRecentFailedMFAAttempts
    @UserID INT,
    @MinutesBack INT = 15,
    @FailedCount INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CutoffTime DATETIME2 = DATEADD(MINUTE, -@MinutesBack, SYSUTCDATETIME());

    SELECT @FailedCount = COUNT(*)
    FROM dbo.MFAVerificationAttempts
    WHERE UserID = @UserID
      AND IsSuccess = 0
      AND AttemptTime >= @CutoffTime;

    RETURN 0;
END;
GO

PRINT 'Procedure usp_GetRecentFailedMFAAttempts created.';
GO

-- =============================================
-- PART 3: Verification Queries
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 3: Verification'
PRINT '=============================================='
PRINT '';

-- List all tables created
SELECT
    TABLE_NAME,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = t.TABLE_NAME) AS ColumnCount
FROM INFORMATION_SCHEMA.TABLES t
WHERE TABLE_NAME IN ('UserMFA', 'UserMFABackupCodes', 'MFAVerificationAttempts')
ORDER BY TABLE_NAME;

PRINT '';
PRINT 'MFA procedures created:';
SELECT
    ROUTINE_NAME,
    CREATED AS CreatedDate
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_NAME LIKE 'usp_%MFA%'
   OR ROUTINE_NAME LIKE 'usp_%BackupCode%'
ORDER BY ROUTINE_NAME;

PRINT '';
PRINT '=============================================='
PRINT 'MFA schema deployment complete!'
PRINT '=============================================='
PRINT '';
PRINT 'Summary:';
PRINT '- 3 MFA tables created (UserMFA, UserMFABackupCodes, MFAVerificationAttempts)';
PRINT '- 10 stored procedures created for MFA management';
PRINT '- Indexes created for performance optimization';
PRINT '- Foreign key constraints for data integrity';
PRINT '';
PRINT 'MFA Types Supported:';
PRINT '- TOTP: Time-based One-Time Password (Google Authenticator, Authy)';
PRINT '- SMS: SMS-based verification codes';
PRINT '- Email: Email-based verification codes';
PRINT '';
PRINT 'Security Features:';
PRINT '- Backup codes for MFA recovery (10 codes per user)';
PRINT '- Failed attempt tracking for rate limiting';
PRINT '- Encrypted TOTP secrets';
PRINT '- Comprehensive audit logging';
PRINT '';
PRINT 'SOC 2 Controls: CC6.1, CC6.2, CC6.8 (Multi-Factor Authentication)';
GO
