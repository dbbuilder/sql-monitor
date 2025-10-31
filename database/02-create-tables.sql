-- =====================================================
-- Script: 02-create-tables.sql
-- Description: Creates core tables for MonitoringDB
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- TDD Phase: GREEN (Create schema to pass tests)
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- Table: dbo.Servers
-- Description: Inventory of monitored SQL Server instances
-- Tests: database/tests/test_Servers.sql
-- =====================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Servers') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Servers
    (
        ServerID            INT             IDENTITY(1,1)   NOT NULL,
        ServerName          NVARCHAR(256)                   NOT NULL,
        Environment         NVARCHAR(50)                    NULL,        -- Production, Development, Staging, Test
        IsActive            BIT                             NOT NULL DEFAULT 1,
        CreatedDate         DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),
        ModifiedDate        DATETIME2                       NULL,
        LinkedServerName    NVARCHAR(128)                   NULL,        -- Name of linked server (NULL=local server)
                                                                         -- Used for remote collection via OPENQUERY
                                                                         -- See: CRITICAL-REMOTE-COLLECTION-FIX.md

        CONSTRAINT PK_Servers PRIMARY KEY CLUSTERED (ServerID),
        CONSTRAINT UQ_Servers_ServerName UNIQUE (ServerName)
    );

    PRINT 'Table [dbo].[Servers] created successfully.';
END
ELSE
BEGIN
    PRINT 'Table [dbo].[Servers] already exists.';

    -- Add LinkedServerName column if it doesn't exist (backwards compatibility)
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Servers') AND name = 'LinkedServerName')
    BEGIN
        ALTER TABLE dbo.Servers ADD LinkedServerName NVARCHAR(128) NULL;
        PRINT 'Added [LinkedServerName] column to [dbo].[Servers].';
    END
END
GO

-- Create index on IsActive for filtering
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Servers') AND name = 'IX_Servers_IsActive')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Servers_IsActive
    ON dbo.Servers(IsActive)
    INCLUDE (ServerName, Environment);

    PRINT 'Index [IX_Servers_IsActive] created on [dbo].[Servers].';
END
GO

-- =====================================================
-- Table: dbo.PerformanceMetrics
-- Description: Time-series performance metrics (partitioned by month)
-- Tests: database/tests/test_PerformanceMetrics.sql
-- Requires: Partition function and scheme (03-create-partitions.sql)
-- =====================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PerformanceMetrics') AND type = 'U')
BEGIN
    CREATE TABLE dbo.PerformanceMetrics
    (
        MetricID        BIGINT          IDENTITY(1,1)   NOT NULL,
        ServerID        INT                             NOT NULL,
        CollectionTime  DATETIME2                       NOT NULL,
        MetricCategory  NVARCHAR(50)                    NOT NULL,    -- CPU, Memory, IO, Wait, Query, etc.
        MetricName      NVARCHAR(100)                   NOT NULL,    -- Specific metric name
        MetricValue     DECIMAL(18,4)                   NULL,        -- Nullable for non-numeric metrics

        CONSTRAINT PK_PerformanceMetrics PRIMARY KEY CLUSTERED (CollectionTime, MetricID),
        CONSTRAINT FK_PerformanceMetrics_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
    )
    ON PS_MonitoringByMonth(CollectionTime);  -- Partition by CollectionTime

    PRINT 'Table [dbo].[PerformanceMetrics] created successfully (partitioned).';
END
ELSE
BEGIN
    PRINT 'Table [dbo].[PerformanceMetrics] already exists.';
END
GO

-- Create columnstore index for fast aggregation and compression
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics') AND name = 'IX_PerformanceMetrics_CS')
BEGIN
    CREATE NONCLUSTERED COLUMNSTORE INDEX IX_PerformanceMetrics_CS
    ON dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue);

    PRINT 'Columnstore index [IX_PerformanceMetrics_CS] created on [dbo].[PerformanceMetrics].';
END
GO

-- Create nonclustered index on ServerID for FK lookups
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics') AND name = 'IX_PerformanceMetrics_ServerID')
BEGIN
    CREATE NONCLUSTERED INDEX IX_PerformanceMetrics_ServerID
    ON dbo.PerformanceMetrics(ServerID, CollectionTime)
    INCLUDE (MetricCategory, MetricName, MetricValue);

    PRINT 'Index [IX_PerformanceMetrics_ServerID] created on [dbo].[PerformanceMetrics].';
END
GO

-- =====================================================
-- Verification
-- =====================================================

PRINT '';
PRINT '========================================================';
PRINT 'Table Creation Complete (GREEN Phase)';
PRINT '========================================================';
PRINT 'Created:';
PRINT '  - dbo.Servers (ServerID, ServerName, Environment, IsActive, CreatedDate, ModifiedDate)';
PRINT '  - dbo.PerformanceMetrics (MetricID, ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Run tests to verify GREEN phase:';
PRINT '   EXEC tSQLt.Run ''ServerTests'';';
PRINT '   EXEC tSQLt.Run ''PerformanceMetricsTests'';';
PRINT '2. Expected: ALL TESTS SHOULD PASS';
PRINT '3. Continue with stored procedures';
PRINT '========================================================';
GO

-- Quick verification query
SELECT
    t.name AS TableName,
    c.name AS ColumnName,
    TYPE_NAME(c.user_type_id) AS DataType,
    c.max_length AS MaxLength,
    c.is_nullable AS IsNullable,
    c.is_identity AS IsIdentity
FROM sys.tables t
INNER JOIN sys.columns c ON t.object_id = c.object_id
WHERE t.name IN ('Servers', 'PerformanceMetrics')
ORDER BY t.name, c.column_id;
GO

-- Show partition information
SELECT
    t.name AS TableName,
    ps.name AS PartitionScheme,
    pf.name AS PartitionFunction,
    p.partition_number AS PartitionNumber,
    p.rows AS RowCount
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id AND i.index_id IN (0, 1)
INNER JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
INNER JOIN sys.partition_functions pf ON ps.function_id = pf.function_id
INNER JOIN sys.partitions p ON t.object_id = p.object_id AND i.index_id = p.index_id
WHERE t.name = 'PerformanceMetrics'
ORDER BY p.partition_number;
GO
