-- =============================================
-- Phase 1.25: Database Schema Browser - Caching Infrastructure
-- Part 1: Core tables for caching and change detection
-- Created: 2025-10-26
-- =============================================

USE [MonitoringDB];
GO

-- Fix for filtered indexes
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Creating Phase 1.25 caching infrastructure tables...';
GO

-- =============================================
-- Table 1: SchemaChangeLog (Change Detection)
-- Purpose: Log all DDL events from monitored databases
-- Populated by: DDL triggers on monitored databases
-- =============================================

IF OBJECT_ID('dbo.SchemaChangeLog', 'U') IS NOT NULL
    DROP TABLE dbo.SchemaChangeLog;
GO

CREATE TABLE dbo.SchemaChangeLog (
    ChangeLogID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerName NVARCHAR(128) NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NULL,
    ObjectName NVARCHAR(128) NULL,
    EventType VARCHAR(50) NOT NULL, -- CREATE_TABLE, ALTER_PROCEDURE, DROP_VIEW, etc.
    EventTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    ProcessedAt DATETIME2(7) NULL, -- NULL = not yet processed

    INDEX IX_SchemaChangeLog_Pending (ProcessedAt)
        INCLUDE (ServerName, DatabaseName, EventType)
        WHERE ProcessedAt IS NULL,
    INDEX IX_SchemaChangeLog_Database (ServerName, DatabaseName, EventTime DESC)
);
GO

PRINT 'Created table: dbo.SchemaChangeLog';
GO

-- =============================================
-- Table 2: DatabaseMetadataCache (Cache Status Tracking)
-- Purpose: Track which databases have current cached metadata
-- Updated by: usp_RefreshMetadataCache
-- =============================================

IF OBJECT_ID('dbo.DatabaseMetadataCache', 'U') IS NOT NULL
    DROP TABLE dbo.DatabaseMetadataCache;
GO

CREATE TABLE dbo.DatabaseMetadataCache (
    CacheID INT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    LastRefreshTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    LastSchemaChangeTime DATETIME2(7) NULL, -- Most recent change from SchemaChangeLog
    ObjectCount INT NULL, -- Total tables + views + SPs + functions
    TableCount INT NULL,
    ViewCount INT NULL,
    ProcedureCount INT NULL,
    FunctionCount INT NULL,
    IsCurrent BIT NOT NULL DEFAULT 1, -- 0 = needs refresh

    CONSTRAINT FK_DatabaseMetadataCache_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
    CONSTRAINT UQ_DatabaseMetadataCache_Server_Database UNIQUE (ServerID, DatabaseName),
    INDEX IX_DatabaseMetadataCache_NeedsRefresh (IsCurrent)
        INCLUDE (ServerID, DatabaseName)
        WHERE IsCurrent = 0
);
GO

PRINT 'Created table: dbo.DatabaseMetadataCache';
GO

-- =============================================
-- Table 3: TableMetadata (Cached Table Inventory)
-- Purpose: Store all table metadata from monitored databases
-- Populated by: usp_CollectTableMetadata
-- =============================================

IF OBJECT_ID('dbo.TableMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.TableMetadata;
GO

CREATE TABLE dbo.TableMetadata (
    MetadataID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    ObjectID INT NOT NULL,

    -- Statistics
    [RowCount] BIGINT NULL,
    TotalSizeMB DECIMAL(18,2) NULL,
    DataSizeMB DECIMAL(18,2) NULL,
    IndexSizeMB DECIMAL(18,2) NULL,
    ColumnCount INT NULL,
    IndexCount INT NULL,
    PartitionCount INT NULL,

    -- Metadata
    IsPartitioned BIT NOT NULL DEFAULT 0,
    CompressionType VARCHAR(20) NULL, -- None, Row, Page, Columnstore
    CreatedDate DATETIME2(7) NULL,
    ModifiedDate DATETIME2(7) NULL,

    -- Cache tracking
    LastRefreshTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_TableMetadata_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID),
    INDEX IX_TableMetadata_Server_Database (ServerID, DatabaseName) INCLUDE (SchemaName, TableName),
    INDEX IX_TableMetadata_TableName (TableName) INCLUDE (DatabaseName, SchemaName),
    INDEX IX_TableMetadata_Size (TotalSizeMB DESC) INCLUDE (DatabaseName, SchemaName, TableName)
);
GO

PRINT 'Created table: dbo.TableMetadata';
GO

-- =============================================
-- Table 4: ColumnMetadata (Cached Column Details)
-- Purpose: Store all column metadata per table
-- Populated by: usp_CollectColumnMetadata
-- =============================================

