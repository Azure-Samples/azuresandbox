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

## Preflight checklist (run attended, before enabling autopilot for any apply or test work)

This project runs in autopilot for long operations (`terraform apply` is 25–95 min; unit tests can be 10+ min). The preflight checklist itself, however, **must be completed with a human present — i.e. NOT in autopilot mode** — because every item may require an `ask_user` prompt (secrets, auth confirmations, sudo password, module selection), and `ask_user` cannot be answered during unattended execution. To avoid failing mid-run because of a missing secret, expired auth, or a missing sudo NOPASSWD drop-in, **collect every human-gated input up front** in a single attended preflight phase. Once preflight passes, the rest of the run should not require user intervention.

The intended workflow is a clean two-phase handoff:

1. **Attended preflight** — autopilot **off**. Work through every preflight item below, batching all `ask_user` prompts back-to-back while the user is present.
2. **Unattended execution** — once (and only once) every preflight item is satisfied, **prompt the user to switch to autopilot mode by running `/allow-all`** so the long-running apply and tests can complete fully automated without further intervention. Do not begin `terraform apply`, `terraform plan`, or `Invoke-UnitTests.ps1` until the user has confirmed they have enabled autopilot.

**Hard rules — never violate:**

- **Do not run the preflight checklist in autopilot mode.** Preflight requires human input via `ask_user`; complete it attended, then hand off to autopilot only after every item passes.
- **Do not start `terraform apply`, `terraform plan`, or `Invoke-UnitTests.ps1` until every preflight item below is satisfied AND the user has switched to autopilot (`/allow-all`).** A failed apply 40 minutes in because a secret was missing is the worst outcome — fail fast at preflight instead.
- Never run concurrent `terraform apply` operations against the same sandbox environment (state file). One apply at a time, full stop.
- Never inspect Terraform state (`terraform state ...`, `terraform output`, `terraform show`, `terraform plan`, etc.) while a `terraform apply` is in flight — it will read/lock the same state file and cause errors or corruption.
- Batch all `ask_user` prompts back-to-back at the start of the session. Do not interleave human prompts with long-running tool calls.

**Preflight items — check each one and resolve before proceeding:**

1. **Service principal secret (`TF_VAR_arm_client_secret`)** — check with `echo "${TF_VAR_arm_client_secret:+set}"`. If empty, use `ask_user` to prompt for the SPN password, then export it in the shell session before any Terraform command. Required for every `terraform plan` / `apply`.
2. **Azure CLI auth (`az login`)** — verify with `az account show`. If it fails, use `ask_user` to instruct the user to run `az login` in their own terminal, and wait for confirmation before proceeding. Required for `terraform apply` and for `enable-public-access.sh`.
3. **Azure PowerShell auth (`Connect-AzAccount`)** — verify with `pwsh -Command 'Get-AzContext'`. If empty, use `ask_user` to instruct the user to run `pwsh -Command 'Connect-AzAccount -UseDeviceAuthentication'` (credentials persist to `~/.Azure`). Required only when `Invoke-UnitTests.ps1` will be run — i.e. when the unit-testing decision in preflight item 7 is **yes**.
4. **Sudo NOPASSWD drop-in for vwan tests (WSL/Linux Terraform execution environment)** — the `vwan` integration tests (`Test-Integration-VwanConnectivity.ps1`) invoke a handful of privileged commands at runtime (`openvpn`, `cat`, `tail`, `kill`, `pkill`). These are granted promptlessly by a persistent, command-scoped sudoers drop-in at `/etc/sudoers.d/azuresandbox-vwan`, so **no sudo password or timestamp-cache refresh is needed** — unattended/autopilot runs work without human intervention. Required only when `Invoke-UnitTests.ps1` will run the vwan integration tests — i.e. when the unit-testing decision in preflight item 7 is **yes**, `vwan` is enabled, and integration tests are requested. Procedure:
   - Verify the drop-in is installed and the rules are active: `sudo -n cat /dev/null && echo ok` (the test scripts use this exact `sudo -n cat /dev/null` probe — not `sudo -n true`, which the command-scoped allowlist deliberately denies). If it prints `ok`, sudo is ready; do nothing further.
   - If the probe fails (drop-in missing — e.g. a fresh execution environment), recreate it: write a file containing `<user> ALL=(root) NOPASSWD: /usr/sbin/openvpn, /usr/bin/cat, /bin/cat, /usr/bin/tail, /bin/tail, /usr/bin/kill, /bin/kill, /usr/bin/pkill`, validate it with `visudo -c -f <file>`, then install it as root with `install -m 0440 -o root -g root <file> /etc/sudoers.d/azuresandbox-vwan`. Installing it needs the sudo password **once** — prompt via `ask_user`, use it inline with `sudo -S`, and do **not** persist it to disk, echo it, pass it as a CLI argument, or store it in the session database.
   - Because the allowlist is binary-scoped (not `NOPASSWD: ALL`), it permits only those specific commands with any arguments; `sudo` for anything else still requires a password. This is an intentional security/convenience tradeoff for the sandbox execution environment.
   - Non-vwan modules' tests do not require sudo, so this item is irrelevant unless `vwan` is enabled and `-Integration` is requested.
