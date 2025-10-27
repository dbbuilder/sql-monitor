/*
 * Phase 2.0 Week 3 Days 13-14: Session Management Schema
 *
 * Purpose: Track user sessions, enforce concurrent session limits, and enable force logout
 *
 * SOC 2 Controls:
 * - CC6.1: Logical and Physical Access Controls (session tracking)
 * - CC6.6: Logical and Physical Access Controls (session timeout)
 * - CC6.7: Transmission of Data (session security)
 *
 * Features:
 * - Active session tracking (IP, user agent, location)
 * - Session timeout enforcement
 * - Concurrent session limits (max 3 per user)
 * - Force logout capability
 * - Session activity audit trail
 * - Remember me token support
 *
 * Compliance: SOC 2 Type II
 * Retention: 2555 days (7 years) for audit
 */

USE [MonitoringDB];
GO

-- =============================================
-- Table: UserSessions
-- Purpose: Track active user sessions
-- =============================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'UserSessions')
BEGIN
    CREATE TABLE dbo.UserSessions (
        SessionID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        UserID INT NOT NULL,
        SessionToken NVARCHAR(512) NOT NULL,              -- JWT token or session identifier
        RefreshToken NVARCHAR(512) NULL,                  -- Refresh token for long-lived sessions
        RefreshTokenHash VARBINARY(64) NULL,              -- Hashed refresh token for security
        IPAddress VARCHAR(45) NOT NULL,                   -- IPv4 or IPv6
        UserAgent NVARCHAR(500) NULL,                     -- Browser/client info
        DeviceType VARCHAR(50) NULL,                      -- Desktop, Mobile, Tablet, API
        DeviceFingerprint NVARCHAR(256) NULL,             -- Device identification hash
        LocationCity VARCHAR(100) NULL,                   -- City (from IP geolocation)
        LocationCountry VARCHAR(100) NULL,                -- Country
        LoginTime DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        LastActivityTime DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ExpiresAt DATETIME2 NOT NULL,                     -- Session expiration time
        IsActive BIT NOT NULL DEFAULT 1,
        LogoutTime DATETIME2 NULL,
        LogoutReason VARCHAR(50) NULL,                    -- Manual, Timeout, ForceLogout, TokenExpired
        RememberMe BIT NOT NULL DEFAULT 0,                -- Extended session (30 days)
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

        CONSTRAINT PK_UserSessions PRIMARY KEY CLUSTERED (SessionID),
        CONSTRAINT FK_UserSessions_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID),
        CONSTRAINT CK_UserSessions_ExpiresAt CHECK (ExpiresAt > LoginTime)
    );

    CREATE NONCLUSTERED INDEX IX_UserSessions_UserID_IsActive
        ON dbo.UserSessions(UserID, IsActive)
        INCLUDE (LoginTime, LastActivityTime, ExpiresAt);

    CREATE NONCLUSTERED INDEX IX_UserSessions_SessionToken
        ON dbo.UserSessions(SessionToken)
        WHERE IsActive = 1;

    CREATE NONCLUSTERED INDEX IX_UserSessions_RefreshToken
        ON dbo.UserSessions(RefreshTokenHash)
        WHERE IsActive = 1 AND RefreshTokenHash IS NOT NULL;

    CREATE NONCLUSTERED INDEX IX_UserSessions_ExpiresAt
        ON dbo.UserSessions(ExpiresAt)
        WHERE IsActive = 1;

    PRINT 'Table UserSessions created successfully';
END
GO

