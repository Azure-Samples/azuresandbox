param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$FirewallName,

    [Parameter(Mandatory = $true)]
    [string]$BastionName,

    [Parameter(Mandatory = $true)]
    [string]$MaintenanceConfigurationName,

    [ValidateSet('true', 'false')]
    [string]$VerboseResults = 'false'
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
        [string]$msg,
        [string]$SanitizedMessage = 'Check result'
    )
    if ($status -ne 'SUMMARY' -and $VerboseResults -ne 'true') {
        $msg = $SanitizedMessage
    }
    Write-Log ("[MODULE:$module] [$status] $msg")
}
#endregion

#region main
# Client-side (orchestrator) unit tests for control-plane resources in the vnet-shared module.
# These run in the orchestrator's authenticated Az session (RunLocal = $true in
# Invoke-UnitTests.ps1) rather than VM-side on adds1, so no role assignment on the domain
# controller is required. VM-side checks (AD DS, AMA, DNS, AMPLS, Windows Update) stay in Test-VnetShared.ps1.
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$moduleName = 'vnet-shared'

Write-Log "Starting local (control-plane) unit tests for module '$moduleName'..."
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' FirewallName='$FirewallName' BastionName='$BastionName' MaintenanceConfigurationName='$MaintenanceConfigurationName'")

$passed = 0
$failed = 0

