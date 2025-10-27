-- =============================================
-- Phase 2.0 Week 1 Day 4: RBAC Foundation Infrastructure
-- Description: Role-Based Access Control tables, stored procedures, and triggers
-- SOC 2 Controls: CC6.1, CC6.2, CC6.3
-- Test-Driven Development: GREEN Phase
-- =============================================

USE MonitoringDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

PRINT 'Creating RBAC infrastructure...';
GO

-- =============================================
-- Table: Users
-- Purpose: Store user accounts for system access
-- =============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Users')
BEGIN
    CREATE TABLE dbo.Users
    (
        UserID INT IDENTITY(1,1) NOT NULL,
        UserName NVARCHAR(100) NOT NULL,
        Email NVARCHAR(255) NOT NULL,
        FullName NVARCHAR(200) NULL,
        IsActive BIT NOT NULL DEFAULT 1,
        IsLocked BIT NOT NULL DEFAULT 0,
        FailedLoginAttempts INT NOT NULL DEFAULT 0,
        LastLoginTime DATETIME2(7) NULL,
        LastLoginIP VARCHAR(45) NULL,
        PasswordHash VARBINARY(64) NULL, -- SHA-256 hash
        PasswordSalt VARBINARY(32) NULL, -- Salt for password
        MustChangePassword BIT NOT NULL DEFAULT 0,
        CreatedDate DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(100) NOT NULL,
        ModifiedDate DATETIME2(7) NULL,
        ModifiedBy NVARCHAR(100) NULL,
        CONSTRAINT PK_Users PRIMARY KEY CLUSTERED (UserID),
        CONSTRAINT UQ_Users_UserName UNIQUE (UserName),
        CONSTRAINT UQ_Users_Email UNIQUE (Email),
        CONSTRAINT CK_Users_Email CHECK (Email LIKE '%@%.%')
    );

    CREATE NONCLUSTERED INDEX IX_Users_UserName ON dbo.Users (UserName) WHERE IsActive = 1;
    CREATE NONCLUSTERED INDEX IX_Users_Email ON dbo.Users (Email) WHERE IsActive = 1;
    CREATE NONCLUSTERED INDEX IX_Users_IsActive ON dbo.Users (IsActive, UserID);

    PRINT 'Table Users created successfully';
END
ELSE
BEGIN
    PRINT 'Table Users already exists';
END
GO

-- =============================================
-- Table: Roles
-- Purpose: Define system roles
-- =============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Roles')
BEGIN
    CREATE TABLE dbo.Roles
    (
        RoleID INT IDENTITY(1,1) NOT NULL,
        RoleName NVARCHAR(100) NOT NULL,
        Description NVARCHAR(500) NULL,
        IsBuiltIn BIT NOT NULL DEFAULT 0, -- System roles cannot be deleted
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(100) NOT NULL,
        ModifiedDate DATETIME2(7) NULL,
        ModifiedBy NVARCHAR(100) NULL,
        CONSTRAINT PK_Roles PRIMARY KEY CLUSTERED (RoleID),
        CONSTRAINT UQ_Roles_RoleName UNIQUE (RoleName)
    );

    CREATE NONCLUSTERED INDEX IX_Roles_RoleName ON dbo.Roles (RoleName) WHERE IsActive = 1;
    CREATE NONCLUSTERED INDEX IX_Roles_IsBuiltIn ON dbo.Roles (IsBuiltIn, IsActive);

    PRINT 'Table Roles created successfully';
END
ELSE
BEGIN
    PRINT 'Table Roles already exists';
END
GO

