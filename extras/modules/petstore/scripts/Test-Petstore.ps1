param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ContainerAppEnvironmentName,

    [Parameter(Mandatory = $true)]
    [string]$ContainerAppName,

    [Parameter(Mandatory = $true)]
    [string]$ContainerRegistryName
)

#region functions
function Write-Log {
    param([string]$msg)
    Write-Output "$(Get-Date -Format FileDateTimeUniversal) : $msg"
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

$moduleName = 'petstore'

Write-Log "Starting unit tests for module '$moduleName'..."
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' ContainerAppEnvironmentName='$ContainerAppEnvironmentName' ContainerAppName='$ContainerAppName' ContainerRegistryName='$ContainerRegistryName'")

$passed = 0
$failed = 0

# Test 1: Container App Environment exists with expected configuration
try {
    $env = Get-AzContainerAppManagedEnv -ResourceGroupName $ResourceGroupName -Name $ContainerAppEnvironmentName -ErrorAction Stop

    $issues = @()

    if ($env.ProvisioningState -ne 'Succeeded') {
        $issues += "ProvisioningState='$($env.ProvisioningState)' (expected 'Succeeded')"
    }

    if (-not $env.VnetConfigurationInternal) {
        $issues += 'InternalLoadBalancer is not enabled (expected enabled)'
    }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("Container App Environment '$ContainerAppEnvironmentName' exists with expected configuration (Succeeded, internal load balancer enabled)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Container App Environment '$ContainerAppEnvironmentName' configuration issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Container App Environment '$ContainerAppEnvironmentName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: Container App Environment uses system-assigned managed identity
try {
    $envResource = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.App/managedEnvironments' -Name $ContainerAppEnvironmentName -ExpandProperties -ErrorAction Stop

    $identityType = $envResource.Identity.Type

    if ($identityType -match 'SystemAssigned') {
        Write-TestResult $moduleName 'PASS' ("Container App Environment '$ContainerAppEnvironmentName' has system-assigned managed identity (PrincipalId: $($envResource.Identity.PrincipalId))")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Container App Environment '$ContainerAppEnvironmentName' identity type is '$identityType' (expected 'SystemAssigned')")
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query identity for Container App Environment '$ContainerAppEnvironmentName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: Container App exists with expected configuration
try {
    $app = Get-AzContainerApp -ResourceGroupName $ResourceGroupName -Name $ContainerAppName -ErrorAction Stop

    $issues = @()

    if ($app.ProvisioningState -ne 'Succeeded') {
        $issues += "ProvisioningState='$($app.ProvisioningState)' (expected 'Succeeded')"
    }

    $container = $app.TemplateContainer | Select-Object -First 1
    if ($container -and $container.Image -notmatch 'petstore') {
        $issues += "Container image='$($container.Image)' (expected to contain 'petstore')"
    }

    if ($app.Configuration.IngressTargetPort -ne 8080) {
        $issues += "IngressTargetPort='$($app.Configuration.IngressTargetPort)' (expected '8080')"
    }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("Container App '$ContainerAppName' exists with expected configuration (Succeeded, petstore image, port 8080)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Container App '$ContainerAppName' configuration issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Container App '$ContainerAppName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 4: Container App ingress is configured
try {
    $app = Get-AzContainerApp -ResourceGroupName $ResourceGroupName -Name $ContainerAppName -ErrorAction Stop

    $issues = @()

    if (-not $app.Configuration.IngressExternal) {
        $issues += 'Ingress external is not enabled (expected enabled)'
    }

    if ($app.Configuration.IngressAllowInsecure) {
        $issues += 'Ingress allows insecure connections (expected disabled)'
    }

    $trafficWeight = $app.Configuration.IngressTraffic | Where-Object { $_.LatestRevision -eq $true } | Select-Object -First 1
    if (-not $trafficWeight -or $trafficWeight.Weight -ne 100) {
        $actualWeight = if ($trafficWeight) { $trafficWeight.Weight } else { 'none' }
        $issues += "Latest revision traffic weight='$actualWeight' (expected '100')"
    }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("Container App '$ContainerAppName' ingress is correctly configured (external, HTTPS-only, 100% latest revision)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Container App '$ContainerAppName' ingress issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query ingress for Container App '$ContainerAppName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: AcrPull role assignment exists
try {
    $envResource = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.App/managedEnvironments' -Name $ContainerAppEnvironmentName -ExpandProperties -ErrorAction Stop
    $principalId = $envResource.Identity.PrincipalId

    $roleAssignments = Get-AzRoleAssignment -ObjectId $principalId -ErrorAction Stop |
        Where-Object { $_.RoleDefinitionName -eq 'AcrPull' -and $_.Scope -match "Microsoft.ContainerRegistry/registries/$ContainerRegistryName`$" }

    if ($roleAssignments) {
        Write-TestResult $moduleName 'PASS' ("AcrPull role assignment exists for environment identity (PrincipalId: $principalId) on registry '$ContainerRegistryName'")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("No AcrPull role assignment found for environment identity (PrincipalId: $principalId) on registry '$ContainerRegistryName'")
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query role assignments for Container App Environment identity"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 6: Private endpoint is connected and approved
try {
    $endpoints = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
        Where-Object {
            $_.PrivateLinkServiceConnections | Where-Object { $_.PrivateLinkServiceId -match "Microsoft.App/managedEnvironments/$ContainerAppEnvironmentName" }
        }

    if ($endpoints) {
        $connection = $endpoints[0].PrivateLinkServiceConnections[0]
        $status = $connection.PrivateLinkServiceConnectionState.Status

        if ($status -eq 'Approved') {
            Write-TestResult $moduleName 'PASS' ("Private endpoint '$($endpoints[0].Name)' is connected with status 'Approved'")
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("Private endpoint '$($endpoints[0].Name)' connection status is '$status' (expected 'Approved')")
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No private endpoint found for Container App Environment '$ContainerAppEnvironmentName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query private endpoints for Container App Environment '$ContainerAppEnvironmentName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 7: Private DNS A record exists
try {
    $env = Get-AzContainerAppManagedEnv -ResourceGroupName $ResourceGroupName -Name $ContainerAppEnvironmentName -ErrorAction Stop
    $location = $env.Location -replace '\s', ''
    $zoneName = "privatelink.$location.azurecontainerapps.io"

    $recordSets = Get-AzPrivateDnsRecordSet -ResourceGroupName $ResourceGroupName -ZoneName $zoneName -RecordType A -ErrorAction Stop

    if ($recordSets) {
        $ip = $recordSets[0].Records[0].Ipv4Address
        Write-TestResult $moduleName 'PASS' ("Private DNS A record exists in zone '$zoneName' (IP: $ip)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No private DNS A record found in zone '$zoneName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query private DNS zone for Container App Environment"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
