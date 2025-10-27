-- =============================================
-- Phase 2.0 Week 1 Day 4: RBAC Optimizations & Compliance Reports
-- Description: Performance indexes, views, and SOC 2 compliance reporting
-- SOC 2 Controls: CC6.1, CC6.2, CC6.3
-- Test-Driven Development: REFACTOR Phase
-- =============================================

USE MonitoringDB;
GO

PRINT 'Creating RBAC optimizations...';
GO

-- =============================================
-- View: vw_UserPermissions
-- Purpose: Simplified view of user permissions for quick lookups
-- =============================================
CREATE OR ALTER VIEW dbo.vw_UserPermissions
AS
SELECT
    u.UserID,
    u.UserName,
    u.Email,
    u.IsActive AS UserIsActive,
    u.IsLocked,
    r.RoleID,
    r.RoleName,
    p.PermissionID,
    p.PermissionName,
    p.ResourceType,
    p.ActionType,
    ur.AssignedDate AS RoleAssignedDate,
    ur.AssignedBy AS RoleAssignedBy
FROM dbo.Users u
INNER JOIN dbo.UserRoles ur ON u.UserID = ur.UserID
INNER JOIN dbo.Roles r ON ur.RoleID = r.RoleID
INNER JOIN dbo.RolePermissions rp ON r.RoleID = rp.RoleID
INNER JOIN dbo.Permissions p ON rp.PermissionID = p.PermissionID
WHERE u.IsActive = 1
  AND u.IsLocked = 0
  AND ur.IsActive = 1
  AND r.IsActive = 1
  AND rp.IsActive = 1
  AND p.IsActive = 1;
GO

PRINT 'View vw_UserPermissions created';
GO

-- =============================================
-- Stored Procedure: usp_GetSOC2_RoleAssignmentReport
-- Purpose: Generate role assignment audit for SOC 2 CC6.1, CC6.2, CC6.3
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetSOC2_RoleAssignmentReport
    @StartTime DATETIME2 = NULL,
    @EndTime DATETIME2 = NULL,
    @UserName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to last 90 days
    SET @StartTime = COALESCE(@StartTime, DATEADD(DAY, -90, SYSUTCDATETIME()));
    SET @EndTime = COALESCE(@EndTime, SYSUTCDATETIME());

    SELECT
        u.UserID,
        u.UserName,
        u.Email,
        u.IsActive,
        u.IsLocked,
        u.CreatedDate,
        u.CreatedBy,
        r.RoleName,
        ur.AssignedDate,
        ur.AssignedBy,
        ur.RevokedDate,
        ur.RevokedBy,
        ur.IsActive AS RoleIsActive,
        DATEDIFF(DAY, ur.AssignedDate, COALESCE(ur.RevokedDate, SYSUTCDATETIME())) AS DaysAssigned
    FROM dbo.Users u
    INNER JOIN dbo.UserRoles ur ON u.UserID = ur.UserID
    INNER JOIN dbo.Roles r ON ur.RoleID = r.RoleID
    WHERE ur.AssignedDate >= @StartTime
      AND ur.AssignedDate <= @EndTime
      AND (@UserName IS NULL OR u.UserName = @UserName)
    ORDER BY ur.AssignedDate DESC;
END;
GO

PRINT 'Procedure usp_GetSOC2_RoleAssignmentReport created';
GO

-- =============================================
-- Stored Procedure: usp_GetSOC2_AccessReviewReport
-- Purpose: Generate access review report for SOC 2 CC6.3
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetSOC2_AccessReviewReport
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserID,
        u.UserName,
        u.Email,
        u.FullName,
        u.IsActive,
        u.IsLocked,
        u.LastLoginTime,
        DATEDIFF(DAY, u.LastLoginTime, SYSUTCDATETIME()) AS DaysSinceLastLogin,
        STRING_AGG(r.RoleName, ', ') AS AssignedRoles,
        COUNT(DISTINCT r.RoleID) AS RoleCount,
        CASE
            WHEN u.IsLocked = 1 THEN 'Locked'
            WHEN u.IsActive = 0 THEN 'Inactive'
            WHEN u.LastLoginTime IS NULL THEN 'Never Logged In'
            WHEN DATEDIFF(DAY, u.LastLoginTime, SYSUTCDATETIME()) > 90 THEN 'Stale (>90 days)'
            ELSE 'Active'
        END AS AccessStatus
    FROM dbo.Users u
    LEFT JOIN dbo.UserRoles ur ON u.UserID = ur.UserID AND ur.IsActive = 1
    LEFT JOIN dbo.Roles r ON ur.RoleID = r.RoleID
    GROUP BY
        u.UserID, u.UserName, u.Email, u.FullName,
        u.IsActive, u.IsLocked, u.LastLoginTime
    ORDER BY
        CASE
            WHEN u.IsLocked = 1 THEN 1
            WHEN u.IsActive = 0 THEN 2
            WHEN u.LastLoginTime IS NULL THEN 3
            WHEN DATEDIFF(DAY, u.LastLoginTime, SYSUTCDATETIME()) > 90 THEN 4
            ELSE 5
        END;