-- =============================================
-- Table: Permissions
-- Purpose: Define granular permissions for resources
-- =============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Permissions')
BEGIN
    CREATE TABLE dbo.Permissions
    (
        PermissionID INT IDENTITY(1,1) NOT NULL,
        PermissionName NVARCHAR(100) NOT NULL, -- Format: Resource.Action (e.g., Servers.Read)
        ResourceType VARCHAR(50) NOT NULL, -- Servers, Metrics, Alerts, Users, Roles, etc.
        ActionType VARCHAR(50) NOT NULL, -- Read, Write, Delete, Execute
        Description NVARCHAR(500) NULL,
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(100) NOT NULL,
        CONSTRAINT PK_Permissions PRIMARY KEY CLUSTERED (PermissionID),
        CONSTRAINT UQ_Permissions_PermissionName UNIQUE (PermissionName),
        CONSTRAINT CK_Permissions_ActionType CHECK (ActionType IN ('Read', 'Write', 'Delete', 'Execute', 'Admin'))
    );

    CREATE NONCLUSTERED INDEX IX_Permissions_ResourceAction ON dbo.Permissions (ResourceType, ActionType) WHERE IsActive = 1;
    CREATE NONCLUSTERED INDEX IX_Permissions_PermissionName ON dbo.Permissions (PermissionName) WHERE IsActive = 1;

    PRINT 'Table Permissions created successfully';
END
ELSE
BEGIN
    PRINT 'Table Permissions already exists';
END
GO

-- =============================================
-- Table: UserRoles (Junction Table)
-- Purpose: Assign roles to users (many-to-many)
-- =============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'UserRoles')
BEGIN
    CREATE TABLE dbo.UserRoles
    (
        UserRoleID INT IDENTITY(1,1) NOT NULL,
        UserID INT NOT NULL,
        RoleID INT NOT NULL,
        AssignedDate DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
        AssignedBy NVARCHAR(100) NOT NULL,
        RevokedDate DATETIME2(7) NULL,
        RevokedBy NVARCHAR(100) NULL,
        IsActive BIT NOT NULL DEFAULT 1,
        CONSTRAINT PK_UserRoles PRIMARY KEY CLUSTERED (UserRoleID),
        CONSTRAINT FK_UserRoles_Users FOREIGN KEY (UserID) REFERENCES dbo.Users (UserID),
        CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (RoleID) REFERENCES dbo.Roles (RoleID),
        CONSTRAINT UQ_UserRoles_UserRole UNIQUE (UserID, RoleID)
    );

    CREATE NONCLUSTERED INDEX IX_UserRoles_UserID ON dbo.UserRoles (UserID, IsActive);
    CREATE NONCLUSTERED INDEX IX_UserRoles_RoleID ON dbo.UserRoles (RoleID, IsActive);

    PRINT 'Table UserRoles created successfully';
END
ELSE
BEGIN
    PRINT 'Table UserRoles already exists';
END
GO

-- =============================================
-- Table: RolePermissions (Junction Table)
-- Purpose: Assign permissions to roles (many-to-many)
-- =============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'RolePermissions')
BEGIN
    CREATE TABLE dbo.RolePermissions
    (
        RolePermissionID INT IDENTITY(1,1) NOT NULL,
        RoleID INT NOT NULL,
        PermissionID INT NOT NULL,
        AssignedDate DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
        AssignedBy NVARCHAR(100) NOT NULL,
        IsActive BIT NOT NULL DEFAULT 1,
        CONSTRAINT PK_RolePermissions PRIMARY KEY CLUSTERED (RolePermissionID),
        CONSTRAINT FK_RolePermissions_Roles FOREIGN KEY (RoleID) REFERENCES dbo.Roles (RoleID),
        CONSTRAINT FK_RolePermissions_Permissions FOREIGN KEY (PermissionID) REFERENCES dbo.Permissions (PermissionID),
        CONSTRAINT UQ_RolePermissions_RolePermission UNIQUE (RoleID, PermissionID)
    );

    CREATE NONCLUSTERED INDEX IX_RolePermissions_RoleID ON dbo.RolePermissions (RoleID, IsActive);
    CREATE NONCLUSTERED INDEX IX_RolePermissions_PermissionID ON dbo.RolePermissions (PermissionID, IsActive);

    PRINT 'Table RolePermissions created successfully';
