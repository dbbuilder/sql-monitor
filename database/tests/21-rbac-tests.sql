-- =============================================
-- Phase 2.0 Week 1 Day 4: RBAC Foundation Tests
-- Description: tSQLt test class for Role-Based Access Control
-- SOC 2 Controls: CC6.1, CC6.2, CC6.3
-- Test-Driven Development: RED Phase
-- =============================================

-- Create test class
EXEC tSQLt.NewTestClass 'RBAC_Tests';
GO

-- =============================================
-- Test 1: Users table exists with required columns
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Users table exists with required columns]
AS
BEGIN
    -- Arrange: Expected columns
    DECLARE @ExpectedColumns TABLE (ColumnName NVARCHAR(128));
    INSERT INTO @ExpectedColumns VALUES
        ('UserID'), ('UserName'), ('Email'), ('FullName'),
        ('IsActive'), ('IsLocked'), ('FailedLoginAttempts'),
        ('LastLoginTime'), ('LastLoginIP'), ('PasswordHash'),
        ('PasswordSalt'), ('MustChangePassword'), ('CreatedDate'),
        ('CreatedBy'), ('ModifiedDate'), ('ModifiedBy');

    -- Assert: All expected columns exist
    IF EXISTS (
        SELECT 1 FROM @ExpectedColumns e
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.columns c
            INNER JOIN sys.tables t ON c.object_id = t.object_id
            WHERE t.name = 'Users' AND c.name = e.ColumnName
        )
    )
    BEGIN
        EXEC tSQLt.Fail 'Users table is missing one or more required columns';
    END
END;
GO

-- =============================================
-- Test 2: Roles table exists with required columns
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Roles table exists with required columns]
AS
BEGIN
    -- Arrange: Expected columns
    DECLARE @ExpectedColumns TABLE (ColumnName NVARCHAR(128));
    INSERT INTO @ExpectedColumns VALUES
        ('RoleID'), ('RoleName'), ('Description'),
        ('IsBuiltIn'), ('IsActive'), ('CreatedDate'),
        ('CreatedBy'), ('ModifiedDate'), ('ModifiedBy');

    -- Assert: All expected columns exist
    IF EXISTS (
        SELECT 1 FROM @ExpectedColumns e
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.columns c
            INNER JOIN sys.tables t ON c.object_id = t.object_id
            WHERE t.name = 'Roles' AND c.name = e.ColumnName
        )
    )
    BEGIN
        EXEC tSQLt.Fail 'Roles table is missing one or more required columns';
    END
END;
GO

-- =============================================
-- Test 3: Permissions table exists with required columns
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Permissions table exists with required columns]
AS
BEGIN
    -- Arrange: Expected columns
    DECLARE @ExpectedColumns TABLE (ColumnName NVARCHAR(128));
    INSERT INTO @ExpectedColumns VALUES
        ('PermissionID'), ('PermissionName'), ('ResourceType'),
        ('ActionType'), ('Description'), ('IsActive'),
        ('CreatedDate'), ('CreatedBy');

    -- Assert: All expected columns exist
    IF EXISTS (
        SELECT 1 FROM @ExpectedColumns e
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.columns c
            INNER JOIN sys.tables t ON c.object_id = t.object_id
            WHERE t.name = 'Permissions' AND c.name = e.ColumnName
        )
    )
    BEGIN
        EXEC tSQLt.Fail 'Permissions table is missing one or more required columns';
    END
END;
GO

-- =============================================
-- Test 4: UserRoles junction table exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test UserRoles junction table exists]
AS
BEGIN
    -- Assert: UserRoles table exists with foreign keys
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'UserRoles')
    BEGIN
        EXEC tSQLt.Fail 'UserRoles junction table does not exist';
    END

    -- Assert: Foreign key to Users exists
    IF NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID('dbo.UserRoles')
        AND referenced_object_id = OBJECT_ID('dbo.Users')
    )
    BEGIN
        EXEC tSQLt.Fail 'UserRoles missing foreign key to Users';
    END

    -- Assert: Foreign key to Roles exists
    IF NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID('dbo.UserRoles')
        AND referenced_object_id = OBJECT_ID('dbo.Roles')
    )
    BEGIN
        EXEC tSQLt.Fail 'UserRoles missing foreign key to Roles';
    END
END;
GO