END;
GO

PRINT 'Procedure usp_GetSOC2_AccessReviewReport created';
GO

-- =============================================
-- Stored Procedure: usp_GetSOC2_PrivilegedAccessReport
-- Purpose: Report on admin/privileged role assignments for SOC 2 CC6.1
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetSOC2_PrivilegedAccessReport
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserID,
        u.UserName,
        u.Email,
        u.FullName,
        r.RoleName,
        ur.AssignedDate,
        ur.AssignedBy,
        DATEDIFF(DAY, ur.AssignedDate, SYSUTCDATETIME()) AS DaysWithPrivilege,
        COUNT(DISTINCT p.PermissionID) AS PermissionCount,
        STRING_AGG(p.PermissionName, ', ') AS Permissions
    FROM dbo.Users u
    INNER JOIN dbo.UserRoles ur ON u.UserID = ur.UserID
    INNER JOIN dbo.Roles r ON ur.RoleID = r.RoleID
    LEFT JOIN dbo.RolePermissions rp ON r.RoleID = rp.RoleID AND rp.IsActive = 1
    LEFT JOIN dbo.Permissions p ON rp.PermissionID = p.PermissionID
    WHERE ur.IsActive = 1
      AND u.IsActive = 1
      AND (
          r.RoleName = 'Admin'
          OR EXISTS (
              SELECT 1 FROM dbo.RolePermissions rp2
              INNER JOIN dbo.Permissions p2 ON rp2.PermissionID = p2.PermissionID
              WHERE rp2.RoleID = r.RoleID
              AND p2.ActionType IN ('Admin', 'Delete')
              AND rp2.IsActive = 1
          )
      )
    GROUP BY
        u.UserID, u.UserName, u.Email, u.FullName,
        r.RoleName, ur.AssignedDate, ur.AssignedBy
    ORDER BY DaysWithPrivilege DESC;
END;
GO

PRINT 'Procedure usp_GetSOC2_PrivilegedAccessReport created';
GO

-- =============================================
-- Stored Procedure: usp_GetUserRoles
-- Purpose: Get all roles assigned to a specific user
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetUserRoles
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.RoleID,
        r.RoleName,
        r.Description,
        r.IsBuiltIn,
        ur.AssignedDate,
        ur.AssignedBy,
        ur.IsActive
    FROM dbo.Roles r
    INNER JOIN dbo.UserRoles ur ON r.RoleID = ur.RoleID
    WHERE ur.UserID = @UserID
      AND ur.IsActive = 1
    ORDER BY r.RoleName;
END;
GO

PRINT 'Procedure usp_GetUserRoles created';
GO

-- =============================================
-- Stored Procedure: usp_UpdateUserLastLogin
-- Purpose: Update user's last login time and IP address
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_UpdateUserLastLogin
    @UserID INT,
    @IPAddress VARCHAR(45)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        UPDATE dbo.Users
        SET LastLoginTime = SYSUTCDATETIME(),
            LastLoginIP = @IPAddress,
            FailedLoginAttempts = 0,
            ModifiedDate = SYSUTCDATETIME()
        WHERE UserID = @UserID;

        -- Audit log
        DECLARE @UserName NVARCHAR(100);
        SELECT @UserName = UserName FROM dbo.Users WHERE UserID = @UserID;

        EXEC dbo.usp_LogAuditEvent
            @EventType = 'UserLogin',
            @UserName = @UserName,
            @IPAddress = @IPAddress,
            @Severity = 'Information',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 0; -- Success
    END TRY
    BEGIN CATCH
        RETURN 99; -- Error
    END CATCH
END;
GO

PRINT 'Procedure usp_UpdateUserLastLogin created';
GO

