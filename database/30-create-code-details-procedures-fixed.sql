-- =====================================================
-- Script: 30-create-code-details-procedures-fixed.sql
-- Description: Create procedures for code/table details (FIXED)
-- Author: SQL Server Monitor Project
-- Date: 2025-10-30
-- Phase: 1.9 - Code Browser Enhancement
-- Purpose: Provide sp_help and sp_helptext style views
-- =====================================================

USE MonitoringDB;
GO

PRINT '=========================================================================';
PRINT 'Phase 1.9: Creating Code Details Procedures (FIXED)';
PRINT '=========================================================================';
PRINT '';
GO

-- =====================================================
-- Procedure: Get Table Details (sp_help style)
-- =====================================================

IF OBJECT_ID('dbo.usp_GetTableDetails', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetTableDetails;
GO

PRINT 'Creating stored procedure: dbo.usp_GetTableDetails';
GO

CREATE PROCEDURE dbo.usp_GetTableDetails
    @ServerID       INT,
    @DatabaseName   SYSNAME,
    @SchemaName     SYSNAME,
    @TableName      SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    -- =====================================================
    -- Table Basic Info
    -- =====================================================

    SELECT
        'Table Information' AS Section,
        s.ServerName,
        tm.DatabaseName,
        tm.SchemaName,
        tm.TableName,
        tm.[RowCount],
        tm.TotalSizeMB,
        tm.DataSizeMB,
        tm.IndexSizeMB,
        tm.ColumnCount,
        tm.IndexCount,
        tm.IsPartitioned,
        tm.CompressionType,
        tm.CreatedDate,
        tm.ModifiedDate,
        tm.LastRefreshTime
    FROM dbo.TableMetadata tm
    INNER JOIN dbo.Servers s ON tm.ServerID = s.ServerID
    WHERE tm.ServerID = @ServerID
      AND tm.DatabaseName = @DatabaseName
      AND tm.SchemaName = @SchemaName
      AND tm.TableName = @TableName;

    -- =====================================================
    -- Columns
    -- =====================================================

    SELECT
        'Columns' AS Section,
        cm.ColumnName,
        cm.DataType,
        cm.MaxLength,
        cm.Precision,
        cm.Scale,
        cm.IsNullable,
        cm.IsIdentity,
        cm.IsComputed,
        cm.DefaultValue,
        cm.OrdinalPosition
    FROM dbo.ColumnMetadata cm
    WHERE cm.ServerID = @ServerID
      AND cm.DatabaseName = @DatabaseName
      AND cm.SchemaName = @SchemaName
      AND cm.TableName = @TableName
    ORDER BY cm.OrdinalPosition;

    -- =====================================================
    -- Indexes
    -- =====================================================

    SELECT
        'Indexes' AS Section,
        im.IndexName,
        im.IndexType,
        im.IsUnique,
        im.IsPrimaryKey,
        im.Columns,
        im.IncludedColumns,
        im.FilterDefinition
    FROM dbo.IndexMetadata im
    WHERE im.ServerID = @ServerID
      AND im.DatabaseName = @DatabaseName
      AND im.SchemaName = @SchemaName
      AND im.TableName = @TableName
    ORDER BY im.IsPrimaryKey DESC, im.IndexName;

    -- =====================================================
    -- Foreign Keys
    -- =====================================================

    SELECT
        'Foreign Keys' AS Section,
        fkm.ConstraintName,
        fkm.ReferencedSchema,
        fkm.ReferencedTable,
        fkm.Columns,
        fkm.ReferencedColumns,
        fkm.IsDisabled,
        fkm.IsNotTrusted
    FROM dbo.ForeignKeyMetadata fkm
    WHERE fkm.ServerID = @ServerID
      AND fkm.DatabaseName = @DatabaseName
      AND fkm.SchemaName = @SchemaName
      AND fkm.TableName = @TableName
    ORDER BY fkm.ConstraintName;

    -- =====================================================
    -- Dependencies (Tables that reference this table)
    -- =====================================================

    SELECT
        'Referenced By' AS Section,
        dm.ReferencingSchemaName AS SchemaName,
        dm.ReferencingObjectName AS ObjectName,
        dm.ReferencingObjectType AS ObjectType
    FROM dbo.DependencyMetadata dm
    WHERE dm.ServerID = @ServerID
      AND dm.DatabaseName = @DatabaseName
      AND dm.ReferencedSchemaName = @SchemaName
      AND dm.ReferencedObjectName = @TableName
    ORDER BY dm.ReferencingObjectType, dm.ReferencingObjectName;

END;
GO

PRINT '  ✓ Stored procedure created: dbo.usp_GetTableDetails';
PRINT '';
GO

-- =====================================================
-- Procedure: Get Code Object Text (sp_helptext style)
-- =====================================================

IF OBJECT_ID('dbo.usp_GetCodeObjectText', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetCodeObjectText;
GO

PRINT 'Creating stored procedure: dbo.usp_GetCodeObjectText';
GO

CREATE PROCEDURE dbo.usp_GetCodeObjectText
    @ServerID       INT,
    @DatabaseName   SYSNAME,
    @SchemaName     SYSNAME,
    @ObjectName     SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    -- =====================================================
    -- Object Basic Info
    -- =====================================================

    SELECT
        'Object Information' AS Section,
        s.ServerName,
        com.DatabaseName,
        com.SchemaName,
        com.ObjectName,
        com.ObjectType,
        com.CreatedDate,
        com.ModifiedDate,
        com.LineCount,
        com.CharacterCount,
        com.DependencyCount,
        com.LastRefreshTime
    FROM dbo.CodeObjectMetadata com
    INNER JOIN dbo.Servers s ON com.ServerID = s.ServerID
    WHERE com.ServerID = @ServerID
      AND com.DatabaseName = @DatabaseName
      AND com.SchemaName = @SchemaName
      AND com.ObjectName = @ObjectName;

    -- =====================================================
    -- Object Definition (Code) - Full Text
    -- =====================================================

    SELECT
        'Object Definition' AS Section,
        oc.Definition AS CodeText,
        LEN(oc.Definition) AS CharacterCount,
        LEN(oc.Definition) - LEN(REPLACE(oc.Definition, CHAR(10), '')) + 1 AS LineCount
    FROM dbo.ObjectCode oc
    WHERE oc.ServerID = @ServerID
      AND oc.DatabaseName = @DatabaseName
      AND oc.SchemaName = @SchemaName
      AND oc.ObjectName = @ObjectName;

    -- =====================================================
    -- Object Definition (Code) - Line by Line
    -- For display purposes, split into individual lines
    -- =====================================================

    ;WITH CodeLines AS (
        SELECT
            oc.Definition,
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS LineNumber,
            value AS CodeLine
        FROM dbo.ObjectCode oc
        CROSS APPLY STRING_SPLIT(oc.Definition, CHAR(10))
        WHERE oc.ServerID = @ServerID
          AND oc.DatabaseName = @DatabaseName
          AND oc.SchemaName = @SchemaName
          AND oc.ObjectName = @ObjectName
    )
    SELECT
        'Code Lines' AS Section,
        LineNumber,
        REPLACE(CodeLine, CHAR(13), '') AS CodeLine  -- Remove CR, keep LF
    FROM CodeLines
    ORDER BY LineNumber;

    -- =====================================================
    -- Dependencies (What this object uses)
    -- =====================================================

    SELECT
        'Dependencies' AS Section,
        dm.ReferencedSchemaName AS SchemaName,
        dm.ReferencedObjectName AS ObjectName,
        dm.ReferencedObjectType AS ObjectType
    FROM dbo.DependencyMetadata dm
    WHERE dm.ServerID = @ServerID
      AND dm.DatabaseName = @DatabaseName
      AND dm.ReferencingSchemaName = @SchemaName
      AND dm.ReferencingObjectName = @ObjectName
    ORDER BY dm.ReferencedObjectType, dm.ReferencedObjectName;

    -- =====================================================
    -- Referenced By (What uses this object)
    -- =====================================================

    SELECT
        'Referenced By' AS Section,
        dm.ReferencingSchemaName AS SchemaName,
        dm.ReferencingObjectName AS ObjectName,
        dm.ReferencingObjectType AS ObjectType
    FROM dbo.DependencyMetadata dm
    WHERE dm.ServerID = @ServerID
      AND dm.DatabaseName = @DatabaseName
      AND dm.ReferencedSchemaName = @SchemaName
      AND dm.ReferencedObjectName = @ObjectName
    ORDER BY dm.ReferencingObjectType, dm.ReferencingObjectName;

END;
GO

PRINT '  ✓ Stored procedure created: dbo.usp_GetCodeObjectText';
PRINT '';
GO

-- =====================================================
-- Helper Function: Get ServerID from ServerName
-- =====================================================

IF OBJECT_ID('dbo.udf_GetServerID', 'FN') IS NOT NULL
    DROP FUNCTION dbo.udf_GetServerID;
GO

PRINT 'Creating function: dbo.udf_GetServerID';
GO

CREATE FUNCTION dbo.udf_GetServerID(@ServerName NVARCHAR(256))
RETURNS INT
AS
BEGIN
    DECLARE @ServerID INT;

    SELECT @ServerID = ServerID
    FROM dbo.Servers
    WHERE ServerName = @ServerName
      AND IsActive = 1;

    RETURN @ServerID;
END;
GO

PRINT '  ✓ Function created: dbo.udf_GetServerID';
PRINT '';
GO

-- =====================================================
-- Wrapper Procedures (Accept ServerName instead of ServerID)
-- =====================================================

IF OBJECT_ID('dbo.usp_GetTableDetailsByName', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetTableDetailsByName;
GO

PRINT 'Creating stored procedure: dbo.usp_GetTableDetailsByName';
GO

CREATE PROCEDURE dbo.usp_GetTableDetailsByName
    @ServerName     NVARCHAR(256),
    @DatabaseName   SYSNAME,
    @SchemaName     SYSNAME,
    @TableName      SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerID INT = dbo.udf_GetServerID(@ServerName);

    IF @ServerID IS NULL
    BEGIN
        RAISERROR('Server not found or inactive: %s', 16, 1, @ServerName);
        RETURN;
    END;

    EXEC dbo.usp_GetTableDetails
        @ServerID = @ServerID,
        @DatabaseName = @DatabaseName,
        @SchemaName = @SchemaName,
        @TableName = @TableName;
END;
GO

PRINT '  ✓ Stored procedure created: dbo.usp_GetTableDetailsByName';
PRINT '';
GO

IF OBJECT_ID('dbo.usp_GetCodeObjectTextByName', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetCodeObjectTextByName;
GO

PRINT 'Creating stored procedure: dbo.usp_GetCodeObjectTextByName';
GO

CREATE PROCEDURE dbo.usp_GetCodeObjectTextByName
    @ServerName     NVARCHAR(256),
    @DatabaseName   SYSNAME,
    @SchemaName     SYSNAME,
    @ObjectName     SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerID INT = dbo.udf_GetServerID(@ServerName);

    IF @ServerID IS NULL
    BEGIN
        RAISERROR('Server not found or inactive: %s', 16, 1, @ServerName);
        RETURN;
    END;

    EXEC dbo.usp_GetCodeObjectText
        @ServerID = @ServerID,
        @DatabaseName = @DatabaseName,
        @SchemaName = @SchemaName,
        @ObjectName = @ObjectName;
END;
GO

PRINT '  ✓ Stored procedure created: dbo.usp_GetCodeObjectTextByName';
PRINT '';
GO

-- =====================================================
-- Usage Examples
-- =====================================================

PRINT '=========================================================================';
PRINT 'Usage Examples:';
PRINT '=========================================================================';
PRINT '';
PRINT '-- Get table details (sp_help style) by ServerID:';
PRINT 'EXEC dbo.usp_GetTableDetails';
PRINT '    @ServerID = 1,';
PRINT '    @DatabaseName = ''YourDatabase'',';
PRINT '    @SchemaName = ''dbo'',';
PRINT '    @TableName = ''YourTable'';';
PRINT '';
PRINT '-- Get table details by ServerName (wrapper):';
PRINT 'EXEC dbo.usp_GetTableDetailsByName';
PRINT '    @ServerName = ''sqltest.schoolvision.net,14333'',';
PRINT '    @DatabaseName = ''YourDatabase'',';
PRINT '    @SchemaName = ''dbo'',';
PRINT '    @TableName = ''YourTable'';';
PRINT '';
PRINT '-- Get code object text (sp_helptext style) by ServerID:';
PRINT 'EXEC dbo.usp_GetCodeObjectText';
PRINT '    @ServerID = 1,';
PRINT '    @DatabaseName = ''YourDatabase'',';
PRINT '    @SchemaName = ''dbo'',';
PRINT '    @ObjectName = ''YourProcedure'';';
PRINT '';
PRINT '-- Get code object text by ServerName (wrapper):';
PRINT 'EXEC dbo.usp_GetCodeObjectTextByName';
PRINT '    @ServerName = ''sqltest.schoolvision.net,14333'',';
PRINT '    @DatabaseName = ''YourDatabase'',';
PRINT '    @SchemaName = ''dbo'',';
PRINT '    @ObjectName = ''YourProcedure'';';
PRINT '';
PRINT '=========================================================================';
PRINT 'Phase 1.9 Code Details Procedures: COMPLETE';
PRINT '=========================================================================';
GO
