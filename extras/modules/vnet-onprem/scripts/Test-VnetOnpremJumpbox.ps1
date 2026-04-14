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
$moduleName = 'vnet-onprem'
$logDir = "C:\unit-tests\$moduleName"
$script:logPath = Join-Path $logDir 'Test-VnetOnpremJumpbox.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting unit tests for module '$moduleName' (jumpbox) on '$env:COMPUTERNAME'..."

$passed = 0
$failed = 0

# Test 1: Domain joined
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

    if ($cs.PartOfDomain) {
        Write-TestResult $moduleName 'PASS' "Domain: '$env:COMPUTERNAME' is domain-joined"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Domain: '$env:COMPUTERNAME' is not domain-joined"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Domain: Failed to query computer system"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: Domain name correct
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $domainName = $cs.Domain

    if ($domainName -match '\.local$') {
        Write-TestResult $moduleName 'PASS' "Domain: Domain name is '$domainName'"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Domain: Domain name '$domainName' does not match expected pattern (*.local)"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Domain: Failed to query domain name"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: RSAT-ADDS feature installed
try {
    $feature = Get-WindowsFeature -Name 'RSAT-ADDS' -ErrorAction Stop

    if ($feature.InstallState -eq 'Installed') {
        Write-TestResult $moduleName 'PASS' "Windows Features: RSAT-ADDS is installed"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Windows Features: RSAT-ADDS install state is '$($feature.InstallState)' (expected 'Installed')"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Windows Features: Failed to query RSAT-ADDS"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 4: RSAT-DNS-Server feature installed
try {
    $feature = Get-WindowsFeature -Name 'RSAT-DNS-Server' -ErrorAction Stop

    if ($feature.InstallState -eq 'Installed') {
        Write-TestResult $moduleName 'PASS' "Windows Features: RSAT-DNS-Server is installed"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Windows Features: RSAT-DNS-Server install state is '$($feature.InstallState)' (expected 'Installed')"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Windows Features: Failed to query RSAT-DNS-Server"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: Software - SQL Server Management Studio installed
$ssmsPath = Get-ChildItem 'C:\Program Files\Microsoft SQL Server Management Studio*\Release\Common7\IDE\Ssms.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($ssmsPath) {
    $ssmsVersion = $ssmsPath.VersionInfo.ProductVersion
    Write-TestResult $moduleName 'PASS' ("Software: SSMS installed at '" + $ssmsPath.FullName + "' (version: $ssmsVersion)")
    $passed++
}
else {
    Write-TestResult $moduleName 'FAIL' "Software: SQL Server Management Studio not found"
    $failed++
}

# Test 6: Software - MySQL Workbench installed
$mysqlWbPath = Get-ChildItem 'C:\Program Files\MySQL\MySQL Workbench*\MySQLWorkbench.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($mysqlWbPath) {
    $mysqlWbVersion = $mysqlWbPath.VersionInfo.ProductVersion
    Write-TestResult $moduleName 'PASS' ("Software: MySQL Workbench installed at '" + $mysqlWbPath.FullName + "' (version: $mysqlWbVersion)")
    $passed++
}
else {
    Write-TestResult $moduleName 'FAIL' "Software: MySQL Workbench not found"
    $failed++
}

# Test 7: Software - Visual Studio Code installed
$vscodePath = 'C:\Program Files\Microsoft VS Code\Code.exe'
if (Test-Path $vscodePath) {
    $vscodeVersion = (Get-Item $vscodePath).VersionInfo.ProductVersion
    Write-TestResult $moduleName 'PASS' "Software: Visual Studio Code installed (version: $vscodeVersion)"
    $passed++
}
else {
    Write-TestResult $moduleName 'FAIL' "Software: Visual Studio Code not found at '$vscodePath'"
    $failed++
}

# Test 8: DNS - resolve on-prem DC (adds2.myonprem.local)
try {
    $onpremFqdn = 'adds2.myonprem.local'
    $dnsResult = Resolve-DnsName $onpremFqdn -ErrorAction Stop
    $ip = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress

    if ($ip -match '^192\.168\.1\.') {
        Write-TestResult $moduleName 'PASS' "DNS: '$onpremFqdn' resolves to '$ip' (in snet-adds-02 subnet)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "DNS: '$onpremFqdn' resolved to '$ip' (expected IP in 192.168.1.0/24)"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "DNS: '$onpremFqdn' does not resolve"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-Log ("[MODULE:$moduleName] [SUMMARY] Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
