param(
    [Parameter(Mandatory = $true)]
    [string]$MssqlServerFqdn,

    [Parameter(Mandatory = $true)]
    [string]$MssqlDatabaseName
)

#region functions
function Write-Log {
    param([string]$msg)
    $entry = "$(Get-Date -Format FileDateTimeUniversal) : $msg"
    $entry | Out-File -FilePath $script:logPath -Append -Force
    Write-Output $entry
}

function Write-TestResult {
    param(
        [string]$module,
        [string]$status,
        [string]$msg
    )
    Write-Log ("[MODULE:$module] [$status] $msg")
}
#endregion

#region main
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$moduleName = 'integration'
$logDir = 'C:\unit-tests\integration'
$script:logPath = Join-Path $logDir 'Test-Integration-AzSqlConnectivity.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting integration test: Azure SQL connectivity from '$env:COMPUTERNAME' to '$MssqlServerFqdn'..."

$passed = 0
$failed = 0

# Test 1: DNS resolves to private IP
try {
    $dnsResult = Resolve-DnsName -Name $MssqlServerFqdn -Type A -ErrorAction Stop
    $ipAddress = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress
    if ($ipAddress -match '^10\.') {
        Write-TestResult $moduleName 'PASS' "Azure SQL: DNS resolved to private IP $ipAddress"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Azure SQL: DNS resolved to non-private IP $ipAddress (expected 10.x.x.x)"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Azure SQL: DNS resolution failed for '$MssqlServerFqdn': $_"
    $failed++
}

# Test 2: TCP connectivity on port 1433
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($MssqlServerFqdn, 1433)
    if ($tcp.Connected) {
        Write-TestResult $moduleName 'PASS' "Azure SQL: TCP connection to port 1433 succeeded"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Azure SQL: TCP connection to port 1433 failed"
        $failed++
    }
    $tcp.Close()
}
catch {
    Write-TestResult $moduleName 'FAIL' "Azure SQL: TCP connection to port 1433 failed: $_"
    $failed++
}

# Test 3: Entra ID token acquisition via managed identity
$token = $null
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $rawToken = (Get-AzAccessToken -ResourceUrl 'https://database.windows.net/' -ErrorAction Stop).Token
    if ($rawToken -is [System.Security.SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($rawToken)
        $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    } else {
        $token = $rawToken
    }
    Write-TestResult $moduleName 'PASS' "Azure SQL: Acquired Entra ID token for managed identity"
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "Azure SQL: Failed to acquire Entra ID token: $_"
    $failed++
}

# Test 4: SQL query succeeds with db_datareader
if ($token) {
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection
        $conn.ConnectionString = "Server=tcp:$MssqlServerFqdn,1433;Initial Catalog=$MssqlDatabaseName;Encrypt=True;TrustServerCertificate=False;"
        $conn.AccessToken = $token
        $conn.Open()

        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT DB_NAME() AS DatabaseName, SUSER_NAME() AS LoginName, HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'SELECT') AS HasSelect"
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        $ds = New-Object System.Data.DataSet
        $adapter.Fill($ds) | Out-Null

        $row = $ds.Tables[0].Rows[0]
        $dbName = "$($row.DatabaseName)"
        $loginName = "$($row.LoginName)"
        $hasSelect = "$($row.HasSelect)"

        $conn.Close()
        $conn.Dispose()
        Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null

        if ($dbName -eq $MssqlDatabaseName -and $hasSelect -eq '1') {
            Write-TestResult $moduleName 'PASS' "Azure SQL: Connected to '$dbName' as '$loginName' with db_datareader"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "Azure SQL: Unexpected results - DB='$dbName' (expected '$MssqlDatabaseName'), HasSelect='$hasSelect' (expected '1'), Login='$loginName'"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Azure SQL: SQL query failed: $_"
        $failed++
        Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "Azure SQL: Skipped SQL query - no token available"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
#endregion
