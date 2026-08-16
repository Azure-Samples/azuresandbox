param(
    [Parameter(Mandatory = $true)]
    [string]$PetstoreFqdn,

    # ARM resource ID of the Log Analytics workspace backing Application Insights.
    # Used to query telemetry via the resource-centric Log Analytics query API. When
    # empty the telemetry-ingestion check is skipped (reported as a failure) rather
    # than erroring.
    [string]$LogAnalyticsWorkspaceResourceId,

    # The cloud role name (AppRoleName) the container app reports to Application
    # Insights. Matches the petstore module's appinsights_role_name variable.
    [string]$ExpectedRoleName = 'petstore'
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

# Test 5: Application Insights is receiving request telemetry from the container app
# via Entra ID authentication. This runs on jumpwin1 (inside the vnet) because the
# Log Analytics query endpoint (api.loganalytics.io) is only reachable through the
# Azure Monitor Private Link Scope; jumpwin1's managed identity holds Monitoring Reader.
if ([string]::IsNullOrWhiteSpace($LogAnalyticsWorkspaceResourceId)) {
    Write-TestResult $moduleName 'FAIL' "Petstore: LogAnalyticsWorkspaceResourceId not provided; cannot verify Application Insights telemetry ingestion"
    $failed++
}
else {
    try {
        # Acquire a managed-identity token for the Log Analytics query API. api.loganalytics.io
        # resolves to a private IP from inside the vnet via the Azure Monitor Private Link Scope.
        $laToken = (Invoke-RestMethod -Method Get -Headers @{ Metadata = 'true' } `
                -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://api.loganalytics.io/' `
                -TimeoutSec 30).access_token

        # Resource-centric query URL: no workspace GUID (customerId) needed.
        $queryUri = "https://api.loganalytics.io/v1$LogAnalyticsWorkspaceResourceId/query"
        $kql = "AppRequests | where TimeGenerated > ago(1h) | where AppRoleName == '$ExpectedRoleName' | summarize Count = count(), Last = max(TimeGenerated)"
        $body = @{ query = $kql } | ConvertTo-Json

        # Application Insights ingestion has latency (typically 2-5 minutes). The request
        # generated by Test 3 above should land within this window, so poll before failing.
        $maxAttempts = 12
        $delaySeconds = 30
        $requestCount = 0
        $lastSeen = $null
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            $resp = Invoke-RestMethod -Uri $queryUri -Method Post -Headers @{ Authorization = "Bearer $laToken" } -ContentType 'application/json' -Body $body -TimeoutSec 60
            $primary = $resp.tables | Where-Object { $_.name -eq 'PrimaryResult' }
            if ($primary -and $primary.rows.Count -gt 0 -and $null -ne $primary.rows[0][0]) {
                $requestCount = [int]$primary.rows[0][0]
                $lastSeen = $primary.rows[0][1]
            }
            if ($requestCount -gt 0) { break }
            if ($attempt -lt $maxAttempts) {
                Write-Log "  No AppRequests telemetry for role '$ExpectedRoleName' yet (attempt $attempt/$maxAttempts); waiting $delaySeconds s for ingestion..."
                Start-Sleep -Seconds $delaySeconds
            }
        }

        if ($requestCount -gt 0) {
            Write-TestResult $moduleName 'PASS' "Petstore: Application Insights received $requestCount request(s) with AppRoleName='$ExpectedRoleName' in the last hour (most recent at $lastSeen), confirming telemetry via Entra ID authentication"
            $passed++
        }
        else {
            # Diagnostic: report which telemetry tables (if any) hold data for this role,
            # to distinguish "no telemetry at all" from "requests specifically missing".
            $diag = ''
            try {
                $diagKql = "union withsource=Tbl AppRequests, AppDependencies, AppTraces, AppExceptions, AppPerformanceCounters | where TimeGenerated > ago(1h) | where AppRoleName == '$ExpectedRoleName' | summarize C = count() by Tbl"
                $diagBody = @{ query = $diagKql } | ConvertTo-Json
                $dresp = Invoke-RestMethod -Uri $queryUri -Method Post -Headers @{ Authorization = "Bearer $laToken" } -ContentType 'application/json' -Body $diagBody -TimeoutSec 60
                $dprimary = $dresp.tables | Where-Object { $_.name -eq 'PrimaryResult' }
                if ($dprimary -and $dprimary.rows.Count -gt 0) {
                    $diag = ($dprimary.rows | ForEach-Object { "$($_[0])=$($_[1])" }) -join ', '
                }
            }
            catch {
                Write-Log "  (diagnostic telemetry-table query failed: $($_.Exception.Message))"
            }
            $diagMsg = if ($diag) { " Other telemetry present for this role: $diag." } else { " No telemetry of any type found for this role." }
            $waitMin = [int]($maxAttempts * $delaySeconds / 60)
            Write-TestResult $moduleName 'FAIL' ("Petstore: No AppRequests telemetry with AppRoleName='$ExpectedRoleName' found after ${waitMin} min of polling." + $diagMsg)
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Petstore: Failed to query Application Insights telemetry: $_"
        $failed++
    }
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
