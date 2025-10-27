-- =============================================
-- Phase 2.0 Week 2 Days 8-9: Encryption at Rest
-- Description: Transparent Data Encryption (TDE) + Column-Level Encryption
-- SOC 2 Controls: CC6.6, CC6.7 (Encryption at Rest, Key Management)
-- =============================================

USE master;
GO

PRINT 'Starting Encryption at Rest deployment...';
GO

-- =============================================
-- PART 1: Transparent Data Encryption (TDE)
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 1: Transparent Data Encryption (TDE)'
PRINT '=============================================='
PRINT '';

-- Check if TDE is supported in this SQL Server edition
-- TDE is only available in Enterprise, Developer, and Evaluation editions
DECLARE @Edition NVARCHAR(100) = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(100));

IF @Edition NOT LIKE '%Enterprise%'
   AND @Edition NOT LIKE '%Developer%'
   AND @Edition NOT LIKE '%Evaluation%'
BEGIN
    PRINT 'WARNING: TDE is not supported in ' + @Edition;
    PRINT 'TDE requires Enterprise, Developer, or Evaluation edition.';
    PRINT 'Skipping TDE setup (will continue with column-level encryption).';
    PRINT '';
END
ELSE
BEGIN
    PRINT 'TDE is supported in ' + @Edition;
    PRINT '';

    -- Step 1: Create Database Master Key in master database
    IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    BEGIN
        PRINT 'Creating Database Master Key in master database...';
        CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'ComplexMasterKeyPassword123!@#';
        PRINT 'Database Master Key created in master.';
    END
    ELSE
    BEGIN
        PRINT 'Database Master Key already exists in master.';
    END

    -- Step 2: Create Server Certificate for TDE
    IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = 'TDE_Certificate_MonitoringDB')
    BEGIN
        PRINT 'Creating TDE certificate...';
        CREATE CERTIFICATE TDE_Certificate_MonitoringDB
        WITH SUBJECT = 'TDE Certificate for MonitoringDB - SOC 2 Compliance',
             EXPIRY_DATE = '2030-12-31';
        PRINT 'TDE certificate created.';
    END
    ELSE
    BEGIN
        PRINT 'TDE certificate already exists.';
    END

    -- Step 3: Backup TDE certificate (CRITICAL - Required for database restore)
    PRINT '';
    PRINT 'IMPORTANT: TDE Certificate Backup';
    PRINT '----------------------------------';
    PRINT 'The TDE certificate MUST be backed up and stored securely.';
    PRINT 'Without this certificate backup, the encrypted database cannot be restored!';
    PRINT '';
    PRINT 'To backup the certificate, run the following commands:';
    PRINT '';
    PRINT '-- Backup certificate to file (CHANGE PATH AS NEEDED):';
    PRINT 'BACKUP CERTIFICATE TDE_Certificate_MonitoringDB';
    PRINT '   TO FILE = ''C:\TDEBackup\TDE_Certificate_MonitoringDB.cer''';
    PRINT '   WITH PRIVATE KEY (';
    PRINT '      FILE = ''C:\TDEBackup\TDE_Certificate_MonitoringDB.pvk'',';
    PRINT '      ENCRYPTION BY PASSWORD = ''StrongPrivateKeyPassword456!@#''';
    PRINT '   );';
    PRINT '';
    PRINT 'Store these files in a secure, off-server location!';
    PRINT '';

    -- Switch to MonitoringDB for TDE setup
    USE MonitoringDB;
    GO

    -- Step 4: Create Database Encryption Key (DEK)
    IF NOT EXISTS (SELECT * FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('MonitoringDB'))
    BEGIN
        PRINT 'Creating Database Encryption Key for MonitoringDB...';
        CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE TDE_Certificate_MonitoringDB;
        PRINT 'Database Encryption Key created.';
    END
    ELSE
    BEGIN
        PRINT 'Database Encryption Key already exists for MonitoringDB.';
    END

    -- Step 5: Enable TDE on MonitoringDB
    PRINT 'Enabling TDE on MonitoringDB...';
    ALTER DATABASE MonitoringDB
    SET ENCRYPTION ON;
    PRINT 'TDE enabled on MonitoringDB.';

    -- Wait for encryption to complete
    PRINT '';
    PRINT 'Checking encryption status (this may take time for large databases)...';

    WAITFOR DELAY '00:00:05'; -- Wait 5 seconds for encryption to start

    SELECT
        DB_NAME(database_id) AS DatabaseName,
        encryption_state,
        CASE encryption_state
            WHEN 0 THEN 'No encryption'
            WHEN 1 THEN 'Unencrypted'
            WHEN 2 THEN 'Encryption in progress'
            WHEN 3 THEN 'Encrypted'
            WHEN 4 THEN 'Key change in progress'
            WHEN 5 THEN 'Decryption in progress'
            WHEN 6 THEN 'Protection change in progress'
        END AS EncryptionStateDescription,
        percent_complete,
        encryptor_type
    FROM sys.dm_database_encryption_keys
    WHERE database_id = DB_ID('MonitoringDB');

    PRINT '';
    PRINT 'TDE setup complete.';
    PRINT 'Note: Full encryption may take time for large databases.';
    PRINT 'Run the above SELECT query to monitor encryption progress.';
