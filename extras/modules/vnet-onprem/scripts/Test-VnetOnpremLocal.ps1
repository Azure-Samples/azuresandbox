param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$VnetOnpremName,

    [Parameter(Mandatory = $true)]
    [string]$PrivateDnsResolverName
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

$moduleName = 'vnet-onprem'

Write-Log "Starting unit tests for module '$moduleName' (local)..."
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' VnetOnpremName='$VnetOnpremName' PrivateDnsResolverName='$PrivateDnsResolverName'")

$passed = 0
$failed = 0

# Test 1: On-prem VNet exists
$vnet = $null
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VnetOnpremName -ErrorAction Stop

    $issues = @()

    if ($vnet.ProvisioningState -ne 'Succeeded') {
        $issues += "ProvisioningState='$($vnet.ProvisioningState)' (expected 'Succeeded')"
    }

    if ($vnet.AddressSpace.AddressPrefixes -notcontains '192.168.0.0/16') {
        $issues += "AddressSpace='$($vnet.AddressSpace.AddressPrefixes -join ', ')' (expected to contain '192.168.0.0/16')"
    }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' "VNet '$VnetOnpremName' exists (Succeeded, AddressSpace: $($vnet.AddressSpace.AddressPrefixes -join ', '))"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("VNet '$VnetOnpremName' issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "VNet '$VnetOnpremName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: Subnets exist
if ($vnet) {
    $expectedSubnets = @('GatewaySubnet', 'snet-adds-02', 'snet-misc-04')
    $actualSubnets = @($vnet.Subnets | ForEach-Object { $_.Name })
    $missing = $expectedSubnets | Where-Object { $_ -notin $actualSubnets }

    if ($missing.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("Subnets: All expected subnets exist ($($expectedSubnets -join ', '))")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Subnets: Missing subnets: $($missing -join ', '). Found: $($actualSubnets -join ', ')")
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "Subnets: Skipped - VNet not available"
    $failed++
}

# Test 3: NAT gateway exists
try {
    $natGateways = Get-AzNatGateway -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    $natGateway = $natGateways | Where-Object { $_.Name -match 'onprem' -or $_.Subnet.Id -match $VnetOnpremName } | Select-Object -First 1

    if (-not $natGateway) {
        $natGateway = $natGateways | Select-Object -First 1
    }

    if ($natGateway -and $natGateway.ProvisioningState -eq 'Succeeded') {
        Write-TestResult $moduleName 'PASS' "NAT Gateway '$($natGateway.Name)' exists (ProvisioningState: Succeeded)"
        $passed++
    }
    elseif ($natGateway) {
        Write-TestResult $moduleName 'FAIL' "NAT Gateway '$($natGateway.Name)' provisioning state is '$($natGateway.ProvisioningState)' (expected 'Succeeded')"
        $failed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No NAT gateway found in resource group '$ResourceGroupName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query NAT gateways in resource group '$ResourceGroupName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 4: VPN gateway exists (on-prem)
$vpnGateway = $null
try {
    $vpnGateways = Get-AzVirtualNetworkGateway -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    $vpnGateway = $vpnGateways | Where-Object { $_.GatewayType -eq 'Vpn' } | Select-Object -First 1

    if ($vpnGateway) {
        $issues = @()

        if ($vpnGateway.ProvisioningState -ne 'Succeeded') {
            $issues += "ProvisioningState='$($vpnGateway.ProvisioningState)' (expected 'Succeeded')"
        }

        if ($vpnGateway.VpnType -ne 'RouteBased') {
            $issues += "VpnType='$($vpnGateway.VpnType)' (expected 'RouteBased')"
        }

        if (-not $vpnGateway.EnableBgp) {
            $issues += "BGP is not enabled (expected enabled)"
        }

        if ($issues.Count -eq 0) {
            Write-TestResult $moduleName 'PASS' "VPN Gateway '$($vpnGateway.Name)' exists (Succeeded, RouteBased, BGP enabled)"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("VPN Gateway '$($vpnGateway.Name)' issues: " + ($issues -join '; '))
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No VPN gateway found in resource group '$ResourceGroupName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query VPN gateways in resource group '$ResourceGroupName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: VPN gateway connection exists
try {
    $connections = Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    $connection = $connections | Select-Object -First 1

    if ($connection) {
        # Re-fetch by name to populate ConnectionStatus (list mode does not include it)
        $connection = Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $ResourceGroupName -Name $connection.Name -ErrorAction Stop
        if ($connection.ConnectionStatus -eq 'Connected') {
            Write-TestResult $moduleName 'PASS' "VPN Connection '$($connection.Name)' status is 'Connected'"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "VPN Connection '$($connection.Name)' status is '$($connection.ConnectionStatus)' (expected 'Connected')"
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No VPN gateway connection found in resource group '$ResourceGroupName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query VPN gateway connections in resource group '$ResourceGroupName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 6: Private DNS resolver exists
$resolver = $null
try {
    $resolver = Get-AzDnsResolver -ResourceGroupName $ResourceGroupName -Name $PrivateDnsResolverName -ErrorAction Stop

    if ($resolver.ProvisioningState -eq 'Succeeded') {
        Write-TestResult $moduleName 'PASS' "Private DNS Resolver '$PrivateDnsResolverName' exists (ProvisioningState: Succeeded)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Private DNS Resolver '$PrivateDnsResolverName' provisioning state is '$($resolver.ProvisioningState)' (expected 'Succeeded')"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Private DNS Resolver '$PrivateDnsResolverName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 7: DNS resolver inbound endpoint exists
try {
    $inboundEndpoints = Get-AzDnsResolverInboundEndpoint -ResourceGroupName $ResourceGroupName -DnsResolverName $PrivateDnsResolverName -ErrorAction Stop

    if ($inboundEndpoints -and $inboundEndpoints.Count -gt 0) {
        $endpoint = $inboundEndpoints | Select-Object -First 1

        if ($endpoint.ProvisioningState -eq 'Succeeded') {
            Write-TestResult $moduleName 'PASS' "DNS Resolver inbound endpoint '$($endpoint.Name)' exists (ProvisioningState: Succeeded)"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "DNS Resolver inbound endpoint '$($endpoint.Name)' provisioning state is '$($endpoint.ProvisioningState)' (expected 'Succeeded')"
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No inbound endpoints found for DNS Resolver '$PrivateDnsResolverName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query inbound endpoints for DNS Resolver '$PrivateDnsResolverName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 8: DNS resolver outbound endpoint exists
try {
    $outboundEndpoints = Get-AzDnsResolverOutboundEndpoint -ResourceGroupName $ResourceGroupName -DnsResolverName $PrivateDnsResolverName -ErrorAction Stop

    if ($outboundEndpoints -and $outboundEndpoints.Count -gt 0) {
        $endpoint = $outboundEndpoints | Select-Object -First 1

        if ($endpoint.ProvisioningState -eq 'Succeeded') {
            Write-TestResult $moduleName 'PASS' "DNS Resolver outbound endpoint '$($endpoint.Name)' exists (ProvisioningState: Succeeded)"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "DNS Resolver outbound endpoint '$($endpoint.Name)' provisioning state is '$($endpoint.ProvisioningState)' (expected 'Succeeded')"
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No outbound endpoints found for DNS Resolver '$PrivateDnsResolverName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query outbound endpoints for DNS Resolver '$PrivateDnsResolverName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 9: DNS forwarding ruleset exists
$ruleset = $null
try {
    $rulesets = Get-AzDnsForwardingRuleset -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    $ruleset = $rulesets | Select-Object -First 1

    if ($ruleset) {
        Write-TestResult $moduleName 'PASS' "DNS Forwarding Ruleset '$($ruleset.Name)' exists"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No DNS forwarding ruleset found in resource group '$ResourceGroupName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query DNS forwarding rulesets in resource group '$ResourceGroupName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 10: Forwarding rule for on-prem domain
if ($ruleset) {
    try {
        $rules = Get-AzDnsForwardingRulesetForwardingRule -ResourceGroupName $ResourceGroupName -DnsForwardingRulesetName $ruleset.Name -ErrorAction Stop
        $onpremRule = $rules | Where-Object { $_.DomainName -match 'myonprem\.local' }

        if ($onpremRule) {
            $targetIp = $onpremRule.TargetDnsServer[0].IPAddress
            $targetPort = $onpremRule.TargetDnsServer[0].Port

            if ($targetIp -match '^192\.168\.1\.' -and $targetPort -eq 53) {
                Write-TestResult $moduleName 'PASS' "Forwarding rule for on-prem domain exists (target: ${targetIp}:${targetPort})"
                $passed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' "Forwarding rule for on-prem domain has unexpected target: ${targetIp}:${targetPort} (expected 192.168.1.x:53)"
                $failed++
            }
        }
        else {
            Write-TestResult $moduleName 'FAIL' "Forwarding rule for on-prem domain (myonprem.local) not found"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Failed to query forwarding rules for ruleset '$($ruleset.Name)'"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "Forwarding rule: Skipped - ruleset not available"
    $failed++
}

# Test 11: Forwarding rule for cloud domain
if ($ruleset) {
    try {
        $rules = Get-AzDnsForwardingRulesetForwardingRule -ResourceGroupName $ResourceGroupName -DnsForwardingRulesetName $ruleset.Name -ErrorAction Stop
        $cloudRule = $rules | Where-Object { $_.DomainName -match 'mysandbox\.local' }

        if ($cloudRule) {
            $targetIp = $cloudRule.TargetDnsServer[0].IPAddress
            $targetPort = $cloudRule.TargetDnsServer[0].Port

            if ($targetIp -match '^10\.' -and $targetPort -eq 53) {
                Write-TestResult $moduleName 'PASS' "Forwarding rule for cloud domain exists (target: ${targetIp}:${targetPort})"
                $passed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' "Forwarding rule for cloud domain has unexpected target: ${targetIp}:${targetPort} (expected 10.x.x.x:53)"
                $failed++
            }
        }
        else {
            Write-TestResult $moduleName 'FAIL' "Forwarding rule for cloud domain (mysandbox.local) not found"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Failed to query forwarding rules for ruleset '$($ruleset.Name)'"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "Forwarding rule: Skipped - ruleset not available"
    $failed++
}

# Test 12: Ruleset VNet links
if ($ruleset) {
    try {
        $links = Get-AzDnsForwardingRulesetVirtualNetworkLink -ResourceGroupName $ResourceGroupName -DnsForwardingRulesetName $ruleset.Name -ErrorAction Stop

        if ($links -and $links.Count -ge 2) {
            $linkNames = ($links | ForEach-Object { $_.Name }) -join ', '
            Write-TestResult $moduleName 'PASS' "DNS Forwarding Ruleset has $($links.Count) VNet links ($linkNames)"
            $passed++
        }
        else {
            $count = if ($links) { $links.Count } else { 0 }
            Write-TestResult $moduleName 'FAIL' "DNS Forwarding Ruleset has $count VNet links (expected at least 2)"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "Failed to query VNet links for ruleset '$($ruleset.Name)'"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "VNet links: Skipped - ruleset not available"
    $failed++
}

# Test 13: S2S VPN gateway exists (cloud/vwan)
try {
    $vpnGateways = Get-AzVpnGateway -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    $s2sGateway = $vpnGateways | Select-Object -First 1

    if ($s2sGateway -and $s2sGateway.ProvisioningState -eq 'Succeeded') {
        Write-TestResult $moduleName 'PASS' "S2S VPN Gateway '$($s2sGateway.Name)' exists (ProvisioningState: Succeeded)"
        $passed++
    }
    elseif ($s2sGateway) {
        Write-TestResult $moduleName 'FAIL' "S2S VPN Gateway '$($s2sGateway.Name)' provisioning state is '$($s2sGateway.ProvisioningState)' (expected 'Succeeded')"
        $failed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No S2S VPN gateway found in resource group '$ResourceGroupName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query S2S VPN gateways in resource group '$ResourceGroupName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 14: VPN site exists with correct ASN
try {
    $vpnSites = Get-AzVpnSite -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    $vpnSite = $vpnSites | Select-Object -First 1

    if ($vpnSite) {
        $siteAsn = $vpnSite.VpnSiteLinks[0].BgpProperties.Asn

        if ($siteAsn -eq 65123) {
            Write-TestResult $moduleName 'PASS' "VPN Site '$($vpnSite.Name)' exists with BGP ASN $siteAsn"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "VPN Site '$($vpnSite.Name)' has ASN '$siteAsn' (expected '65123')"
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No VPN site found in resource group '$ResourceGroupName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query VPN sites in resource group '$ResourceGroupName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-Log ("[MODULE:$moduleName] [SUMMARY] Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