-- =============================================
-- Table: SessionActivity
-- Purpose: Audit trail of session events
-- =============================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'SessionActivity')
BEGIN
    CREATE TABLE dbo.SessionActivity (
        ActivityID BIGINT IDENTITY(1,1) NOT NULL,
        SessionID UNIQUEIDENTIFIER NOT NULL,
        UserID INT NOT NULL,
        ActivityType VARCHAR(50) NOT NULL,               -- Login, Refresh, Activity, Logout, ForceLogout, Timeout
        ActivityTime DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        IPAddress VARCHAR(45) NULL,
        UserAgent NVARCHAR(500) NULL,
        Endpoint NVARCHAR(200) NULL,                     -- API endpoint accessed
        HttpMethod VARCHAR(10) NULL,                     -- GET, POST, PUT, DELETE
        ResponseStatus INT NULL,                         -- HTTP status code
        Details NVARCHAR(1000) NULL,                     -- Additional context
        RetentionDate DATETIME2 NOT NULL DEFAULT DATEADD(DAY, 2555, GETUTCDATE()),

        CONSTRAINT PK_SessionActivity PRIMARY KEY CLUSTERED (ActivityID),
        CONSTRAINT FK_SessionActivity_UserSessions FOREIGN KEY (SessionID) REFERENCES dbo.UserSessions(SessionID),
        CONSTRAINT FK_SessionActivity_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID)
    );

    CREATE NONCLUSTERED INDEX IX_SessionActivity_SessionID_ActivityTime
        ON dbo.SessionActivity(SessionID, ActivityTime DESC);

    CREATE NONCLUSTERED INDEX IX_SessionActivity_UserID_ActivityTime
        ON dbo.SessionActivity(UserID, ActivityTime DESC);

    CREATE NONCLUSTERED INDEX IX_SessionActivity_ActivityType
        ON dbo.SessionActivity(ActivityType, ActivityTime DESC);

    CREATE NONCLUSTERED INDEX IX_SessionActivity_RetentionDate
        ON dbo.SessionActivity(RetentionDate)
        WHERE RetentionDate IS NOT NULL;

    PRINT 'Table SessionActivity created successfully';
END
GO

-- =============================================
-- Stored Procedure: usp_CreateSession
-- Purpose: Create new user session
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_CreateSession
    @UserID INT,
    @SessionToken NVARCHAR(512),
    @RefreshToken NVARCHAR(512) = NULL,
    @RefreshTokenHash VARBINARY(64) = NULL,
    @IPAddress VARCHAR(45),
    @UserAgent NVARCHAR(500) = NULL,
    @DeviceType VARCHAR(50) = NULL,
    @DeviceFingerprint NVARCHAR(256) = NULL,
    @LocationCity VARCHAR(100) = NULL,
    @LocationCountry VARCHAR(100) = NULL,
    @RememberMe BIT = 0,
    @SessionID UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExpiresAt DATETIME2;
    DECLARE @SessionDurationMinutes INT;

    -- Set session duration based on RememberMe flag
    IF @RememberMe = 1
        SET @SessionDurationMinutes = 43200; -- 30 days
    ELSE
        SET @SessionDurationMinutes = 480;   -- 8 hours (default)

    SET @ExpiresAt = DATEADD(MINUTE, @SessionDurationMinutes, GETUTCDATE());
    SET @SessionID = NEWID();

    -- Insert new session
    INSERT INTO dbo.UserSessions (
        SessionID, UserID, SessionToken, RefreshToken, RefreshTokenHash,
        IPAddress, UserAgent, DeviceType, DeviceFingerprint,
        LocationCity, LocationCountry, ExpiresAt, RememberMe
    )
    VALUES (
        @SessionID, @UserID, @SessionToken, @RefreshToken, @RefreshTokenHash,
        @IPAddress, @UserAgent, @DeviceType, @DeviceFingerprint,
        @LocationCity, @LocationCountry, @ExpiresAt, @RememberMe
    );

    -- Log session activity
    INSERT INTO dbo.SessionActivity (
        SessionID, UserID, ActivityType, IPAddress, UserAgent, Details
    )
    VALUES (
        @SessionID, @UserID, 'Login', @IPAddress, @UserAgent,
        'New session created (RememberMe: ' + CAST(@RememberMe AS VARCHAR(1)) + ')'
    );

    RETURN 0;
END
GO

-- =============================================
-- Stored Procedure: usp_GetUserSessions
-- Purpose: Get all active sessions for a user
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetUserSessions
    @UserID INT,
    @IncludeInactive BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SessionID,
        UserID,
        SessionToken,
        IPAddress,
        UserAgent,
        DeviceType,
        DeviceFingerprint,
        LocationCity,
        LocationCountry,
        LoginTime,
        LastActivityTime,
        ExpiresAt,
        IsActive,
        LogoutTime,
        LogoutReason,
        RememberMe,
        CreatedDate,
        ModifiedDate
    FROM dbo.UserSessions
    WHERE UserID = @UserID
      AND (@IncludeInactive = 1 OR IsActive = 1)
    ORDER BY LoginTime DESC;
