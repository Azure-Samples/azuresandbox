param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$VirtualWanName,

    [Parameter(Mandatory = $true)]
    [string]$VirtualHubName
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

$moduleName = 'vwan'

Write-Log "Starting unit tests for module '$moduleName'..."
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' VirtualWanName='$VirtualWanName' VirtualHubName='$VirtualHubName'")

$passed = 0
$failed = 0

# Test 1: Virtual WAN exists
try {
    $vwan = Get-AzVirtualWan -ResourceGroupName $ResourceGroupName -Name $VirtualWanName -ErrorAction Stop

    if ($vwan.ProvisioningState -eq 'Succeeded') {
        Write-TestResult $moduleName 'PASS' ("Virtual WAN '$VirtualWanName' exists (ProvisioningState: Succeeded)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Virtual WAN '$VirtualWanName' provisioning state is '$($vwan.ProvisioningState)' (expected 'Succeeded')")
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Virtual WAN '$VirtualWanName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: Virtual Hub exists with expected address prefix
try {
    $hub = Get-AzVirtualHub -ResourceGroupName $ResourceGroupName -Name $VirtualHubName -ErrorAction Stop

    $issues = @()

    if ($hub.ProvisioningState -ne 'Succeeded') {
        $issues += "ProvisioningState='$($hub.ProvisioningState)' (expected 'Succeeded')"
    }

    if ($hub.AddressPrefix -ne '10.3.0.0/16') {
        $issues += "AddressPrefix='$($hub.AddressPrefix)' (expected '10.3.0.0/16')"
    }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("Virtual Hub '$VirtualHubName' exists with expected configuration (Succeeded, AddressPrefix: $($hub.AddressPrefix))")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Virtual Hub '$VirtualHubName' configuration issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Virtual Hub '$VirtualHubName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: Virtual Hub connections exist
try {
    $connections = Get-AzVirtualHubVnetConnection -ResourceGroupName $ResourceGroupName -ParentResourceName $VirtualHubName -ErrorAction Stop

    if ($connections.Count -ge 2) {
        $allSucceeded = $true
        $failedConnections = @()

        foreach ($conn in $connections) {
            if ($conn.ProvisioningState -ne 'Succeeded') {
                $allSucceeded = $false
                $failedConnections += "$($conn.Name)=$($conn.ProvisioningState)"
            }
        }

        if ($allSucceeded) {
            $connNames = ($connections | ForEach-Object { $_.Name }) -join ', '
            Write-TestResult $moduleName 'PASS' ("Virtual Hub '$VirtualHubName' has $($connections.Count) VNet connections, all Succeeded ($connNames)")
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("Virtual Hub '$VirtualHubName' has connections with non-Succeeded state: " + ($failedConnections -join '; '))
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Virtual Hub '$VirtualHubName' has $($connections.Count) VNet connections (expected at least 2)")
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query VNet connections for Virtual Hub '$VirtualHubName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 4: Point-to-site VPN gateway exists and is configured
try {
    $gateways = Get-AzP2sVpnGateway -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    $gateway = $gateways | Where-Object { $_.VirtualHub.Id -match $VirtualHubName }

    if ($gateway) {
        $issues = @()

        if ($gateway.ProvisioningState -ne 'Succeeded') {
            $issues += "ProvisioningState='$($gateway.ProvisioningState)' (expected 'Succeeded')"
        }

        $addressPrefixes = $gateway.P2SConnectionConfigurations | ForEach-Object { $_.VpnClientAddressPool.AddressPrefixes } | Select-Object -First 1
        if ($addressPrefixes -notcontains '10.4.0.0/16') {
            $issues += "VpnClientAddressPool='$($addressPrefixes -join ', ')' (expected to contain '10.4.0.0/16')"
        }

        if ($issues.Count -eq 0) {
            Write-TestResult $moduleName 'PASS' ("P2S VPN gateway '$($gateway.Name)' exists with expected configuration (Succeeded, ClientAddressPool: 10.4.0.0/16)")
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("P2S VPN gateway '$($gateway.Name)' configuration issues: " + ($issues -join '; '))
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No P2S VPN gateway found associated with Virtual Hub '$VirtualHubName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query P2S VPN gateways in resource group '$ResourceGroupName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: VPN server configuration exists with certificate authentication
try {
    $configs = Get-AzVpnServerConfiguration -ResourceGroupName $ResourceGroupName -ErrorAction Stop

    if ($configs) {
        $config = $configs | Select-Object -First 1

        $issues = @()

        if ($config.VpnAuthenticationTypes -notcontains 'Certificate') {
            $issues += "VpnAuthenticationTypes='$($config.VpnAuthenticationTypes -join ', ')' (expected to contain 'Certificate')"
        }

        if (-not $config.VpnServerConfigurationPropertiesEtag -and -not $config.VpnClientRootCertificates -and -not $config.RadiusServerRootCertificates) {
            # Check for root certificates via the VpnClientRootCertificates property
            $hasRootCert = $false
        }
        else {
            $hasRootCert = $true
        }

        if ($config.VpnClientRootCertificates -and $config.VpnClientRootCertificates.Count -gt 0) {
            $hasRootCert = $true
        }
        elseif (-not $hasRootCert) {
            $issues += 'No root certificates configured'
        }

        if ($issues.Count -eq 0) {
            Write-TestResult $moduleName 'PASS' ("VPN server configuration '$($config.Name)' exists with certificate authentication")
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("VPN server configuration '$($config.Name)' issues: " + ($issues -join '; '))
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No VPN server configuration found in resource group '$ResourceGroupName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query VPN server configurations in resource group '$ResourceGroupName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
