-- 00-size-lobmaxsize.sql
-- Determine the AWS DMS LobMaxSize (KB) for limited LOB mode.
-- Run against each source SQL Server database before the AWS DMS full load.
--
-- Because the source table has no primary key, the DMS full load must use
-- limited LOB mode (full and inline LOB modes populate LOBs through a
-- primary-key/unique-key lookup this table lacks). Limited LOB mode truncates
-- any value larger than LobMaxSize, so set LobMaxSize to the value reported
-- here to guarantee the baseline copies every LOB intact.
--
-- Covers varchar(max), nvarchar(max), varbinary(max), text, ntext, image, xml,
-- and geometry/geography (DMS reads spatial types as LOBs). For geometry and
-- geography, DMS sends the value as WKB, so the size measured here is
-- STAsBinary() (the WKB size), not the serialized SQL Server size.

SET NOCOUNT ON;

CREATE TABLE #LobColumns
(
      TableSchema    SYSNAME
    , TableName      SYSNAME
    , ColumnName     SYSNAME
    , TypeName       SYSNAME
    , MaxBytes       BIGINT      -- size DMS must hold (WKB for spatial types)
    , MaxStoredBytes BIGINT      -- DATALENGTH of the stored value, for comparison
    , NonNullRows    BIGINT
);

DECLARE @sql NVARCHAR(MAX), @schema SYSNAME, @table SYSNAME, @col SYSNAME, @type SYSNAME;

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
SELECT s.name, t.name, c.name, TYPE_NAME(c.user_type_id)
FROM sys.columns c
JOIN sys.tables  t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
  AND (c.max_length = -1
       OR TYPE_NAME(c.user_type_id) IN ('text','ntext','image','xml','geometry','geography'));

OPEN cur;
FETCH NEXT FROM cur INTO @schema, @table, @col, @type;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @q NVARCHAR(512) = QUOTENAME(@col);
    DECLARE @measured NVARCHAR(600) =
        CASE WHEN @type IN ('geometry','geography')
             THEN 'DATALENGTH(' + @q + '.STAsBinary())'
             ELSE 'DATALENGTH(' + @q + ')' END;
    SET @sql = N'INSERT INTO #LobColumns
        SELECT @s, @t, @c, @ty,
               COALESCE(MAX(' + @measured + N'), 0),
               COALESCE(MAX(DATALENGTH(' + @q + N')), 0),
               COUNT(' + @q + N')
        FROM ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N';';
    EXEC sp_executesql @sql,
         N'@s SYSNAME, @t SYSNAME, @c SYSNAME, @ty SYSNAME',
         @s = @schema, @t = @table, @c = @col, @ty = @type;
    FETCH NEXT FROM cur INTO @schema, @table, @col, @type;
END
CLOSE cur;
DEALLOCATE cur;

-- 1. Per-column detail, largest first.
SELECT TableSchema, TableName, ColumnName, TypeName,
       MaxBytes,
       CAST(MaxBytes / 1024.0 AS DECIMAL(18,1)) AS MaxKB,
       MaxStoredBytes, NonNullRows
FROM #LobColumns
ORDER BY MaxBytes DESC;

-- 2. Recommended LobMaxSize (KB): largest value rounded up to the next KB.
--    xml is doubled because DMS reads it as UTF-16. Add headroom if the source
--    can change before the load; for a frozen, full-load-only source the exact
--    maximum is normally sufficient.
SELECT
    CEILING(MAX(CASE WHEN TypeName = 'xml' THEN MaxBytes * 2 ELSE MaxBytes END) / 1024.0)
        AS [Recommended LobMaxSize (KB)],
    CEILING(MAX(CASE WHEN TypeName = 'xml' THEN MaxBytes * 2 ELSE MaxBytes END) / 1024.0 * 1.2)
        AS [With 20% headroom (KB)]
FROM #LobColumns;

DROP TABLE #LobColumns;