END
GO

-- =============================================
-- Stored Procedure: usp_GetSessionByToken
-- Purpose: Validate and retrieve session by token
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetSessionByToken
    @SessionToken NVARCHAR(512)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SessionID,
        UserID,
        SessionToken,
        RefreshToken,
        RefreshTokenHash,
        IPAddress,
        UserAgent,
        DeviceType,
        DeviceFingerprint,
        LocationCity,
        LocationCountry,
        LoginTime,
        LastActivityTime,
        ExpiresAt,
        IsActive,
        LogoutTime,
        LogoutReason,
        RememberMe,
        CreatedDate,
        ModifiedDate
    FROM dbo.UserSessions
    WHERE SessionToken = @SessionToken
      AND IsActive = 1
      AND ExpiresAt > GETUTCDATE();
END
GO

-- =============================================
-- Stored Procedure: usp_UpdateSessionActivity
-- Purpose: Update last activity time for session
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_UpdateSessionActivity
    @SessionID UNIQUEIDENTIFIER,
    @IPAddress VARCHAR(45) = NULL,
    @UserAgent NVARCHAR(500) = NULL,
    @Endpoint NVARCHAR(200) = NULL,
    @HttpMethod VARCHAR(10) = NULL,
    @ResponseStatus INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserID INT;

    -- Update session last activity
    UPDATE dbo.UserSessions
    SET LastActivityTime = GETUTCDATE(),
        ModifiedDate = GETUTCDATE()
    WHERE SessionID = @SessionID
      AND IsActive = 1;

    -- Get UserID for activity log
    SELECT @UserID = UserID
    FROM dbo.UserSessions
    WHERE SessionID = @SessionID;

    -- Log activity
    IF @UserID IS NOT NULL
    BEGIN
        INSERT INTO dbo.SessionActivity (
            SessionID, UserID, ActivityType, IPAddress, UserAgent,
            Endpoint, HttpMethod, ResponseStatus
        )
        VALUES (
            @SessionID, @UserID, 'Activity', @IPAddress, @UserAgent,
            @Endpoint, @HttpMethod, @ResponseStatus
        );
    END

    RETURN 0;
END
GO

-- =============================================
-- Stored Procedure: usp_RefreshSession
-- Purpose: Refresh session using refresh token
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_RefreshSession
    @RefreshTokenHash VARBINARY(64),
    @NewSessionToken NVARCHAR(512),
    @NewRefreshToken NVARCHAR(512) = NULL,
    @NewRefreshTokenHash VARBINARY(64) = NULL,
    @IPAddress VARCHAR(45),
    @SessionID UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserID INT;
    DECLARE @RememberMe BIT;
    DECLARE @SessionDurationMinutes INT;
    DECLARE @ExpiresAt DATETIME2;

    -- Find existing session by refresh token
    SELECT
        @SessionID = SessionID,
        @UserID = UserID,
        @RememberMe = RememberMe
    FROM dbo.UserSessions
    WHERE RefreshTokenHash = @RefreshTokenHash
      AND IsActive = 1
      AND ExpiresAt > GETUTCDATE();

    IF @SessionID IS NULL
    BEGIN
        RAISERROR('Invalid or expired refresh token', 16, 1);
        RETURN 1;
    END

    -- Calculate new expiration
    IF @RememberMe = 1
        SET @SessionDurationMinutes = 43200; -- 30 days
    ELSE
        SET @SessionDurationMinutes = 480;   -- 8 hours

    SET @ExpiresAt = DATEADD(MINUTE, @SessionDurationMinutes, GETUTCDATE());

    -- Update session with new tokens
    UPDATE dbo.UserSessions
    SET SessionToken = @NewSessionToken,
        RefreshToken = @NewRefreshToken,
        RefreshTokenHash = @NewRefreshTokenHash,
        LastActivityTime = GETUTCDATE(),
        ExpiresAt = @ExpiresAt,
        ModifiedDate = GETUTCDATE()
    WHERE SessionID = @SessionID;

    -- Log refresh activity
    INSERT INTO dbo.SessionActivity (
        SessionID, UserID, ActivityType, IPAddress, Details
    )
    VALUES (
        @SessionID, @UserID, 'Refresh', @IPAddress, 'Session refreshed with new tokens'
    );

    RETURN 0;
END
GO

-- =============================================
-- Stored Procedure: usp_LogoutSession
-- Purpose: Logout user session
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_LogoutSession
    @SessionID UNIQUEIDENTIFIER,
    @LogoutReason VARCHAR(50) = 'Manual',
    @IPAddress VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserID INT;

    -- Get UserID
    SELECT @UserID = UserID
    FROM dbo.UserSessions
    WHERE SessionID = @SessionID;

    -- Deactivate session
    UPDATE dbo.UserSessions
    SET IsActive = 0,
        LogoutTime = GETUTCDATE(),
        LogoutReason = @LogoutReason,
        ModifiedDate = GETUTCDATE()
    WHERE SessionID = @SessionID;

    -- Log logout activity
    IF @UserID IS NOT NULL
    BEGIN
        INSERT INTO dbo.SessionActivity (
            SessionID, UserID, ActivityType, IPAddress, Details
        )
        VALUES (
            @SessionID, @UserID, 'Logout', @IPAddress,
            'Session ended: ' + @LogoutReason
        );
    END

    RETURN 0;
END
GO

-- =============================================
-- Stored Procedure: usp_ForceLogoutUser
-- Purpose: Force logout all sessions for a user
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_ForceLogoutUser
    @UserID INT,
    @ExcludeSessionID UNIQUEIDENTIFIER = NULL,  -- Optional: keep current session active
    @AdminUserName VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LoggedOutCount INT = 0;

    -- Deactivate all active sessions for user
    UPDATE dbo.UserSessions
    SET IsActive = 0,
        LogoutTime = GETUTCDATE(),
        LogoutReason = 'ForceLogout',
        ModifiedDate = GETUTCDATE()
    WHERE UserID = @UserID
      AND IsActive = 1
      AND (@ExcludeSessionID IS NULL OR SessionID <> @ExcludeSessionID);

    SET @LoggedOutCount = @@ROWCOUNT;

    -- Log force logout activity for each session
    INSERT INTO dbo.SessionActivity (
        SessionID, UserID, ActivityType, Details
    )
    SELECT
        SessionID,
        UserID,
        'ForceLogout',
        'Force logout by admin: ' + ISNULL(@AdminUserName, 'System')
    FROM dbo.UserSessions
    WHERE UserID = @UserID
      AND LogoutReason = 'ForceLogout'
      AND LogoutTime >= DATEADD(SECOND, -5, GETUTCDATE());

    -- Log audit event
    INSERT INTO dbo.AuditLog (
        EventType, UserName, IPAddress, Severity, ComplianceFlag, RetentionDays, Details
    )
    VALUES (
        'ForceLogoutUser',
        ISNULL(@AdminUserName, 'System'),
        NULL,
        'Warning',
        'SOC2',
        2555,
        'Force logout ' + CAST(@LoggedOutCount AS VARCHAR(10)) + ' sessions for UserID: ' + CAST(@UserID AS VARCHAR(10))
    );

    SELECT @LoggedOutCount AS LoggedOutSessions;

    RETURN 0;
END
GO

-- =============================================
-- Stored Procedure: usp_EnforceConcurrentSessionLimit
-- Purpose: Enforce maximum concurrent sessions per user
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_EnforceConcurrentSessionLimit
    @UserID INT,
    @MaxSessions INT = 3,
    @CurrentSessionID UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActiveCount INT;
    DECLARE @ExcessCount INT;

    -- Count active sessions
    SELECT @ActiveCount = COUNT(*)
    FROM dbo.UserSessions
    WHERE UserID = @UserID
      AND IsActive = 1
      AND ExpiresAt > GETUTCDATE();

    -- If over limit, terminate oldest sessions
    IF @ActiveCount > @MaxSessions
    BEGIN
        SET @ExcessCount = @ActiveCount - @MaxSessions;

        -- Deactivate oldest sessions (excluding current if specified)
        UPDATE TOP (@ExcessCount) dbo.UserSessions
        SET IsActive = 0,
            LogoutTime = GETUTCDATE(),
            LogoutReason = 'ConcurrentLimitExceeded',
            ModifiedDate = GETUTCDATE()
        WHERE SessionID IN (
            SELECT TOP (@ExcessCount) SessionID
            FROM dbo.UserSessions
            WHERE UserID = @UserID
              AND IsActive = 1
              AND (@CurrentSessionID IS NULL OR SessionID <> @CurrentSessionID)
            ORDER BY LastActivityTime ASC
        );

        -- Log activity
        INSERT INTO dbo.SessionActivity (
            SessionID, UserID, ActivityType, Details
        )
        SELECT
            SessionID,
            UserID,
            'ForceLogout',
            'Terminated due to concurrent session limit (' + CAST(@MaxSessions AS VARCHAR(10)) + ')'
        FROM dbo.UserSessions
        WHERE UserID = @UserID
          AND LogoutReason = 'ConcurrentLimitExceeded'
          AND LogoutTime >= DATEADD(SECOND, -5, GETUTCDATE());
    END

    RETURN 0;
