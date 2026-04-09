param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$AvdWorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$HostPoolPersonalName,

    [Parameter(Mandatory = $true)]
    [string]$HostPoolRemoteappName,

    [Parameter(Mandatory = $true)]
    [string]$AppGroupPersonalName,

    [Parameter(Mandatory = $true)]
    [string]$AppGroupRemoteappName,

    [Parameter(Mandatory = $true)]
    [string]$VmNamePersonal,

    [Parameter(Mandatory = $true)]
    [string]$VmNameRemoteapp
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

$moduleName = 'avd'

Write-Log "Starting unit tests for module '$moduleName'..."
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' AvdWorkspaceName='$AvdWorkspaceName' HostPoolPersonalName='$HostPoolPersonalName' HostPoolRemoteappName='$HostPoolRemoteappName' AppGroupPersonalName='$AppGroupPersonalName' AppGroupRemoteappName='$AppGroupRemoteappName' VmNamePersonal='$VmNamePersonal' VmNameRemoteapp='$VmNameRemoteapp'")

$passed = 0
$failed = 0

# Test 1: Workspace exists with expected friendly name
try {
    $workspace = Get-AzWvdWorkspace -ResourceGroupName $ResourceGroupName -Name $AvdWorkspaceName -ErrorAction Stop

    if ($workspace.FriendlyName -eq 'AVD Quickstart Workspace') {
        Write-TestResult $moduleName 'PASS' "Workspace '$AvdWorkspaceName' exists with friendly name 'AVD Quickstart Workspace'"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Workspace '$AvdWorkspaceName' friendly name is '$($workspace.FriendlyName)' (expected 'AVD Quickstart Workspace')"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Workspace '$AvdWorkspaceName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: Personal host pool exists with expected configuration
try {
    $pool = Get-AzWvdHostPool -ResourceGroupName $ResourceGroupName -Name $HostPoolPersonalName -ErrorAction Stop

    $issues = @()

    if ($pool.HostPoolType -ne 'Pooled') { $issues += "HostPoolType='$($pool.HostPoolType)' (expected 'Pooled')" }
    if ($pool.LoadBalancerType -ne 'BreadthFirst') { $issues += "LoadBalancerType='$($pool.LoadBalancerType)' (expected 'BreadthFirst')" }
    if ($pool.MaxSessionLimit -ne 2) { $issues += "MaxSessionLimit='$($pool.MaxSessionLimit)' (expected '2')" }
    if ($pool.PreferredAppGroupType -ne 'Desktop') { $issues += "PreferredAppGroupType='$($pool.PreferredAppGroupType)' (expected 'Desktop')" }
    if ($pool.ValidationEnvironment -ne $false) { $issues += "ValidationEnvironment='$($pool.ValidationEnvironment)' (expected 'False')" }
    if ($pool.StartVMOnConnect -ne $false) { $issues += "StartVMOnConnect='$($pool.StartVMOnConnect)' (expected 'False')" }
    if ($pool.CustomRdpProperty -notmatch 'enablerdsaadauth:i:1') { $issues += "CustomRdpProperty missing 'enablerdsaadauth:i:1'" }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "Personal host pool '$HostPoolPersonalName' exists with expected configuration (Pooled, BreadthFirst, MaxSessions=2, Desktop, RDP AAD auth)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Personal host pool '$HostPoolPersonalName' configuration issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Personal host pool '$HostPoolPersonalName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: RemoteApp host pool exists with expected configuration
try {
    $pool = Get-AzWvdHostPool -ResourceGroupName $ResourceGroupName -Name $HostPoolRemoteappName -ErrorAction Stop

    $issues = @()

    if ($pool.HostPoolType -ne 'Pooled') { $issues += "HostPoolType='$($pool.HostPoolType)' (expected 'Pooled')" }
    if ($pool.LoadBalancerType -ne 'BreadthFirst') { $issues += "LoadBalancerType='$($pool.LoadBalancerType)' (expected 'BreadthFirst')" }
    if ($pool.MaxSessionLimit -ne 10) { $issues += "MaxSessionLimit='$($pool.MaxSessionLimit)' (expected '10')" }
    if ($pool.PreferredAppGroupType -ne 'RailApplications') { $issues += "PreferredAppGroupType='$($pool.PreferredAppGroupType)' (expected 'RailApplications')" }
    if ($pool.ValidationEnvironment -ne $false) { $issues += "ValidationEnvironment='$($pool.ValidationEnvironment)' (expected 'False')" }
    if ($pool.StartVMOnConnect -ne $false) { $issues += "StartVMOnConnect='$($pool.StartVMOnConnect)' (expected 'False')" }
    if ($pool.CustomRdpProperty -notmatch 'enablerdsaadauth:i:1') { $issues += "CustomRdpProperty missing 'enablerdsaadauth:i:1'" }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "RemoteApp host pool '$HostPoolRemoteappName' exists with expected configuration (Pooled, BreadthFirst, MaxSessions=10, RailApplications, RDP AAD auth)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("RemoteApp host pool '$HostPoolRemoteappName' configuration issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "RemoteApp host pool '$HostPoolRemoteappName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 4: Personal app group exists with expected configuration
try {
    $appGroup = Get-AzWvdApplicationGroup -ResourceGroupName $ResourceGroupName -Name $AppGroupPersonalName -ErrorAction Stop

    $issues = @()

    if ($appGroup.ApplicationGroupType -ne 'Desktop') { $issues += "Type='$($appGroup.ApplicationGroupType)' (expected 'Desktop')" }
    if ($appGroup.HostPoolArmPath -notmatch [regex]::Escape($HostPoolPersonalName)) { $issues += "HostPoolArmPath does not reference '$HostPoolPersonalName'" }
    if ($appGroup.FriendlyName -ne 'Personal Desktop') { $issues += "FriendlyName='$($appGroup.FriendlyName)' (expected 'Personal Desktop')" }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "Personal app group '$AppGroupPersonalName' exists (Desktop type, friendly name 'Personal Desktop', linked to '$HostPoolPersonalName')"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Personal app group '$AppGroupPersonalName' issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Personal app group '$AppGroupPersonalName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: RemoteApp app group exists with expected configuration
try {
    $appGroup = Get-AzWvdApplicationGroup -ResourceGroupName $ResourceGroupName -Name $AppGroupRemoteappName -ErrorAction Stop

    $issues = @()

    if ($appGroup.ApplicationGroupType -ne 'RemoteApp') { $issues += "Type='$($appGroup.ApplicationGroupType)' (expected 'RemoteApp')" }
    if ($appGroup.HostPoolArmPath -notmatch [regex]::Escape($HostPoolRemoteappName)) { $issues += "HostPoolArmPath does not reference '$HostPoolRemoteappName'" }
    if ($appGroup.FriendlyName -ne 'RemoteApp Group') { $issues += "FriendlyName='$($appGroup.FriendlyName)' (expected 'RemoteApp Group')" }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "RemoteApp app group '$AppGroupRemoteappName' exists (RemoteApp type, friendly name 'RemoteApp Group', linked to '$HostPoolRemoteappName')"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("RemoteApp app group '$AppGroupRemoteappName' issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "RemoteApp app group '$AppGroupRemoteappName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 6: Microsoft Edge published in RemoteApp group
try {
    $app = Get-AzWvdApplication -ResourceGroupName $ResourceGroupName -ApplicationGroupName $AppGroupRemoteappName -Name 'MicrosoftEdge' -ErrorAction Stop

    $issues = @()

    if ($app.FriendlyName -ne 'Microsoft Edge') { $issues += "FriendlyName='$($app.FriendlyName)' (expected 'Microsoft Edge')" }
    if ($app.CommandLineSetting -ne 'DoNotAllow') { $issues += "CommandLineSetting='$($app.CommandLineSetting)' (expected 'DoNotAllow')" }
    if ($app.ShowInPortal -ne $true) { $issues += "ShowInPortal='$($app.ShowInPortal)' (expected 'True')" }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "Microsoft Edge published in RemoteApp group (FriendlyName='Microsoft Edge', CommandLineSetting='DoNotAllow', ShowInPortal=True)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Microsoft Edge application issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Microsoft Edge application not found in RemoteApp group '$AppGroupRemoteappName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 7: Workspace has both app groups associated
try {
    $workspace = Get-AzWvdWorkspace -ResourceGroupName $ResourceGroupName -Name $AvdWorkspaceName -ErrorAction Stop

    $refs = $workspace.ApplicationGroupReference
    $personalRef = $refs | Where-Object { $_ -match [regex]::Escape($AppGroupPersonalName) }
    $remoteappRef = $refs | Where-Object { $_ -match [regex]::Escape($AppGroupRemoteappName) }

    $issues = @()

    if (-not $personalRef) { $issues += "Personal app group '$AppGroupPersonalName' not found in ApplicationGroupReference" }
    if (-not $remoteappRef) { $issues += "RemoteApp app group '$AppGroupRemoteappName' not found in ApplicationGroupReference" }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "Workspace '$AvdWorkspaceName' has both app groups associated ($($refs.Count) references)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Workspace '$AvdWorkspaceName' association issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query workspace '$AvdWorkspaceName' for app group associations"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 8: Personal session host VM exists with expected config
try {
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmNamePersonal -ErrorAction Stop

    $issues = @()

    if ($vm.LicenseType -ne 'Windows_Client') { $issues += "LicenseType='$($vm.LicenseType)' (expected 'Windows_Client')" }
    if (-not $vm.SecurityProfile.SecurityType -or $vm.SecurityProfile.SecurityType -ne 'TrustedLaunch') { $issues += "SecurityType='$($vm.SecurityProfile.SecurityType)' (expected 'TrustedLaunch')" }
    if (-not $vm.SecurityProfile.UefiSettings.SecureBootEnabled) { $issues += "SecureBoot is not enabled" }
    if (-not $vm.SecurityProfile.UefiSettings.VTpmEnabled) { $issues += "vTPM is not enabled" }
    if ($vm.StorageProfile.OsDisk.Caching -ne 'ReadWrite') { $issues += "OsDisk Caching='$($vm.StorageProfile.OsDisk.Caching)' (expected 'ReadWrite')" }
    if ($vm.Identity.Type -notmatch 'SystemAssigned') { $issues += "Identity Type='$($vm.Identity.Type)' (expected 'SystemAssigned')" }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "Personal VM '$VmNamePersonal' exists with expected config (Windows_Client, TrustedLaunch, SecureBoot, vTPM, ReadWrite cache, SystemAssigned identity)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Personal VM '$VmNamePersonal' configuration issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Personal VM '$VmNamePersonal' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 9: RemoteApp session host VM exists with expected config
try {
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmNameRemoteapp -ErrorAction Stop

    $issues = @()

    if ($vm.LicenseType -ne 'Windows_Client') { $issues += "LicenseType='$($vm.LicenseType)' (expected 'Windows_Client')" }
    if (-not $vm.SecurityProfile.SecurityType -or $vm.SecurityProfile.SecurityType -ne 'TrustedLaunch') { $issues += "SecurityType='$($vm.SecurityProfile.SecurityType)' (expected 'TrustedLaunch')" }
    if (-not $vm.SecurityProfile.UefiSettings.SecureBootEnabled) { $issues += "SecureBoot is not enabled" }
    if (-not $vm.SecurityProfile.UefiSettings.VTpmEnabled) { $issues += "vTPM is not enabled" }
    if ($vm.StorageProfile.OsDisk.Caching -ne 'ReadWrite') { $issues += "OsDisk Caching='$($vm.StorageProfile.OsDisk.Caching)' (expected 'ReadWrite')" }
    if ($vm.Identity.Type -notmatch 'SystemAssigned') { $issues += "Identity Type='$($vm.Identity.Type)' (expected 'SystemAssigned')" }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "RemoteApp VM '$VmNameRemoteapp' exists with expected config (Windows_Client, TrustedLaunch, SecureBoot, vTPM, ReadWrite cache, SystemAssigned identity)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("RemoteApp VM '$VmNameRemoteapp' configuration issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "RemoteApp VM '$VmNameRemoteapp' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 10: Personal session host registered to personal host pool
try {
    $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolPersonalName -ErrorAction Stop
    $match = $sessionHosts | Where-Object { $_.Name -match [regex]::Escape($VmNamePersonal) }

    if ($match) {
        Write-TestResult $moduleName 'PASS' "Personal session host '$VmNamePersonal' registered to host pool '$HostPoolPersonalName' (Status=$($match.Status))"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Personal session host '$VmNamePersonal' not found in host pool '$HostPoolPersonalName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query session hosts for host pool '$HostPoolPersonalName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 11: RemoteApp session host registered to remoteapp host pool
try {
    $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolRemoteappName -ErrorAction Stop
    $match = $sessionHosts | Where-Object { $_.Name -match [regex]::Escape($VmNameRemoteapp) }

    if ($match) {
        Write-TestResult $moduleName 'PASS' "RemoteApp session host '$VmNameRemoteapp' registered to host pool '$HostPoolRemoteappName' (Status=$($match.Status))"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "RemoteApp session host '$VmNameRemoteapp' not found in host pool '$HostPoolRemoteappName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query session hosts for host pool '$HostPoolRemoteappName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 12: NICs have accelerated networking enabled
try {
    $nics = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
        Where-Object { $_.Name -match [regex]::Escape($VmNamePersonal) -or $_.Name -match [regex]::Escape($VmNameRemoteapp) }

    $issues = @()

    if ($nics.Count -lt 2) {
        $issues += "Found $($nics.Count) NICs (expected 2)"
    }
    else {
        foreach ($nic in $nics) {
            if (-not $nic.EnableAcceleratedNetworking) {
                $issues += "NIC '$($nic.Name)' does not have accelerated networking enabled"
            }
        }
    }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "Both NICs have accelerated networking enabled ($($nics.Count) NICs found)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("NIC issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query network interfaces"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 13: Virtual Machine User Login role assigned on resource group
try {
    $vmUserLoginRole = 'fb879df8-f326-4884-b1cf-06f3ad86be52'
    $rgScope = (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop).ResourceId
    $assignments = Get-AzRoleAssignment -Scope $rgScope -ErrorAction Stop |
        Where-Object { $_.RoleDefinitionId -match $vmUserLoginRole }

    if ($assignments) {
        Write-TestResult $moduleName 'PASS' "Virtual Machine User Login role assigned on resource group '$ResourceGroupName' ($($assignments.Count) assignment(s))"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No Virtual Machine User Login role assignment found on resource group '$ResourceGroupName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query role assignments on resource group '$ResourceGroupName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 14: Desktop Virtualization User role on personal app group
try {
    $dvuRole = '1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63'
    $appGroup = Get-AzWvdApplicationGroup -ResourceGroupName $ResourceGroupName -Name $AppGroupPersonalName -ErrorAction Stop
    $appGroupId = $appGroup.Id
    $assignments = Get-AzRoleAssignment -Scope $appGroupId -ErrorAction Stop |
        Where-Object { $_.RoleDefinitionId -match $dvuRole }

    if ($assignments) {
        Write-TestResult $moduleName 'PASS' "Desktop Virtualization User role assigned on personal app group '$AppGroupPersonalName' ($($assignments.Count) assignment(s))"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No Desktop Virtualization User role assignment found on personal app group '$AppGroupPersonalName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query role assignments on personal app group '$AppGroupPersonalName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 15: Desktop Virtualization User role on remoteapp app group
try {
    $dvuRole = '1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63'
    $appGroup = Get-AzWvdApplicationGroup -ResourceGroupName $ResourceGroupName -Name $AppGroupRemoteappName -ErrorAction Stop
    $appGroupId = $appGroup.Id
    $assignments = Get-AzRoleAssignment -Scope $appGroupId -ErrorAction Stop |
        Where-Object { $_.RoleDefinitionId -match $dvuRole }

    if ($assignments) {
        Write-TestResult $moduleName 'PASS' "Desktop Virtualization User role assigned on remoteapp app group '$AppGroupRemoteappName' ($($assignments.Count) assignment(s))"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No Desktop Virtualization User role assignment found on remoteapp app group '$AppGroupRemoteappName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query role assignments on remoteapp app group '$AppGroupRemoteappName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