-- =============================================
-- Test 5: RolePermissions junction table exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test RolePermissions junction table exists]
AS
BEGIN
    -- Assert: RolePermissions table exists with foreign keys
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'RolePermissions')
    BEGIN
        EXEC tSQLt.Fail 'RolePermissions junction table does not exist';
    END

    -- Assert: Foreign key to Roles exists
    IF NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID('dbo.RolePermissions')
        AND referenced_object_id = OBJECT_ID('dbo.Roles')
    )
    BEGIN
        EXEC tSQLt.Fail 'RolePermissions missing foreign key to Roles';
    END

    -- Assert: Foreign key to Permissions exists
    IF NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID('dbo.RolePermissions')
        AND referenced_object_id = OBJECT_ID('dbo.Permissions')
    )
    BEGIN
        EXEC tSQLt.Fail 'RolePermissions missing foreign key to Permissions';
    END
END;
GO

-- =============================================
-- Test 6: usp_CreateUser procedure exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_CreateUser procedure exists]
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_CreateUser')
    BEGIN
        EXEC tSQLt.Fail 'Stored procedure usp_CreateUser does not exist';
    END
END;
GO

-- =============================================
-- Test 7: usp_CreateUser creates user successfully
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_CreateUser creates user successfully]
AS
BEGIN
    -- Arrange: Fake Users table
    EXEC tSQLt.FakeTable 'dbo.Users';
    EXEC tSQLt.FakeTable 'dbo.AuditLog';

    DECLARE @UserID INT;
    DECLARE @ReturnCode INT;

    -- Act: Create a new user
    EXEC @ReturnCode = dbo.usp_CreateUser
        @UserName = 'john.doe',
        @Email = 'john.doe@company.com',
        @FullName = 'John Doe',
        @CreatedBy = 'admin',
        @UserID = @UserID OUTPUT;

    -- Assert: User was created
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM dbo.Users WHERE UserName = 'john.doe';

    EXEC tSQLt.AssertEquals 1, @ActualCount;
    EXEC tSQLt.AssertEquals 0, @ReturnCode; -- Success
END;
GO

-- =============================================
-- Test 8: usp_CreateUser prevents duplicate username
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_CreateUser prevents duplicate username]
AS
BEGIN
    -- Arrange: Fake Users table with existing user
    EXEC tSQLt.FakeTable 'dbo.Users';
    EXEC tSQLt.FakeTable 'dbo.AuditLog';

    INSERT INTO dbo.Users (UserName, Email, FullName, IsActive, CreatedDate, CreatedBy)
    VALUES ('john.doe', 'john@company.com', 'John Doe', 1, GETUTCDATE(), 'admin');

    DECLARE @UserID INT;
    DECLARE @ReturnCode INT;

    -- Act: Try to create duplicate user
    EXEC @ReturnCode = dbo.usp_CreateUser
        @UserName = 'john.doe',
        @Email = 'john.doe2@company.com',
        @FullName = 'John Doe Jr',
        @CreatedBy = 'admin',
        @UserID = @UserID OUTPUT;

    -- Assert: Duplicate rejected (return code 1)
    EXEC tSQLt.AssertEquals 1, @ReturnCode; -- Failure
END;
GO

-- =============================================
-- Test 9: usp_AssignRole procedure exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_AssignRole procedure exists]
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_AssignRole')
    BEGIN
        EXEC tSQLt.Fail 'Stored procedure usp_AssignRole does not exist';
    END
END;
GO

-- =============================================
-- Test 10: usp_AssignRole assigns role to user
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_AssignRole assigns role to user]
AS
BEGIN
    -- Arrange: Fake tables
    EXEC tSQLt.FakeTable 'dbo.Users';
    EXEC tSQLt.FakeTable 'dbo.Roles';
    EXEC tSQLt.FakeTable 'dbo.UserRoles';
    EXEC tSQLt.FakeTable 'dbo.AuditLog';

    INSERT INTO dbo.Users (UserID, UserName, Email, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'john.doe', 'john@company.com', 1, GETUTCDATE(), 'admin');

    INSERT INTO dbo.Roles (RoleID, RoleName, IsBuiltIn, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'Admin', 1, 1, GETUTCDATE(), 'system');

    DECLARE @ReturnCode INT;

    -- Act: Assign role to user
    EXEC @ReturnCode = dbo.usp_AssignRole
        @UserID = 1,
        @RoleID = 1,
        @AssignedBy = 'admin';

    -- Assert: Role assignment created
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM dbo.UserRoles WHERE UserID = 1 AND RoleID = 1;

    EXEC tSQLt.AssertEquals 1, @ActualCount;
    EXEC tSQLt.AssertEquals 0, @ReturnCode; -- Success