# Test 1: Azure Firewall diagnostic setting streams structured logs and metrics to Log Analytics.
# Confirms the firewall is integrated with the observability framework (issue #610). We assert
# the resource-specific (Dedicated) log categories and the AllMetrics metric category are enabled.
try {
    $firewall = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Network/azureFirewalls' -Name $FirewallName -ErrorAction Stop

    # Get-AzDiagnosticSetting Log/Metric output properties are changing to List types in
    # Az.Monitor 7.0.0; query the diagnostic settings via the REST API to stay version-agnostic.
    $uri = "$($firewall.ResourceId)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
    $response = Invoke-AzRestMethod -Method GET -Path $uri -ErrorAction Stop
    $settings = ($response.Content | ConvertFrom-Json).value

    $diagIssues = @()

    $laSetting = $settings | Where-Object { $_.properties.workspaceId } | Select-Object -First 1

    if (-not $laSetting) {
        $diagIssues += 'no diagnostic setting targeting a Log Analytics workspace found'
    }
    else {
        $enabledLogs = @($laSetting.properties.logs | Where-Object { $_.enabled } | ForEach-Object { $_.category })
        foreach ($category in @('AZFWApplicationRule', 'AZFWNetworkRule', 'AZFWNatRule', 'AZFWThreatIntel', 'AZFWDnsQuery')) {
            if ($enabledLogs -notcontains $category) {
                $diagIssues += "log category '$category' is not enabled"
            }
        }

        $metricsEnabled = @($laSetting.properties.metrics | Where-Object { $_.enabled -and $_.category -eq 'AllMetrics' })
        if ($metricsEnabled.Count -eq 0) {
            $diagIssues += "metric category 'AllMetrics' is not enabled"
        }

        if ($laSetting.properties.logAnalyticsDestinationType -ne 'Dedicated') {
            $diagIssues += "logAnalyticsDestinationType is '$($laSetting.properties.logAnalyticsDestinationType)', expected 'Dedicated'"
        }
    }

    if ($diagIssues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("Firewall diagnostics: '$($laSetting.name)' streams structured AZFW* logs and 'AllMetrics' to Log Analytics (Dedicated tables)") -SanitizedMessage 'Firewall diagnostics: ''<value>'' streams structured AZFW* logs and ''AllMetrics'' to Log Analytics (Dedicated tables)'
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Firewall diagnostics: " + ($diagIssues -join '; ')) -SanitizedMessage 'Firewall diagnostics: <value>'
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to verify diagnostic setting for Azure Firewall '$FirewallName'" -SanitizedMessage 'Failed to verify diagnostic setting for Azure Firewall ''<value>'''
    Write-TestResult $moduleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Test 2: Azure Bastion diagnostic setting streams audit logs and metrics to Log Analytics.
# Confirms the Bastion host is integrated with the observability framework (issue #611). We
# assert the BastionAuditLogs log category and the AllMetrics metric category are enabled.
# BastionAuditLogs requires the Standard (or Premium) SKU. Unlike the firewall test we do NOT
# assert logAnalyticsDestinationType: BastionAuditLogs only writes to the resource-specific
# MicrosoftAzureBastionAuditLogs table, so Azure ignores/clears the destination-type toggle.
try {
    $bastion = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Network/bastionHosts' -Name $BastionName -ErrorAction Stop

    # Get-AzDiagnosticSetting Log/Metric output properties are changing to List types in
    # Az.Monitor 7.0.0; query the diagnostic settings via the REST API to stay version-agnostic.
    $uri = "$($bastion.ResourceId)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
    $response = Invoke-AzRestMethod -Method GET -Path $uri -ErrorAction Stop
    $settings = ($response.Content | ConvertFrom-Json).value

    $diagIssues = @()

    $laSetting = $settings | Where-Object { $_.properties.workspaceId } | Select-Object -First 1

    if (-not $laSetting) {
        $diagIssues += 'no diagnostic setting targeting a Log Analytics workspace found'
    }
    else {
        $enabledLogs = @($laSetting.properties.logs | Where-Object { $_.enabled } | ForEach-Object { $_.category })
        if ($enabledLogs -notcontains 'BastionAuditLogs') {
            $diagIssues += "log category 'BastionAuditLogs' is not enabled"
        }

        $metricsEnabled = @($laSetting.properties.metrics | Where-Object { $_.enabled -and $_.category -eq 'AllMetrics' })
        if ($metricsEnabled.Count -eq 0) {
            $diagIssues += "metric category 'AllMetrics' is not enabled"
        }
    }

    if ($diagIssues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("Bastion diagnostics: '$($laSetting.name)' streams 'BastionAuditLogs' and 'AllMetrics' to Log Analytics") -SanitizedMessage 'Bastion diagnostics: ''<value>'' streams ''BastionAuditLogs'' and ''AllMetrics'' to Log Analytics'
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Bastion diagnostics: " + ($diagIssues -join '; ')) -SanitizedMessage 'Bastion diagnostics: <value>'
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to verify diagnostic setting for Azure Bastion '$BastionName'" -SanitizedMessage 'Failed to verify diagnostic setting for Azure Bastion ''<value>'''
    Write-TestResult $moduleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Test 3: The Azure Update Manager maintenance configuration that patches every sandbox VM on a schedule.
# Asserts the design invariants (in-guest patching, user-managed schedule, Windows and Linux patch settings,
# reboot setting). The configurable schedule values (patch_schedule_* variables) are logged for information only;
# Terraform plan already detects drift from the configuration.
try {
    $maintenanceConfiguration = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Maintenance/maintenanceConfigurations' -Name $MaintenanceConfigurationName -ErrorAction Stop
    $response = Invoke-AzRestMethod -Method GET -Path "$($maintenanceConfiguration.ResourceId)?api-version=2023-04-01" -ErrorAction Stop
    if ($response.StatusCode -ne 200) {
        throw "GET maintenance configuration returned HTTP $($response.StatusCode)"
    }

    $properties = ($response.Content | ConvertFrom-Json).properties
    $scheduleIssues = @()

    if ($properties.maintenanceScope -ne 'InGuestPatch') {
        $scheduleIssues += "maintenanceScope is '$($properties.maintenanceScope)', expected 'InGuestPatch'"
    }
    if ($properties.extensionProperties.InGuestPatchMode -ne 'User') {
        $scheduleIssues += "InGuestPatchMode is '$($properties.extensionProperties.InGuestPatchMode)', expected 'User'"
    }
    if (@($properties.installPatches.windowsParameters.classificationsToInclude).Count -eq 0) {
        $scheduleIssues += 'no Windows classifications are included'
    }
    if (@($properties.installPatches.linuxParameters.classificationsToInclude).Count -eq 0) {
        $scheduleIssues += 'no Linux classifications are included'
    }
    if (-not $properties.installPatches.rebootSetting) {
        $scheduleIssues += 'no reboot setting'
    }

    Write-Log ("Patch schedule: start '$($properties.maintenanceWindow.startDateTime)' ($($properties.maintenanceWindow.timeZone)), recurrence '$($properties.maintenanceWindow.recurEvery)', duration '$($properties.maintenanceWindow.duration)', reboot '$($properties.installPatches.rebootSetting)'")
    Write-Log ("Patch classifications: Windows '" + (@($properties.installPatches.windowsParameters.classificationsToInclude) -join ', ') + "'; Linux '" + (@($properties.installPatches.linuxParameters.classificationsToInclude) -join ', ') + "'")

    if ($scheduleIssues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "Patch schedule: maintenance configuration '$MaintenanceConfigurationName' is an InGuestPatch schedule with Windows and Linux patch settings" -SanitizedMessage 'Patch schedule: maintenance configuration is an InGuestPatch schedule with Windows and Linux patch settings'
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Patch schedule: " + ($scheduleIssues -join '; ')) -SanitizedMessage 'Patch schedule: <value>'
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to verify maintenance configuration '$MaintenanceConfigurationName'" -SanitizedMessage 'Failed to verify the maintenance configuration'
    Write-TestResult $moduleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion