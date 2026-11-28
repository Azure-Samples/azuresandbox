# GitHub Runner Module (github-runner)

## Contents

* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Overview

This optional module makes `jumplinux2` a [GitHub Actions self-hosted runner](https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners) for the [Azure Sandbox](https://github.com/Azure-Samples/azuresandbox) repository. `rg-devops-iac` creates it when `enable_github_runner` is true. Without it, `rg-devops-iac` is a basic Terraform execution environment.

The module creates, depending on its inputs:

* The [GitHub Actions runner](https://github.com/actions/runner) agent on `jumplinux2`, installed and registered by a managed Run Command. See [Runner Installation](#runner-installation).
* GitHub Actions federated identity credentials on the rg-devops-iac [deployment identity](../../README.md#optional-deployment-identity), when `deployment_identity` is `oidc`. See [OIDC Federated Identity Credentials](#oidc-federated-identity-credentials).
* A separate runner power state identity, when `deployment_identity` is `oidc`. See [Runner Power State Identity](#runner-power-state-identity).

The runner exists to run the Azure Sandbox [Sandbox deployment workflow](../../../../../.github/workflows/sandbox-deployment.yml), which supports the **release gate** and **on-demand deployment** use cases. The workflow's design, prerequisites, configuration, setup and runs are documented in [Sandbox deployment workflow](../../../../../CONTRIBUTING.md#sandbox-deployment-workflow) in CONTRIBUTING.md.

## Smoke Testing

Navigate to the target repository on GitHub > *Settings* > *Actions* > *Runners* and verify that a runner named *jumplinux2* is listed with an *Idle* status and the expected labels.

## Documentation

This section provides additional information on various aspects of this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Outputs](#outputs)
* [Runner Installation](#runner-installation)
* [Self-Hosted Runner Registration](#self-hosted-runner-registration)
* [Elevated Permissions for Integration Tests](#elevated-permissions-for-integration-tests)
* [Terraform Version on the Runner](#terraform-version-on-the-runner)
* [Terraform State](#terraform-state)
* [OIDC Federated Identity Credentials](#oidc-federated-identity-credentials)
* [Runner Power State Identity](#runner-power-state-identity)

### Dependencies

This module depends upon resources provisioned by `rg-devops-iac`:

* The resource group.
* The `jumplinux2` VM, from the [vm-jumpbox-linux](../vm-jumpbox-linux/README.md) module. It hosts the runner Run Command and scopes the runner power state identity's role assignment.
* The [deployment identity](../../README.md#optional-deployment-identity), when `deployment_identity` is `oidc`. This module adds its federated identity credentials.

`rg-devops-iac` passes the VM id from the `vm-jumpbox-linux` module's `virtual_machine_extensions_complete` output, which is available only after the VM's extensions are installed, so installing the runner doesn't contend with them for the apt locks.

The runner Run Command also uses the repository's VPN tunnel scripts. See [Elevated Permissions for Integration Tests](#elevated-permissions-for-integration-tests).

### Module Structure

This module is organized as follows:

```plaintext
├── scripts/                              # Runner, administrator and workflow scripts
│   ├── configure-github-runner.sh        # Runner: installs and registers the runner
│   ├── Connect-SandboxRunner.ps1         # Workflow: runs unit tests as the deployment identity
│   ├── Invoke-RunnerPowerState.sh        # Workflow: starts and stops jumplinux2
│   ├── Invoke-SandboxDeployment.ps1      # Workflow: runs the deployment stages
│   ├── Invoke-SandboxDeployment.sh       # Workflow: Bash entry point for the .ps1
│   ├── new-runner-registration-token.sh  # Administrator: devops administrator gets a registration token (sourced)
│   ├── SandboxOidc.ps1                   # Workflow: OIDC sign-in helpers
│   ├── SandboxProgress.ps1               # Workflow: progress parsing helpers
│   ├── SandboxRedaction.ps1              # Workflow: redacts ids and tags from job output
│   └── SandboxTerraformError.ps1         # Workflow: extracts Terraform errors for job output
├── compute.tf                            # Runner Run Command
├── locals.tf                             # OIDC subjects
├── main.tf                               # Federated credentials, power state identity and checks
├── outputs.tf                            # Output values
├── terraform.tf                          # Terraform configuration block
└── variables.tf                          # Input variables
```

Source the administrator script from the rg-devops-iac directory. It reads `terraform.tfvars` from there. The workflow scripts are run by the [Sandbox deployment workflow](../../../../../CONTRIBUTING.md#sandbox-deployment-workflow), not by hand.

### Input Variables

This section lists the input variables used in this module. All of them except `github_runner_version` are set by the root module, which documents them in [Optional: GitHub Self-Hosted Runner Configuration](../../README.md#optional-github-self-hosted-runner-configuration).

Variable | Default | Description
--- | --- | ---
deployment_identity | | `none`, `managed_identity` or `oidc`. The federated identity credentials and runner power state identity are created only for `oidc`.
deployment_identity_github_environments | | The GitHub Actions environments whose jobs can sign in as the deployment identity. Only used when `deployment_identity` is `"oidc"`.
deployment_identity_id | `null` | The resource id of the rg-devops-iac [deployment identity](../../README.md#optional-deployment-identity), or `null` when `deployment_identity` is "none".
github_repository_id | | The numeric id of the GitHub repository. Only used when `deployment_identity` is `"oidc"`. When empty, it is looked up from the repository in `github_runner_url`.
github_repository_owner_id | | The numeric id of the repository's owner. Only used when `deployment_identity` is `"oidc"`. When empty, it is looked up from the repository in `github_runner_url`.
github_runner_labels | | Additional labels to apply to the runner.
github_runner_power_state_environment | | The GitHub Actions environment whose jobs can sign in as the runner power state identity. Only used when `deployment_identity` is `"oidc"`.
github_runner_token | `""` | Ephemeral. The runner registration token. Passed to the Run Command through a write-only protected parameter, so it never lands in Terraform state or the saved plan. Required only when the runner is registered (when the Run Command is created or `github_runner_token_version` changes).
github_runner_token_version | 1 | Increment to send a new `github_runner_token` to the VM and re-run runner registration, for example after a failed registration.
github_runner_url | `""` | The GitHub repository URL to register the runner with, e.g. `https://github.com/myorg/myrepo`. Required.
github_runner_version | `2.338.2` | The version of the GitHub Actions runner agent to install, without the leading `v`.
location | | The Azure region where the resources will be created.
resource_group_name | | The name of the resource group.
tags | | The tags from the root module.
virtual_machine_id | | The id of `jumplinux2`, from the `vm-jumpbox-linux` module's `virtual_machine_extensions_complete` output.
virtual_machine_name | | The name of `jumplinux2`. The runner is registered with this name.

### Module Resources

Address | Name | Notes
--- | --- | ---
module.github_runner[0].azapi_resource.github_runner | | Managed Run Command on `jumplinux2` that installs and registers the GitHub Actions runner after the VM's extensions. The runner registration token is a write-only protected parameter. See [Runner Installation](#runner-installation).
module.github_runner[0].azurerm_federated_identity_credential.deployment_identity_github[*] | github-sandbox-deployment, github-sandbox-release-gate | Trusts GitHub Actions OIDC tokens for the deployment identity, one per environment in `deployment_identity_github_environments`. Created only when `deployment_identity` is `"oidc"`.
module.github_runner[0].azurerm_federated_identity_credential.runner_power_state_github[0] | github-sandbox-runner-power-state | Trusts GitHub Actions OIDC tokens for the runner power state identity from the `github_runner_power_state_environment` environment. Created only when `deployment_identity` is `"oidc"`.
module.github_runner[0].azurerm_role_assignment.runner_power_state[0] | | Assigns `Desktop Virtualization Power On Off Contributor` on `jumplinux2` to the runner power state identity. Created only when `deployment_identity` is `"oidc"`.
module.github_runner[0].azurerm_user_assigned_identity.runner_power_state[0] | id-devops-dev-runner | Runner power state identity that starts and deallocates `jumplinux2` for workflow runs. Unattached and federated with GitHub Actions. Created only when `deployment_identity` is `"oidc"`.

### Outputs

The root module includes `github_subjects` in its `deployment_identity` output, returns `github_runner` unchanged, and merges `resource_ids` and `resource_names` into its own.

Name | Description
--- | ---
github_runner | The runner. An object with `name`, `power_state_identity_client_id` and `power_state_identity_github_subject`.
github_subjects | The GitHub OIDC subjects accepted by the deployment identity's federated identity credentials, keyed by environment. An empty map unless `deployment_identity` is `oidc`.
resource_ids | A map with `runner_power_state_identity` when `deployment_identity` is `oidc`.
resource_names | A map with `runner_power_state_identity` when `deployment_identity` is `oidc`.

### Runner Installation

When `enable_github_runner` is true, the module installs the [GitHub Actions runner](https://github.com/actions/runner) agent so `jumplinux2` can run GitHub Actions jobs for the [Azure Sandbox](https://github.com/Azure-Samples/azuresandbox) repository. See [Self-Hosted Runner Registration](#self-hosted-runner-registration).

* **Installation**
  * A managed Run Command (`ConfigureGitHubRunner`) runs [configure-github-runner.sh](./scripts/configure-github-runner.sh).
  * It runs after cloud-init and the VM extensions finish.
* **Token**
  * `github_runner_token` is an [ephemeral](https://developer.hashicorp.com/terraform/language/values/variables#exclude-values-from-state) input.
  * It is passed as a protected parameter through the write-only `sensitive_body` argument.
  * It is never stored in Terraform state, the saved plan, VM custom data or Key Vault.
  * It is sent only when the Run Command is created or `github_runner_token_version` changes.
  * The token is a runner registration token for the repository in `github_runner_url`.
* **Errors**
  * Registration errors fail `terraform apply` (`treatFailureAsDeploymentFailure`).
  * Script output is in the Run Command instance view.
* **Runner service**
  * Installed to `/opt/actions-runner`.
  * Named using the VM name (*jumplinux2*).
  * Registered with the configured URL and labels.
  * Runs as a systemd service (`actions.runner.*`) that starts on boot.
  * Runs as the non-root service account `githubrunner`.
  * Agent automatically updates itself.
* **Azure access**
  * `terraform`, `az` and `pwsh` (with Az modules) are on the runner `PATH`.
  * `ARM_USE_MSI` and `ARM_TENANT_ID` are set in `/opt/actions-runner/.env`.
  * Workflows authenticate with the VM managed identity. No Azure secrets are stored on the VM.
* **Terraform state**
  * No local state directory is provisioned. Workflows use the remote state backend. See [Terraform State](#terraform-state).

### Self-Hosted Runner Registration

`enable_github_runner = true` installs the runner agent on `jumplinux2` and registers it with `github_runner_url` (default: the Azure Sandbox repository) and `github_runner_labels` (default `["azuresandbox"]`, the label the workflow targets). See [Runner Installation](#runner-installation). It's **disabled by default**.

Right before [Step 5](../../README.md#step-5-validate-and-apply-configuration), in the shell that runs Terraform, create a registration token. The script must be sourced. It uses the [GitHub CLI](https://cli.github.com) signed in as a repository administrator (Admin role), reads `github_runner_url` from `terraform.tfvars`, and sets `TF_VAR_github_runner_token` without displaying it:

```bash
source ./modules/github-runner/scripts/new-runner-registration-token.sh
```

The token expires after one hour and can only register runners. Run `terraform plan` and `terraform apply` in the same shell within the hour. It's an ephemeral variable passed to a Run Command through a write-only argument, so it's never stored in state, the saved plan, custom data or Key Vault.

Because Terraform can't detect changes to an ephemeral value, the token is sent only when the Run Command is created or `github_runner_token_version` changes:

Situation | What to do
--- | ---
Later applies | Leave `github_runner_token_version` unchanged and don't set the token. Ignore the `github_runner_token is empty` plan warning. Changes to the runner's name or labels aren't applied to a registered runner; redeploy rg-devops-iac to apply them.
Plan creates or replaces `module.github_runner[0].azapi_resource.github_runner` (e.g. `jumplinux2` is replaced) | Source the token script before `terraform plan`. Registration replaces any existing runner with the same name.
Registration failed (e.g. the token expired) | Source the token script, increment `github_runner_token_version` and apply. The VM isn't replaced.

The runner service account has command-scoped passwordless `sudo` for the `vwan` point-to-site VPN integration tests ([Elevated Permissions for Integration Tests](#elevated-permissions-for-integration-tests)) and for a wrapper that installs a specific Terraform version ([Terraform Version on the Runner](#terraform-version-on-the-runner)).

### Elevated Permissions for Integration Tests

The runner service account is unprivileged. The `vwan` integration tests in [Test-Integration-VwanConnectivity.ps1](../../../../../scripts/Test-Integration-VwanConnectivity.ps1) establish a point-to-site VPN tunnel, which requires root to create the `tun` device and update the routing table.

The configuration script runs the root repo's [install-vwan-tunnel.sh](../../../../../scripts/install-vwan-tunnel.sh), the same installer developers use on their workstations. Terraform reads the installer and [vwan-tunnel.sh](../../../../../scripts/vwan-tunnel.sh) from the root repo's `scripts/` directory and passes them to the Run Command, so this configuration keeps no copy of either. The installer:

* Installs the wrapper as `/usr/local/libexec/azuresandbox/vwan-tunnel`, owned by `root` with `0755` permissions, in a directory only `root` can write to.
* Writes the sudoers drop-in `/etc/sudoers.d/azuresandbox-vwan`, granting the runner service account passwordless `sudo` for that installed wrapper only. The drop-in is written with `0440` permissions and validated with `visudo -cf` before it takes effect. If validation fails, it's removed and the Run Command fails rather than leaving `sudo` broken.

The wrapper is the only thing the tests run as root. It accepts only an allowlisted OpenVPN configuration, rejects options that run scripts or plugins or point at arbitrary files, and can start, check, read the log of, and stop only its own tunnel.

The installed wrapper is a copy taken at deployment time. The configuration script skips setup on a VM where the runner is already configured, so redeploy the VM to pick up changes to `vwan-tunnel.sh`. If the tests in a workflow run need a newer wrapper than the one installed, they fail and say so.

### Terraform Version on the Runner

Cloud-init installs the latest Terraform from the HashiCorp apt repository, which may not satisfy the `required_version` of the branch a workflow run deploys. Preflight in the [Sandbox deployment workflow](../../../../../CONTRIBUTING.md#workflow-runs) checks compatibility and, only when the runner's Terraform doesn't satisfy the constraint, installs the version static CI uses.

To allow this without broader root access, the configuration script always installs a root-owned wrapper, `/usr/local/sbin/azuresandbox-install-terraform` (`0755`), and a separate sudoers drop-in, `/etc/sudoers.d/azuresandbox-github-runner-terraform`, granting the runner service account passwordless `sudo` for that wrapper only. The drop-in is written with `0440` permissions and validated with `visudo -cf`, with the same fail-closed handling as the `azuresandbox-vwan` drop-in. The wrapper:

* Accepts exactly one argument in `X.Y.Z` form and rejects anything else.
* Refreshes only the HashiCorp apt source, then installs the matching `terraform` package version, downgrading if needed.
* Waits up to 10 minutes for the apt lock, since the VM may have just booted and automatic updates may be running.

**IMPORTANT:** This is a privilege grant, limited to installing a HashiCorp-signed `terraform` package version from the configured repository. It changes the system-wide Terraform, so attended sessions on *jumplinux2* use whichever version the last workflow run installed.

### Terraform State

Workflows on this runner always use the `azurerm` backend in the rg-devops-iac storage account. `jumplinux2`'s system-assigned identity has `Storage Blob Data Contributor` on it, so no secrets are needed. A local state file on a disposable runner is an anti-pattern:

Concern | `azurerm` backend | Local file on the runner
--- | --- | ---
Locking | Blob lease across runs and interactive applies | Only within a single Terraform invocation
Durability | Versioning and soft delete | Lost when the VM is resized, reimaged or replaced
Secrets at rest | Encrypted, Azure RBAC, private endpoint only | Plain file readable by the runner account and any compromised job
Source of truth | Shared by interactive and workflow runs | Diverges

The `vm-jumpbox-linux` module therefore doesn't create a persistent local state directory, and `actions/checkout` cleans the workspace between jobs. Local state is used only for rg-devops-iac's own bootstrap apply, which creates the storage account, from a workstation or another Terraform execution environment. The Sandbox deployment workflow gets its backend from the `SANDBOX_BACKEND_HCL` secret and sets a state key per run; see [Workflow configuration](../../../../../CONTRIBUTING.md#workflow-configuration).

For a terminal apply on `jumplinux2`, use the same backend with a fixed `key`:

```hcl
# backend.tf
terraform {
  backend "azurerm" {
    use_azuread_auth     = true
    use_msi              = true
    tenant_id            = "YOUR-ENTRA-TENANT-ID-HERE"
    subscription_id      = "YOUR-AZURE-SUBSCRIPTION-ID-HERE"
    storage_account_name = "YOUR-STORAGE-ACCOUNT-NAME-HERE"
    container_name       = "tfstate"
    key                  = "YOUR-STATE-FILE-NAME-HERE.tfstate"
  }
}
```

### OIDC Federated Identity Credentials

With `deployment_identity = "oidc"`, this module adds GitHub Actions federated identity credentials to the rg-devops-iac [deployment identity](../../README.md#optional-deployment-identity), one per environment in `deployment_identity_github_environments`, so approved jobs on the runner can sign in as it without a secret. See [Deployment Identity Options](../../README.md#deployment-identity-options).

* With `oidc`, each federated credential has issuer `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange` and a subject such as `repository_owner_id:987654321:repository_id:123456789:environment:sandbox-deployment`. `github_subjects` in the `deployment_identity` output lists them.
* With `oidc`, the unit-test stage signs in once. A GitHub Actions OIDC token expires after 5 minutes, after which the session can't get a token for a new audience. So `Connect-SandboxRunner.ps1` gets the Azure Resource Manager and Key Vault tokens the tests use right after sign-in. If a later token request still fails because the OIDC token has expired, the test signs in again once with a new OIDC token and retries.
* The `oidc` subjects use numeric repository and owner ids, which don't change on a rename. Terraform looks them up anonymously from the GitHub API on each plan, which works only for public repositories. For a private repository, set `github_repository_id` (`gh api repos/OWNER/NAME --jq .id`) and `github_repository_owner_id` (`gh api repos/OWNER/NAME --jq .owner.id`).

#### OIDC Subject Claim Template

With `oidc`, the federated credentials accept only subjects in the `repository_owner_id`, `repository_id` and `context` format. A repository administrator checks the repository's OIDC subject claim template once:

```bash
gh api repos/OWNER/NAME/actions/oidc/customization/sub
```

If it shows `"use_default":false` with the three keys, don't change it. If it shows `"use_default":true`, set it once, **after** the federated credentials exist, because it changes the subject of every OIDC token the repository issues. If the repository uses a different template, follow your organization's policy instead.

```bash
gh api --method PUT repos/OWNER/NAME/actions/oidc/customization/sub --input - <<'EOF'
{"use_default":false,"include_claim_keys":["repository_owner_id","repository_id","context"]}
EOF
```

If a sign-in fails with `AADSTS70021`, compare the subject in the error with `github_subjects` in the `deployment_identity` output.

### Runner Power State Identity

With `deployment_identity = "oidc"`, this module also creates a separate identity that starts `jumplinux2` before an approved run and deallocates it afterwards, from GitHub-hosted jobs. It can't deploy anything.

Property | Value
--- | ---
Attachment | None
Role | `Desktop Virtualization Power On Off Contributor` on `jumplinux2` only. It allows reading the VM and changing its power state, but not running commands, changing extensions or deleting it. `Virtual Machine Contributor` would allow all of those.
Federated credential | One, for `github_runner_power_state_environment` (default `sandbox-runner-power-state`). Its subject is `power_state_identity_github_subject` in the `github_runner` output.
Environment | Must not be in `deployment_identity_github_environments`, so neither identity accepts the other's tokens. Restrict it to `main`, with no required reviewers. The workflow uses this name, so keep the default unless you change the workflow too.

The Sandbox deployment workflow's `start_runner` and `stop_runner` jobs sign in as this identity. Their behavior and the environment secrets they need are described in [Runner power state jobs](../../../../../CONTRIBUTING.md#runner-power-state-jobs). With `managed_identity`, the identity isn't created; keep `jumplinux2` running.
