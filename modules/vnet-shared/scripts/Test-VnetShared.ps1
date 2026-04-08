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
$moduleName = 'vnet-shared'
$logDir = "C:\unit-tests\$moduleName"
$script:logPath = Join-Path $logDir 'Test-VnetShared.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting unit tests for module '$moduleName' on '$env:COMPUTERNAME'..."

$passed = 0
$failed = 0
$domainName = $null

# Test 1: AD DS Domain exists
try {
    $adDomain = Get-ADDomain -ErrorAction Stop
    $domainName = $adDomain.DNSRoot
    Write-TestResult $moduleName 'PASS' "AD DS: Domain '$domainName' exists"
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "AD DS: Domain does not exist or is not reachable"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: This machine is a domain controller
try {
    $dc = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop
    Write-TestResult $moduleName 'PASS' "AD DS: '$env:COMPUTERNAME' is a domain controller"
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "AD DS: '$env:COMPUTERNAME' is not a domain controller"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: DNS server responding (resolve this machine's FQDN)
if ($domainName) {
    try {
        $fqdn = "$env:COMPUTERNAME.$domainName"
        $dnsResult = Resolve-DnsName $fqdn -ErrorAction Stop
        $ip = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress
        Write-TestResult $moduleName 'PASS' "DNS: '$fqdn' resolves to '$ip'"
        $passed++
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "DNS: '$fqdn' does not resolve"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "DNS: Skipped - domain name not available (Test 1 failed)"
    $failed++
}

# Test 4: Azure DNS forwarder configured
try {
    $forwarders = Get-DnsServerForwarder -ErrorAction Stop
    $azureDns = '168.63.129.16'
    $forwarderIPs = @($forwarders.IPAddress | ForEach-Object { "$_" })

    if ($forwarderIPs -contains $azureDns) {
        Write-TestResult $moduleName 'PASS' "DNS: Azure DNS forwarder '$azureDns' is configured"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "DNS: Azure DNS forwarder '$azureDns' not found. Current forwarders: $($forwarderIPs -join ', ')"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "DNS: Unable to query DNS server forwarders"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: DNS A record exists for this machine in the zone
if ($domainName) {
    try {
        $record = Get-DnsServerResourceRecord -ZoneName $domainName -Name $env:COMPUTERNAME -RRType A -ErrorAction Stop
        $recordIp = "$($record.RecordData.IPv4Address)"
        Write-TestResult $moduleName 'PASS' "DNS: A record for '$env:COMPUTERNAME' in zone '$domainName' has IP '$recordIp'"
        $passed++
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "DNS: A record for '$env:COMPUTERNAME' in zone '$domainName' not found"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "DNS: Skipped - domain name not available (Test 1 failed)"
    $failed++
}

# Summary
$total = $passed + $failed
Write-Log ("[MODULE:$moduleName] [SUMMARY] Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
