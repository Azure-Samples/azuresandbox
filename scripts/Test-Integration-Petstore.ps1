param(
    [Parameter(Mandatory = $true)]
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
$script:logPath = Join-Path $logDir 'Test-Integration-Petstore.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting integration test: Petstore API connectivity from '$env:COMPUTERNAME' to '$PetstoreFqdn'..."

$passed = 0
$failed = 0

# Test 1: DNS resolves to private IP
try {
    $dnsResult = Resolve-DnsName -Name $PetstoreFqdn -Type A -ErrorAction Stop
    $ipAddress = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress
    if ($ipAddress -match '^10\.') {
        Write-TestResult $moduleName 'PASS' "Petstore: DNS resolved to private IP $ipAddress"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Petstore: DNS resolved to non-private IP $ipAddress (expected 10.x.x.x)"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Petstore: DNS resolution failed for '$PetstoreFqdn': $_"
    $failed++
}

# Test 2: HTTPS connectivity on port 443
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($PetstoreFqdn, 443)
    if ($tcp.Connected) {
        Write-TestResult $moduleName 'PASS' "Petstore: TCP connection to port 443 succeeded"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Petstore: TCP connection to port 443 failed"
        $failed++
    }
    $tcp.Close()
}
catch {
    Write-TestResult $moduleName 'FAIL' "Petstore: TCP connection to port 443 failed: $_"
    $failed++
}

# Test 3: OpenAPI spec is reachable and returns valid JSON
$apiResponse = $null
try {
    $uri = "https://$PetstoreFqdn/api/v31/openapi.json"
    Write-Log "Requesting OpenAPI spec from '$uri'..."
    $apiResponse = Invoke-RestMethod -Uri $uri -Method Get -UseBasicParsing -ErrorAction Stop

    if ($apiResponse) {
        Write-TestResult $moduleName 'PASS' "Petstore: OpenAPI spec endpoint returned valid JSON response"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Petstore: OpenAPI spec endpoint returned empty response"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Petstore: Failed to reach OpenAPI spec endpoint '$uri': $_"
    $failed++
}

# Test 4: API metadata contains expected Swagger Petstore fields
if ($apiResponse) {
    try {
        $issues = @()

        if ($apiResponse.openapi -notmatch '^3\.1') {
            $issues += "openapi='$($apiResponse.openapi)' (expected '3.1.x')"
        }

        if ($apiResponse.info.title -notmatch 'Swagger Petstore') {
            $issues += "info.title='$($apiResponse.info.title)' (expected to contain 'Swagger Petstore')"
        }

        if (-not $apiResponse.info.version) {
            $issues += 'info.version is empty (expected non-empty, e.g. 1.0.10)'
        }

        if ($apiResponse.info.license.name -ne 'Apache 2.0') {
            $issues += "info.license.name='$($apiResponse.info.license.name)' (expected 'Apache 2.0')"
        }

        if ($apiResponse.info.contact.email -ne 'apiteam@swagger.io') {
            $issues += "info.contact.email='$($apiResponse.info.contact.email)' (expected 'apiteam@swagger.io')"
        }

        if ($issues.Count -eq 0) {
            $version = $apiResponse.info.version
            $title = $apiResponse.info.title
            Write-TestResult $moduleName 'PASS' "Petstore: API metadata is correct (title='$title', version='$version', openapi='$($apiResponse.openapi)', license='Apache 2.0', contact='apiteam@swagger.io')"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("Petstore: API metadata issues: " + ($issues -join '; '))
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Petstore: Failed to parse API metadata: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "Petstore: Skipping metadata validation - no API response available"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
