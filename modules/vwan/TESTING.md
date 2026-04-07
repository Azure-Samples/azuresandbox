# vwan Module Unit Testing Plan

## Summary

Add automated unit tests for the `vwan` module following the same **local test** pattern used by the `mssql` and `mysql` modules. Like those modules, `vwan` provisions PaaS resources (Virtual WAN, Virtual Hub, Point-to-Site VPN Gateway) that can be validated from the Terraform execution environment using Azure PowerShell — no VM-based test execution is needed.

The smoke testing procedures in `README.md` primarily describe **integration testing** (P2S VPN client connectivity to various endpoints) and will be addressed separately in a future effort.

## Scope — Unit Tests Only

Unit tests validate that the vwan module's Azure resources were provisioned correctly and are in the expected state. They do **not** test end-to-end P2S VPN connectivity (that is integration testing).

## Test Script

Create: `modules/vwan/scripts/Test-Vwan.ps1`

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `ResourceGroupName` | string | The resource group containing the vwan resources. |
| `VirtualWanName` | string | The name of the Azure Virtual WAN resource. |
| `VirtualHubName` | string | The name of the Azure Virtual WAN Hub resource. |

These values will come from `terraform output resource_names` (keys `virtual_wan` and `virtual_wan_hub`) and `resource_group`, matching the pattern used by mssql/mysql.

### Test Cases

#### Test 1: Virtual WAN exists

- Use `Get-AzVirtualWan -ResourceGroupName $ResourceGroupName -Name $VirtualWanName`.
- Verify the resource exists and is in a succeeded provisioning state.

#### Test 2: Virtual Hub exists with expected address prefix

- Use `Get-AzVirtualHub -ResourceGroupName $ResourceGroupName -Name $VirtualHubName`.
- Verify the resource exists and is in a succeeded provisioning state.
- Verify `AddressPrefix` matches expected value (`10.3.0.0/16`).

#### Test 3: Virtual Hub connections exist

- Use `Get-AzVirtualHubVnetConnection -ResourceGroupName $ResourceGroupName -ParentResourceName $VirtualHubName`.
- Verify at least two connections exist (one for `vnet-shared`, one for `vnet-app`).
- Verify each connection's provisioning state is `Succeeded`.

#### Test 4: Point-to-site VPN gateway exists and is configured

- Use `Get-AzP2sVpnGateway -ResourceGroupName $ResourceGroupName` and filter to the gateway associated with the target virtual hub.
- Verify the gateway exists and provisioning state is `Succeeded`.
- Verify `VpnClientAddressPool` contains the expected client address pool (default `10.4.0.0/16`).

#### Test 5: VPN server configuration exists with certificate authentication

- Use `Get-AzVpnServerConfiguration -ResourceGroupName $ResourceGroupName` and filter to the configuration associated with the VPN gateway.
- Verify the configuration exists.
- Verify `VpnAuthenticationType` contains `Certificate`.
- Verify at least one root certificate is configured.

### Script Template

Follow the exact structure of `Test-Mssql.ps1` / `Test-Mysql.ps1`:

```
param(...)

#region functions
function Write-Log { ... }         # Same as mssql/mysql
function Write-TestResult { ... }  # Same as mssql/mysql
#endregion

#region main
$moduleName = 'vwan'
$passed = 0; $failed = 0

# Test 1..5 (each wrapped in try/catch, incrementing $passed or $failed)

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
```

## Test Runner Changes

### File: `scripts/Invoke-UnitTests.ps1`

#### 1. Add vwan to `$moduleToVmKey`

```powershell
$moduleToVmKey = @{
    # ... existing entries ...
    'vwan' = '$local_vwan'
}
```

Valid module names comment should be updated to include `vwan`.

#### 2. Add vwan test configuration to `$testConfigs`

```powershell
'$local_vwan' = @{
    Module     = 'vwan'
    ModuleName = 'vwan'
    RunLocal   = $true
    ScriptPath = Join-Path $repoRoot 'modules' 'vwan' 'scripts' 'Test-Vwan.ps1'
    Parameters = @{
        ResourceGroupName = $resourceGroupName
        VirtualWanName    = $resourceNames['virtual_wan']
        VirtualHubName    = $resourceNames['virtual_wan_hub']
    }
}
```

#### 3. Required PowerShell modules

No new module dependencies — the tests use `Az.Network` which is already listed in the `#requires` statement.

## Terraform Output Changes

### File: `modules/vwan/outputs.tf`

No changes needed. The module already outputs `resource_names` with keys `virtual_wan` and `virtual_wan_hub`, and these are merged into the root module's `resource_names` output.

### File: `outputs.tf` (root)

No changes needed. Already merges `module.vwan[0].resource_names`.

The `key_vault` key is provided by `vnet_shared.resource_names` and is always present.

## Implementation Checklist

1. [ ] Create `modules/vwan/scripts/Test-Vwan.ps1` with tests 1–5
2. [ ] Add `'vwan' = '$local_vwan'` to `$moduleToVmKey` in `Invoke-UnitTests.ps1`
3. [ ] Add `'$local_vwan'` test config to `$testConfigs` in `Invoke-UnitTests.ps1`
4. [ ] Update valid module names comment in `Invoke-UnitTests.ps1` to include `vwan`
5. [ ] Test locally: `pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vwan`
6. [ ] Test full suite: `pwsh -File ./scripts/Invoke-UnitTests.ps1`

## Future Work (Out of Scope)

- **Integration tests**: Validate actual P2S VPN connectivity from a remote Windows client to sandbox endpoints (RDP, SSH, SMB, TDS, MySQL). These correspond to the smoke testing procedures in `README.md` and will require a connected VPN client as the test execution environment.