IF OBJECT_ID('dbo.ColumnMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.ColumnMetadata;
GO

CREATE TABLE dbo.ColumnMetadata (
    ColumnMetadataID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    ColumnName NVARCHAR(128) NOT NULL,

    -- Column details
    DataType NVARCHAR(128) NOT NULL,
    MaxLength INT NULL,
    Precision INT NULL,
    Scale INT NULL,
    IsNullable BIT NOT NULL,
    IsIdentity BIT NOT NULL,
    IsComputed BIT NOT NULL,
    IsPrimaryKey BIT NOT NULL,
    IsForeignKey BIT NOT NULL,
    DefaultConstraint NVARCHAR(MAX) NULL,
    OrdinalPosition INT NOT NULL,

    -- Cache tracking
    LastRefreshTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    INDEX IX_ColumnMetadata_Table (ServerID, DatabaseName, SchemaName, TableName, OrdinalPosition)
);
GO

PRINT 'Created table: dbo.ColumnMetadata';
GO

-- =============================================
-- Table 5: IndexMetadata (Cached Index Details)
-- Purpose: Store all index metadata with fragmentation
-- Populated by: usp_CollectIndexMetadata
-- =============================================

IF OBJECT_ID('dbo.IndexMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.IndexMetadata;
GO

CREATE TABLE dbo.IndexMetadata (
    IndexMetadataID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    IndexName NVARCHAR(128) NOT NULL,

    -- Index details
    IndexType VARCHAR(50) NOT NULL, -- CLUSTERED, NONCLUSTERED, COLUMNSTORE, etc.
    KeyColumns NVARCHAR(MAX) NULL,
    IncludedColumns NVARCHAR(MAX) NULL,
    FilterDefinition NVARCHAR(MAX) NULL,
    IsUnique BIT NOT NULL,
    IsPrimaryKey BIT NOT NULL,
    [FillFactor] INT NULL,

    -- Statistics
    SizeMB DECIMAL(18,2) NULL,
    [RowCount] BIGINT NULL,
    FragmentationPercent DECIMAL(5,2) NULL,
    PageCount BIGINT NULL,
    CompressionType VARCHAR(20) NULL,

    -- Cache tracking
    LastRefreshTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    INDEX IX_IndexMetadata_Table (ServerID, DatabaseName, SchemaName, TableName),
    INDEX IX_IndexMetadata_Fragmentation (FragmentationPercent DESC)
        WHERE FragmentationPercent > 10
);
GO

PRINT 'Created table: dbo.IndexMetadata';
GO

-- =============================================
-- Table 6: PartitionMetadata (Cached Partition Statistics)
-- Purpose: Store partition details for partitioned tables
-- Populated by: usp_CollectPartitionMetadata
-- =============================================

IF OBJECT_ID('dbo.PartitionMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.PartitionMetadata;
GO

CREATE TABLE dbo.PartitionMetadata (
    PartitionMetadataID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    IndexName NVARCHAR(128) NOT NULL,
    PartitionNumber INT NOT NULL,

    -- Partition details
    BoundaryValue NVARCHAR(MAX) NULL, -- Converted to string for storage
    [RowCount] BIGINT NULL,
    SizeMB DECIMAL(18,2) NULL,
    CompressionType VARCHAR(20) NULL,
    DataSpace NVARCHAR(128) NULL,

    -- Cache tracking
    LastRefreshTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    INDEX IX_PartitionMetadata_Table (ServerID, DatabaseName, SchemaName, TableName, PartitionNumber)
);
GO

PRINT 'Created table: dbo.PartitionMetadata';
GO

-- =============================================
-- Table 7: ForeignKeyMetadata (Cached FK Relationships)
-- Purpose: Store all foreign key relationships
-- Populated by: usp_CollectForeignKeyMetadata
-- =============================================

IF OBJECT_ID('dbo.ForeignKeyMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.ForeignKeyMetadata;
GO

CREATE TABLE dbo.ForeignKeyMetadata (
    ForeignKeyMetadataID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    ForeignKeyName NVARCHAR(128) NOT NULL,

    -- Parent (referencing) side
    ParentSchemaName NVARCHAR(128) NOT NULL,
    ParentTableName NVARCHAR(128) NOT NULL,
    ParentColumns NVARCHAR(MAX) NOT NULL, -- Comma-separated list

    -- Referenced side
    ReferencedSchemaName NVARCHAR(128) NOT NULL,
    ReferencedTableName NVARCHAR(128) NOT NULL,
    ReferencedColumns NVARCHAR(MAX) NOT NULL, -- Comma-separated list

    -- Rules
    DeleteRule VARCHAR(20) NULL, -- CASCADE, SET NULL, NO ACTION, etc.
    UpdateRule VARCHAR(20) NULL,
    IsDisabled BIT NOT NULL,
    IsNotTrusted BIT NOT NULL,

    -- Cache tracking
    LastRefreshTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    INDEX IX_ForeignKeyMetadata_ParentTable (ServerID, DatabaseName, ParentSchemaName, ParentTableName),
    INDEX IX_ForeignKeyMetadata_ReferencedTable (ServerID, DatabaseName, ReferencedSchemaName, ReferencedTableName)
);
GO

PRINT 'Created table: dbo.ForeignKeyMetadata';
GO

-- =============================================
-- Table 8: CodeObjectMetadata (Cached Code Objects)
-- Purpose: Store metadata for SPs, views, functions, triggers
-- Populated by: usp_CollectCodeObjectMetadata
-- =============================================

IF OBJECT_ID('dbo.CodeObjectMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.CodeObjectMetadata;
GO

CREATE TABLE dbo.CodeObjectMetadata (
    CodeObjectMetadataID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    ObjectName NVARCHAR(128) NOT NULL,
    ObjectType VARCHAR(50) NOT NULL, -- PROCEDURE, VIEW, FUNCTION, TRIGGER

    -- Metadata
    CreatedDate DATETIME2(7) NULL,
    ModifiedDate DATETIME2(7) NULL,
    LineCount INT NULL,
    CharacterCount INT NULL,
    DependencyCount INT NULL, -- Count of tables/views referenced

    -- Code reference (links to existing ObjectCode table)
    CodeID BIGINT NULL,

    -- Cache tracking
    LastRefreshTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_CodeObjectMetadata_ObjectCode FOREIGN KEY (CodeID) REFERENCES dbo.ObjectCode(CodeID),
    INDEX IX_CodeObjectMetadata_Server_Database (ServerID, DatabaseName, ObjectType),
    INDEX IX_CodeObjectMetadata_ObjectType (ObjectType) INCLUDE (DatabaseName, SchemaName, ObjectName),
    INDEX IX_CodeObjectMetadata_Modified (ModifiedDate DESC) INCLUDE (DatabaseName, SchemaName, ObjectName)
);
GO

PRINT 'Created table: dbo.CodeObjectMetadata';
GO

-- =============================================
-- Table 9: DependencyMetadata (Cached Dependencies)
-- Purpose: Store object-to-object dependencies
-- Populated by: usp_CollectDependencyMetadata
-- =============================================

IF OBJECT_ID('dbo.DependencyMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.DependencyMetadata;
GO

CREATE TABLE dbo.DependencyMetadata (
    DependencyMetadataID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,

    -- Referencing object (depends on)
    ReferencingSchemaName NVARCHAR(128) NOT NULL,
    ReferencingObjectName NVARCHAR(128) NOT NULL,
    ReferencingObjectType VARCHAR(50) NOT NULL, -- TABLE, VIEW, PROCEDURE, FUNCTION, TRIGGER

    -- Referenced object (is dependency)
    ReferencedSchemaName NVARCHAR(128) NULL,
    ReferencedObjectName NVARCHAR(128) NULL,
    ReferencedObjectType VARCHAR(50) NULL,

    -- Dependency details
    IsSchemaDependent BIT NOT NULL DEFAULT 0,
    IsAmbiguous BIT NOT NULL DEFAULT 0,

    -- Cache tracking
    LastRefreshTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    INDEX IX_DependencyMetadata_Referencing (ServerID, DatabaseName, ReferencingSchemaName, ReferencingObjectName),
    INDEX IX_DependencyMetadata_Referenced (ServerID, DatabaseName, ReferencedSchemaName, ReferencedObjectName)
);
GO

PRINT 'Created table: dbo.DependencyMetadata';
GO

-- =============================================
-- Summary
-- =============================================

PRINT '';
PRINT '========================================';
PRINT 'Phase 1.25 Infrastructure Summary';
PRINT '========================================';
PRINT 'Tables created:';
PRINT '  1. SchemaChangeLog - DDL event tracking';
PRINT '  2. DatabaseMetadataCache - Cache status';
PRINT '  3. TableMetadata - Table inventory';
PRINT '  4. ColumnMetadata - Column details';
PRINT '  5. IndexMetadata - Index details';
PRINT '  6. PartitionMetadata - Partition stats';
PRINT '  7. ForeignKeyMetadata - FK relationships';
PRINT '  8. CodeObjectMetadata - Code objects';
PRINT '  9. DependencyMetadata - Dependencies';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Write TDD tests for change detection';
PRINT '  2. Implement usp_DetectSchemaChanges';
PRINT '  3. Implement usp_RefreshMetadataCache';
PRINT '  4. Create DDL triggers on monitored databases';
PRINT '========================================';
GO
