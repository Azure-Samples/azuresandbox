param(
    [Parameter(Mandatory = $true)][string]$MssqlServerFqdn,
    [Parameter(Mandatory = $true)][string]$MssqlDatabaseName,
    [Parameter(Mandatory = $true)][string]$VmName,
    [Parameter(Mandatory = $true)][string]$SqlAdminUamiClientId,
    [Parameter(Mandatory = $true)][string]$SqlAdminGroupObjectId,
    [int]$MaxWaitSeconds = 600
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

Write-Output "Creating contained database user '$VmName' with db_datareader on '$MssqlDatabaseName'..."

function Test-PrivateIPv4 {
    param([string]$Address)
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) { return $false }
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $b = $ip.GetAddressBytes()
    return ($b[0] -eq 10) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168)
}

function Get-JwtPayload {
    param([string]$Jwt)
    $payload = $Jwt.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
}

$deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
$delaySeconds = 10

# Discover this VM's system-assigned managed identity client ID via IMDS. With no identity
# selector, IMDS returns the system-assigned identity even when a user-assigned one is attached.
$imdsHeaders = @{ Metadata = 'true' }
$imdsManagementTokenUrl = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/'
$imdsResponse = Invoke-RestMethod -Uri $imdsManagementTokenUrl -Headers $imdsHeaders -ErrorAction Stop
$VmClientId = $imdsResponse.client_id
Write-Output "Discovered VM managed identity client_id: $VmClientId"

# The SQL admin user-assigned identity is a member of the Azure SQL Entra admin group. A token
# is requested on every connection attempt so a retry never reuses a token whose groups claim
# predates the group membership.
$imdsSqlTokenUrl = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fdatabase.windows.net%2F&client_id=$SqlAdminUamiClientId"
Write-Output "Using SQL admin user-assigned identity client_id: $SqlAdminUamiClientId"

# The private endpoint's DNS record may not resolve from this VM immediately after it is
# created. Until it does, the FQDN resolves to the public SQL gateway, and the firewall
# silently drops TCP 1433 to it. Wait for a private address before connecting.
Write-Output "Waiting up to $MaxWaitSeconds seconds for '$MssqlServerFqdn' to resolve to a private endpoint address..."
$privateAddress = $null
while ($true) {
    Clear-DnsClientCache
    $resolution = 'unresolved'
    try {
        $records = Resolve-DnsName -Name $MssqlServerFqdn -DnsOnly -ErrorAction Stop
        $chain = @($records | Where-Object { $_.Type -eq 'CNAME' } | ForEach-Object { $_.NameHost })
        $addresses = @($records | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.IPAddress })
        $resolution = "CNAME chain: [$($chain -join ' -> ')], A: [$($addresses -join ', ')]"
        $privateAddress = $addresses | Where-Object { Test-PrivateIPv4 $_ } | Select-Object -First 1
    }
    catch {
        $resolution = "lookup failed: $($_.Exception.Message)"
    }
    Write-Output "DNS resolution for '$MssqlServerFqdn': $resolution"
    if ($privateAddress) { break }
    if ((Get-Date) -ge $deadline) {
        throw "Timed out after $MaxWaitSeconds seconds waiting for '$MssqlServerFqdn' to resolve to a private endpoint address. Last result: $resolution"
    }
    Start-Sleep -Seconds $delaySeconds
    $delaySeconds = [Math]::Min($delaySeconds * 2, 60)
}
Write-Output "'$MssqlServerFqdn' resolves to private address $privateAddress."

# Connect to database, retrying transient connection failures until the deadline
$delaySeconds = 10
$attempt = 0
while ($true) {
    $attempt++
    $conn = $null
    try {
        $token = (Invoke-RestMethod -Uri $imdsSqlTokenUrl -Headers $imdsHeaders -ErrorAction Stop).access_token
        $claims = Get-JwtPayload $token
        $issuedAt = [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.iat).UtcDateTime.ToString('u')
        $hasGroup = @($claims.groups) -contains $SqlAdminGroupObjectId
        Write-Output "Attempt ${attempt}: SQL admin token issued at $issuedAt, groups claim contains admin group: $hasGroup"

        $conn = New-Object System.Data.SqlClient.SqlConnection
        $conn.ConnectionString = "Server=tcp:$MssqlServerFqdn,1433;Initial Catalog=$MssqlDatabaseName;Encrypt=True;TrustServerCertificate=False;"
        $conn.AccessToken = $token
        $conn.Open()
        Write-Output "Connected to '$MssqlServerFqdn' on attempt $attempt."
        break
    }
    catch {
        if ($conn) { $conn.Dispose() }
        if ((Get-Date) -ge $deadline) {
            throw "Failed to connect to '$MssqlServerFqdn' after $attempt attempt(s): $($_.Exception.Message)"
        }
        Write-Output "Connection attempt $attempt failed: $($_.Exception.Message) Retrying in $delaySeconds seconds..."
        Start-Sleep -Seconds $delaySeconds
        $delaySeconds = [Math]::Min($delaySeconds * 2, 60)
    }
}

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
