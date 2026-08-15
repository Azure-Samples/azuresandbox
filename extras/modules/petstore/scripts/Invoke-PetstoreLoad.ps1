<#
.SYNOPSIS
    Generates demo load and failure traffic against the Petstore API to populate
    Application Insights blades (Performance, Requests, Failures, Smart Detection).

.DESCRIPTION
    On-demand demo utility (NOT part of 'terraform apply'). Because the Petstore
    Container App is network isolated, run this from *jumpwin1* (inside the virtual
    network), which can reach the private FQDN.

    Each iteration issues a request drawn from a weighted mix of successful
    operations (HTTP 200) and deliberate failures (HTTP 4xx), so the resulting
    telemetry exercises both the success and failure experiences in Application
    Insights. After running, review the telemetry from *jumpwin1* (portal APM
    blades) or query the Log Analytics workspace.

.PARAMETER PetstoreFqdn
    Fully qualified domain name of the Petstore Container App, e.g.
    'petstore.<suffix>.<region>.azurecontainerapps.io'. Obtain it with
    'terraform output fqdns'.

.PARAMETER DurationSeconds
    How long to generate traffic, in seconds. Default 300 (5 minutes).

.PARAMETER DelayMilliseconds
    Delay between requests, in milliseconds. Default 500.

.PARAMETER FailureRate
    Fraction of requests (0.0 - 1.0) that are drawn from the deliberate-failure
    set (HTTP 4xx). Default 0.3. The Petstore app keeps pets in memory and can
    scale to multiple replicas under load, so a read of a freshly created pet may
    occasionally land on a different replica and return an additional not-found
    response; observed failure proportions can therefore exceed this target.

.EXAMPLE
    ./Invoke-PetstoreLoad.ps1 -PetstoreFqdn 'petstore.example.centralus.azurecontainerapps.io'

.EXAMPLE
    ./Invoke-PetstoreLoad.ps1 -PetstoreFqdn 'petstore.example.centralus.azurecontainerapps.io' -DurationSeconds 600 -FailureRate 0.4
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PetstoreFqdn,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 86400)]
    [int]$DurationSeconds = 300,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 60000)]
    [int]$DelayMilliseconds = 500,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0.0, 1.0)]
    [double]$FailureRate = 0.3
)

#region functions
function Write-Log {
    param([string]$msg)
    Write-Output "$(Get-Date -Format FileDateTimeUniversal) : $msg"
}

function Invoke-PetstoreRequest {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Body
    )

    $params = @{
        Uri             = $Uri
        Method          = $Method
        UseBasicParsing = $true
        TimeoutSec      = 30
    }

    if ($Body) {
        $params['Body'] = $Body
        $params['ContentType'] = 'application/json'
    }

    try {
        $response = Invoke-WebRequest @params
        return [int]$response.StatusCode
    }
    catch {
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode.value__
        }

        Write-Log "Request '$Method $Uri' failed without an HTTP response: $($_.Exception.Message)"
        return 0
    }
}
#endregion

#region main
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$baseUri = "https://$PetstoreFqdn/api/v31"

Write-Log 'Starting Petstore demo load generation...'
Write-Log ("Parameters: PetstoreFqdn='$PetstoreFqdn' DurationSeconds=$DurationSeconds DelayMilliseconds=$DelayMilliseconds FailureRate=$FailureRate")
Write-Log "Base URI: $baseUri"

# Successful operations (expected HTTP 200)
$successRequests = @(
    { param($id) Invoke-PetstoreRequest -Method 'POST' -Uri "$baseUri/pet" -Body ('{"id":' + $id + ',"name":"demo-pet-' + $id + '","photoUrls":["https://example.invalid/pet.jpg"],"status":"available"}') },
    { param($id) Invoke-PetstoreRequest -Method 'PUT'  -Uri "$baseUri/pet" -Body ('{"id":' + $id + ',"name":"demo-pet-' + $id + '","photoUrls":["https://example.invalid/pet.jpg"],"status":"sold"}') },
    { param($id) Invoke-PetstoreRequest -Method 'GET'  -Uri "$baseUri/pet/$id" }
)

# Deliberate failures (expected HTTP 4xx) to populate the Failures blade
$failureRequests = @(
    { param($id) Invoke-PetstoreRequest -Method 'GET'    -Uri "$baseUri/pet/999999999" },                 # 400 - pet not found
    { param($id) Invoke-PetstoreRequest -Method 'GET'    -Uri "$baseUri/pet/notanumber" },                # 404 - unmatched route
    { param($id) Invoke-PetstoreRequest -Method 'POST'   -Uri "$baseUri/pet" -Body '{"bad":"data"}' },    # 400 - invalid body
    { param($id) Invoke-PetstoreRequest -Method 'DELETE' -Uri "$baseUri/pet/$id" }                        # 405 - method not allowed
)

$statusCounts = @{}
$successCount = 0
$failureCount = 0
$errorCount = 0
$total = 0

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$deadline = [datetime]::UtcNow.AddSeconds($DurationSeconds)
$random = [System.Random]::new()

# Seed the store so GET/PUT operations have an existing pet to act on.
$seededId = $random.Next(1, 100000)
$null = Invoke-PetstoreRequest -Method 'POST' -Uri "$baseUri/pet" -Body ('{"id":' + $seededId + ',"name":"demo-seed","photoUrls":["https://example.invalid/pet.jpg"],"status":"available"}')

while ([datetime]::UtcNow -lt $deadline) {
    if ($random.NextDouble() -lt $FailureRate) {
        $request = $failureRequests[$random.Next($failureRequests.Count)]
    }
    else {
        $request = $successRequests[$random.Next($successRequests.Count)]
    }

    $statusCode = & $request $seededId

    $key = "$statusCode"
    if ($statusCounts.ContainsKey($key)) { $statusCounts[$key]++ } else { $statusCounts[$key] = 1 }

    if ($statusCode -eq 0) { $errorCount++ }
    elseif ($statusCode -ge 400) { $failureCount++ }
    else { $successCount++ }

    $total++

    if ($total % 25 -eq 0) {
        Write-Log ("Progress: $total requests sent ($successCount ok, $failureCount failed) after $([int]$stopwatch.Elapsed.TotalSeconds)s")
    }

    Start-Sleep -Milliseconds $DelayMilliseconds
}

$stopwatch.Stop()

Write-Log '----------------------------------------'
Write-Log ("Load generation complete in $([int]$stopwatch.Elapsed.TotalSeconds)s")
Write-Log ("Total requests : $total")
Write-Log ("Successful     : $successCount")
Write-Log ("Failed (4xx)   : $failureCount")
Write-Log ("Transport errs : $errorCount")
Write-Log 'Status code breakdown:'
foreach ($code in ($statusCounts.Keys | Sort-Object)) {
    Write-Log ("  $code : $($statusCounts[$code])")
}
Write-Log 'Review telemetry from jumpwin1 (Application Insights: Performance / Requests / Failures blades) or query the Log Analytics workspace.'
#endregion
