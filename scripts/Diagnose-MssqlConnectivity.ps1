param(
    [Parameter(Mandatory = $true)]
    [string]$MssqlServerFqdn,

    [Parameter(Mandatory = $true)]
    [string]$MssqlDatabaseName
)

$ErrorActionPreference = 'Continue'
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Write-Section {
    param([string]$Title)
    Write-Output ""
    Write-Output ("=" * 60)
    Write-Output $Title
    Write-Output ("=" * 60)
}

Write-Section "1. VM Identity Information"
Write-Output "Computer name: $env:COMPUTERNAME"

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $context = Get-AzContext
    Write-Output "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
    Write-Output "Tenant: $($context.Tenant.Id)"
    Write-Output "Account ID: $($context.Account.Id)"
    Write-Output "Account Type: $($context.Account.Type)"
} catch {
    Write-Output "[ERROR] Failed to authenticate with managed identity: $_"
    exit 1
}

Write-Section "2. Token Acquisition & Identity Details"
try {
    $rawToken = (Get-AzAccessToken -ResourceUrl 'https://database.windows.net/' -ErrorAction Stop).Token
    if ($rawToken -is [System.Security.SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($rawToken)
        $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    } else {
        $token = $rawToken
    }
    Write-Output "Token acquired successfully (length: $($token.Length))"

    # Decode JWT payload to extract identity details
    $parts = $token.Split('.')
    $base64 = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($base64.Length % 4) {
        2 { $base64 += '==' }
        3 { $base64 += '=' }
    }
    $payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64)) | ConvertFrom-Json

    Write-Output "Token OID (object ID):  $($payload.oid)"
    Write-Output "Token App ID:           $($payload.appid)"
    Write-Output "Token Subject:          $($payload.sub)"
    Write-Output "Token Audience:         $($payload.aud)"
    Write-Output "Token Issuer:           $($payload.iss)"
    $tokenOid = $payload.oid
} catch {
    Write-Output "[ERROR] Failed to acquire token: $_"
    $token = $null
    $tokenOid = $null
}

Write-Section "3. DNS Resolution"
try {
    $dnsResult = Resolve-DnsName -Name $MssqlServerFqdn -Type A -ErrorAction Stop
    foreach ($record in $dnsResult) {
        Write-Output "  $($record.Name) -> $($record.IPAddress) (Type: $($record.QueryType), TTL: $($record.TTL))"
    }
} catch {
    Write-Output "[ERROR] DNS resolution failed: $_"
}

Write-Section "4. TCP Connectivity (port 1433)"
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($MssqlServerFqdn, 1433)
    Write-Output "TCP connection to ${MssqlServerFqdn}:1433 succeeded"
    $tcp.Close()
} catch {
    Write-Output "[ERROR] TCP connection failed: $_"
}

Write-Section "5. SQL Login Attempt (managed identity token)"
if ($token) {
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection
        $conn.ConnectionString = "Server=tcp:$MssqlServerFqdn,1433;Initial Catalog=$MssqlDatabaseName;Encrypt=True;TrustServerCertificate=False;"
        $conn.AccessToken = $token
        $conn.Open()

        Write-Output "[OK] SQL connection opened successfully to '$MssqlDatabaseName'"

        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT DB_NAME() AS DatabaseName, SUSER_NAME() AS LoginName, USER_NAME() AS UserName, HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'SELECT') AS HasSelect"
        $reader = $cmd.ExecuteReader()
        if ($reader.Read()) {
            Write-Output "  DatabaseName: $($reader['DatabaseName'])"
            Write-Output "  LoginName:    $($reader['LoginName'])"
            Write-Output "  UserName:     $($reader['UserName'])"
            Write-Output "  HasSelect:    $($reader['HasSelect'])"
        }
        $reader.Close()
        $conn.Close()
        $conn.Dispose()
    } catch {
        Write-Output "[FAIL] SQL login failed: $_"
        Write-Output ""
        Write-Output "This means the managed identity (OID: $tokenOid) is NOT a recognized principal in database '$MssqlDatabaseName'."
    }
} else {
    Write-Output "[SKIP] No token available"
}

Write-Section "6. Query Contained Database Users (master via token - may fail)"
if ($token) {
    # Try connecting to master to list server-level principals
    try {
        $conn2 = New-Object System.Data.SqlClient.SqlConnection
        $conn2.ConnectionString = "Server=tcp:$MssqlServerFqdn,1433;Initial Catalog=master;Encrypt=True;TrustServerCertificate=False;"
        $conn2.AccessToken = $token
        $conn2.Open()

        Write-Output "[OK] Connected to 'master' database"
        $cmd2 = $conn2.CreateCommand()
        $cmd2.CommandText = "SELECT name, type_desc, CONVERT(UNIQUEIDENTIFIER, sid) AS sid_guid FROM sys.database_principals WHERE type IN ('E','X') ORDER BY name"
        $reader2 = $cmd2.ExecuteReader()
        Write-Output "External principals in 'master':"
        while ($reader2.Read()) {
            Write-Output "  Name: $($reader2['name']), Type: $($reader2['type_desc']), SID: $($reader2['sid_guid'])"
        }
        $reader2.Close()
        $conn2.Close()
        $conn2.Dispose()
    } catch {
        Write-Output "[INFO] Cannot connect to 'master' with managed identity token (expected if identity is not a server-level admin)."
        Write-Output "       Detail: $_"
    }
}

Write-Section "7. Summary & Recommendations"
Write-Output "Target server:   $MssqlServerFqdn"
Write-Output "Target database: $MssqlDatabaseName"
Write-Output "VM name:         $env:COMPUTERNAME"
Write-Output "Identity OID:    $tokenOid"
Write-Output ""
Write-Output "If the SQL login in step 5 failed, the contained database user for this"
Write-Output "managed identity does not exist or has a mismatched SID in '$MssqlDatabaseName'."
Write-Output ""
Write-Output "To fix, a SQL admin should run this T-SQL against '$MssqlDatabaseName':"
Write-Output ""
Write-Output "  -- Check existing external users"
Write-Output "  SELECT name, type_desc, CONVERT(UNIQUEIDENTIFIER, sid) AS sid_guid"
Write-Output "  FROM sys.database_principals WHERE type IN ('E','X');"
Write-Output ""
Write-Output "  -- Create/recreate the user (using VM name)"
Write-Output "  IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$env:COMPUTERNAME')"
Write-Output "      DROP USER [$env:COMPUTERNAME];"
Write-Output "  CREATE USER [$env:COMPUTERNAME] FROM EXTERNAL PROVIDER;"
Write-Output "  ALTER ROLE db_datareader ADD MEMBER [$env:COMPUTERNAME];"
Write-Output ""

Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
