param(
    [Parameter(Mandatory = $false)]
    [string]$PetstoreFqdn
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
$script:logPath = Join-Path $logDir 'Test-Integration-AvdRemoteapp.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting integration test: AVD remoteapp session host on '$env:COMPUTERNAME'..."
Write-Log ("Parameters: PetstoreFqdn='$PetstoreFqdn'")

$passed = 0
$failed = 0

# Tests 1-3: Petstore connectivity (conditional - requires petstore module)
if ($PetstoreFqdn) {
    Write-Log "Petstore FQDN provided: '$PetstoreFqdn'. Running petstore connectivity tests..."

    # Test 1: Petstore FQDN resolves to private IP
    try {
        $dnsResult = Resolve-DnsName -Name $PetstoreFqdn -Type A -ErrorAction Stop
        $ipAddress = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress

        if ($ipAddress -match '^10\.') {
            Write-TestResult $moduleName 'PASS' "Petstore: DNS resolved '$PetstoreFqdn' to private IP '$ipAddress'"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "Petstore: DNS resolved '$PetstoreFqdn' to '$ipAddress' (expected private IP 10.x.x.x)"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Petstore: DNS resolution failed for '$PetstoreFqdn'"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }

    # Test 2: Petstore API is reachable via HTTPS (port 443)
    try {
        $tcpTest = Test-NetConnection -ComputerName $PetstoreFqdn -Port 443 -ErrorAction Stop

        if ($tcpTest.TcpTestSucceeded) {
            Write-TestResult $moduleName 'PASS' "Petstore: TCP connection to port 443 succeeded (remote IP: $($tcpTest.RemoteAddress))"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "Petstore: TCP connection to '$PetstoreFqdn':443 failed"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Petstore: TCP connectivity test failed for '$PetstoreFqdn':443"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }

    # Test 3: Petstore OpenAPI spec returns valid JSON
    try {
        $uri = "https://$PetstoreFqdn/api/v31/openapi.json"
        $apiResponse = Invoke-RestMethod -Uri $uri -Method Get -UseBasicParsing -ErrorAction Stop

        if ($apiResponse -and $apiResponse.openapi -match '^3\.') {
            Write-TestResult $moduleName 'PASS' "Petstore: OpenAPI spec returned valid JSON (openapi=$($apiResponse.openapi), title=$($apiResponse.info.title))"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "Petstore: OpenAPI spec response missing or invalid"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Petstore: Failed to fetch OpenAPI spec from '$uri'"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-Log "Petstore FQDN not provided. Skipping petstore connectivity tests (petstore module not deployed)."
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
