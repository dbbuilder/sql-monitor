-- =============================================
-- Phase 2.0 Week 2 Day 6: Authentication Procedures
-- Description: Login, logout, password management procedures
-- SOC 2 Controls: CC6.1, CC6.2, CC6.3
-- =============================================

USE MonitoringDB;
GO

PRINT 'Creating authentication procedures...';
GO

-- =============================================
-- Stored Procedure: usp_AuthenticateUser
-- Purpose: Authenticate user with username/email and password
-- Returns: UserID and user details if successful, NULL if failed
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_AuthenticateUser
    @UserNameOrEmail NVARCHAR(255),
    @PasswordHash VARBINARY(64),
    @IPAddress VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserID INT;
    DECLARE @StoredHash VARBINARY(64);
    DECLARE @StoredSalt VARBINARY(32);
    DECLARE @IsActive BIT;
    DECLARE @IsLocked BIT;
    DECLARE @UserName NVARCHAR(100);

    -- Find user by username or email
    SELECT
        @UserID = UserID,
        @StoredHash = PasswordHash,
        @StoredSalt = PasswordSalt,
        @IsActive = IsActive,
        @IsLocked = IsLocked,
        @UserName = UserName
    FROM dbo.Users
    WHERE (UserName = @UserNameOrEmail OR Email = @UserNameOrEmail);

    -- User not found
    IF @UserID IS NULL
    BEGIN
        -- Log failed attempt (user not found)
        EXEC dbo.usp_LogAuditEvent
            @EventType = 'LoginAttemptUserNotFound',
            @UserName = @UserNameOrEmail,
            @IPAddress = @IPAddress,
            @Severity = 'Warning',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 1; -- User not found
    END

    -- Check if user is active
    IF @IsActive = 0
    BEGIN
        EXEC dbo.usp_LogAuditEvent
            @EventType = 'LoginAttemptInactiveUser',
            @UserName = @UserName,
            @IPAddress = @IPAddress,
            @Severity = 'Warning',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 2; -- User inactive
    END

    -- Check if user is locked
    IF @IsLocked = 1
    BEGIN
        EXEC dbo.usp_LogAuditEvent
            @EventType = 'LoginAttemptLockedUser',
            @UserName = @UserName,
            @IPAddress = @IPAddress,
            @Severity = 'Critical',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 3; -- User locked
    END

    -- Verify password hash (comparison must be done in application layer with salt)
    -- This procedure assumes the hash passed in is already salted and hashed
    IF @StoredHash = @PasswordHash
    BEGIN
        -- Password correct - update last login
        EXEC dbo.usp_UpdateUserLastLogin
            @UserID = @UserID,
            @IPAddress = @IPAddress;

        -- Return user details
        SELECT
            UserID,
            UserName,
            Email,
            FullName,
            MustChangePassword,
            LastLoginTime
        FROM dbo.Users
        WHERE UserID = @UserID;

        RETURN 0; -- Success
    END
    ELSE
    BEGIN
        -- Password incorrect - record failed attempt
        EXEC dbo.usp_RecordFailedLogin
            @UserName = @UserName,
            @IPAddress = @IPAddress,
            @MaxAttempts = 5;

        RETURN 4; -- Invalid password
    END
END;
GO

PRINT 'Procedure usp_AuthenticateUser created';
GO

-- =============================================
-- Stored Procedure: usp_CreateUserWithPassword
-- Purpose: Create user with hashed password (used during registration/admin creation)
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_CreateUserWithPassword
    @UserName NVARCHAR(100),
    @Email NVARCHAR(255),
    @FullName NVARCHAR(200) = NULL,
    @PasswordHash VARBINARY(64),
    @PasswordSalt VARBINARY(32),
    @CreatedBy NVARCHAR(100),
    @UserID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Use existing usp_CreateUser but with password
        INSERT INTO dbo.Users (
            UserName, Email, FullName,
            PasswordHash, PasswordSalt,
            IsActive, CreatedDate, CreatedBy
        )
        VALUES (
            @UserName, @Email, @FullName,
            @PasswordHash, @PasswordSalt,
            1, SYSUTCDATETIME(), @CreatedBy
        );

        SET @UserID = SCOPE_IDENTITY();

        -- Audit log
        EXEC dbo.usp_LogAuditEvent
            @EventType = 'UserCreatedWithPassword',
            @UserName = @CreatedBy,
            @ObjectName = @UserName,
            @ObjectType = 'User',
            @ActionType = 'INSERT',
            @NewValue = @Email,
            @Severity = 'Information',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 0; -- Success
    END TRY
    BEGIN CATCH
        SET @UserID = NULL;

        DECLARE @ErrNum INT = ERROR_NUMBER();
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();

        EXEC dbo.usp_LogAuditEvent
            @EventType = 'UserCreationFailed',
            @UserName = @CreatedBy,
            @ErrorNumber = @ErrNum,
            @ErrorMessage = @ErrMsg,
            @Severity = 'Error',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 99; -- Error
    END CATCH
END;
GO

PRINT 'Procedure usp_CreateUserWithPassword created';
GO

-- =============================================
-- Stored Procedure: usp_ChangePassword
-- Purpose: Change user password (with old password verification)
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_ChangePassword
    @UserID INT,
    @OldPasswordHash VARBINARY(64),
    @NewPasswordHash VARBINARY(64),
    @NewPasswordSalt VARBINARY(32),
    @ChangedBy NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StoredHash VARBINARY(64);
    DECLARE @UserName NVARCHAR(100);

    -- Get current password hash and username
    SELECT
        @StoredHash = PasswordHash,
        @UserName = UserName
    FROM dbo.Users
    WHERE UserID = @UserID;

    -- Verify old password (comparison with salt done in app layer)
    IF @StoredHash != @OldPasswordHash
    BEGIN
        EXEC dbo.usp_LogAuditEvent
            @EventType = 'PasswordChangeFailedWrongPassword',
            @UserName = @UserName,
            @ObjectName = @UserName,
            @ObjectType = 'User',
            @ActionType = 'UPDATE',
            @Severity = 'Warning',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 1; -- Wrong old password
    END

    -- Update password
    UPDATE dbo.Users
    SET PasswordHash = @NewPasswordHash,
        PasswordSalt = @NewPasswordSalt,
        MustChangePassword = 0,
        ModifiedDate = SYSUTCDATETIME(),
        ModifiedBy = @ChangedBy
    WHERE UserID = @UserID;

    -- Audit log
    EXEC dbo.usp_LogAuditEvent
        @EventType = 'PasswordChanged',
        @UserName = @ChangedBy,
        @ObjectName = @UserName,
        @ObjectType = 'User',
        @ActionType = 'UPDATE',
        @Severity = 'Information',
        @ComplianceFlag = 'SOC2',
        @RetentionDays = 2555;

    RETURN 0; -- Success
END;
GO

PRINT 'Procedure usp_ChangePassword created';
GO

-- =============================================
-- Stored Procedure: usp_ResetPassword
-- Purpose: Admin reset user password (bypass old password check)
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_ResetPassword
    @UserID INT,
    @NewPasswordHash VARBINARY(64),
    @NewPasswordSalt VARBINARY(32),
    @ResetBy NVARCHAR(100),
    @MustChangePassword BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserName NVARCHAR(100);

    SELECT @UserName = UserName
    FROM dbo.Users
    WHERE UserID = @UserID;

    IF @UserName IS NULL
    BEGIN
        RETURN 1; -- User not found
    END

    -- Reset password
    UPDATE dbo.Users
    SET PasswordHash = @NewPasswordHash,
        PasswordSalt = @NewPasswordSalt,
        MustChangePassword = @MustChangePassword,
        FailedLoginAttempts = 0,
        IsLocked = 0,
        ModifiedDate = SYSUTCDATETIME(),
        ModifiedBy = @ResetBy
    WHERE UserID = @UserID;

    -- Audit log
    EXEC dbo.usp_LogAuditEvent
        @EventType = 'PasswordResetByAdmin',
        @UserName = @ResetBy,
        @ObjectName = @UserName,
        @ObjectType = 'User',
        @ActionType = 'UPDATE',
        @Severity = 'Warning',
        @ComplianceFlag = 'SOC2',
        @RetentionDays = 2555;

    RETURN 0; -- Success
END;
GO

PRINT 'Procedure usp_ResetPassword created';
GO

-- =============================================
-- Stored Procedure: usp_GetUserByUserName
-- Purpose: Get user details by username (for authentication)
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetUserByUserName
    @UserName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        UserID,
        UserName,
        Email,
        FullName,
        IsActive,
        IsLocked,
        FailedLoginAttempts,
        LastLoginTime,
        LastLoginIP,
        PasswordHash,
        PasswordSalt,
        MustChangePassword
    FROM dbo.Users
    WHERE UserName = @UserName;
END;
GO

PRINT 'Procedure usp_GetUserByUserName created';
GO

-- =============================================
-- Stored Procedure: usp_GetUserByEmail
-- Purpose: Get user details by email (for authentication)
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetUserByEmail
    @Email NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        UserID,
        UserName,
        Email,
        FullName,
        IsActive,
        IsLocked,
        FailedLoginAttempts,
        LastLoginTime,
        LastLoginIP,
        PasswordHash,
        PasswordSalt,
        MustChangePassword
    FROM dbo.Users
    WHERE Email = @Email;
END;
GO

PRINT 'Procedure usp_GetUserByEmail created';
GO

PRINT '==============================================';
PRINT 'Authentication procedures deployment complete!';
PRINT '==============================================';
PRINT '';
PRINT 'Summary:';
PRINT '- 6 stored procedures created:';
PRINT '  - usp_AuthenticateUser (login validation)';
PRINT '  - usp_CreateUserWithPassword (user registration)';
PRINT '  - usp_ChangePassword (user-initiated password change)';
PRINT '  - usp_ResetPassword (admin password reset)';
PRINT '  - usp_GetUserByUserName (user lookup)';
PRINT '  - usp_GetUserByEmail (user lookup by email)';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Deploy to database';
PRINT '2. Create test users with passwords';
PRINT '3. Implement JWT authentication in API';
PRINT '4. Create login/logout endpoints';
GO
