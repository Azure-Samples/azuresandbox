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

# Test 6: Azure Monitor Agent is installed and running.
# AMA 1.41+ on Windows Server Core does NOT register a Windows service -- it runs as a set
# of processes launched by the extension handler. Evidence of a healthy agent is:
#   MonAgentCore, MonAgentHost, MonAgentLauncher, MonAgentManager, AMAExtHealthMonitor
# running from C:\Packages\Plugins\Microsoft.Azure.Monitor.AzureMonitorWindowsAgent\<ver>\.
# We require MonAgentCore (the data-plane collector) at minimum.
try {
    $amaProcs = Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -match '^(MonAgent|AMAExt)') -and
            ($_.Path -like 'C:\Packages\Plugins\Microsoft.Azure.Monitor.AzureMonitorWindowsAgent\*')
        }

    $core = $amaProcs | Where-Object { $_.Name -eq 'MonAgentCore' } | Select-Object -First 1

    if ($core) {
        $amaDir = Get-ChildItem 'C:\Packages\Plugins\Microsoft.Azure.Monitor.AzureMonitorWindowsAgent' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^[0-9.]+$' } |
            Sort-Object Name -Descending |
            Select-Object -First 1
        $version = if ($amaDir) { $amaDir.Name } else { 'unknown' }
        $names = ($amaProcs | Select-Object -ExpandProperty Name -Unique) -join ', '
        Write-TestResult $moduleName 'PASS' "AMA: Running (version $version, processes: $names)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "AMA: MonAgentCore process not running (found: $(($amaProcs | Select-Object -ExpandProperty Name -Unique) -join ', '))"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "AMA: Unable to enumerate AMA processes"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 7: AMA has fetched DCR configuration from the DCE (proves DCR association + private DNS + AMPLS are wired correctly).
# The AMA agent writes its active DCR config under C:\WindowsAzure\Resources\AMADataStore.*\mcs\configchunks\*.json
# once it has successfully called the configurationAccessEndpoint on the DCE.
try {
    $configFiles = Get-ChildItem -Path 'C:\WindowsAzure\Resources' -Recurse -Filter '*.json' -ErrorAction Stop |
        Where-Object { $_.FullName -match 'mcs\\configchunks' }

    if ($configFiles -and $configFiles.Count -gt 0) {
        $latest = $configFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-TestResult $moduleName 'PASS' "AMA: DCR config fetched from DCE; $($configFiles.Count) chunk(s) present (latest: $($latest.Name) @ $($latest.LastWriteTime))"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "AMA: No DCR config chunks found under C:\WindowsAzure\Resources\*\mcs\configchunks -- agent has not successfully contacted the DCE"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "AMA: Unable to enumerate AMA config directory"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 8: AMPLS data plane FQDNs resolve to private (RFC1918) IPs via the AMPLS private DNS zones.
# When AMPLS is in PrivateOnly mode, AMA must resolve these hostnames to the private endpoint IP
# in snet-privatelink-02 (10.1.5.0/24) -- resolving to a public IP here would mean private DNS
# links are missing and ingestion would fail. The global control endpoint is always in
# privatelink.monitor.azure.com when AMPLS is active, so it is a reliable DNS-shadowing probe.
try {
    $testHost = 'global.handler.control.monitor.azure.com'
    $resolved = Resolve-DnsName -Name $testHost -Type A -ErrorAction Stop |
        Where-Object { $_.QueryType -eq 'A' -and $_.IPAddress } |
        Select-Object -First 1

    if (-not $resolved) {
        Write-TestResult $moduleName 'FAIL' "AMPLS DNS: '$testHost' did not return an A record"
        $failed++
    }
    elseif ($resolved.IPAddress -match '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)') {
        Write-TestResult $moduleName 'PASS' "AMPLS DNS: '$testHost' resolves to private IP '$($resolved.IPAddress)' (AMPLS private endpoint reachable)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "AMPLS DNS: '$testHost' resolved to PUBLIC IP '$($resolved.IPAddress)' -- AMPLS private DNS zone link missing or misconfigured"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "AMPLS DNS: Unable to resolve 'global.handler.control.monitor.azure.com'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 9: TCP/443 reachability to the AMPLS private endpoint (via the DCE ingestion FQDN).
# Any AMPLS-fronted endpoint works; we use the global control endpoint resolved in Test 8.
try {
    $tnc = Test-NetConnection -ComputerName 'global.handler.control.monitor.azure.com' -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop
    if ($tnc.TcpTestSucceeded) {
        Write-TestResult $moduleName 'PASS' "AMPLS: TCP/443 to '$($tnc.ComputerName)' ($($tnc.RemoteAddress)) succeeded"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "AMPLS: TCP/443 to '$($tnc.ComputerName)' ($($tnc.RemoteAddress)) FAILED -- ingestion path is broken"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "AMPLS: TCP connectivity test raised an exception"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-Log ("[MODULE:$moduleName] [SUMMARY] Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
