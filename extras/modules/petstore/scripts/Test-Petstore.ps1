param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ContainerAppEnvironmentName,

    [Parameter(Mandatory = $true)]
    [string]$ContainerAppName,

    [Parameter(Mandatory = $true)]
    [string]$ContainerRegistryName,

    [Parameter(Mandatory = $true)]
    [string]$ApplicationInsightsName
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
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' ContainerAppEnvironmentName='$ContainerAppEnvironmentName' ContainerAppName='$ContainerAppName' ContainerRegistryName='$ContainerRegistryName' ApplicationInsightsName='$ApplicationInsightsName'")

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
    if ($container -and $container.Image -notmatch 'petstore-appinsights') {
        $issues += "Container image='$($container.Image)' (expected to contain 'petstore-appinsights')"
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

# Test 8: Container App has a system-assigned managed identity
try {
    $app = Get-AzContainerApp -ResourceGroupName $ResourceGroupName -Name $ContainerAppName -ErrorAction Stop

    if ($app.IdentityType -match 'SystemAssigned' -and $app.IdentityPrincipalId) {
        Write-TestResult $moduleName 'PASS' ("Container App '$ContainerAppName' has a system-assigned managed identity (PrincipalId: $($app.IdentityPrincipalId))")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Container App '$ContainerAppName' identity type is '$($app.IdentityType)' (expected 'SystemAssigned')")
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query identity for Container App '$ContainerAppName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 9: Container App has the Application Insights environment variables wired for Entra ID auth
try {
    $app = Get-AzContainerApp -ResourceGroupName $ResourceGroupName -Name $ContainerAppName -ErrorAction Stop
    $container = $app.TemplateContainer | Select-Object -First 1
    $envVars = @{}
    foreach ($e in $container.Env) { $envVars[$e.Name] = $e.Value }

    $issues = @()

    if ([string]::IsNullOrEmpty($envVars['APPLICATIONINSIGHTS_CONNECTION_STRING'])) {
        $issues += 'APPLICATIONINSIGHTS_CONNECTION_STRING is not set'
    }

    if ($envVars['APPLICATIONINSIGHTS_AUTHENTICATION_STRING'] -ne 'Authorization=AAD') {
        $issues += "APPLICATIONINSIGHTS_AUTHENTICATION_STRING='$($envVars['APPLICATIONINSIGHTS_AUTHENTICATION_STRING'])' (expected 'Authorization=AAD')"
    }

    if ([string]::IsNullOrEmpty($envVars['APPLICATIONINSIGHTS_ROLE_NAME'])) {
        $issues += 'APPLICATIONINSIGHTS_ROLE_NAME is not set'
    }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("Container App '$ContainerAppName' has Application Insights env vars wired for Entra ID auth (connection string set, Authorization=AAD, role name '$($envVars['APPLICATIONINSIGHTS_ROLE_NAME'])')")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Container App '$ContainerAppName' Application Insights env var issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query environment variables for Container App '$ContainerAppName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 10: Container App identity has Monitoring Metrics Publisher on Application Insights
try {
    $app = Get-AzContainerApp -ResourceGroupName $ResourceGroupName -Name $ContainerAppName -ErrorAction Stop
    $principalId = $app.IdentityPrincipalId

    $appInsights = Get-AzApplicationInsights -ResourceGroupName $ResourceGroupName -Name $ApplicationInsightsName -ErrorAction Stop

    $roleAssignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $appInsights.Id -ErrorAction Stop |
        Where-Object { $_.RoleDefinitionName -eq 'Monitoring Metrics Publisher' }

    if ($roleAssignments) {
        Write-TestResult $moduleName 'PASS' ("Monitoring Metrics Publisher role assignment exists for container app identity (PrincipalId: $principalId) on Application Insights '$ApplicationInsightsName'")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("No Monitoring Metrics Publisher role assignment found for container app identity (PrincipalId: $principalId) on Application Insights '$ApplicationInsightsName'")
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query Monitoring Metrics Publisher role assignment for the container app identity"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 11: An AcrPush role assignment exists on the registry (jumplinux1 build identity)
try {
    $registry = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName -Name $ContainerRegistryName -ErrorAction Stop

    $roleAssignments = Get-AzRoleAssignment -Scope $registry.Id -RoleDefinitionName 'AcrPush' -ErrorAction Stop |
        Where-Object { $_.Scope -match "Microsoft.ContainerRegistry/registries/$ContainerRegistryName`$" }

    if ($roleAssignments) {
        Write-TestResult $moduleName 'PASS' ("AcrPush role assignment exists on registry '$ContainerRegistryName' for the image build identity (PrincipalId: $($roleAssignments[0].ObjectId))")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("No AcrPush role assignment found on registry '$ContainerRegistryName' (required for jumplinux1 to build and push the instrumented image)")
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query AcrPush role assignments on registry '$ContainerRegistryName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
