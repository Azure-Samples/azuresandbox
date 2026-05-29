# Azure Sandbox — Copilot Instructions

Terraform IaC project that provisions a modular Azure sandbox environment. Not for production use.

## Tech stack

- **Terraform** (version pinned in `terraform.tf` — check there for the current required version)
- **Providers**: `azurerm ~> 4.73`, `azapi ~> 2.9`, `azuread ~> 3.8`, plus `cloudinit`, `null`, `random`, `time`, `tls`
- **Resource naming**: the `Azure/naming/azurerm` module (`module.naming`) — never hand-write resource names; use e.g. `module.naming.key_vault.name_unique`
- **Scripts**: PowerShell 7.x (Az modules) and Bash (Azure CLI). VM-side config uses PowerShell + `azurerm_virtual_machine_run_command` (Windows) and `cloud-init` (Linux)
- Active development branch is `vnext` (not `main`)

## Build / validate / test

Run from repo root. Terraform state lives locally by default (sensitive — see README about adding `backend.tf`).

```bash
terraform init
terraform validate
terraform plan
terraform apply          # 25–95 min depending on enabled modules
tflint                   # uses .tflint.hcl (recommended + azurerm ruleset)
```

The SPN password must come from the env var `TF_VAR_arm_client_secret` — never commit it.

## Applying Terraform configurations (interactive — follow exactly)

**Hard rules — never violate:**

- Never run concurrent `terraform apply` operations against the same sandbox environment (state file). One apply at a time, full stop.
- Never inspect Terraform state (`terraform state ...`, `terraform output`, `terraform show`, `terraform plan`, etc.) while a `terraform apply` is in flight — it will read/lock the same state file and cause errors or corruption.

Two scenarios. In **both**, before doing anything:

1. **Check `TF_VAR_arm_client_secret`** is set (`echo "${TF_VAR_arm_client_secret:+set}"`). If empty, prompt the user for the service principal password using the `ask_user` tool and export it yourself in the shell session before running Terraform.
2. **Ensure `terraform.tfvars` exists** in the repo root. If it doesn't, run `./scripts/bootstrap.sh` to generate it.
3. **Ask the user which modules to enable / disable** in `terraform.tfvars`. Default is: enable **all base modules** in `./modules` (set every `enable_module_*` flag to `true`); leave **all extra modules** in `./extras/modules` (`ai-foundry`, `avd`, `petstore`, `vnet-onprem`, etc.) **disabled**. Confirm "use defaults" vs. a custom subset before editing the file.
4. Normal Terraform rules apply: run `terraform init` before `terraform apply`, `terraform validate` and `terraform plan` first.

### Scenario 1 — Fresh sandbox from scratch

No advance environment prep needed beyond the user being signed in via `az login` (verify with `az account show`). After steps 1–3 above, just run `terraform init && terraform plan && terraform apply`.

After a successful apply, ask the user whether to run unit tests for all installed modules:

```bash
pwsh -File ./scripts/Invoke-UnitTests.ps1
```

### Scenario 2 — Modifying an existing sandbox (enable / disable modules in `terraform.tfvars`)

The barrier pattern leaves Key Vault and Storage Account with public access **disabled** after a successful apply, which breaks subsequent plans. Before `terraform plan` / `apply`, you **must** re-enable public access:

```bash
./scripts/enable-public-access.sh
```

Then proceed with `terraform init` (if providers changed) → `terraform plan` → `terraform apply`. The barrier resources will re-disable public access at the end of the apply.

After a successful apply, if a module was **newly enabled**, ask the user whether to run that module's unit tests + integration tests:

```bash
pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module <module_name> -Integration
```

### Tests (Pester-free, PowerShell-orchestrated)

```bash
# Auth once (persisted to ~/.Azure):
pwsh -Command 'Connect-AzAccount -UseDeviceAuthentication'

# All modules:
pwsh -File ./scripts/Invoke-UnitTests.ps1

# Single module unit tests:
pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vnet_app

# Module unit + its integration tests:
pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vm_mssql_win -Integration
```

