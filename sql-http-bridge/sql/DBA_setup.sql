-- DBA_setup.sql
-- This script prepares auditing/logging and a least-privilege API surface.
-- Adjust "YourAppDB", table/column names, and regenerate a fresh strong password.

------------------------------------------------------------
-- 1. Create DBATools (if not exists) and Api_AccessLog
------------------------------------------------------------
IF DB_ID('DBATools') IS NULL
    CREATE DATABASE DBATools
GO

USE DBATools
IF OBJECT_ID('dbo.Api_AccessLog') IS NULL
BEGIN
    CREATE TABLE dbo.Api_AccessLog
    (
        ApiAccessLogID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        AccessedDate   DATETIME NOT NULL DEFAULT GETDATE(),
        ProcName       VARCHAR(200) NOT NULL,
        LoginUsed      VARCHAR(200) NOT NULL,
        ClientInfo     VARCHAR(4000) NULL
    )
END
GO

------------------------------------------------------------
-- 2. Create a sample safe proc in your app DB
--    Replace YourAppDB and dbo.Inventory accordingly.
------------------------------------------------------------
USE YourAppDB
CREATE OR ALTER PROCEDURE dbo.Api_GetInventory
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        INSERT INTO DBATools.dbo.Api_AccessLog
        (
            ProcName,
            LoginUsed,
            ClientInfo
        )
        SELECT
            'dbo.Api_GetInventory',
            ORIGINAL_LOGIN(),
            HOST_NAME()

        SELECT
            i.ItemID,
            i.ItemName,
            i.QtyOnHand,
            i.Price,
            i.LastUpdatedDate
        FROM dbo.Inventory i

    END TRY
    BEGIN CATCH
        INSERT INTO DBATools.dbo.Api_AccessLog
        (
            ProcName,
            LoginUsed,
            ClientInfo
        )
        SELECT
            'dbo.Api_GetInventory.ERROR: ' + ERROR_MESSAGE(),
            ORIGINAL_LOGIN(),
            HOST_NAME()

        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE()
        RAISERROR(@ErrMsg, 16, 1)
    END CATCH
END
GO

------------------------------------------------------------
-- 3. Create least-privilege SQL login for API access
--    The password below is an EXAMPLE. Generate your own fresh secret.
------------------------------------------------------------
USE master
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = 'svc_api_readonly')
BEGIN
    CREATE LOGIN svc_api_readonly
    WITH PASSWORD = 'N3&yq9dV#4uWgZr!L0p^CH1tR7@xFm2K',
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = ON
END
GO

USE YourAppDB
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'svc_api_readonly')
BEGIN
    CREATE USER svc_api_readonly FOR LOGIN svc_api_readonly
END
GO

-- Ensure minimal rights
REVOKE CONNECT TO svc_api_readonly
GRANT  CONNECT TO svc_api_readonly

EXEC sp_droprolemember 'db_owner',      'svc_api_readonly'
EXEC sp_droprolemember 'db_datareader', 'svc_api_readonly'
EXEC sp_droprolemember 'db_datawriter', 'svc_api_readonly'
GO

-- Grant EXECUTE ONLY on approved proc(s)
GRANT EXECUTE ON dbo.Api_GetInventory TO svc_api_readonly
GO

------------------------------------------------------------
-- SECURITY MODEL:
-- * svc_api_readonly:
--   - NOT sysadmin
--   - NOT db_owner
--   - NO blanket SELECT rights
--   - EXECUTE ONLY on vetted dbo.Api_* procedures
--
-- * Each dbo.Api_* proc logs use in DBATools.dbo.Api_AccessLog
--   (who called, when, HOST_NAME()).
--
-- * Python HTTP bridge:
--   - Listens on 127.0.0.1 only
--   - Requires valid SQL login/pass each call
--   - Only allowlists known procs
--
-- * Revocation:
--   - REVOKE EXECUTE
--   - ALTER LOGIN ... WITH PASSWORD = 'newStrongPassword'
--   - Stop OS service
------------------------------------------------------------