END
ELSE
BEGIN
    PRINT 'Table RolePermissions already exists';
END
GO

-- =============================================
-- Stored Procedure: usp_CreateUser
-- Purpose: Create a new user account
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_CreateUser
    @UserName NVARCHAR(100),
    @Email NVARCHAR(255),
    @FullName NVARCHAR(200) = NULL,
    @PasswordHash VARBINARY(64) = NULL,
    @PasswordSalt VARBINARY(32) = NULL,
    @CreatedBy NVARCHAR(100),
    @UserID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Check for duplicate username
        IF EXISTS (SELECT 1 FROM dbo.Users WHERE UserName = @UserName)
        BEGIN
            SET @UserID = NULL;
            RETURN 1; -- Duplicate username
        END

        -- Check for duplicate email
        IF EXISTS (SELECT 1 FROM dbo.Users WHERE Email = @Email)
        BEGIN
            SET @UserID = NULL;
            RETURN 2; -- Duplicate email
        END

        -- Create user
        INSERT INTO dbo.Users (UserName, Email, FullName, PasswordHash, PasswordSalt, IsActive, CreatedDate, CreatedBy)
        VALUES (@UserName, @Email, @FullName, @PasswordHash, @PasswordSalt, 1, SYSUTCDATETIME(), @CreatedBy);

        SET @UserID = SCOPE_IDENTITY();

        -- Audit log
        EXEC dbo.usp_LogAuditEvent
            @EventType = 'UserCreated',
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

-- =============================================
-- Stored Procedure: usp_AssignRole
-- Purpose: Assign a role to a user
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_AssignRole
    @UserID INT,
    @RoleID INT,
    @AssignedBy NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Validate user exists and is active
        IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @UserID AND IsActive = 1)
        BEGIN
            RETURN 1; -- User not found or inactive
        END

        -- Validate role exists and is active
        IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleID = @RoleID AND IsActive = 1)
        BEGIN
            RETURN 2; -- Role not found or inactive
        END

        -- Check if role already assigned
        IF EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID = @UserID AND RoleID = @RoleID AND IsActive = 1)
        BEGIN
            RETURN 3; -- Role already assigned
        END

        -- Check if role was previously revoked (reactivate)
        IF EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID = @UserID AND RoleID = @RoleID AND IsActive = 0)
        BEGIN
            UPDATE dbo.UserRoles
            SET IsActive = 1,
                AssignedDate = SYSUTCDATETIME(),
                AssignedBy = @AssignedBy,
                RevokedDate = NULL,
                RevokedBy = NULL
            WHERE UserID = @UserID AND RoleID = @RoleID;
        END
        ELSE
        BEGIN
            -- Assign new role
            INSERT INTO dbo.UserRoles (UserID, RoleID, AssignedDate, AssignedBy, IsActive)
            VALUES (@UserID, @RoleID, SYSUTCDATETIME(), @AssignedBy, 1);
        END

        -- Audit log
        DECLARE @UserName NVARCHAR(100), @RoleName NVARCHAR(100);
        SELECT @UserName = UserName FROM dbo.Users WHERE UserID = @UserID;
        SELECT @RoleName = RoleName FROM dbo.Roles WHERE RoleID = @RoleID;

        EXEC dbo.usp_LogAuditEvent
            @EventType = 'RoleAssigned',
            @UserName = @AssignedBy,
            @ObjectName = @UserName,
            @ObjectType = 'UserRole',
            @ActionType = 'INSERT',
            @NewValue = @RoleName,
            @Severity = 'Information',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 0; -- Success
    END TRY
    BEGIN CATCH
        DECLARE @ErrNum INT = ERROR_NUMBER();
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();

        EXEC dbo.usp_LogAuditEvent
            @EventType = 'RoleAssignmentFailed',
            @UserName = @AssignedBy,
            @ErrorNumber = @ErrNum,
            @ErrorMessage = @ErrMsg,
            @Severity = 'Error',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 99; -- Error
    END CATCH
