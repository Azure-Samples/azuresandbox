param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$VmName,

    [Parameter(Mandatory = $true)]
    [string]$ModuleName,

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
# Client-side (orchestrator) unit tests for the scheduled patching configuration of one sandbox VM.
# Every base VM (Windows and Linux, platform image or custom image) is patched the same way:
# patch_mode AutomaticByPlatform with Customer Managed Schedules (bypass platform safety checks), and
# an assignment to the sandbox's Azure Update Manager maintenance configuration (owned by vnet-shared).
# With the bypass flag on, an unassigned VM is never patched by Azure, so the assignment is checked too.
# Runs in the orchestrator's authenticated Az session (RunLocal = $true in Invoke-UnitTests.ps1).
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

Write-Log "Starting local (control-plane) patching tests for VM '$VmName' in module '$ModuleName'..."
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' VmName='$VmName' MaintenanceConfigurationName='$MaintenanceConfigurationName'")

$passed = 0
$failed = 0

# Test 1: The VM uses AutomaticByPlatform patching with Customer Managed Schedules and periodic assessment.
$vm = $null
try {
    $vm = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Compute/virtualMachines' -Name $VmName -ErrorAction Stop
    $response = Invoke-AzRestMethod -Method GET -Path "$($vm.ResourceId)?api-version=2024-07-01" -ErrorAction Stop
    if ($response.StatusCode -ne 200) {
        throw "GET virtual machine returned HTTP $($response.StatusCode)"
    }

    $osProfile = ($response.Content | ConvertFrom-Json).properties.osProfile
    $patchSettings = if ($osProfile.windowsConfiguration) { $osProfile.windowsConfiguration.patchSettings } else { $osProfile.linuxConfiguration.patchSettings }

    $patchIssues = @()
    if ($patchSettings.patchMode -ne 'AutomaticByPlatform') {
        $patchIssues += "patchMode is '$($patchSettings.patchMode)', expected 'AutomaticByPlatform'"
    }
    if ($patchSettings.automaticByPlatformSettings.bypassPlatformSafetyChecksOnUserSchedule -ne $true) {
        $patchIssues += "bypassPlatformSafetyChecksOnUserSchedule is '$($patchSettings.automaticByPlatformSettings.bypassPlatformSafetyChecksOnUserSchedule)', expected 'True'"
    }
    if ($patchSettings.assessmentMode -ne 'AutomaticByPlatform') {
        $patchIssues += "assessmentMode is '$($patchSettings.assessmentMode)', expected 'AutomaticByPlatform'"
    }

    if ($patchIssues.Count -eq 0) {
        Write-TestResult $ModuleName 'PASS' "VM '$VmName' patch settings: AutomaticByPlatform with Customer Managed Schedules and AutomaticByPlatform assessment" -SanitizedMessage 'VM patch settings: AutomaticByPlatform with Customer Managed Schedules and AutomaticByPlatform assessment'
        $passed++
    }
    else {
        Write-TestResult $ModuleName 'FAIL' ("VM '$VmName' patch settings: " + ($patchIssues -join '; ')) -SanitizedMessage 'VM patch settings: <value>'
        $failed++
    }
}
catch {
    Write-TestResult $ModuleName 'FAIL' "Failed to verify patch settings for VM '$VmName'" -SanitizedMessage 'Failed to verify VM patch settings'
    Write-TestResult $ModuleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Test 2: The VM is assigned to the sandbox maintenance configuration.
try {
    if (-not $vm) {
        throw "VM '$VmName' wasn't found"
    }

    $response = Invoke-AzRestMethod -Method GET -Path "$($vm.ResourceId)/providers/Microsoft.Maintenance/configurationAssignments?api-version=2023-04-01" -ErrorAction Stop
    if ($response.StatusCode -ne 200) {
        throw "GET configuration assignments returned HTTP $($response.StatusCode)"
    }

    $assignedConfigurationNames = @(($response.Content | ConvertFrom-Json).value | ForEach-Object { ($_.properties.maintenanceConfigurationId -split '/')[-1] })

    if ($assignedConfigurationNames -contains $MaintenanceConfigurationName) {
        Write-TestResult $ModuleName 'PASS' "VM '$VmName' is assigned to maintenance configuration '$MaintenanceConfigurationName'" -SanitizedMessage 'VM is assigned to the sandbox maintenance configuration'
        $passed++
    }
    else {
        Write-TestResult $ModuleName 'FAIL' ("VM '$VmName' isn't assigned to maintenance configuration '$MaintenanceConfigurationName' (assigned: '" + ($assignedConfigurationNames -join "', '") + "')") -SanitizedMessage 'VM is not assigned to the sandbox maintenance configuration'
        $failed++
    }
}
catch {
    Write-TestResult $ModuleName 'FAIL' "Failed to verify maintenance assignment for VM '$VmName'" -SanitizedMessage 'Failed to verify the VM maintenance assignment'
    Write-TestResult $ModuleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $ModuleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
