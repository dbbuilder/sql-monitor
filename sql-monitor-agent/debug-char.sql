-- Debug: What character is causing the FOR XML error?
USE DBATools
GO

DECLARE @RunID INT = (SELECT MAX(PerfSnapshotRunID) FROM PerfSnapshotRun)

-- Find the problematic row
SELECT TOP 1
    DatabaseName,
    SqlText,
    LEN(SqlText) AS TextLength,
    -- Get ASCII value of each byte in first 20 characters
    ASCII(SUBSTRING(SqlText, 1, 1)) AS Char1,
    ASCII(SUBSTRING(SqlText, 2, 1)) AS Char2,
    ASCII(SUBSTRING(SqlText, 3, 1)) AS Char3,
    ASCII(SUBSTRING(SqlText, 4, 1)) AS Char4,
    ASCII(SUBSTRING(SqlText, 5, 1)) AS Char5,
    -- Check for specific characters
    CASE WHEN SqlText LIKE '%' + CHAR(0) + '%' THEN 'Has CHAR(0)' ELSE 'No CHAR(0)' END AS HasChar0,
    CASE WHEN SqlText LIKE '%' + NCHAR(0) + '%' THEN 'Has NCHAR(0)' ELSE 'No NCHAR(0)' END AS HasNChar0,
    -- Try to find position of null character
    CHARINDEX(CHAR(0), SqlText) AS Char0Position,
    CHARINDEX(NCHAR(0), SqlText) AS NChar0Position,
    -- Show hex representation of first 50 bytes
    CONVERT(VARBINARY(50), LEFT(SqlText, 50)) AS HexDump
FROM PerfSnapshotQueryStats
WHERE PerfSnapshotRunID = @RunID
  AND SqlText LIKE '%' + CHAR(0) + '%'
ORDER BY TotalCpuMs DESC

PRINT ''
PRINT 'Now test if REPLACE actually works:'

SELECT
    'Original' AS Test,
    LEN(SqlText) AS OriginalLength,
    CASE WHEN SqlText LIKE '%' + CHAR(0) + '%' THEN 'Has CHAR(0)' ELSE 'Clean' END AS OriginalStatus
FROM PerfSnapshotQueryStats
WHERE PerfSnapshotRunID = @RunID
  AND SqlText LIKE '%' + CHAR(0) + '%'

UNION ALL

SELECT
    'After REPLACE(CHAR(0))' AS Test,
    LEN(REPLACE(SqlText, CHAR(0), '')) AS NewLength,
    CASE WHEN REPLACE(SqlText, CHAR(0), '') LIKE '%' + CHAR(0) + '%' THEN 'Still has CHAR(0)!' ELSE 'Clean' END AS NewStatus
FROM PerfSnapshotQueryStats
WHERE PerfSnapshotRunID = @RunID
  AND SqlText LIKE '%' + CHAR(0) + '%'

UNION ALL

SELECT
    'After REPLACE(NCHAR(0))' AS Test,
    LEN(REPLACE(SqlText, NCHAR(0), '')) AS NewLength,
    CASE WHEN REPLACE(SqlText, NCHAR(0), '') LIKE '%' + CHAR(0) + '%' THEN 'Still has CHAR(0)!' ELSE 'Clean' END AS NewStatus
FROM PerfSnapshotQueryStats
WHERE PerfSnapshotRunID = @RunID
  AND SqlText LIKE '%' + CHAR(0) + '%'
GO