END;
GO

-- =============================================
-- Stored Procedure: usp_RevokeRole
-- Purpose: Revoke a role from a user
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_RevokeRole
    @UserID INT,
    @RoleID INT,
    @RevokedBy NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Validate role assignment exists and is active
        IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID = @UserID AND RoleID = @RoleID AND IsActive = 1)
        BEGIN
            RETURN 1; -- Role assignment not found or already revoked
        END

        -- Revoke role (soft delete)
        UPDATE dbo.UserRoles
        SET IsActive = 0,
            RevokedDate = SYSUTCDATETIME(),
            RevokedBy = @RevokedBy
        WHERE UserID = @UserID AND RoleID = @RoleID;

        -- Audit log
        DECLARE @UserName NVARCHAR(100), @RoleName NVARCHAR(100);
        SELECT @UserName = UserName FROM dbo.Users WHERE UserID = @UserID;
        SELECT @RoleName = RoleName FROM dbo.Roles WHERE RoleID = @RoleID;

        EXEC dbo.usp_LogAuditEvent
            @EventType = 'RoleRevoked',
            @UserName = @RevokedBy,
            @ObjectName = @UserName,
            @ObjectType = 'UserRole',
            @ActionType = 'DELETE',
            @OldValue = @RoleName,
            @Severity = 'Warning',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 0; -- Success
    END TRY
    BEGIN CATCH
        DECLARE @ErrNum INT = ERROR_NUMBER();
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();

        EXEC dbo.usp_LogAuditEvent
            @EventType = 'RoleRevocationFailed',
            @UserName = @RevokedBy,
            @ErrorNumber = @ErrNum,
            @ErrorMessage = @ErrMsg,
            @Severity = 'Error',
            @ComplianceFlag = 'SOC2',
            @RetentionDays = 2555;

        RETURN 99; -- Error
    END CATCH
END;
GO

-- =============================================
-- Stored Procedure: usp_GetUserPermissions
-- Purpose: Get all permissions for a user (via roles)
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_GetUserPermissions
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        p.PermissionID,
        p.PermissionName,
        p.ResourceType,
        p.ActionType,
        p.Description
    FROM dbo.Permissions p
    INNER JOIN dbo.RolePermissions rp ON p.PermissionID = rp.PermissionID
    INNER JOIN dbo.Roles r ON rp.RoleID = r.RoleID
    INNER JOIN dbo.UserRoles ur ON r.RoleID = ur.RoleID
    INNER JOIN dbo.Users u ON ur.UserID = u.UserID
    WHERE u.UserID = @UserID
      AND u.IsActive = 1
      AND u.IsLocked = 0
      AND ur.IsActive = 1
      AND r.IsActive = 1
      AND rp.IsActive = 1
      AND p.IsActive = 1
    ORDER BY p.ResourceType, p.ActionType;
END;
GO

-- =============================================
-- Stored Procedure: usp_CheckPermission
-- Purpose: Check if a user has a specific permission
-- =============================================
CREATE OR ALTER PROCEDURE dbo.usp_CheckPermission
    @UserID INT,
    @ResourceType VARCHAR(50),
    @ActionType VARCHAR(50),
    @HasPermission BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Default to no permission
    SET @HasPermission = 0;

    -- Check if user is active and not locked
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @UserID AND IsActive = 1 AND IsLocked = 0)
    BEGIN
        RETURN;
    END

    -- Check if user has permission through any active role
    IF EXISTS (
        SELECT 1
        FROM dbo.Users u
        INNER JOIN dbo.UserRoles ur ON u.UserID = ur.UserID
        INNER JOIN dbo.Roles r ON ur.RoleID = r.RoleID
        INNER JOIN dbo.RolePermissions rp ON r.RoleID = rp.RoleID
        INNER JOIN dbo.Permissions p ON rp.PermissionID = p.PermissionID
        WHERE u.UserID = @UserID
          AND u.IsActive = 1
          AND u.IsLocked = 0
          AND ur.IsActive = 1
          AND r.IsActive = 1
          AND rp.IsActive = 1
          AND p.IsActive = 1
          AND p.ResourceType = @ResourceType
          AND p.ActionType = @ActionType
    )
    BEGIN
        SET @HasPermission = 1;
    END
END;
GO

-- =============================================
-- Audit Trigger: Users Table
-- =============================================
CREATE OR ALTER TRIGGER dbo.trg_Audit_Users_IUD
ON dbo.Users
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActionType VARCHAR(20);
    DECLARE @OldValue NVARCHAR(MAX);
    DECLARE @NewValue NVARCHAR(MAX);

    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted)
        SET @ActionType = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted)
        SET @ActionType = 'INSERT';
    ELSE
        SET @ActionType = 'DELETE';

    -- Exclude password fields from audit for security
    SET @OldValue = (
        SELECT UserID, UserName, Email, FullName, IsActive, IsLocked,
               LastLoginTime, LastLoginIP, ModifiedDate, ModifiedBy
        FROM deleted
        FOR JSON AUTO
    );

    SET @NewValue = (
        SELECT UserID, UserName, Email, FullName, IsActive, IsLocked,
               LastLoginTime, LastLoginIP, ModifiedDate, ModifiedBy
        FROM inserted
        FOR JSON AUTO
    );

    EXEC dbo.usp_LogAuditEvent
        @EventType = 'TableModified',
        @ObjectName = 'Users',
        @ObjectType = 'Table',
        @ActionType = @ActionType,
        @OldValue = @OldValue,
        @NewValue = @NewValue,
        @ComplianceFlag = 'SOC2',
        @Severity = 'Information';
END;
GO

-- =============================================
-- Audit Trigger: Roles Table
-- =============================================
CREATE OR ALTER TRIGGER dbo.trg_Audit_Roles_IUD
ON dbo.Roles
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActionType VARCHAR(20);
    DECLARE @OldValue NVARCHAR(MAX);
    DECLARE @NewValue NVARCHAR(MAX);

    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted)
        SET @ActionType = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted)
        SET @ActionType = 'INSERT';
    ELSE
        SET @ActionType = 'DELETE';

    SET @OldValue = (SELECT * FROM deleted FOR JSON AUTO);
    SET @NewValue = (SELECT * FROM inserted FOR JSON AUTO);

    EXEC dbo.usp_LogAuditEvent
        @EventType = 'TableModified',
        @ObjectName = 'Roles',
        @ObjectType = 'Table',
        @ActionType = @ActionType,
        @OldValue = @OldValue,
        @NewValue = @NewValue,
        @ComplianceFlag = 'SOC2',
        @Severity = 'Warning';
END;
GO

-- =============================================
-- Audit Trigger: UserRoles Table
-- =============================================
CREATE OR ALTER TRIGGER dbo.trg_Audit_UserRoles_IUD
ON dbo.UserRoles
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActionType VARCHAR(20);
    DECLARE @OldValue NVARCHAR(MAX);
    DECLARE @NewValue NVARCHAR(MAX);

    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted)
        SET @ActionType = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted)
        SET @ActionType = 'INSERT';
    ELSE
        SET @ActionType = 'DELETE';

    SET @OldValue = (SELECT * FROM deleted FOR JSON AUTO);
    SET @NewValue = (SELECT * FROM inserted FOR JSON AUTO);

    EXEC dbo.usp_LogAuditEvent
        @EventType = 'TableModified',
        @ObjectName = 'UserRoles',
        @ObjectType = 'Table',
        @ActionType = @ActionType,
        @OldValue = @OldValue,
        @NewValue = @NewValue,
        @ComplianceFlag = 'SOC2',
        @Severity = 'Warning';
END;
GO

PRINT 'RBAC infrastructure created successfully';
GO

-- =============================================
-- Insert Default Roles
-- =============================================
PRINT 'Inserting default roles...';
GO

-- Admin role (full access)
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'Admin')
BEGIN
    INSERT INTO dbo.Roles (RoleName, Description, IsBuiltIn, IsActive, CreatedDate, CreatedBy)
    VALUES ('Admin', 'Full system administrator with all permissions', 1, 1, SYSUTCDATETIME(), 'system');
    PRINT 'Admin role created';
END
ELSE
    PRINT 'Admin role already exists';

-- User role (standard access)
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'User')
BEGIN
    INSERT INTO dbo.Roles (RoleName, Description, IsBuiltIn, IsActive, CreatedDate, CreatedBy)
    VALUES ('User', 'Standard user with read and limited write access', 1, 1, SYSUTCDATETIME(), 'system');
    PRINT 'User role created';
END
ELSE
    PRINT 'User role already exists';

-- ReadOnly role (view-only access)
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = 'ReadOnly')
BEGIN
    INSERT INTO dbo.Roles (RoleName, Description, IsBuiltIn, IsActive, CreatedDate, CreatedBy)
    VALUES ('ReadOnly', 'Read-only access to view monitoring data', 1, 1, SYSUTCDATETIME(), 'system');
    PRINT 'ReadOnly role created';
END
ELSE
    PRINT 'ReadOnly role already exists';
GO

-- =============================================
-- Insert Default Permissions
-- =============================================
PRINT 'Inserting default permissions...';
GO

-- Servers permissions
IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Servers.Read')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Servers.Read', 'Servers', 'Read', 'View server list and details', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Servers.Write')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Servers.Write', 'Servers', 'Write', 'Add or edit servers', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Servers.Delete')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Servers.Delete', 'Servers', 'Delete', 'Delete servers from monitoring', 1, SYSUTCDATETIME(), 'system');

-- Metrics permissions
IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Metrics.Read')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Metrics.Read', 'Metrics', 'Read', 'View performance metrics', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Metrics.Write')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Metrics.Write', 'Metrics', 'Write', 'Manually insert or edit metrics', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Metrics.Delete')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Metrics.Delete', 'Metrics', 'Delete', 'Delete historical metrics', 1, SYSUTCDATETIME(), 'system');

-- Alerts permissions
IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Alerts.Read')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Alerts.Read', 'Alerts', 'Read', 'View alerts and alert rules', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Alerts.Write')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Alerts.Write', 'Alerts', 'Write', 'Create or edit alert rules', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Alerts.Delete')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Alerts.Delete', 'Alerts', 'Delete', 'Delete alert rules', 1, SYSUTCDATETIME(), 'system');

-- Users permissions (admin only)
IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Users.Read')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Users.Read', 'Users', 'Read', 'View user accounts', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Users.Write')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Users.Write', 'Users', 'Write', 'Create or edit user accounts', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Users.Delete')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Users.Delete', 'Users', 'Delete', 'Delete user accounts', 1, SYSUTCDATETIME(), 'system');

-- Roles permissions (admin only)
IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Roles.Read')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Roles.Read', 'Roles', 'Read', 'View roles and permissions', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Roles.Write')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Roles.Write', 'Roles', 'Write', 'Create or edit roles', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Roles.Delete')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Roles.Delete', 'Roles', 'Delete', 'Delete custom roles', 1, SYSUTCDATETIME(), 'system');

-- Audit permissions (admin only)
IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Audit.Read')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Audit.Read', 'Audit', 'Read', 'View audit logs and reports', 1, SYSUTCDATETIME(), 'system');

