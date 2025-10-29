USE [DBATools]
GO

CREATE OR ALTER PROCEDURE dbo.DBA_LogEntry_Insert
      @ProcedureName     SYSNAME
    , @ProcedureSection  VARCHAR(200)
    , @IsError           BIT
    , @ErrDescription    VARCHAR(2000) = NULL
    , @ErrNumber         BIGINT        = NULL
    , @ErrSeverity       INT           = NULL
    , @ErrState          INT           = NULL
    , @ErrLine           INT           = NULL
    , @ErrProcedure      SYSNAME       = NULL
    , @AdditionalInfo    VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON

    INSERT dbo.LogEntry
    (
        DateTime_Occurred,
        ProcedureName,
        ProcedureSection,
        ErrDescription,
        ErrNumber,
        ErrSeverity,
        ErrState,
        ErrLine,
        ErrProcedure,
        IsError,
        AdditionalInfo
    )
    VALUES
    (
        SYSUTCDATETIME(),
        @ProcedureName,
        @ProcedureSection,
        @ErrDescription,
        @ErrNumber,
        @ErrSeverity,
        @ErrState,
        @ErrLine,
        @ErrProcedure,
        @IsError,
        @AdditionalInfo
    )
END
GO
