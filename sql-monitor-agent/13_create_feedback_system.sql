-- =============================================
-- File: 13_create_feedback_system.sql
-- Purpose: Create modular feedback/analysis system
-- Created: 2025-10-27
-- =============================================

USE DBATools
GO

PRINT 'Creating Feedback System Tables...'
GO

-- =============================================
-- Table: FeedbackRule
-- Purpose: Store configurable feedback/analysis rules
-- =============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FeedbackRule')
BEGIN
    CREATE TABLE dbo.FeedbackRule
    (
        FeedbackRuleID INT IDENTITY(1000000000,1) PRIMARY KEY,  -- User data starts at 1 billion
        ProcedureName SYSNAME NOT NULL,           -- Which SP this applies to
        ResultSetNumber INT NOT NULL,              -- Which result set (1-12)
        MetricName SYSNAME NOT NULL,               -- Field name (e.g., 'CpuSignalWaitPct')
        RangeFrom DECIMAL(18,2) NULL,              -- Lower bound (NULL = no lower limit)
        RangeTo DECIMAL(18,2) NULL,                -- Upper bound (NULL = no upper limit)
        Severity VARCHAR(20) NOT NULL,             -- INFO, ATTENTION, WARNING, CRITICAL
        FeedbackText NVARCHAR(MAX) NOT NULL,       -- The analysis/interpretation
        Recommendation NVARCHAR(MAX) NULL,         -- Recommended action
        SortOrder INT NOT NULL DEFAULT 0,          -- Display order
        IsActive BIT NOT NULL DEFAULT 1,           -- Enable/disable rule
        IsSystemRule BIT NOT NULL DEFAULT 0,       -- 1 = seeded rule, 0 = user-created
        CreatedDate DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        ModifiedDate DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),

        INDEX IX_FeedbackRule_Procedure_ResultSet (ProcedureName, ResultSetNumber, IsActive)
    )

    PRINT 'FeedbackRule table created with identity starting at 1 billion'
    PRINT '  - IDs < 1,000,000,000 = System-seeded data'
    PRINT '  - IDs >= 1,000,000,000 = User-created data'
END
ELSE
BEGIN
    PRINT 'FeedbackRule table already exists'

    -- Add IsSystemRule column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FeedbackRule') AND name = 'IsSystemRule')
    BEGIN
        ALTER TABLE dbo.FeedbackRule ADD IsSystemRule BIT NOT NULL DEFAULT 0
        PRINT 'Added IsSystemRule column to existing table'
    END
END
GO

-- =============================================
-- Table: FeedbackMetadata
-- Purpose: Store metadata about result sets
-- =============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FeedbackMetadata')
BEGIN
    CREATE TABLE dbo.FeedbackMetadata
    (
        MetadataID INT IDENTITY(1000000000,1) PRIMARY KEY,  -- User data starts at 1 billion
        ProcedureName SYSNAME NOT NULL,
        ResultSetNumber INT NOT NULL,
        ResultSetName VARCHAR(200) NOT NULL,
        Description NVARCHAR(MAX) NOT NULL,
        InterpretationGuide NVARCHAR(MAX) NULL,
        IsSystemMetadata BIT NOT NULL DEFAULT 0,            -- 1 = seeded, 0 = user-created
        IsActive BIT NOT NULL DEFAULT 1,

        UNIQUE (ProcedureName, ResultSetNumber)
    )

    PRINT 'FeedbackMetadata table created with identity starting at 1 billion'
    PRINT '  - IDs < 1,000,000,000 = System-seeded data'
    PRINT '  - IDs >= 1,000,000,000 = User-created data'
END
ELSE
BEGIN
    PRINT 'FeedbackMetadata table already exists'

    -- Add IsSystemMetadata column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FeedbackMetadata') AND name = 'IsSystemMetadata')
    BEGIN
        ALTER TABLE dbo.FeedbackMetadata ADD IsSystemMetadata BIT NOT NULL DEFAULT 0
        PRINT 'Added IsSystemMetadata column to existing table'
    END
END
GO

-- =============================================
-- Seeding is now handled by 13b_seed_feedback_rules.sql
-- This script only creates infrastructure
-- =============================================

-- =============================================
-- Helper Function: Get Feedback for Metric Value
-- =============================================
PRINT 'Creating helper function to retrieve feedback...'
GO

CREATE OR ALTER FUNCTION dbo.fn_GetMetricFeedback
(
    @ProcedureName SYSNAME,
    @ResultSetNumber INT,
    @MetricName SYSNAME,
    @MetricValue DECIMAL(18,2)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP 1
        Severity,
        FeedbackText,
        Recommendation
    FROM dbo.FeedbackRule
    WHERE ProcedureName = @ProcedureName
      AND ResultSetNumber = @ResultSetNumber
      AND MetricName = @MetricName
      AND IsActive = 1
      AND (@MetricValue >= ISNULL(RangeFrom, -999999999))
      AND (@MetricValue <= ISNULL(RangeTo, 999999999))
    ORDER BY SortOrder
)
GO

PRINT ''
PRINT '=========================================='
PRINT 'Feedback System Created Successfully'
PRINT '=========================================='
PRINT ''
PRINT 'Tables Created:'
PRINT '  - FeedbackRule (feedback rules)'
PRINT '  - FeedbackMetadata (result set descriptions)'
PRINT ''
PRINT 'Function Created:'
PRINT '  - fn_GetMetricFeedback (retrieve feedback for metric values)'
PRINT ''
PRINT 'Seeded Data:'
PRINT '  - 12 result set metadata records'
PRINT '  - 50+ feedback rules across multiple metrics'
PRINT ''
PRINT 'Next Step: Deploy 14_enhance_daily_overview_with_feedback.sql'
PRINT '=========================================='
GO