IF NOT EXISTS (SELECT 1 FROM dbo.Permissions WHERE PermissionName = 'Audit.Admin')
    INSERT INTO dbo.Permissions (PermissionName, ResourceType, ActionType, Description, IsActive, CreatedDate, CreatedBy)
    VALUES ('Audit.Admin', 'Audit', 'Admin', 'Manage audit log retention and cleanup', 1, SYSUTCDATETIME(), 'system');

PRINT '17 default permissions created';
GO

-- =============================================
-- Assign Permissions to Roles
-- =============================================
PRINT 'Assigning permissions to roles...';
GO

-- Admin role gets ALL permissions
INSERT INTO dbo.RolePermissions (RoleID, PermissionID, AssignedDate, AssignedBy, IsActive)
SELECT
    (SELECT RoleID FROM dbo.Roles WHERE RoleName = 'Admin'),
    p.PermissionID,
    SYSUTCDATETIME(),
    'system',
    1
FROM dbo.Permissions p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.RolePermissions rp
    WHERE rp.RoleID = (SELECT RoleID FROM dbo.Roles WHERE RoleName = 'Admin')
    AND rp.PermissionID = p.PermissionID
);

PRINT 'Admin role assigned all permissions';

-- User role gets Read/Write for Servers, Metrics, Alerts (no delete, no admin)
INSERT INTO dbo.RolePermissions (RoleID, PermissionID, AssignedDate, AssignedBy, IsActive)
SELECT
    (SELECT RoleID FROM dbo.Roles WHERE RoleName = 'User'),
    p.PermissionID,
    SYSUTCDATETIME(),
    'system',
    1
FROM dbo.Permissions p
WHERE p.PermissionName IN (
    'Servers.Read', 'Servers.Write',
    'Metrics.Read', 'Metrics.Write',
    'Alerts.Read', 'Alerts.Write'
)
AND NOT EXISTS (
    SELECT 1 FROM dbo.RolePermissions rp
    WHERE rp.RoleID = (SELECT RoleID FROM dbo.Roles WHERE RoleName = 'User')
    AND rp.PermissionID = p.PermissionID
);

PRINT 'User role assigned read/write permissions';

-- ReadOnly role gets only Read permissions
INSERT INTO dbo.RolePermissions (RoleID, PermissionID, AssignedDate, AssignedBy, IsActive)
SELECT
    (SELECT RoleID FROM dbo.Roles WHERE RoleName = 'ReadOnly'),
    p.PermissionID,
    SYSUTCDATETIME(),
    'system',
    1
FROM dbo.Permissions p
WHERE p.ActionType = 'Read'
AND p.ResourceType IN ('Servers', 'Metrics', 'Alerts')
AND NOT EXISTS (
    SELECT 1 FROM dbo.RolePermissions rp
    WHERE rp.RoleID = (SELECT RoleID FROM dbo.Roles WHERE RoleName = 'ReadOnly')
    AND rp.PermissionID = p.PermissionID
);

PRINT 'ReadOnly role assigned read-only permissions';
GO

PRINT '==============================================';
PRINT 'RBAC infrastructure deployment complete!';
PRINT '==============================================';
PRINT '';
PRINT 'Summary:';
PRINT '- 5 tables created (Users, Roles, Permissions, UserRoles, RolePermissions)';
PRINT '- 5 stored procedures created (usp_CreateUser, usp_AssignRole, usp_RevokeRole, usp_GetUserPermissions, usp_CheckPermission)';
PRINT '- 3 audit triggers created (Users, Roles, UserRoles)';
PRINT '- 3 default roles created (Admin, User, ReadOnly)';
PRINT '- 17 default permissions created';
PRINT '- Role-permission assignments completed';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Run tests: EXEC tSQLt.RunTestClass ''RBAC_Tests'';';
PRINT '2. Create first admin user: EXEC usp_CreateUser ...';
PRINT '3. Assign admin role: EXEC usp_AssignRole ...';
GO
