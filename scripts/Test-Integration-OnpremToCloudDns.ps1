param(
    [Parameter(Mandatory = $false)]
    [string]$JumpLinuxFqdn,

    [Parameter(Mandatory = $false)]
    [string]$MssqlWinFqdn,

    [Parameter(Mandatory = $false)]
    [string]$MssqlServerFqdn,

    [Parameter(Mandatory = $false)]
    [string]$MysqlServerFqdn,

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $false)]
    [string]$JumpWinCloudFqdn
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

function Test-DnsAndPort {
    param(
        [string]$Module,
        [string]$TestName,
        [string]$Fqdn,
        [int]$Port,
        [string]$PreferSubnet,
        [ref]$Passed,
        [ref]$Failed
    )

    # DNS resolution
    try {
        $dnsResult = Resolve-DnsName $Fqdn -ErrorAction Stop
        $ips = ($dnsResult | Where-Object { $_.QueryType -eq 'A' }).IPAddress

        # If a preferred subnet is specified, prefer IPs matching it
        if ($PreferSubnet -and $ips) {
            $preferred = $ips | Where-Object { $_ -like $PreferSubnet }
            if ($preferred) {
                $ip = $preferred | Select-Object -First 1
            }
            else {
                $ip = $ips | Select-Object -First 1
            }
        }
        else {
            $ip = $ips | Select-Object -First 1
        }

        if ($ip -match '^10\.' -or $ip -match '^192\.168\.') {
            Write-TestResult $Module 'PASS' "${TestName}: DNS '$Fqdn' resolves to private IP '$ip'"
            $Passed.Value++
        }
        else {
            Write-TestResult $Module 'FAIL' "${TestName}: DNS '$Fqdn' resolved to '$ip' (expected private IP)"
            $Failed.Value++
            return
        }
    }
    catch {
        Write-TestResult $Module 'FAIL' "${TestName}: DNS '$Fqdn' does not resolve"
        Write-TestResult $Module 'FAIL' "Exception: $_"
        $Failed.Value++
        return
    }

    # TCP port reachability
    try {
        $tcpTest = Test-NetConnection -ComputerName $Fqdn -Port $Port -ErrorAction Stop

        if ($tcpTest.TcpTestSucceeded) {
            Write-TestResult $Module 'PASS' ("${TestName}: TCP port $Port reachable on '$Fqdn' (remote IP: " + $tcpTest.RemoteAddress + ")")
            $Passed.Value++
        }
        else {
            Write-TestResult $Module 'FAIL' "${TestName}: TCP port $Port not reachable on '$Fqdn'"
            $Failed.Value++
        }
    }
    catch {
        Write-TestResult $Module 'FAIL' "${TestName}: Failed to test TCP connectivity to '${Fqdn}':${Port}"
        Write-TestResult $Module 'FAIL' "Exception: $_"
        $Failed.Value++
    }
}
#endregion

#region main
$moduleName = 'integration'
$logDir = 'C:\unit-tests\integration'
$script:logPath = Join-Path $logDir 'Test-Integration-OnpremToCloudDns.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting integration test: on-prem to cloud connectivity on '$env:COMPUTERNAME'..."
Write-Log ("Parameters: JumpLinuxFqdn='$JumpLinuxFqdn' MssqlWinFqdn='$MssqlWinFqdn' MssqlServerFqdn='$MssqlServerFqdn' MysqlServerFqdn='$MysqlServerFqdn' StorageAccountName='$StorageAccountName' JumpWinCloudFqdn='$JumpWinCloudFqdn'")

$passed = 0
$failed = 0

# Build test cases from parameters — skip any where the parameter is empty
$testCases = @()

if ($JumpLinuxFqdn) {
    $testCases += @{ Name = 'SSH: jumplinux1'; Fqdn = $JumpLinuxFqdn; Port = 22; PreferSubnet = '10.2.*' }
}
else {
    Write-Log "Skipping SSH test: JumpLinuxFqdn parameter is empty (vm-jumpbox-linux not deployed)"
}

if ($MssqlWinFqdn) {
    $testCases += @{ Name = 'SQL: mssqlwin1'; Fqdn = $MssqlWinFqdn; Port = 1433; PreferSubnet = '10.2.*' }
}
else {
    Write-Log "Skipping SQL Server test: MssqlWinFqdn parameter is empty (vm-mssql-win not deployed)"
}

if ($MssqlServerFqdn) {
    $testCases += @{ Name = 'Azure SQL'; Fqdn = $MssqlServerFqdn; Port = 1433 }
}
else {
    Write-Log "Skipping Azure SQL test: MssqlServerFqdn parameter is empty (mssql not deployed)"
}

if ($MysqlServerFqdn) {
    $testCases += @{ Name = 'Azure MySQL'; Fqdn = $MysqlServerFqdn; Port = 3306 }
}
else {
    Write-Log "Skipping Azure MySQL test: MysqlServerFqdn parameter is empty (mysql not deployed)"
}

if ($StorageAccountName) {
    $testCases += @{ Name = 'Azure Files'; Fqdn = "$StorageAccountName.file.core.windows.net"; Port = 445 }
}
else {
    Write-Log "Skipping Azure Files test: StorageAccountName parameter is empty (vnet-app not deployed)"
}

if ($JumpWinCloudFqdn) {
    $testCases += @{ Name = 'RDP: jumpwin1'; Fqdn = $JumpWinCloudFqdn; Port = 3389; PreferSubnet = '10.2.*' }
}
else {
    Write-Log "Skipping RDP test: JumpWinCloudFqdn parameter is empty (vnet-app not deployed)"
}

if ($testCases.Count -eq 0) {
    Write-Log "No test cases to run - all dependent modules appear to be undeployed."
}

foreach ($tc in $testCases) {
    Test-DnsAndPort -Module $moduleName -TestName $tc.Name -Fqdn $tc.Fqdn -Port $tc.Port -PreferSubnet $tc.PreferSubnet -Passed ([ref]$passed) -Failed ([ref]$failed)
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
