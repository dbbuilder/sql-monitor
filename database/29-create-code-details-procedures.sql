-- =====================================================
-- Script: 29-create-code-details-procedures.sql
-- Description: Create procedures for code/table details
-- Author: SQL Server Monitor Project
-- Date: 2025-10-30
-- Phase: 1.9 - Code Browser Enhancement
-- Purpose: Provide sp_help and sp_helptext style views
-- =====================================================

USE MonitoringDB;
GO

PRINT '=========================================================================';
PRINT 'Phase 1.9: Creating Code Details Procedures';
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
    @ServerName     NVARCHAR(256),
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
        tm.ServerName,
        tm.DatabaseName,
        tm.SchemaName,
        tm.TableName,
        tm.RowCount,
        tm.TotalSpaceMB,
        tm.DataSpaceMB,
        tm.IndexSpaceMB,
        tm.LastUpdated
    FROM dbo.TableMetadata tm
    WHERE tm.ServerName = @ServerName
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
        cm.DefaultValue
    FROM dbo.ColumnMetadata cm
    WHERE cm.ServerName = @ServerName
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
    WHERE im.ServerName = @ServerName
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
    WHERE fkm.ServerName = @ServerName
      AND fkm.DatabaseName = @DatabaseName
      AND fkm.SchemaName = @SchemaName
      AND fkm.TableName = @TableName
    ORDER BY fkm.ConstraintName;

    -- =====================================================
    -- Dependencies (Tables that reference this table)
    -- =====================================================

    SELECT
        'Referenced By' AS Section,
        dm.ReferencedSchema,
        dm.ReferencedName,
        dm.ReferencedType,
        dm.ReferencingSchema,
        dm.ReferencingName,
        dm.ReferencingType
    FROM dbo.DependencyMetadata dm
    WHERE dm.ServerName = @ServerName
      AND dm.DatabaseName = @DatabaseName
      AND dm.ReferencedSchema = @SchemaName
      AND dm.ReferencedName = @TableName
    ORDER BY dm.ReferencingType, dm.ReferencingName;

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
    @ServerName     NVARCHAR(256),
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
        com.ServerName,
        com.DatabaseName,
        com.SchemaName,
        com.ObjectName,
        com.ObjectType,
        com.CreateDate,
        com.ModifyDate,
        com.DefinitionLines
    FROM dbo.CodeObjectMetadata com
    WHERE com.ServerName = @ServerName
      AND com.DatabaseName = @DatabaseName
      AND com.SchemaName = @SchemaName
      AND com.ObjectName = @ObjectName;

    -- =====================================================
    -- Object Definition (Code)
    -- =====================================================

    SELECT
        'Object Definition' AS Section,
        oc.LineNumber,
        oc.CodeLine
    FROM dbo.ObjectCode oc
    WHERE oc.ServerName = @ServerName
      AND oc.DatabaseName = @DatabaseName
      AND oc.SchemaName = @SchemaName
      AND oc.ObjectName = @ObjectName
    ORDER BY oc.LineNumber;

    -- =====================================================
    -- Parameters (if procedure/function)
    -- =====================================================

    IF EXISTS (
        SELECT 1 FROM dbo.CodeObjectMetadata
        WHERE ServerName = @ServerName
          AND DatabaseName = @DatabaseName
          AND SchemaName = @SchemaName
          AND ObjectName = @ObjectName
          AND ObjectType IN ('PROCEDURE', 'FUNCTION')
    )
    BEGIN
        -- Note: Parameters would need to be stored separately
        -- For now, extract from code or add ParameterMetadata table
        SELECT
            'Parameters' AS Section,
            'No parameter metadata stored yet' AS Note;
    END;

    -- =====================================================
    -- Dependencies
    -- =====================================================

    SELECT
        'Dependencies' AS Section,
        dm.ReferencedSchema,
        dm.ReferencedName,
        dm.ReferencedType
    FROM dbo.DependencyMetadata dm
    WHERE dm.ServerName = @ServerName
      AND dm.DatabaseName = @DatabaseName
      AND dm.ReferencingSchema = @SchemaName
      AND dm.ReferencingName = @ObjectName
    ORDER BY dm.ReferencedType, dm.ReferencedName;

    -- =====================================================
    -- Referenced By (What uses this object)
    -- =====================================================

    SELECT
        'Referenced By' AS Section,
        dm.ReferencingSchema,
        dm.ReferencingName,
        dm.ReferencingType
    FROM dbo.DependencyMetadata dm
    WHERE dm.ServerName = @ServerName
      AND dm.DatabaseName = @DatabaseName
      AND dm.ReferencedSchema = @SchemaName
      AND dm.ReferencedName = @ObjectName
    ORDER BY dm.ReferencingType, dm.ReferencingName;

END;
GO

PRINT '  ✓ Stored procedure created: dbo.usp_GetCodeObjectText';
PRINT '';
GO

-- =====================================================
-- Usage Examples
-- =====================================================

PRINT '=========================================================================';
PRINT 'Usage Examples:';
PRINT '=========================================================================';
PRINT '';
PRINT '-- Get table details (sp_help style):';
PRINT 'EXEC dbo.usp_GetTableDetails';
PRINT '    @ServerName = ''sqltest.schoolvision.net,14333'',';
PRINT '    @DatabaseName = ''YourDatabase'',';
PRINT '    @SchemaName = ''dbo'',';
PRINT '    @TableName = ''YourTable'';';
PRINT '';
PRINT '-- Get code object text (sp_helptext style):';
PRINT 'EXEC dbo.usp_GetCodeObjectText';
PRINT '    @ServerName = ''sqltest.schoolvision.net,14333'',';
PRINT '    @DatabaseName = ''YourDatabase'',';
PRINT '    @SchemaName = ''dbo'',';
PRINT '    @ObjectName = ''YourProcedure'';';
PRINT '';
PRINT '=========================================================================';
PRINT 'Phase 1.9 Code Details Procedures: COMPLETE';
PRINT '=========================================================================';
GO