END;
GO

-- =============================================
-- Test 11: usp_RevokeRole procedure exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_RevokeRole procedure exists]
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_RevokeRole')
    BEGIN
        EXEC tSQLt.Fail 'Stored procedure usp_RevokeRole does not exist';
    END
END;
GO

-- =============================================
-- Test 12: usp_RevokeRole removes role from user
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_RevokeRole removes role from user]
AS
BEGIN
    -- Arrange: Fake tables with existing role assignment
    EXEC tSQLt.FakeTable 'dbo.Users';
    EXEC tSQLt.FakeTable 'dbo.Roles';
    EXEC tSQLt.FakeTable 'dbo.UserRoles';
    EXEC tSQLt.FakeTable 'dbo.AuditLog';

    INSERT INTO dbo.Users (UserID, UserName, Email, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'john.doe', 'john@company.com', 1, GETUTCDATE(), 'admin');

    INSERT INTO dbo.Roles (RoleID, RoleName, IsBuiltIn, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'Admin', 1, 1, GETUTCDATE(), 'system');

    INSERT INTO dbo.UserRoles (UserID, RoleID, AssignedDate, AssignedBy, IsActive)
    VALUES (1, 1, GETUTCDATE(), 'admin', 1);

    DECLARE @ReturnCode INT;

    -- Act: Revoke role from user
    EXEC @ReturnCode = dbo.usp_RevokeRole
        @UserID = 1,
        @RoleID = 1,
        @RevokedBy = 'admin';

    -- Assert: Role assignment removed (IsActive = 0)
    DECLARE @ActualIsActive BIT;
    SELECT @ActualIsActive = IsActive FROM dbo.UserRoles WHERE UserID = 1 AND RoleID = 1;

    EXEC tSQLt.AssertEquals 0, @ActualIsActive;
    EXEC tSQLt.AssertEquals 0, @ReturnCode; -- Success
END;
GO

-- =============================================
-- Test 13: usp_GetUserPermissions procedure exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_GetUserPermissions procedure exists]
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_GetUserPermissions')
    BEGIN
        EXEC tSQLt.Fail 'Stored procedure usp_GetUserPermissions does not exist';
    END
END;
GO

-- =============================================
-- Test 14: usp_GetUserPermissions returns all user permissions
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_GetUserPermissions returns all user permissions]
AS
BEGIN
    -- Arrange: Fake tables with user, role, and permissions
    EXEC tSQLt.FakeTable 'dbo.Users';
    EXEC tSQLt.FakeTable 'dbo.Roles';
    EXEC tSQLt.FakeTable 'dbo.Permissions';
    EXEC tSQLt.FakeTable 'dbo.UserRoles';
    EXEC tSQLt.FakeTable 'dbo.RolePermissions';

    INSERT INTO dbo.Users (UserID, UserName, Email, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'john.doe', 'john@company.com', 1, GETUTCDATE(), 'admin');

    INSERT INTO dbo.Roles (RoleID, RoleName, IsBuiltIn, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'Admin', 1, 1, GETUTCDATE(), 'system');

    INSERT INTO dbo.Permissions (PermissionID, PermissionName, ResourceType, ActionType, IsActive, CreatedDate, CreatedBy)
    VALUES
        (1, 'Servers.Read', 'Servers', 'Read', 1, GETUTCDATE(), 'system'),
        (2, 'Servers.Write', 'Servers', 'Write', 1, GETUTCDATE(), 'system');

    INSERT INTO dbo.UserRoles (UserID, RoleID, AssignedDate, AssignedBy, IsActive)
    VALUES (1, 1, GETUTCDATE(), 'admin', 1);

    INSERT INTO dbo.RolePermissions (RoleID, PermissionID, AssignedDate, AssignedBy, IsActive)
    VALUES
        (1, 1, GETUTCDATE(), 'system', 1),
        (1, 2, GETUTCDATE(), 'system', 1);

    -- Act: Get user permissions
    DECLARE @ResultTable TABLE (
        PermissionID INT,
        PermissionName NVARCHAR(100),
        ResourceType VARCHAR(50),
        ActionType VARCHAR(50)
    );

    INSERT INTO @ResultTable
    EXEC dbo.usp_GetUserPermissions @UserID = 1;

    -- Assert: User has 2 permissions
    DECLARE @ActualCount INT;
    SELECT @ActualCount = COUNT(*) FROM @ResultTable;

    EXEC tSQLt.AssertEquals 2, @ActualCount;
END;
GO

-- =============================================
-- Test 15: usp_CheckPermission procedure exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_CheckPermission procedure exists]
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_CheckPermission')
    BEGIN
        EXEC tSQLt.Fail 'Stored procedure usp_CheckPermission does not exist';
    END
END;
GO

-- =============================================
-- Test 16: usp_CheckPermission returns 1 when user has permission
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_CheckPermission returns 1 when user has permission]
AS
BEGIN
    -- Arrange: Fake tables with user having Servers.Read permission
    EXEC tSQLt.FakeTable 'dbo.Users';
    EXEC tSQLt.FakeTable 'dbo.Roles';
    EXEC tSQLt.FakeTable 'dbo.Permissions';
    EXEC tSQLt.FakeTable 'dbo.UserRoles';
    EXEC tSQLt.FakeTable 'dbo.RolePermissions';

    INSERT INTO dbo.Users (UserID, UserName, Email, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'john.doe', 'john@company.com', 1, GETUTCDATE(), 'admin');

    INSERT INTO dbo.Roles (RoleID, RoleName, IsBuiltIn, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'User', 1, 1, GETUTCDATE(), 'system');

    INSERT INTO dbo.Permissions (PermissionID, PermissionName, ResourceType, ActionType, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'Servers.Read', 'Servers', 'Read', 1, GETUTCDATE(), 'system');

    INSERT INTO dbo.UserRoles (UserID, RoleID, AssignedDate, AssignedBy, IsActive)
    VALUES (1, 1, GETUTCDATE(), 'admin', 1);

    INSERT INTO dbo.RolePermissions (RoleID, PermissionID, AssignedDate, AssignedBy, IsActive)
    VALUES (1, 1, GETUTCDATE(), 'system', 1);

    -- Act: Check if user has permission
    DECLARE @HasPermission BIT;
    EXEC dbo.usp_CheckPermission
        @UserID = 1,
        @ResourceType = 'Servers',
        @ActionType = 'Read',
        @HasPermission = @HasPermission OUTPUT;

    -- Assert: User has permission
    EXEC tSQLt.AssertEquals 1, @HasPermission;
END;
GO

-- =============================================
-- Test 17: usp_CheckPermission returns 0 when user lacks permission
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test usp_CheckPermission returns 0 when user lacks permission]
AS
BEGIN
    -- Arrange: Fake tables with user NOT having Servers.Write permission
    EXEC tSQLt.FakeTable 'dbo.Users';
    EXEC tSQLt.FakeTable 'dbo.Roles';
    EXEC tSQLt.FakeTable 'dbo.Permissions';
    EXEC tSQLt.FakeTable 'dbo.UserRoles';
    EXEC tSQLt.FakeTable 'dbo.RolePermissions';

    INSERT INTO dbo.Users (UserID, UserName, Email, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'john.doe', 'john@company.com', 1, GETUTCDATE(), 'admin');

    INSERT INTO dbo.Roles (RoleID, RoleName, IsBuiltIn, IsActive, CreatedDate, CreatedBy)
    VALUES (1, 'ReadOnly', 1, 1, GETUTCDATE(), 'system');

    INSERT INTO dbo.Permissions (PermissionID, PermissionName, ResourceType, ActionType, IsActive, CreatedDate, CreatedBy)
    VALUES
        (1, 'Servers.Read', 'Servers', 'Read', 1, GETUTCDATE(), 'system'),
        (2, 'Servers.Write', 'Servers', 'Write', 1, GETUTCDATE(), 'system');

    INSERT INTO dbo.UserRoles (UserID, RoleID, AssignedDate, AssignedBy, IsActive)
    VALUES (1, 1, GETUTCDATE(), 'admin', 1);

    INSERT INTO dbo.RolePermissions (RoleID, PermissionID, AssignedDate, AssignedBy, IsActive)
    VALUES (1, 1, GETUTCDATE(), 'system', 1); -- Only Read, not Write

    -- Act: Check if user has Write permission
    DECLARE @HasPermission BIT;
    EXEC dbo.usp_CheckPermission
        @UserID = 1,
        @ResourceType = 'Servers',
        @ActionType = 'Write',
        @HasPermission = @HasPermission OUTPUT;

    -- Assert: User does NOT have permission
    EXEC tSQLt.AssertEquals 0, @HasPermission;
END;
GO

