-- Move all tempdb data and log files to T:\SQLTEMP
-- This takes effect after the next SQL Server service restart.
-- Run this connected to the target SQL Server instance as sysadmin.

USE master;
GO

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + 
    N'ALTER DATABASE tempdb MODIFY FILE (NAME = ' + QUOTENAME(name, '''') + 
    N', FILENAME = ''T:\SQLTEMP\' + 
    REVERSE(LEFT(REVERSE(physical_name), CHARINDEX('\', REVERSE(physical_name)) - 1)) + 
    N''');' + CHAR(13) + CHAR(10)
FROM sys.master_files
WHERE database_id = DB_ID('tempdb');

PRINT @sql;
EXEC sp_executesql @sql;
GO

-- Verify the pending file locations (effective after restart)
SELECT 
    name,
    physical_name AS [Current Location],
    type_desc
FROM sys.master_files
WHERE database_id = DB_ID('tempdb');
GO
