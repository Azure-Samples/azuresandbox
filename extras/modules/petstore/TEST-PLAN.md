# Petstore Module — Test Plan

## Overview

The petstore module deploys an Azure Container Apps-based PaaS workload. Because there are no VMs to run tests on, all tests follow the **local** execution pattern — PowerShell scripts executed on the Terraform client machine via `Invoke-LocalTest` in `Invoke-UnitTests.ps1`.

### Conventions (from existing local-pattern tests)

| Convention | Detail |
|---|---|
| Test script location | `extras/modules/petstore/scripts/Test-Petstore.ps1` |
| Test runner key | `$local_petstore` with `RunLocal = $true` |
| Module name in `moduleToVmKey` | `petstore` |
| Parameters sourced from | `terraform output resource_names` and `terraform output fqdns` |
| Output format | `Write-TestResult` with `[MODULE:petstore] [PASS/FAIL]` prefix |
| Summary line | `[SUMMARY] Passed: N  Failed: N  Total: N` |

---

## Unit Tests

The test script `Test-Petstore.ps1` will accept the following parameters:

| Parameter | Source |
|---|---|
| `ResourceGroupName` | `resource_names['resource_group']` |
| `ContainerAppEnvironmentName` | `resource_names['container_app_environment']` (new output from module) |
| `ContainerAppName` | hardcoded `petstore` (static name in `main.tf`) |

> **Note:** The module's `outputs.tf` currently only exposes `fqdns`. A new `resource_names` output will need to be added for the container app environment name. The container app name is always `petstore` per `main.tf`.

### Test 1 — Container App Environment exists with expected configuration

| Item | Detail |
|---|---|
| **What** | Verify the Container App Environment resource exists and is properly configured |
| **How** | `Get-AzContainerAppManagedEnv -ResourceGroupName $ResourceGroupName -EnvName $ContainerAppEnvironmentName` |
| **Assertions** | ProvisioningState = `Succeeded`; InternalLoadBalancerEnabled = `$true`; ZoneRedundant setting is present |

### Test 2 — Container App Environment uses system-assigned managed identity

| Item | Detail |
|---|---|
| **What** | Verify the environment has a system-assigned identity for ACR pull |
| **How** | Check `Identity.Type` on the environment resource |
| **Assertions** | Identity type includes `SystemAssigned` |

### Test 3 — Container App exists with expected configuration

| Item | Detail |
|---|---|
| **What** | Verify the Container App resource exists with correct settings |
| **How** | `Get-AzContainerApp -ResourceGroupName $ResourceGroupName -Name $ContainerAppName` |
| **Assertions** | ProvisioningState = `Succeeded`; RevisionMode = `Single`; Template container image matches `*/petstore31:latest`; Ingress target port = `8080` |

### Test 4 — Container App ingress is configured

| Item | Detail |
|---|---|
| **What** | Verify ingress is externally accessible within the environment and uses HTTPS |
| **How** | Inspect the Container App's ingress configuration |
| **Assertions** | External = `$true`; AllowInsecure = `$false`; Traffic weight = 100% on latest revision |

### Test 5 — AcrPull role assignment exists

| Item | Detail |
|---|---|
| **What** | Verify the Container App Environment's managed identity has the AcrPull role on the container registry |
| **How** | `Get-AzRoleAssignment` scoped to the container registry for the environment's principal ID |
| **Assertions** | Role definition name = `AcrPull`; Principal ID matches the environment's system-assigned identity |

### Test 6 — Private endpoint is connected and approved

| Item | Detail |
|---|---|
| **What** | Verify a private endpoint exists for the Container App Environment and is approved |
| **How** | `Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName` filtered to `managedEnvironments` sub-resource |
| **Assertions** | At least one private endpoint exists; connection status = `Approved` |

### Test 7 — Private DNS zone record exists

| Item | Detail |
|---|---|
| **What** | Verify a private DNS A record exists for the Container App Environment |
| **How** | `Get-AzPrivateDnsRecordSet` for zone `privatelink.<location>.azurecontainerapps.io` |
| **Assertions** | At least one A record exists; IP address is non-empty |

---

## Changes Required in Test Runner (`Invoke-UnitTests.ps1`)

