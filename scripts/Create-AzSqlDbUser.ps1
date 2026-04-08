param(
    [Parameter(Mandatory = $true)][string]$ArmClientId,
    [Parameter(Mandatory = $true)][string]$ArmClientSecret,
    [Parameter(Mandatory = $true)][string]$AadTenantId,
    [Parameter(Mandatory = $true)][string]$MssqlServerFqdn,
    [Parameter(Mandatory = $true)][string]$MssqlDatabaseName,
    [Parameter(Mandatory = $true)][string]$VmName
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

Write-Output "Creating contained database user '$VmName' with db_datareader on '$MssqlDatabaseName'..."

# Discover this VM's managed identity client_id via IMDS
$imdsUrl = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/'
$imdsResponse = Invoke-RestMethod -Uri $imdsUrl -Headers @{ Metadata = 'true' } -ErrorAction Stop
$VmClientId = $imdsResponse.client_id
Write-Output "Discovered VM managed identity client_id: $VmClientId"

# Authenticate as SP (SQL admin) and acquire SQL access token
$secureSecret = ConvertTo-SecureString $ArmClientSecret -AsPlainText -Force
$credential = New-Object PSCredential($ArmClientId, $secureSecret)
Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId $AadTenantId | Out-Null
$rawToken = (Get-AzAccessToken -ResourceUrl 'https://database.windows.net/').Token
if ($rawToken -is [System.Security.SecureString]) {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($rawToken)
    $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
} else {
    $token = $rawToken
}

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
Disconnect-AzAccount | Out-Null

Write-Output "Created contained database user '$VmName' with db_datareader on '$MssqlDatabaseName'."
