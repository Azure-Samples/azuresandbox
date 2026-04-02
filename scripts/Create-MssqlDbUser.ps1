param(
    [Parameter(Mandatory = $true)][string]$ArmClientId,
    [Parameter(Mandatory = $true)][string]$ArmClientSecret,
    [Parameter(Mandatory = $true)][string]$AadTenantId,
    [Parameter(Mandatory = $true)][string]$MssqlServerFqdn,
    [Parameter(Mandatory = $true)][string]$MssqlDatabaseName,
    [Parameter(Mandatory = $true)][string]$VmName,
    [Parameter(Mandatory = $true)][string]$VmPrincipalId
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

Write-Output "Creating contained database user '$VmName' with db_datareader on '$MssqlDatabaseName'..."

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
    DECLARE @sid VARBINARY(16) = CAST(CAST('$VmPrincipalId' AS UNIQUEIDENTIFIER) AS VARBINARY(16));
    DECLARE @sql NVARCHAR(MAX) = N'CREATE USER [$VmName] WITH SID = ' + CONVERT(NVARCHAR(MAX), @sid, 1) + N', TYPE = E;';
    EXEC sp_executesql @sql;
END
ALTER ROLE db_datareader ADD MEMBER [$VmName];
"@
$cmd.ExecuteNonQuery() | Out-Null
$conn.Close()
Disconnect-AzAccount | Out-Null

Write-Output "Created contained database user '$VmName' with db_datareader on '$MssqlDatabaseName'."