Valid `-Module` values: `vnet_shared`, `vnet_app`, `vm_jumpbox_linux`, `vm_mssql_win`, `mssql`, `mysql`, `vwan`, `vnet_onprem`. Tests require an applied sandbox in the current Terraform state. Exit code is `0`/`1` for CI use.

## Architecture

Root module (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `terraform.tf`) wires together child modules in `modules/`. Each child module is conditionally enabled via a root variable.

### Module enablement pattern

Every optional module follows the same shape — do not deviate when adding new ones:

```hcl
module "vnet_app" {
  source = "./modules/vnet-app"
  count  = var.enable_module_vnet_app ? 1 : 0
  ...
}
```

Required: `vnet_shared` (always on). Optional, with `enable_module_*` toggles: `vnet_app`, `vm_jumpbox_linux`, `vm_mssql_win`, `mssql`, `mysql`, `vwan`. `vnet_app` is the hub all other optional modules depend on.

Cross-module references must guard for the optional modules being disabled, e.g.:
`var.enable_module_vnet_app ? module.vnet_app[0].resource_ids["storage_account"] : null`.

### Public-access barrier pattern (critical — read before touching `main.tf`)

Several shared resources (Key Vault, Storage Account, AMPLS, Log Analytics, App Insights) are provisioned with `public_network_access_enabled = true` because Terraform data-plane writes (secrets, blob uploads, diagnostic settings) need it. The root module flips them to private **after** every enabled module finishes its writes, using an implicit-dependency "barrier":

1. Each module that performs public-access-requiring writes exposes a `*_operations_complete` output (e.g. `key_vault_operations_complete`, `storage_operations_complete`, `log_analytics_operations_complete`) that depends on its last data-plane write.
2. Root `main.tf` collects these signals into a `terraform_data` barrier resource (one per shared resource: `key_vault_access_barrier`, `storage_access_barrier`, `ampls_access_barrier`).
3. An `azapi_update_resource` references `terraform_data.<barrier>.output.<id>`, creating the implicit dependency chain. No `depends_on` needed.
4. Each child resource that the barrier closes must declare `lifecycle { ignore_changes = [public_network_access_enabled] }` so subsequent plans don't fight the barrier.

When adding a new module that touches one of these shared resources: emit the appropriate `*_operations_complete` output and add it as an input to the matching barrier in root `main.tf`. The AMPLS barrier is being rolled out incrementally — see comments in `main.tf` for which modules are wired in.

### File layout convention inside modules

Larger modules split HCL by concern instead of one giant `main.tf`:
`compute.tf`, `network.tf`, `storage.tf`, `locals.tf`, `main.tf`, `outputs.tf`, `terraform.tf`, `variables.tf`. Within a `.tf` file, group resources with `#region <name>` / `#endregion` comments.

### Outputs convention

Modules expose two map outputs used heavily by the root and other modules: `resource_ids` and `resource_names` (and sometimes `fqdns`, `private_dns_zones`). Look them up by key, e.g. `module.vnet_shared.resource_ids["key_vault"]`. Add new resources to these maps rather than creating new top-level outputs.

## Secrets handling

- Secrets that should never be in state files are passed via env var (`TF_VAR_arm_client_secret`).
- Key Vault secrets use the **write-only** attribute pair: `value_wo = ...` + `value_wo_version = var.<name>_secret_version`. Use this pattern (not `value`) for any new Key Vault secret so values don't land in state.
- `.gitignore` excludes `*.tfvars`, `*.pem`, `*.pfx`, `*.tfstate*`, `terraform.log`.

## Documentation expectations

Every module has a `README.md` with the same sections: Architecture (drawio SVG in `images/`), Overview, Smoke testing, Documentation (variables / resources / outputs tables). When adding or changing inputs, resources, or outputs, update both the module README and the root README's relevant table.

## Branch / PR notes

- Day-to-day work happens on `vnext`; PRs target `vnext`.
- A CLA bot runs on PRs (Microsoft Open Source CLA).
- `.vscode/tasks.json` provides a one-shot task to squash-merge all open PRs into `vnext` (`gh pr list ... | xargs gh pr merge --squash`).
