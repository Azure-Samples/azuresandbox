param(
    [Parameter(Mandatory = $true)][string]$MssqlServerFqdn,
    [Parameter(Mandatory = $true)][string]$MssqlDatabaseName,
    [Parameter(Mandatory = $true)][string]$VmName
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

Write-Output "Creating contained database user '$VmName' with db_datareader on '$MssqlDatabaseName'..."

# Discover this VM's managed identity client ID via IMDS.
$imdsHeaders = @{ Metadata = 'true' }
$imdsManagementTokenUrl = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/'
$imdsResponse = Invoke-RestMethod -Uri $imdsManagementTokenUrl -Headers $imdsHeaders -ErrorAction Stop
$VmClientId = $imdsResponse.client_id
Write-Output "Discovered VM managed identity client_id: $VmClientId"

# This VM is an Azure SQL administrator through its managed identity.
$imdsSqlTokenUrl = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fdatabase.windows.net%2F'
$token = (Invoke-RestMethod -Uri $imdsSqlTokenUrl -Headers $imdsHeaders -ErrorAction Stop).access_token

# Connect to database and create contained database user with db_datareader
$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=tcp:$MssqlServerFqdn,1433;Initial Catalog=$MssqlDatabaseName;Encrypt=True;TrustServerCertificate=False;"
$conn.AccessToken = $token
$conn.Open()

$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$VmName')
BEGIN
    DECLARE @sid VARBINARY(16) = CAST(CAST('$VmClientId' AS UNIQUEIDENTIFIER) AS VARBINARY(16));
    DECLARE @sql NVARCHAR(MAX) = N'CREATE USER [$VmName] WITH SID = ' + CONVERT(NVARCHAR(MAX), @sid, 1) + N', TYPE = E;';
    EXEC sp_executesql @sql;
END
ELSE
BEGIN
    -- Update SID if identity was recreated
    DECLARE @existingSid VARBINARY(16) = (SELECT sid FROM sys.database_principals WHERE name = '$VmName');
    DECLARE @expectedSid VARBINARY(16) = CAST(CAST('$VmClientId' AS UNIQUEIDENTIFIER) AS VARBINARY(16));
    IF @existingSid <> @expectedSid
    BEGIN
        DECLARE @alterSql NVARCHAR(MAX) = N'ALTER USER [$VmName] WITH SID = ' + CONVERT(NVARCHAR(MAX), @expectedSid, 1) + N';';
        EXEC sp_executesql @alterSql;
    END
END
ALTER ROLE db_datareader ADD MEMBER [$VmName];
"@
$cmd.ExecuteNonQuery() | Out-Null
$conn.Close()

Write-Output "Created contained database user '$VmName' with db_datareader on '$MssqlDatabaseName'."