END
GO

-- =============================================
-- PART 2: Column-Level Encryption
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 2: Column-Level Encryption'
PRINT '=============================================='
PRINT '';

USE MonitoringDB;
GO

-- Step 1: Create Database Master Key in MonitoringDB (for column encryption)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    PRINT 'Creating Database Master Key in MonitoringDB...';
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'ComplexDBMasterKeyPassword789!@#';
    PRINT 'Database Master Key created in MonitoringDB.';
END
ELSE
BEGIN
    PRINT 'Database Master Key already exists in MonitoringDB.';
END
GO

-- Step 2: Create Certificate for Column Encryption
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = 'ColumnEncryption_Certificate')
BEGIN
    PRINT 'Creating column encryption certificate...';
    CREATE CERTIFICATE ColumnEncryption_Certificate
    WITH SUBJECT = 'Certificate for Column-Level Encryption - SOC 2 Compliance',
         EXPIRY_DATE = '2030-12-31';
    PRINT 'Column encryption certificate created.';
END
ELSE
BEGIN
    PRINT 'Column encryption certificate already exists.';
END
GO

-- Step 3: Create Symmetric Key for Column Encryption
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = 'ColumnEncryption_SymmetricKey')
BEGIN
    PRINT 'Creating symmetric key for column encryption...';
    CREATE SYMMETRIC KEY ColumnEncryption_SymmetricKey
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE ColumnEncryption_Certificate;
    PRINT 'Symmetric key created.';
END
ELSE
BEGIN
    PRINT 'Symmetric key already exists.';
END
GO

-- Step 4: Backup Column Encryption Certificate
PRINT '';
PRINT 'IMPORTANT: Column Encryption Certificate Backup';
PRINT '------------------------------------------------';
PRINT 'The column encryption certificate should be backed up and stored securely.';
PRINT '';
PRINT 'To backup the certificate, run the following commands:';
PRINT '';
PRINT '-- Backup certificate to file (CHANGE PATH AS NEEDED):';
PRINT 'BACKUP CERTIFICATE ColumnEncryption_Certificate';
PRINT '   TO FILE = ''C:\TDEBackup\ColumnEncryption_Certificate.cer''';
PRINT '   WITH PRIVATE KEY (';
PRINT '      FILE = ''C:\TDEBackup\ColumnEncryption_Certificate.pvk'',';
PRINT '      ENCRYPTION BY PASSWORD = ''StrongColumnKeyPassword789!@#''';
PRINT '   );';
PRINT '';

-- =============================================
-- PART 3: Add Encrypted Columns to Users Table
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 3: Add Encrypted Columns (Example)'
PRINT '=============================================='
PRINT '';

-- Add encrypted columns for sensitive user data (if not already present)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Users') AND name = 'EncryptedSSN')
BEGIN
    PRINT 'Adding encrypted SSN column to Users table...';
    ALTER TABLE dbo.Users
    ADD EncryptedSSN VARBINARY(256) NULL;
    PRINT 'EncryptedSSN column added.';
END
ELSE
BEGIN
    PRINT 'EncryptedSSN column already exists.';
END

IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Users') AND name = 'EncryptedPhone')
BEGIN
    PRINT 'Adding encrypted phone column to Users table...';
    ALTER TABLE dbo.Users
    ADD EncryptedPhone VARBINARY(256) NULL;
    PRINT 'EncryptedPhone column added.';
END
ELSE
BEGIN
    PRINT 'EncryptedPhone column already exists.';
END
GO

-- =============================================
-- PART 4: Encryption/Decryption Helper Procedures
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 4: Encryption Helper Procedures'
PRINT '=============================================='
PRINT '';

