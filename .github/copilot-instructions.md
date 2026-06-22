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

## Preflight checklist (run attended, before enabling `/allow-all` mode for any apply or test work)

This project runs in `/allow-all` mode (the CLI's auto-approve mode, where tool calls are executed without per-action confirmation) for long operations (`terraform apply` is 25–95 min; unit tests can be 10+ min). The preflight checklist itself, however, **must be completed with a human present — i.e. NOT in `/allow-all` mode** — because every item may require an `ask_user` prompt (secrets, auth confirmations, module selection), and `ask_user` cannot be answered during unattended execution. To avoid failing mid-run because of a missing secret or expired auth, **collect every human-gated input up front** in a single attended preflight phase. Once preflight passes, the rest of the run should not require user intervention.

The intended workflow is a clean two-phase handoff:

1. **Attended preflight** — `/allow-all` mode **off**. Work through every preflight item below, batching all `ask_user` prompts back-to-back while the user is present.
2. **Unattended execution** — once (and only once) every preflight item is satisfied, **prompt the user to enable `/allow-all` mode by running `/allow-all`** so the long-running apply and tests can complete fully automated without further intervention. Do not begin `terraform apply`, `terraform plan`, or `Invoke-UnitTests.ps1` until the user has confirmed they have enabled `/allow-all` mode.

**Hard rules — never violate:**

- **Do not run the preflight checklist in `/allow-all` mode.** Preflight requires human input via `ask_user`; complete it attended, then hand off to `/allow-all` mode only after every item passes.
- **Do not start `terraform apply`, `terraform plan`, or `Invoke-UnitTests.ps1` until every preflight item below is satisfied AND the user has switched to `/allow-all` mode (`/allow-all`).** A failed apply 40 minutes in because a secret was missing is the worst outcome — fail fast at preflight instead.
- Never run concurrent `terraform apply` operations against the same sandbox environment (state file). One apply at a time, full stop.
- Never inspect Terraform state (`terraform state ...`, `terraform output`, `terraform show`, `terraform plan`, etc.) while a `terraform apply` is in flight — it will read/lock the same state file and cause errors or corruption.
- Batch all `ask_user` prompts back-to-back at the start of the session. Do not interleave human prompts with long-running tool calls.

**Preflight items — check each one and resolve before proceeding:**

1. **Service principal secret (`TF_VAR_arm_client_secret`)** — check with `echo "${TF_VAR_arm_client_secret:+set}"`. If empty, use `ask_user` to prompt for the SPN password, then export it in the shell session before any Terraform command. Required for every `terraform plan` / `apply`.
2. **Azure CLI auth (`az login`)** — verify with `az account show`. If it fails, use `ask_user` to instruct the user to run `az login` in their own terminal, and wait for confirmation before proceeding. Required for `terraform apply` and for `enable-public-access.sh`.
3. **Azure PowerShell auth (`Connect-AzAccount`)** — verify with `pwsh -Command 'Get-AzContext'`. If empty, use `ask_user` to instruct the user to run `pwsh -Command 'Connect-AzAccount -UseDeviceAuthentication'` (credentials persist to `~/.Azure`). Required only when `Invoke-UnitTests.ps1` will be run — i.e. when the unit-testing decision in preflight item 7 is **yes**.
4. **`terraform.tfvars` exists** in the repo root. If missing, run `./scripts/bootstrap.sh` (Linux Terraform execution environment) or `./scripts/bootstrap.ps1` (Windows). The two scripts are equivalent — pick the one matching the host OS. **How `bootstrap.sh` works (so you don't have to re-read it each run):**
   - **It is interactive** — it issues a series of `read -e` prompts and therefore must be run **attended (`/allow-all` mode off)**, batched with the other preflight prompts. It cannot complete unattended. Because all prompts except one are pre-filled with sane defaults, the only value you must actively collect from the user is `arm_client_id` (the service principal appId) — surface it via `ask_user`.
   - **Preconditions it enforces** (it exits with usage if any fail): `az` CLI installed, `python3` installed, the `PyJWT` python library importable (`python3 -c "import jwt"`), `TF_VAR_arm_client_secret` exported, and an active `az login` (it reads the default subscription from `az account list`). These overlap with preflight items 1–2, so satisfy those first.
   - **Prompts and their defaults** (default derived from the signed-in `az` context unless noted): `arm_client_id` (**no default — required input**), `aad_tenant_id` (current tenant), `user_name` (signed-in UPN), `user_object_id` (decoded from the access-token JWT `oid` claim via PyJWT), `subscription_id` (default subscription), `location` (`eastus2`), `environment` (`dev`), `costcenter` (`mycostcenter`), `project` (`sand`). It validates the SPN, subscription, and location against Azure before writing.
   - **Known gotcha — empty `user_name`:** the script derives the `user_name` default from `az ad user show --id <user_object_id> --query userPrincipalName` (where `user_object_id` is the JWT `oid` claim). When the signed-in identity lacks Microsoft Entra directory read permission (common for guest accounts and many service-principal-style admin logins), that lookup returns **empty**, so the prompt has no default and a non-interactive run (piping an empty line) writes `user_name = ""` to `terraform.tfvars`. This **fails the `user_name` UPN-format validation in `variables.tf`** at `terraform plan`/`apply`. After running `bootstrap.sh`, **always verify `user_name` is a non-empty valid UPN** (`grep '^user_name' terraform.tfvars`); if it is blank, set it explicitly — get the UPN from `az ad signed-in-user show --query userPrincipalName -o tsv` (or `az account show --query user.name -o tsv` as a fallback) and edit `terraform.tfvars`. When driving the script non-interactively, prefer supplying the UPN explicitly for the `user_name` prompt rather than relying on the (possibly empty) default.
   - **Output** — it (over)writes `./terraform.tfvars` in the repo root containing `aad_tenant_id`, `arm_client_id`, `location`, `subscription_id`, `user_name`, `user_object_id`, a `tags` map (`project`/`costcenter`/`environment`), and **all `enable_module_*` toggles commented out (every module disabled by default)**. Module enablement is therefore handled separately in preflight item 6 by editing `terraform.tfvars` afterward — `bootstrap.sh` never enables a module. Note it does **not** prompt for or write the SPN secret (that stays in `TF_VAR_arm_client_secret`).
   - **To drive it non-interactively** (e.g. when you already have every value), pipe the answers to stdin in prompt order — `arm_client_id`, `aad_tenant_id`, `user_name`, `user_object_id`, `subscription_id`, `location`, `environment`, `costcenter`, `project` — e.g. `printf '%s\n' "$appid" "" "" "" "" "" "" "" "" | ./scripts/bootstrap.sh` (empty lines accept the defaults). Prefer the attended interactive flow unless the user has supplied all inputs.
6. **Module enablement confirmed** — use `ask_user` to ask whether **all base modules** in `./modules` should be deployed (every `enable_module_*` flag `true`). Extra modules in `./extras/modules` (`ai-foundry`, `avd`, `petstore`, `vnet-onprem`, etc.) are **always excluded** from this question and left **disabled**. If the answer is **no**, use `ask_user` again to have the user specify exactly which base modules to enable (e.g. `vnet_app` only); all other base modules stay disabled. Confirm the selection before editing `terraform.tfvars`.
7. **Automated unit testing decision** — use `ask_user` to ask whether automated unit tests (`Invoke-UnitTests.ps1`) should be run after a successful `terraform apply`. Capture this decision now, batched with the other preflight prompts, because it determines whether preflight item 3 (Azure PowerShell auth) is required — that human-gated input must be collected up front, not after the `/allow-all`-mode handoff. If the answer is **yes**, also confirm scope: all installed modules (`Invoke-UnitTests.ps1`, which runs each installed module's unit **and** integration tests automatically) versus a single module's unit tests, optionally with its integration tests (`-Module <name> [-Integration]` — `-Integration` applies only to a single-module run). If the answer is **no**, record it and skip item 3 (unless otherwise needed). The recorded decision drives the post-apply test step in Scenarios 1 and 2 — do not re-prompt for it after the apply.

After all preflight items pass, the remaining attended setup depends on the scenario: for a fresh vnext sandbox there are additional human-gated prep steps (see Scenario 1) that must also be completed attended. Once **all** attended setup (preflight plus any scenario-specific prep) is done and nothing further requires `ask_user`, **use `ask_user` to prompt the user to enable `/allow-all` mode by running `/allow-all`**, and wait for their confirmation before proceeding. This is the handoff from the attended phase to fully automated execution. Once `/allow-all` mode is enabled, normal Terraform rules apply: `terraform init` before `terraform apply`; run `terraform validate` and `terraform plan` first.

## Applying Terraform configurations

### Progress reporting for long-running operations (apply, tests — `/allow-all` mode included)

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

### Error-handling policy (applies to all apply/deploy work — `/allow-all` mode included)

When deploying or modifying a sandbox environment, **do not attempt to automatically diagnose or fix any error you encounter — even in `/allow-all` mode.** This applies to failures from `terraform init`, `terraform validate`, `terraform plan`, `terraform apply`, the vnext-testing prep steps, `enable-public-access.sh`, unit/integration tests, and any other step in these workflows.

On the first error, stop the workflow immediately and instead:

1. **Document the error.** Capture the exact failing command, the full error output, the step/scenario it occurred in, the enabled modules, and any other relevant context (branch, Terraform/provider versions). Do not retry, re-run, or alter configuration in an attempt to work around it.
2. **Open a GitHub issue** against the repo describing the failure, using the documented details above:
   ```bash
   gh issue create --title "<concise error summary>" --body "<command, full error output, step, context>"
   ```
3. **Report back to the user** with a brief summary of the error and a link to the issue you opened.

Do not resume the workflow until the user explicitly instructs you to. Never silently swallow, retry past, or self-patch a failure.

### Scenario 1 — Fresh sandbox from scratch

When deploying a new sandbox environment while the working branch is `vnext` in the IDE, **assume this is vnext testing** and complete the following vnext-testing prep steps **attended (`/allow-all` mode still off), after preflight passes but before the `/allow-all`-mode handoff and `terraform init`** — these steps contain their own `ask_user` prompts (PR decisions):

After the vnext-testing prep steps complete (or for non-vnext branches, immediately after preflight), perform the `/allow-all`-mode handoff — prompt the user to run `/allow-all` and wait for confirmation — then run `terraform init && terraform plan && terraform apply`.

After a successful apply, act on the unit-testing decision captured in preflight item 7. If it was **yes**, run unit tests for all installed modules (per the scope confirmed in preflight) without re-prompting; if it was **no**, skip this step. **First satisfy the VM-start gate** (`./scripts/manage-vms.sh start`; see the Tests section) — a policy may have deallocated VMs since the apply:

```bash
./scripts/manage-vms.sh start
pwsh -File ./scripts/Invoke-UnitTests.ps1
```

### Scenario 2 — Modifying an existing sandbox (enable / disable modules in `terraform.tfvars`)

The barrier pattern leaves Key Vault and Storage Account with public access **disabled** after a successful apply, which breaks subsequent plans. Before `terraform plan` / `apply`, you **must** re-enable public access:

```bash
./scripts/enable-public-access.sh
```

Then perform the `/allow-all`-mode handoff — prompt the user to run `/allow-all` and wait for confirmation — then proceed with `terraform init` (if providers changed) → `terraform plan` → `terraform apply`. The barrier resources will re-disable public access at the end of the apply.

After a successful apply, act on the unit-testing decision captured in preflight item 7. If it was **yes** and a module was **newly enabled**, run that module's unit tests + integration tests (per the scope confirmed in preflight) without re-prompting; if it was **no**, skip this step. **First satisfy the VM-start gate** (`./scripts/manage-vms.sh start`; see the Tests section) — a policy may have deallocated VMs since the apply:

```bash
./scripts/manage-vms.sh start
pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module <module_name> -Integration
```

### Scenario 3 — Reproducing a reported test failure for a VM-containing module (re-provision repro)

**Applicability gate — VM modules only.** Use this repro **only** when the issue under investigation is a unit/integration **test failure for a module that provisions one or more VMs** (e.g. `vm_jumpbox_linux`, `vm_mssql_win`, `avd`, `vnet_onprem`, or the `adds1`/`jumpwin1` VMs in `vnet_shared`). The pattern works by tearing down and re-creating the module's VM(s) so cloud-init / run-command VM-side configuration re-runs against the current environment. **Do not use it for modules with no VM** (e.g. `mssql`, `mysql` flexible servers, `vnet_app` on its own) — there is no VM-side config to re-trigger, so the re-provision proves nothing; investigate those differently. If unsure whether the target module provisions a VM, confirm before using this scenario.

**Why this works (root-cause class it targets).** Many VM-module test failures are environmental rather than code defects — most commonly a **dependency VM (especially the domain controller `adds1`) was stopped/deallocated** (e.g. by a cost-optimization auto-shutdown policy) when the original tests ran, breaking AD DNS resolution, Kerberos TGT acquisition, domain join, CIFS mounts, SQL auth, etc. Re-provisioning the failing module's VM **with every VM confirmed running** isolates that class: if the tests now **pass**, the failure was environmental (transient) → **close the issue**; if they still **fail**, it is a genuine, reproducible defect → **update the issue** with the evidence and leave it open.

This is a specialization of Scenario 2 (it disables then re-enables a single module), so all Scenario 2 rules apply — most importantly running `./scripts/enable-public-access.sh` before **each** `terraform plan`/`apply`, and the `/allow-all`-mode handoff. It requires an already-applied sandbox in the current Terraform state.

**Steps (this is exactly the repro plan validated against issue #447):**

1. **Start all VMs** so no dependency (DC, SQL host, etc.) is deallocated during re-provision and testing:
   ```bash
   ./scripts/manage-vms.sh start
   ```
   The script starts `adds1` (domain controller) **first** and waits for it; verify with `az vm list -g <rg> -d --query "[].{Name:name, PowerState:powerState}" -o table` that the relevant VMs report `VM running` before continuing. The DC being up is the whole point — do not skip this.
2. **Disable** the target module's `enable_module_<name>` flag in `terraform.tfvars`.
3. `./scripts/enable-public-access.sh` (re-enable KV/Storage public access before the plan).
4. `terraform apply` to **de-provision** the module's VM(s) (run `terraform init` first if needed; `terraform validate` + `terraform plan -out=<name>.tfplan` then apply the saved plan).
5. **Re-enable** the same `enable_module_<name>` flag in `terraform.tfvars`.
6. `./scripts/enable-public-access.sh` again (the prior apply's barrier re-disabled public access).
7. `terraform apply` to **re-provision** the module's VM(s); cloud-init / run-command VM-side config re-runs.
8. Run the module's unit **and** integration tests:
   ```bash
   pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module <module_name> -Integration
   ```

**Interpreting the result and acting on the issue:**

- `RESULT: PASS` → **no repro**. Post a comment to the issue documenting the full steps, the passing summary (per-check `[PASS]` lines + overall `Passed=N Failed=0`), and the conclusion that the original failure was environmental (e.g. deallocated DC). **Close the issue** (`gh issue close <n> --reason "not planned"`).
- `RESULT: FAIL` → **repro confirmed**. Post a comment with the failing `[FAIL]` lines and context, and **leave the issue open** for a fix. A reproduced test FAIL is the expected *outcome* of this scenario and is **not** itself a workflow error — do **not** open a second issue or invoke the error-handling policy for it. (The error-handling policy still applies to *infrastructure/command* failures — a `terraform apply` error, a script crash, etc. — which are distinct from a test reporting FAIL.)

**Cleanup.** Always restore `terraform.tfvars` to its original module configuration (the target flag back to its starting value, normally `true`) and delete any temporary plan/log files created during the repro.

### Tests (Pester-free, PowerShell-orchestrated)

Preflight item 3 (Azure PowerShell auth) must be satisfied before invoking any of these.

**VM-start gate (mandatory — always run immediately before any unit/integration test invocation).** In some subscriptions an Azure policy can **arbitrarily stop/deallocate VMs** (e.g. cost-optimization auto-shutdown), which makes VM-side tests fail spuriously — a deallocated domain controller (`adds1`) breaks AD DNS, Kerberos, domain join, CIFS, and SQL auth (this is the root cause confirmed in issue #447). Therefore, **before every `Invoke-UnitTests.ps1` run — in Scenario 1, Scenario 2, the Scenario 3 repro, and any ad-hoc test run — first start all VMs and confirm they are running:**

```bash
./scripts/manage-vms.sh start
az vm list -g <rg> -d --query "[].{Name:name, PowerState:powerState}" -o table   # confirm all 'VM running'
```

`manage-vms.sh start` starts `adds1` (domain controller) **first** and waits for it, then starts the rest. Do not begin testing until the relevant VMs report `VM running`. This gate is non-negotiable because the policy can deallocate VMs at any time, including after a successful `terraform apply` but before tests run.

**For everything else about running tests — invocation syntax, the `-Module`/`-Integration` scope rules, valid module names, prerequisites, and how the orchestrator dispatches integration tests — read the header comments at the top of `scripts/Invoke-UnitTests.ps1`** (they are the source of truth; do not duplicate them here). The two rules that most often trip up automation:

- Running **all** modules (no `-Module`) auto-discovers what's deployed and runs each module's unit **and** integration tests automatically. `-Integration` does **not** apply to an all-modules run and is ignored when `-Module` is omitted.
- `-Integration` is meaningful **only** with `-Module` (a single-module run), e.g. `pwsh -File ./scripts/Invoke-UnitTests.ps1 -Module vm_mssql_win -Integration`.

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
- **Merge strategy:** squash-merge topic/contributor PRs → `vnext`; use a **regular merge commit (no squash)** for the `vnext` → `main` release PR so individual commits and branch lineage are preserved on `main`. See CONTRIBUTING.md "Merge strategy".

## Standalone configurations under `extras/configurations/`

`extras/configurations/rg-devops-iac/` is a **standalone** Terraform configuration (not a module of the root sandbox) that provisions a minimal Linux Terraform execution environment — VNet + NAT, storage account for remote state, Key Vault, and a reusable `vm-jumpbox-linux` child module configured with managed-identity-based azurerm provider auth. Use it as a starting point for DevOps/IaC pipelines, not as part of a sandbox apply. See `extras/configurations/rg-devops-iac/README.md` for its own preflight, apply, and teardown steps — it has independent state and lifecycle.

## MCP servers configured for this workspace

These MCP servers are wired up for Copilot sessions in this repo; prefer them over web search / memory for the topics they cover:

- **Microsoft Learn** (`microsoft_docs_search`, `microsoft_docs_fetch`, `microsoft_code_sample_search`) — first stop for Azure service docs, ARM/AzAPI resource reference, and Microsoft SDK code samples. Use before falling back to general web search for any Azure/Microsoft topic.
- **Azure Terraform** (`azure-terraform-*`, `azure-azureterraform`, `azure-azureterraformbestpractices`, `azure-bicepschema`) — `azurerm` / `azapi` / AVM provider documentation, resource schemas, Azure Terraform best-practice guidance, `aztfexport` command generation, and `conftest` policy validation. Use these to look up resource arguments/attributes before guessing or grepping provider source.
- **GitHub** (`gh` CLI, plus `github-mcp-server-*` tools) — PR/issue/workflow/repo operations. Prefer the `gh` CLI for routine operations (per the gh-cli preference); the MCP tools are useful for cross-repo code search (`github-mcp-server-search_code`) and Copilot Spaces lookup.