5. **`terraform.tfvars` exists** in the repo root. If missing, run `./scripts/bootstrap.sh` (Linux Terraform execution environment) or `./scripts/bootstrap.ps1` (Windows). The two scripts are equivalent — pick the one matching the host OS.
6. **Module enablement confirmed** — use `ask_user` to ask whether **all base modules** in `./modules` should be deployed (every `enable_module_*` flag `true`). Extra modules in `./extras/modules` (`ai-foundry`, `avd`, `petstore`, `vnet-onprem`, etc.) are **always excluded** from this question and left **disabled**. If the answer is **no**, use `ask_user` again to have the user specify exactly which base modules to enable (e.g. `vnet_app` only); all other base modules stay disabled. Confirm the selection before editing `terraform.tfvars`.
7. **Automated unit testing decision** — use `ask_user` to ask whether automated unit tests (`Invoke-UnitTests.ps1`) should be run after a successful `terraform apply`. Capture this decision now, batched with the other preflight prompts, because it determines whether preflight items 3 (Azure PowerShell auth) and 4 (sudo NOPASSWD drop-in for vwan tests) are required — those human-gated inputs must be collected up front, not after the autopilot handoff. If the answer is **yes**, also confirm scope: all installed modules (`Invoke-UnitTests.ps1`) versus a specific module and whether to include its integration tests (`-Module <name> [-Integration]`). If the answer is **no**, record it and skip items 3 and 4 (unless otherwise needed). The recorded decision drives the post-apply test step in Scenarios 1 and 2 — do not re-prompt for it after the apply.

After all preflight items pass, the remaining attended setup depends on the scenario: for a fresh vnext sandbox there are additional human-gated prep steps (see Scenario 1) that must also be completed attended. Once **all** attended setup (preflight plus any scenario-specific prep) is done and nothing further requires `ask_user`, **use `ask_user` to prompt the user to enable autopilot by running `/allow-all`**, and wait for their confirmation before proceeding. This is the handoff from the attended phase to fully automated execution. Once autopilot is enabled, normal Terraform rules apply: `terraform init` before `terraform apply`; run `terraform validate` and `terraform plan` first.

## Applying Terraform configurations

### Progress reporting for long-running operations (apply, tests — autopilot included)

Long-running commands (`terraform apply` is 25–95 min; `terraform plan`, `terraform destroy`, and `Invoke-UnitTests.ps1` can each run 10+ min) must be run with the **bash tool in `mode="async"`** so they keep streaming output while you monitor them. **Emit a progress report to the user every two minutes** until the command completes. Each report should be short (1–2 sentences) and include:

- Elapsed wall-clock time since the command started (e.g. "≈12 min elapsed").
- The most recent meaningful line(s) of output — for `terraform apply`, the resources currently being created/modified and any `Still creating... [Xm Ys elapsed]` progress lines; for unit tests, the current module/test.
- A one-line assessment of whether the operation is healthy, stalled, or hung (see detection logic below).

Implementation guidance:

- Start the command with `mode="async"` (use `detach: true` only for true background servers, not for apply/tests you are monitoring), then poll with `read_bash` on a roughly two-minute cadence to capture incremental output and drive each report.
- Do **not** spam the user between reports. One concise update every ~2 minutes is the target — no per-tool-call narration in between.
- Keep reporting until the process exits, then give a final completion (or failure) summary.

#### Hung-process detection logic

A long-running operation is **healthy as long as its output keeps advancing**, even when an individual resource takes a long time. Some Azure resources legitimately provision slowly — e.g. a **Point-to-Site (P2S) VPN Gateway, VPN/ExpressRoute gateway, AVD host pool, or AMPLS can take 30–45+ minutes** — but during that time `terraform apply` still prints a `Still creating... [Xm Ys elapsed]` heartbeat for the in-flight resource roughly **every 10 seconds to a minute**. That steady heartbeat means the run is **healthy, not hung**, regardless of total elapsed time.

Classify the operation on each two-minute check:

- **Healthy** — new output has appeared since the last check, or the `Still creating...` elapsed counter for the in-flight resource(s) is still incrementing. Report progress and keep waiting. **Never cancel a healthy run just because a single resource has been provisioning for >30 min** — that is expected for gateways and similar resources.
- **Possibly stalled** — no new output for **two consecutive checks (~4 minutes)** and no advancing `Still creating...` heartbeat. Note this in the report, keep waiting one more interval, and look more closely (the process may simply be between heartbeats).
- **Likely hung** — **no new output and no advancing heartbeat for ~10 minutes** (roughly five consecutive two-minute checks), or the underlying shell/process is no longer running while the command has not returned an exit status. Stop reporting "in progress", surface it to the user as a suspected hang with the elapsed time and last captured output, and ask how to proceed. Do **not** silently kill the process or self-diagnose — follow the error-handling policy below if the user decides to abort.