-- =============================================
-- Stored Procedure: usp_RecordFailedLogin
-- Purpose: Record failed login attempt and lock account if threshold exceeded
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_RecordFailedLogin
    @UserName NVARCHAR(100),
    @IPAddress VARCHAR(45),
    @MaxAttempts INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @UserID INT;
        DECLARE @FailedAttempts INT;

        -- Get user
        SELECT @UserID = UserID, @FailedAttempts = FailedLoginAttempts
        FROM dbo.Users
        WHERE UserName = @UserName;

        IF @UserID IS NOT NULL
        BEGIN
            -- Increment failed attempts
            SET @FailedAttempts = @FailedAttempts + 1;

            UPDATE dbo.Users
            SET FailedLoginAttempts = @FailedAttempts,
                IsLocked = CASE WHEN @FailedAttempts >= @MaxAttempts THEN 1 ELSE IsLocked END,
                ModifiedDate = SYSUTCDATETIME()
            WHERE UserID = @UserID;

            -- Audit log
            DECLARE @ErrMsg NVARCHAR(4000);
            DECLARE @Sev VARCHAR(20);

            SET @ErrMsg = CASE WHEN @FailedAttempts >= @MaxAttempts
                THEN 'Account locked after ' + CAST(@FailedAttempts AS NVARCHAR(10)) + ' failed attempts'
                ELSE 'Failed attempt ' + CAST(@FailedAttempts AS NVARCHAR(10)) + ' of ' + CAST(@MaxAttempts AS NVARCHAR(10))
            END;

            SET @Sev = CASE WHEN @FailedAttempts >= @MaxAttempts THEN 'Critical' ELSE 'Warning' END;

            EXEC dbo.usp_LogAuditEvent
                @EventType = 'UserLoginFailed',
                @UserName = @UserName,
                @IPAddress = @IPAddress,
                @ErrorMessage = @ErrMsg,
                @Severity = @Sev,
                @ComplianceFlag = 'SOC2',
                @RetentionDays = 2555;
        END

        RETURN 0; -- Success
    END TRY
    BEGIN CATCH
        RETURN 99; -- Error
    END CATCH
END;
GO

PRINT 'Procedure usp_RecordFailedLogin created';
GO

-- =============================================
-- Stored Procedure: usp_UnlockUser
-- Purpose: Unlock a locked user account (admin action)
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_UnlockUser
    @UserID INT,
    @UnlockedBy NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Validate user is locked
        IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @UserID AND IsLocked = 1)
        BEGIN
            RETURN 1; -- User not locked
        END

        UPDATE dbo.Users
        SET IsLocked = 0,
            FailedLoginAttempts = 0,
            ModifiedDate = SYSUTCDATETIME(),
            ModifiedBy = @UnlockedBy
        WHERE UserID = @UserID;

        -- Audit log
        DECLARE @UserName NVARCHAR(100);
        SELECT @UserName = UserName FROM dbo.Users WHERE UserID = @UserID;

        EXEC dbo.usp_LogAuditEvent
            @EventType = 'UserUnlocked',
            @UserName = @UnlockedBy,
            @ObjectName = @UserName,
            @ObjectType = 'User',
            @ActionType = 'UPDATE',
            @Severity = 'Warning',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 0; -- Success
    END TRY
    BEGIN CATCH
        RETURN 99; -- Error
    END CATCH
END;
GO

PRINT 'Procedure usp_UnlockUser created';
GO

PRINT '==============================================';
PRINT 'RBAC optimizations deployment complete!';
PRINT '==============================================';
PRINT '';
PRINT 'Summary:';
PRINT '- 1 view created (vw_UserPermissions)';
PRINT '- 7 stored procedures created:';
PRINT '  - usp_GetSOC2_RoleAssignmentReport (CC6.1, CC6.2, CC6.3)';
PRINT '  - usp_GetSOC2_AccessReviewReport (CC6.3)';
PRINT '  - usp_GetSOC2_PrivilegedAccessReport (CC6.1)';
PRINT '  - usp_GetUserRoles';
PRINT '  - usp_UpdateUserLastLogin';
PRINT '  - usp_RecordFailedLogin';
PRINT '  - usp_UnlockUser';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Run SOC 2 reports to verify compliance data';
PRINT '2. Integrate usp_UpdateUserLastLogin in API authentication';
PRINT '3. Integrate usp_RecordFailedLogin in API authentication';
GO
