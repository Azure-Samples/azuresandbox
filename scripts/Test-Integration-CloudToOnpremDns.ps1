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
$moduleName = 'integration'
$logDir = 'C:\unit-tests\integration'
$script:logPath = Join-Path $logDir 'Test-Integration-CloudToOnpremDns.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting integration test: cloud to on-prem DNS resolution on '$env:COMPUTERNAME'..."

$passed = 0
$failed = 0

# Test 1: DNS - resolve on-prem jumpbox (jumpwin2.myonprem.local)
try {
    $fqdn = 'jumpwin2.myonprem.local'
    $dnsResult = Resolve-DnsName $fqdn -ErrorAction Stop
    $ip = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress

    if ($ip -match '^192\.168\.2\.') {
        Write-TestResult $moduleName 'PASS' "DNS: '$fqdn' resolves to '$ip' (in snet-misc-04 subnet)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "DNS: '$fqdn' resolved to '$ip' (expected IP in 192.168.2.0/24)"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "DNS: '$fqdn' does not resolve"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: DNS - resolve on-prem DC (adds2.myonprem.local)
try {
    $fqdn = 'adds2.myonprem.local'
    $dnsResult = Resolve-DnsName $fqdn -ErrorAction Stop
    $ip = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress

    if ($ip -match '^192\.168\.1\.') {
        Write-TestResult $moduleName 'PASS' "DNS: '$fqdn' resolves to '$ip' (in snet-adds-02 subnet)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "DNS: '$fqdn' resolved to '$ip' (expected IP in 192.168.1.0/24)"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "DNS: '$fqdn' does not resolve"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: TCP - RDP port 3389 reachable on jumpwin2
try {
    $fqdn = 'jumpwin2.myonprem.local'
    $tcpTest = Test-NetConnection -ComputerName $fqdn -Port 3389 -ErrorAction Stop

    if ($tcpTest.TcpTestSucceeded) {
        Write-TestResult $moduleName 'PASS' ("RDP: TCP port 3389 reachable on '$fqdn' (remote IP: " + $tcpTest.RemoteAddress + ")")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "RDP: TCP port 3389 not reachable on '$fqdn'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "RDP: Failed to test TCP connectivity to '${fqdn}':3389"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