-- =============================================
-- Test 18: Audit trigger exists for Users table
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Audit trigger exists for Users table]
AS
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.triggers
        WHERE name = 'trg_Audit_Users_IUD'
        AND parent_id = OBJECT_ID('dbo.Users')
    )
    BEGIN
        EXEC tSQLt.Fail 'Audit trigger trg_Audit_Users_IUD does not exist on Users table';
    END
END;
GO

-- =============================================
-- Test 19: Audit trigger exists for Roles table
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Audit trigger exists for Roles table]
AS
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.triggers
        WHERE name = 'trg_Audit_Roles_IUD'
        AND parent_id = OBJECT_ID('dbo.Roles')
    )
    BEGIN
        EXEC tSQLt.Fail 'Audit trigger trg_Audit_Roles_IUD does not exist on Roles table';
    END
END;
GO

-- =============================================
-- Test 20: Audit trigger exists for UserRoles table
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Audit trigger exists for UserRoles table]
AS
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.triggers
        WHERE name = 'trg_Audit_UserRoles_IUD'
        AND parent_id = OBJECT_ID('dbo.UserRoles')
    )
    BEGIN
        EXEC tSQLt.Fail 'Audit trigger trg_Audit_UserRoles_IUD does not exist on UserRoles table';
    END
END;
GO

-- =============================================
-- Test 21: Default Admin role exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Default Admin role exists]
AS
BEGIN
    -- Assert: Admin role exists and is built-in
    IF NOT EXISTS (
        SELECT 1 FROM dbo.Roles
        WHERE RoleName = 'Admin'
        AND IsBuiltIn = 1
        AND IsActive = 1
    )
    BEGIN
        EXEC tSQLt.Fail 'Default Admin role does not exist or is not configured correctly';
    END
END;
GO

-- =============================================
-- Test 22: Default User role exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Default User role exists]
AS
BEGIN
    -- Assert: User role exists and is built-in
    IF NOT EXISTS (
        SELECT 1 FROM dbo.Roles
        WHERE RoleName = 'User'
        AND IsBuiltIn = 1
        AND IsActive = 1
    )
    BEGIN
        EXEC tSQLt.Fail 'Default User role does not exist or is not configured correctly';
    END
END;
GO

-- =============================================
-- Test 23: Default ReadOnly role exists
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Default ReadOnly role exists]
AS
BEGIN
    -- Assert: ReadOnly role exists and is built-in
    IF NOT EXISTS (
        SELECT 1 FROM dbo.Roles
        WHERE RoleName = 'ReadOnly'
        AND IsBuiltIn = 1
        AND IsActive = 1
    )
    BEGIN
        EXEC tSQLt.Fail 'Default ReadOnly role does not exist or is not configured correctly';
    END
END;
GO

-- =============================================
-- Test 24: Default permissions exist
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Default permissions exist]
AS
BEGIN
    -- Assert: At least 12 core permissions exist (4 resources × 3 actions)
    DECLARE @PermissionCount INT;
    SELECT @PermissionCount = COUNT(*)
    FROM dbo.Permissions
    WHERE IsActive = 1;

    IF @PermissionCount < 12
    BEGIN
        EXEC tSQLt.Fail 'Expected at least 12 default permissions, found fewer';
    END
END;
GO

-- =============================================
-- Test 25: Admin role has all permissions
-- =============================================
CREATE PROCEDURE RBAC_Tests.[test Admin role has all permissions]
AS
BEGIN
    -- Assert: Admin role has all active permissions assigned
    DECLARE @TotalPermissions INT;
    DECLARE @AdminPermissions INT;

    SELECT @TotalPermissions = COUNT(*) FROM dbo.Permissions WHERE IsActive = 1;

    SELECT @AdminPermissions = COUNT(*)
    FROM dbo.RolePermissions rp
    INNER JOIN dbo.Roles r ON rp.RoleID = r.RoleID
    WHERE r.RoleName = 'Admin'
    AND r.IsActive = 1
    AND rp.IsActive = 1;

    IF @AdminPermissions < @TotalPermissions
    BEGIN
        DECLARE @ErrorMsg NVARCHAR(200);
        SET @ErrorMsg = 'Admin role has ' + CAST(@AdminPermissions AS NVARCHAR) +
                        ' permissions, expected ' + CAST(@TotalPermissions AS NVARCHAR);
        EXEC tSQLt.Fail @ErrorMsg;
    END
END;
GO

PRINT 'RBAC test class created with 25 tests';
PRINT 'Run tests: EXEC tSQLt.RunTestClass ''RBAC_Tests'';';
GO