When in doubt, prefer waiting over cancelling: the cost of a needlessly cancelled 40-minute apply is high, and a still-advancing heartbeat always means the run is fine.

### Error-handling policy (applies to all apply/deploy work — autopilot included)

When deploying or modifying a sandbox environment, **do not attempt to automatically diagnose or fix any error you encounter — even in autopilot mode.** This applies to failures from `terraform init`, `terraform validate`, `terraform plan`, `terraform apply`, the vnext-testing prep steps, `enable-public-access.sh`, unit/integration tests, and any other step in these workflows.

On the first error, stop the workflow immediately and instead:

1. **Document the error.** Capture the exact failing command, the full error output, the step/scenario it occurred in, the enabled modules, and any other relevant context (branch, Terraform/provider versions). Do not retry, re-run, or alter configuration in an attempt to work around it.
2. **Open a GitHub issue** against the repo describing the failure, using the documented details above:
   ```bash
   gh issue create --title "<concise error summary>" --body "<command, full error output, step, context>"
   ```
3. **Report back to the user** with a brief summary of the error and a link to the issue you opened.

Do not resume the workflow until the user explicitly instructs you to. Never silently swallow, retry past, or self-patch a failure.

### Scenario 1 — Fresh sandbox from scratch

When deploying a new sandbox environment while the working branch is `vnext` in the IDE, **assume this is vnext testing** and complete the following vnext-testing prep steps **attended (autopilot still off), after preflight passes but before the autopilot handoff and `terraform init`** — these steps contain their own `ask_user` prompts (sudo password, PR decisions):

1. **Update the WSL/Linux execution environment.** This needs a real sudo password (`apt` is **not** covered by the vwan NOPASSWD drop-in in preflight item 4). Prompt for the sudo password via `ask_user` (do not persist it), then run both commands under `sudo -S` in the same invocation:
   ```bash
   printf '%s\n' "$SUDO_PASSWORD" | sudo -S apt update && printf '%s\n' "$SUDO_PASSWORD" | sudo -S apt upgrade -y
   ```
2. **Check the Terraform CLI version against `terraform.tf`.** Compare `terraform --version` against the `required_version` in the root `terraform.tf`. If they differ, open a pull request against `vnext` that updates `required_version` in:
   - the root `terraform.tf`, and
   - every module's `terraform.tf` under `./modules/**` and `./extras/modules/**`.

   Use `gh pr create --base vnext` for the PR. Do not proceed with the apply until the version mismatch is resolved (either by merging the PR or by switching the local Terraform CLI to match the pinned version).
3. **Update the PowerShell 7.x Az module to the latest version** so unit tests run against current cmdlets. First compare the installed version against the latest published version, and **skip the update if already on the latest**:
   ```bash
   pwsh -Command '$installed = (Get-InstalledModule -Name Az -ErrorAction SilentlyContinue).Version; $latest = (Find-Module -Name Az).Version; if ($installed -ge $latest) { "Az $installed is already the latest ($latest) — skipping update." } else { "Updating Az from $installed to $latest..."; Update-Module -Name Az -Force -Scope CurrentUser -AcceptLicense }'
   ```
   Confirm with `pwsh -Command 'Get-InstalledModule -Name Az | Select-Object Version'`.

After the vnext-testing prep steps complete (or for non-vnext branches, immediately after preflight), perform the autopilot handoff — prompt the user to run `/allow-all` and wait for confirmation — then run `terraform init && terraform plan && terraform apply`.

After a successful apply, act on the unit-testing decision captured in preflight item 7. If it was **yes**, run unit tests for all installed modules (per the scope confirmed in preflight) without re-prompting; if it was **no**, skip this step:

```bash
pwsh -File ./scripts/Invoke-UnitTests.ps1
```

### Scenario 2 — Modifying an existing sandbox (enable / disable modules in `terraform.tfvars`)

The barrier pattern leaves Key Vault and Storage Account with public access **disabled** after a successful apply, which breaks subsequent plans. Before `terraform plan` / `apply`, you **must** re-enable public access:

```bash
./scripts/enable-public-access.sh
```

Then perform the autopilot handoff — prompt the user to run `/allow-all` and wait for confirmation — then proceed with `terraform init` (if providers changed) → `terraform plan` → `terraform apply`. The barrier resources will re-disable public access at the end of the apply.

After a successful apply, act on the unit-testing decision captured in preflight item 7. If it was **yes** and a module was **newly enabled**, run that module's unit tests + integration tests (per the scope confirmed in preflight) without re-prompting; if it was **no**, skip this step:

```bash
pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module <module_name> -Integration
```

### Tests (Pester-free, PowerShell-orchestrated)

Preflight items 3 (Azure PowerShell auth) and 4 (sudo NOPASSWD drop-in for vwan tests) must be satisfied before invoking any of these.

```bash
# All modules:
pwsh -File ./scripts/Invoke-UnitTests.ps1

# Single module unit tests:
pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vnet_app

# Module unit + its integration tests:
pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vm_mssql_win -Integration
```

Valid `-Module` values: `vnet_shared`, `vnet_app`, `vm_jumpbox_linux`, `vm_mssql_win`, `mssql`, `mysql`, `vwan`, `vnet_onprem`, `avd`, `petstore` (note: `ai_foundry` is **not** currently supported by `Invoke-UnitTests.ps1`). Tests require an applied sandbox in the current Terraform state. Exit code is `0`/`1` for CI use.

**WSL automation note — `vwan` now runs unattended via a sudoers drop-in.** The vwan integration tests invoke privileged commands (`openvpn`, `cat`, `tail`, `kill`, `pkill`) at runtime. These are granted promptlessly by the persistent command-scoped sudoers drop-in at `/etc/sudoers.d/azuresandbox-vwan` (preflight item 4), so `Invoke-UnitTests.ps1` runs fully autonomously in WSL **with `vwan` enabled** — no cached sudo timestamp and no mid-run password prompt. The test scripts probe sudo readiness with `sudo -n cat /dev/null` (an allowed command), not `sudo -n true`. If that drop-in is missing on a given execution environment, the vwan tests will instead prompt for a password the agent cannot answer — recreate the drop-in per preflight item 4, or skip the vwan test phase and ask the user to run `Invoke-UnitTests.ps1` interactively. Note: the openvpn launch in `Test-Integration-VwanConnectivity.ps1` runs `bash -c "sudo openvpn …"` (elevating only `openvpn`) rather than `sudo bash -c …`, which is what keeps the NOPASSWD allowlist scoped to specific binaries instead of all of `bash`.

`Invoke-UnitTests.ps1` is the orchestrator — it discovers what's deployed via `terraform output`, then per-module dispatches to `scripts/Test-Integration-*.ps1` (one script per integration scenario): `Test-Integration-SqlConnectivity.ps1`, `Test-Integration-AzSqlConnectivity.ps1`, `Test-Integration-AzMySqlConnectivity.ps1`, `Test-Integration-SshConnectivity.ps1`, `Test-Integration-VwanConnectivity.ps1`, `Test-Integration-CloudToOnpremDns.ps1`, `Test-Integration-OnpremToCloudDns.ps1`, `Test-Integration-Petstore.ps1`, `Test-Integration-AvdPersonal.ps1`, `Test-Integration-AvdRemoteapp.ps1`. Do not invoke these directly — go through the orchestrator so the right parameters (resource names, FQDNs) are populated from Terraform outputs.

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

## Standalone configurations under `extras/configurations/`

`extras/configurations/rg-devops-iac/` is a **standalone** Terraform configuration (not a module of the root sandbox) that provisions a minimal Linux Terraform execution environment — VNet + NAT, storage account for remote state, Key Vault, and a reusable `vm-jumpbox-linux` child module configured with managed-identity-based azurerm provider auth. Use it as a starting point for DevOps/IaC pipelines, not as part of a sandbox apply. See `extras/configurations/rg-devops-iac/README.md` for its own preflight, apply, and teardown steps — it has independent state and lifecycle.

## MCP servers configured for this workspace

These MCP servers are wired up for Copilot sessions in this repo; prefer them over web search / memory for the topics they cover:

- **Microsoft Learn** (`microsoft_docs_search`, `microsoft_docs_fetch`, `microsoft_code_sample_search`) — first stop for Azure service docs, ARM/AzAPI resource reference, and Microsoft SDK code samples. Use before falling back to general web search for any Azure/Microsoft topic.
- **Azure Terraform** (`azure-terraform-*`, `azure-azureterraform`, `azure-azureterraformbestpractices`, `azure-bicepschema`) — `azurerm` / `azapi` / AVM provider documentation, resource schemas, Azure Terraform best-practice guidance, `aztfexport` command generation, and `conftest` policy validation. Use these to look up resource arguments/attributes before guessing or grepping provider source.
- **GitHub** (`gh` CLI, plus `github-mcp-server-*` tools) — PR/issue/workflow/repo operations. Prefer the `gh` CLI for routine operations (per the gh-cli preference); the MCP tools are useful for cross-repo code search (`github-mcp-server-search_code`) and Copilot Spaces lookup.