1. **`$moduleToVmKey`** — Add entry: `'petstore' = '$local_petstore'`
2. **`$testConfigs`** — Add `$local_petstore` configuration:

   ```powershell
   '$local_petstore' = @{
       Module     = 'petstore'
       ModuleName = 'petstore'
       RunLocal   = $true
       ScriptPath = Join-Path $repoRoot 'extras' 'modules' 'petstore' 'scripts' 'Test-Petstore.ps1'
       Parameters = @{
           ResourceGroupName            = $resourceGroupName
           ContainerAppEnvironmentName  = $resourceNames['container_app_environment']
           ContainerAppName             = 'petstore'
       }
   }
   ```

3. **Module `outputs.tf`** — Add `resource_names` output with `container_app_environment` key.
4. **Root `outputs.tf`** — Merge `module.petstore[0].resource_names` into the `resource_names` output.

---

## Changes Required in Module (`extras/modules/petstore/outputs.tf`)

Add:

```hcl
output "resource_names" {
  value = {
    container_app_environment = azurerm_container_app_environment.this.name
  }
}
```

---

## Integration Testing

Integration test for petstore runs on `jumpwin1` (Windows Server 2025, PowerShell 5.x) via `Invoke-AzVMRunCommand` with `RunPowerShellScript`. The test validates end-to-end connectivity from within the virtual network to the Container App's private endpoint and verifies the Swagger Petstore API is operational.

### Conventions

| Convention | Detail |
|---|---|
| Test script location | `scripts/Test-Integration-Petstore.ps1` |
| Execution target | `jumpwin1` (`virtual_machine_jumpwin1`) via `RunPowerShellScript` |
| PowerShell version | 5.x (Windows built-in) |
| Parameter | `PetstoreFqdn` sourced from `$fqdns['petstore']` |
| API endpoint | `https://<PetstoreFqdn>/api/v31/openapi.json` |
| Module association | `petstore` in `$moduleIntegrationMap` |

### Test 1 — DNS resolves to private IP

| Item | Detail |
|---|---|
| **What** | Verify the petstore FQDN resolves to a private IP address (confirming private DNS is working) |
| **How** | `Resolve-DnsName -Name $PetstoreFqdn -Type A` |
| **Assertions** | Returns an A record; IP address starts with `10.` (private vnet range) |

### Test 2 — HTTPS connectivity on port 443

| Item | Detail |
|---|---|
| **What** | Verify TCP connectivity to the petstore endpoint over HTTPS |
| **How** | `[System.Net.Sockets.TcpClient]::new().Connect($PetstoreFqdn, 443)` |
| **Assertions** | TCP connection succeeds |

### Test 3 — OpenAPI spec is reachable and returns valid JSON

| Item | Detail |
|---|---|
| **What** | Verify the Swagger Petstore OpenAPI spec endpoint responds with valid JSON |
| **How** | `Invoke-RestMethod -Uri "https://$PetstoreFqdn/api/v31/openapi.json" -UseBasicParsing` |
| **Assertions** | HTTP 200 response; response body parses as JSON |

### Test 4 — API metadata contains expected Swagger Petstore fields

| Item | Detail |
|---|---|
| **What** | Verify the OpenAPI `info` block contains expected metadata for the Swagger Petstore 3.1 API |
| **How** | Parse the `info` object from the OpenAPI JSON response |
| **Assertions** | `info.title` matches `Swagger Petstore*`; `info.version` is non-empty (e.g. `1.0.10`); `openapi` field starts with `3.1`; `info.license.name` = `Apache 2.0`; `info.contact.email` = `apiteam@swagger.io` |

---

### Changes Required in Test Runner (`Invoke-UnitTests.ps1`)

1. **`$moduleIntegrationMap`** — Add entry: `'petstore' = @('Petstore API: jumpwin1 -> petstore')`
2. **`$integrationTests`** — Add test configuration:

   ```powershell
   @{
       Name         = 'Petstore API: jumpwin1 -> petstore'
       RequiredVMs  = @('virtual_machine_jumpwin1')
       RequiredFqdn = 'petstore'
       RunOnVM      = 'virtual_machine_jumpwin1'
       ScriptPath   = Join-Path $repoRoot 'scripts' 'Test-Integration-Petstore.ps1'
       CommandId    = 'RunPowerShellScript'
       Parameters   = @{
           PetstoreFqdn = $fqdns['petstore']
       }
   }
   ```

---
