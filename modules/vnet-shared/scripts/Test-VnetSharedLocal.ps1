param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$FirewallName,

    [Parameter(Mandatory = $true)]
    [string]$BastionName
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
# Client-side (orchestrator) unit tests for control-plane resources in the vnet-shared module.
# These run in the orchestrator's authenticated Az session (RunLocal = $true in
# Invoke-UnitTests.ps1) rather than VM-side on adds1, so no role assignment on the domain
# controller is required. VM-side checks (AD DS, AMA, DNS, AMPLS) stay in Test-VnetShared.ps1.
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$moduleName = 'vnet-shared'

Write-Log "Starting local (control-plane) unit tests for module '$moduleName'..."
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' FirewallName='$FirewallName' BastionName='$BastionName'")

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
        Write-TestResult $moduleName 'PASS' ("Firewall diagnostics: '$($laSetting.name)' streams structured AZFW* logs and 'AllMetrics' to Log Analytics (Dedicated tables)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Firewall diagnostics: " + ($diagIssues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to verify diagnostic setting for Azure Firewall '$FirewallName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
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
        Write-TestResult $moduleName 'PASS' ("Bastion diagnostics: '$($laSetting.name)' streams 'BastionAuditLogs' and 'AllMetrics' to Log Analytics")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Bastion diagnostics: " + ($diagIssues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to verify diagnostic setting for Azure Bastion '$BastionName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion