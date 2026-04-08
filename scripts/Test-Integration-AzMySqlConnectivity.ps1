param(
    [Parameter(Mandatory = $true)]
    [string]$MysqlServerFqdn,

    [Parameter(Mandatory = $true)]
    [string]$MysqlDatabaseName,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName
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
$script:logPath = Join-Path $logDir 'Test-Integration-AzMySqlConnectivity.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting integration test: MySQL connectivity from '$env:COMPUTERNAME' to '$MysqlServerFqdn'..."

$passed = 0
$failed = 0

# Test 1: DNS resolves to private IP
try {
    $dnsResult = Resolve-DnsName -Name $MysqlServerFqdn -Type A -ErrorAction Stop
    $ipAddress = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress
    if ($ipAddress -match '^10\.') {
        Write-TestResult $moduleName 'PASS' "MySQL: DNS resolved to private IP $ipAddress"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "MySQL: DNS resolved to non-private IP $ipAddress (expected 10.x.x.x)"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "MySQL: DNS resolution failed for '$MysqlServerFqdn': $_"
    $failed++
}

# Test 2: TCP connectivity on port 3306
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($MysqlServerFqdn, 3306)
    if ($tcp.Connected) {
        Write-TestResult $moduleName 'PASS' "MySQL: TCP connection to port 3306 succeeded"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "MySQL: TCP connection to port 3306 failed"
        $failed++
    }
    $tcp.Close()
}
catch {
    Write-TestResult $moduleName 'FAIL' "MySQL: TCP connection to port 3306 failed: $_"
    $failed++
}

# Test 3: Key Vault credential retrieval via managed identity
$adminUsername = $null
$adminPassword = $null

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $adminUsername = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminuser' -AsPlainText -ErrorAction Stop
    $adminPassword = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminpassword' -AsPlainText -ErrorAction Stop
    Write-TestResult $moduleName 'PASS' "MySQL: Retrieved credentials from Key Vault '$KeyVaultName'"
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "MySQL: Failed to retrieve credentials from Key Vault '$KeyVaultName': $_"
    $failed++
}

# Test 4: MySQL query via mysql.exe CLI (shipped with MySQL Workbench)
if ($adminUsername -and $adminPassword) {
    # Locate mysql.exe from MySQL Workbench or MySQL Server installation
    $mysqlExe = $null
    $searchPaths = @(
        "${env:ProgramFiles}\MySQL\MySQL Workbench*",
        "${env:ProgramFiles}\MySQL\MySQL Server*\bin",
        "${env:ProgramFiles(x86)}\MySQL\MySQL Workbench*",
        "${env:ProgramFiles}\MySQL\MySQL Shell*\bin"
    )
    foreach ($pattern in $searchPaths) {
        $candidate = Get-ChildItem -Path $pattern -Filter 'mysql.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($candidate) {
            $mysqlExe = $candidate.FullName
            break
        }
    }

    if ($mysqlExe) {
        Write-Log "MySQL: Found mysql.exe at '$mysqlExe'"
        try {
            $query = "SELECT DATABASE() AS DatabaseName;"
            $env:MYSQL_PWD = $adminPassword
            $result = & $mysqlExe --host=$MysqlServerFqdn --port=3306 --user=$adminUsername --database=$MysqlDatabaseName --ssl-mode=REQUIRED --batch --skip-column-names --execute=$query 2>&1
            $env:MYSQL_PWD = $null
            $exitCode = $LASTEXITCODE

            Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null

            if ($exitCode -eq 0 -and $result -eq $MysqlDatabaseName) {
                Write-TestResult $moduleName 'PASS' "MySQL: Connected to '$result' as '$adminUsername' via private endpoint"
                $passed++
            }
            elseif ($exitCode -ne 0) {
                Write-TestResult $moduleName 'FAIL' "MySQL: mysql.exe exited with code $exitCode`: $result"
                $failed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' "MySQL: Unexpected database name '$result' (expected '$MysqlDatabaseName')"
                $failed++
            }
        }
        catch {
            $env:MYSQL_PWD = $null
            Write-TestResult $moduleName 'FAIL' "MySQL: SQL query failed: $_"
            $failed++
            Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "MySQL: mysql.exe not found in standard MySQL installation paths"
        $failed++
        Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "MySQL: Skipped SQL query - no credentials available"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
#endregion