-- Procedure to encrypt sensitive data
CREATE OR ALTER PROCEDURE dbo.usp_EncryptData
    @PlainText NVARCHAR(256),
    @EncryptedData VARBINARY(256) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Open symmetric key
    OPEN SYMMETRIC KEY ColumnEncryption_SymmetricKey
    DECRYPTION BY CERTIFICATE ColumnEncryption_Certificate;

    -- Encrypt data
    SET @EncryptedData = EncryptByKey(Key_GUID('ColumnEncryption_SymmetricKey'), @PlainText);

    -- Close symmetric key
    CLOSE SYMMETRIC KEY ColumnEncryption_SymmetricKey;
END;
GO

PRINT 'Procedure usp_EncryptData created.';
GO

-- Procedure to decrypt sensitive data
CREATE OR ALTER PROCEDURE dbo.usp_DecryptData
    @EncryptedData VARBINARY(256),
    @PlainText NVARCHAR(256) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Open symmetric key
    OPEN SYMMETRIC KEY ColumnEncryption_SymmetricKey
    DECRYPTION BY CERTIFICATE ColumnEncryption_Certificate;

    -- Decrypt data
    SET @PlainText = CAST(DecryptByKey(@EncryptedData) AS NVARCHAR(256));

    -- Close symmetric key
    CLOSE SYMMETRIC KEY ColumnEncryption_SymmetricKey;
END;
GO

PRINT 'Procedure usp_DecryptData created.';
GO

-- =============================================
-- PART 5: Example Usage and Testing
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 5: Encryption Testing'
PRINT '=============================================='
PRINT '';

-- Test encryption/decryption
DECLARE @OriginalSSN NVARCHAR(256) = '123-45-6789';
DECLARE @EncryptedSSN VARBINARY(256);
DECLARE @DecryptedSSN NVARCHAR(256);

-- Encrypt
EXEC dbo.usp_EncryptData @PlainText = @OriginalSSN, @EncryptedData = @EncryptedSSN OUTPUT;
PRINT 'Encrypted SSN: ' + CAST(@EncryptedSSN AS NVARCHAR(MAX));

-- Decrypt
EXEC dbo.usp_DecryptData @EncryptedData = @EncryptedSSN, @PlainText = @DecryptedSSN OUTPUT;
PRINT 'Decrypted SSN: ' + @DecryptedSSN;

IF @OriginalSSN = @DecryptedSSN
    PRINT 'Encryption/Decryption test PASSED.';
ELSE
    PRINT 'Encryption/Decryption test FAILED.';
GO

-- =============================================
-- PART 6: Verification Queries
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 6: Encryption Status Verification'
PRINT '=============================================='
PRINT '';

PRINT 'Database Master Keys:';
SELECT name, create_date, modify_date
FROM sys.symmetric_keys
WHERE name = '##MS_DatabaseMasterKey##';

PRINT '';
PRINT 'Certificates:';
SELECT name, subject, start_date, expiry_date
FROM sys.certificates
WHERE name IN ('TDE_Certificate_MonitoringDB', 'ColumnEncryption_Certificate');

PRINT '';
PRINT 'Symmetric Keys:';
SELECT name, algorithm_desc, key_length, create_date
FROM sys.symmetric_keys
WHERE name = 'ColumnEncryption_SymmetricKey';

PRINT '';
PRINT 'TDE Encryption Status:';
SELECT
    DB_NAME(database_id) AS DatabaseName,
    encryption_state,
    CASE encryption_state
        WHEN 0 THEN 'No encryption'
        WHEN 1 THEN 'Unencrypted'
        WHEN 2 THEN 'Encryption in progress'
        WHEN 3 THEN 'Encrypted'
        WHEN 4 THEN 'Key change in progress'
        WHEN 5 THEN 'Decryption in progress'
        WHEN 6 THEN 'Protection change in progress'
    END AS EncryptionStateDescription,
    percent_complete,
    encryptor_type
FROM sys.dm_database_encryption_keys
WHERE database_id = DB_ID('MonitoringDB');

PRINT '';
PRINT '=============================================='
PRINT 'Encryption at Rest deployment complete!'
PRINT '=============================================='
PRINT '';
PRINT 'Summary:';
PRINT '- TDE enabled on MonitoringDB (if supported)';
PRINT '- Column-level encryption configured';
PRINT '- Encryption/decryption procedures created';
PRINT '- Test encryption/decryption successful';
PRINT '';
PRINT 'CRITICAL REMINDERS:';
PRINT '1. BACKUP TDE certificate and private key immediately!';
PRINT '2. Store certificate backups in secure, off-server location';
PRINT '3. Without certificate backups, encrypted databases cannot be restored';
PRINT '4. Document certificate passwords in secure password manager';
PRINT '5. Test certificate restoration process in non-production environment';
PRINT '';
PRINT 'SOC 2 Controls: CC6.6 (Encryption at Rest), CC6.7 (Key Management)';
GO