END
GO

-- =============================================
-- Stored Procedure: usp_CleanupExpiredSessions
-- Purpose: Cleanup expired/inactive sessions
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_CleanupExpiredSessions
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CleanedUpCount INT = 0;

    -- Mark expired sessions as inactive
    UPDATE dbo.UserSessions
    SET IsActive = 0,
        LogoutTime = GETUTCDATE(),
        LogoutReason = 'Timeout',
        ModifiedDate = GETUTCDATE()
    WHERE IsActive = 1
      AND ExpiresAt <= GETUTCDATE();

    SET @CleanedUpCount = @@ROWCOUNT;

    -- Log timeout activity
    INSERT INTO dbo.SessionActivity (
        SessionID, UserID, ActivityType, Details
    )
    SELECT
        SessionID,
        UserID,
        'Timeout',
        'Session expired'
    FROM dbo.UserSessions
    WHERE LogoutReason = 'Timeout'
      AND LogoutTime >= DATEADD(SECOND, -5, GETUTCDATE());

    SELECT @CleanedUpCount AS ExpiredSessions;

    RETURN 0;
END
GO

-- =============================================
-- Stored Procedure: usp_GetSessionStatistics
-- Purpose: Get session statistics for monitoring
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetSessionStatistics
    @TimeRangeHours INT = 24
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = DATEADD(HOUR, -@TimeRangeHours, GETUTCDATE());

    SELECT
        -- Active sessions
        (SELECT COUNT(*) FROM dbo.UserSessions WHERE IsActive = 1 AND ExpiresAt > GETUTCDATE()) AS ActiveSessions,

        -- Total sessions in time range
        (SELECT COUNT(*) FROM dbo.UserSessions WHERE LoginTime >= @StartTime) AS TotalSessionsCreated,

        -- Expired sessions
        (SELECT COUNT(*) FROM dbo.UserSessions WHERE LogoutReason = 'Timeout' AND LogoutTime >= @StartTime) AS ExpiredSessions,

        -- Force logouts
        (SELECT COUNT(*) FROM dbo.UserSessions WHERE LogoutReason = 'ForceLogout' AND LogoutTime >= @StartTime) AS ForceLogouts,

        -- Manual logouts
        (SELECT COUNT(*) FROM dbo.UserSessions WHERE LogoutReason = 'Manual' AND LogoutTime >= @StartTime) AS ManualLogouts,

        -- Average session duration (minutes)
        (SELECT AVG(DATEDIFF(MINUTE, LoginTime, ISNULL(LogoutTime, GETUTCDATE())))
         FROM dbo.UserSessions
         WHERE LoginTime >= @StartTime) AS AvgSessionDurationMinutes,

        -- Peak concurrent sessions
        (SELECT MAX(SessionCount)
         FROM (
            SELECT COUNT(*) AS SessionCount, DATEADD(HOUR, DATEDIFF(HOUR, 0, LoginTime), 0) AS Hour
            FROM dbo.UserSessions
            WHERE LoginTime >= @StartTime
            GROUP BY DATEADD(HOUR, DATEDIFF(HOUR, 0, LoginTime), 0)
         ) AS HourlyCounts) AS PeakConcurrentSessions;
END
GO

PRINT 'Session Management schema deployment complete';
PRINT '- Tables: UserSessions, SessionActivity';
PRINT '- Stored Procedures: 10 procedures for session lifecycle';
PRINT '- SOC 2 Controls: CC6.1, CC6.6, CC6.7';
GO
