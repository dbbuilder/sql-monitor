-- =============================================
-- Create function to clean text for XML serialization
-- Keeps only printable ASCII + common Unicode, removes control chars
-- =============================================

USE DBATools
GO

PRINT 'Creating fn_CleanTextForXML function...'
GO

CREATE OR ALTER FUNCTION dbo.fn_CleanTextForXML(@input NVARCHAR(MAX))
RETURNS NVARCHAR(4000)
AS
BEGIN
    DECLARE @output NVARCHAR(4000) = ''
    DECLARE @i INT = 1
    DECLARE @len INT = LEN(@input)
    DECLARE @char NCHAR(1)
    DECLARE @ascii INT

    -- Limit to 4000 chars for performance and to avoid NVARCHAR(MAX) issues
    IF @len > 4000 SET @len = 4000

    WHILE @i <= @len
    BEGIN
        SET @char = SUBSTRING(@input, @i, 1)
        SET @ascii = UNICODE(@char)

        -- Keep only:
        -- - Space (32)
        -- - Printable ASCII (33-126)
        -- - Tab (9), Line Feed (10), Carriage Return (13)
        -- - Common Unicode letters and symbols (128-591, 8192-8303)
        IF (@ascii = 32)                                -- Space
           OR (@ascii >= 33 AND @ascii <= 126)          -- Printable ASCII
           OR (@ascii IN (9, 10, 13))                   -- Tab, LF, CR
           OR (@ascii >= 128 AND @ascii <= 591)         -- Extended Latin
           OR (@ascii >= 8192 AND @ascii <= 8303)       -- Punctuation
        BEGIN
            SET @output = @output + @char
        END
        -- All other characters (including CHAR(0)) are silently dropped

        SET @i = @i + 1
    END

    RETURN @output
END
GO

PRINT 'fn_CleanTextForXML created successfully'
GO

-- Test the function
PRINT ''
PRINT 'Testing fn_CleanTextForXML...'

SELECT
    'Test 1: Normal text' AS Test,
    dbo.fn_CleanTextForXML('SELECT * FROM Users WHERE ID = 123') AS Result

SELECT
    'Test 2: Text with CHAR(0)' AS Test,
    dbo.fn_CleanTextForXML('SELECT' + CHAR(0) + ' * FROM' + CHAR(0) + ' Users') AS Result

SELECT
    'Test 3: Text with multiple control chars' AS Test,
    dbo.fn_CleanTextForXML('SELECT' + CHAR(1) + CHAR(2) + CHAR(0) + ' * FROM Users' + CHAR(7)) AS Result

PRINT ''
PRINT 'Function testing complete'
GO
