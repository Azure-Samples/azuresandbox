# DevOps IaC Configuration (rg-devops-iac)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Features](#features)
* [Prerequisites](#prerequisites)
* [Getting Started (Interactive Execution)](#getting-started-interactive-execution)
* [Deployment Identity and Authentication](#deployment-identity-and-authentication)
* [Documentation](#documentation)

## Architecture

![diagram](./images/rg-devops-iac-diagram.drawio.svg)

## Overview

This configuration provides a minimal set of resources to function as an execution environment for Terraform which is often a critical part of a DevOps pipeline. It is a useful starting point for DevOps / Infrastructure-As-Code (IaC) projects that require a secure and isolated environment for deploying and managing infrastructure using Terraform. The root module creates network, storage and security prerequisites. The virtual machine used as a Terraform execution environment is implemented in a child module which can be repurposed in other environments (such as a platform landing zone) where the resources defined in the root module already exist.

## Features

This section provides a brief overview of the features included in this configuration.

* A pre-configured virtual network, including:
  * A subnet for use by the Linux virtual machine
  * A NAT gateway for outbound internet connectivity
  * An Azure Bastion host (Standard SKU with native client support) in its own `AzureBastionSubnet`, which is the only inbound path to the Linux virtual machine
* A pre-configured storage account, including:
  * A container for storing Terraform state files
  * Public access is enabled by design since there may be the first environment provisioned in Azure. This can be disabled once a platform landing zone is in place.
  * Shared access keys are disabled by default and Azure RBAC is used for authorization.
* A pre-configured key vault for managing secrets
* Network-isolated observability, including:
  * A Log Analytics workspace that accepts ingestion and queries only through an Azure Monitor Private Link Scope (AMPLS) private endpoint in the devops virtual network
  * Diagnostic settings that send logs and metrics to the workspace for every resource in this configuration that supports them, for example key vault audit events (including break-glass SSH key retrieval), Terraform state blob reads and writes, and Bastion sign-ins
  * Azure Monitor Agent on the Linux virtual machine, with a data collection rule for syslog (including SSH sign-in and `sudo` activity) and performance counters
* A pre-configured Linux virtual machine for use as a Terraform execution environment implemented as a module for inclusion in other configurations, including:
  * No public IP address. Operators connect through Azure Bastion and sign in with Microsoft Entra ID using short-lived OpenSSH certificates, including Visual Studio Code Remote-SSH through a Bastion tunnel
  * Key vault secrets for a break-glass local admin account, used only when Microsoft Entra ID sign-in fails
  * Managed identity role assignments for Azure Blob Storage for use as a Terraform state backend
  * Pre-configured environment variables for Terraform azurerm provider to use managed identities
  * Pre-installed software for IaC / DevOps projects
  * Optional registration as a GitHub Actions self-hosted runner for CI/CD workflows (disabled by default)
  * Optional deployment identity (disabled by default), either:
    * a user-assigned managed identity attached to the Linux virtual machine, with standing subscription `Contributor` and conditioned `Role Based Access Control Administrator`, for sandbox applies with `auth_mode = "managed_identity"`, or
    * an unattached user-assigned managed identity with standing subscription `Reader` and GitHub Actions federated identity credentials, for approval-gated workflow applies with `auth_mode = "oidc"` after the operator grants time-bound roles

**NOTE:** The Linux virtual machine is implemented as a module so it can be easily reused in other configurations. It is not intended to be used as a production jumpbox. It is intended to be used as a Terraform execution environment for DevOps / IaC projects.

## Prerequisites

This section describes the prerequisites required in order to provision this configuration.

* [Microsoft Entra ID Tenant and Azure Subscription](#microsoft-entra-id-tenant-and-azure-subscription)
* [Self-Hosted Runner and Managed Identity Prerequisites (Optional)](#self-hosted-runner-and-managed-identity-prerequisites-optional)
* [Other Prerequisites](#other-prerequisites)
* [Terraform Execution Environment](#terraform-execution-environment)

### Microsoft Entra ID Tenant and Azure Subscription

* Identify the [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/fundamentals/whatis) tenant to be used for identity and access management, or create a new tenant using [Quickstart: Set up a tenant](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-create-new-tenant).
* Identify a single Azure [subscription](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/considerations/fundamental-concepts#azure-terminology) or create a new Azure subscription. See [Azure Offer Details](https://azure.microsoft.com/support/legal/offer-details/) and [Associate or add an Azure subscription to your Microsoft Entra tenant](https://learn.microsoft.com/entra/fundamentals/how-subscriptions-associated-directory) for more information.
* Identify the owner of the Azure subscription to be used to provision this configuration. This user should have an [Owner](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#owner) Azure RBAC role assignment on the subscription. See [Steps to assign an Azure role](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-steps) for more information.
* The subscription owner provisions this configuration with their own identity, signed in to Azure CLI. No service principal or client secret is needed: this is a one-time bootstrap, and a service principal with `Owner` would only duplicate the owner's access as a standing credential. If your organization uses [Privileged Identity Management](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-configure), activate an eligible `Owner` assignment for the duration of the deployment.

### Self-Hosted Runner and Managed Identity Prerequisites (Optional)

These prerequisites apply only if you plan to use this configuration as a self-hosted runner that deploys Azure Sandbox with a deployment identity (`enable_github_runner = true` and `deployment_identity = "managed_identity"` or `"oidc"`). Arrange them **before** provisioning, because some of them need privileged roles that the person running the deployment may not hold.

* **GitHub repository administrator.** Registering a repository-level runner needs a fine-grained personal access token with `Administration: Read and write` on the target repository, created by a repository administrator. See [Optional: GitHub Actions Self-Hosted Runner](#optional-github-actions-self-hosted-runner).
* **Microsoft Entra Privileged Role Administrator or Global Administrator.** Required only if the sandbox will be deployed with the `mssql` module enabled. The user-assigned managed identity then needs the Microsoft Graph `Group.Create`, `GroupMember.Read.All`, `User.Read.All` and `Application.Read.All` application permissions, and only one of these Entra roles can grant them. An Owner on the subscription cannot grant them. Read-only Entra roles such as Global Reader are not enough. Privileged Role Administrator is the least privileged role that works. If your organization uses [Privileged Identity Management](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-configure), activate an eligible assignment for the grant, or arrange for an administrator to run it. The grant is a one-time step after the identity is created. See [Optional: Deployment Identity for Managed Identity Sandbox Applies](#optional-deployment-identity-for-managed-identity-sandbox-applies).
* **OIDC deployment identity only (`deployment_identity = "oidc"`).**
  * Microsoft Entra ID P2 or Microsoft Entra ID Governance, for the time-bound role assignments the operator grants before each workflow run.
  * A subscription `Owner` (for example, the operator with `Owner` activated through PIM) to grant those assignments.
  * A GitHub repository administrator to set the repository's OIDC subject claim template once, unless the repository already uses the expected template (for example, from its organization).

  See [Optional: Deployment Identity for OIDC Workflow Applies](#optional-deployment-identity-for-oidc-workflow-applies).

### Other Prerequisites

* Some Azure subscriptions may have low quota limits for specific Azure resources which may cause failures. See [Resolve errors for resource quotas](https://learn.microsoft.com/azure/azure-resource-manager/templates/error-resource-quota) for more information.
* Some Azure subscriptions may not have the required resource providers registered. Terraform is configured to automatically register the required resource providers, but this may take some time on first use.
* Some Azure subscriptions may not have the required features enabled which may cause failures. Monitor your plan application for errors related to specific subscription features and enable them as needed.
* Connecting to the Linux virtual machine requires the Azure CLI `bastion` and `ssh` extensions on the client (`az extension add --name bastion` and `az extension add --name ssh`). See [Connection paths](./modules/vm-jumpbox-linux/README.md#connection-paths).
* Azure Bastion Standard is billed hourly while deployed, plus outbound data transfer beyond the included amount. See [Azure Bastion pricing](https://azure.microsoft.com/pricing/details/azure-bastion/). Bastion is the only inbound path to the Linux virtual machine, so it's always deployed.
* Some organizations may institute [Azure policy](https://learn.microsoft.com/azure/governance/policy/overview) which may cause failures. This can be addressed by using custom settings which pass the policy checks, or by disabling the policies on the Azure subscription being used for the configurations.

### Terraform Execution Environment

#### Interactive Execution

A variety of Terraform execution environments can be used to provision this configuration interactively, including:

* **Windows-Only Client**: A Windows-only client can be used to run Terraform. The following software should be installed:
  * git
  * PowerShell 7.x
  * Azure CLI
  * Terraform
  * Visual Studio Code

* **Windows Subsystem for Linux (WSL) Client**: WSL offers the best of Windows and Linux in the same client environment and was used to develop this project. The following software should be installed:
  * Linux (WSL) software
    * Linux Distro: Ubuntu 24.04 LTS (Noble Numbat)
    * git
    * Azure CLI
    * Terraform
  * Windows software
    * Visual Studio Code configured for [Remote development in WSL](https://code.visualstudio.com/docs/remote/wsl-tutorial)

* **Linux / MacOs Client**: A Linux or MacOS client can be used to run Terraform. The following software should be installed:
  * git
  * Azure CLI
  * Terraform
  * Visual Studio Code

* **Azure Cloud Shell**: Azure Cloud Shell can be used to run Terraform. Most of the software dependencies are pre-installed.

* **GitHub Codespaces**: GitHub Codespaces has not been tested but should be okay. Most of the software dependencies should be pre-installed.

## Getting Started (Interactive Execution)

This section covers the steps to get started with this configuration using an interactive Terraform execution environment. The steps include logging into Azure, cloning the repository, initializing Terraform, configuring variables, validating and applying the configuration, and smoke testing.

The VM can serve as a GitHub Actions self-hosted runner for the
[Sandbox deployment workflow](../../../.github/workflows/sandbox-deployment.yml),
a manually triggered deployment with all base modules enabled and
post-deployment unit/integration testing in three stages: `preflight`,
`apply`, and `unit-test`. Each deployment uses its own state key, and runner
logs stay private.
The unit-test stage publishes default-sanitized JSON evidence as
workflow artifacts on both test success and failure; raw logs and plans stay
on the runner.

After a successful apply, the helper reads `terraform output -json resource_names`
and records its actual `resource_group` value for the stage-results summary.
The exact resource group name is an operator-approved exception to public
deployment-name sanitization; other resource names, IDs, and raw outputs remain
private. The summary retains the name even if subsequent unit testing fails.
Preflight-only runs and runs without a verified post-apply name explicitly report
it as unavailable rather than guessing. Completed run summaries are not rewritten.

The updated workflow restricts automation to **new Sandboxes only**:
each workflow run derives a new ID/key, and every preflight attempt rejects an
existing state blob. Automated updates and recovery of existing Sandboxes are
not supported. Unit-test also finalizes evidence itself, leaving only Publish
and Report afterward.

The workflow also supports a release-PR entry path through
`pull_request_target` for same-repository `vnext` PRs targeting `main`.
The normal release flow is: open a draft `vnext` → `main` PR → mark it ready
for review → static CI runs → the deployment is queued awaiting approval →
the owner approves → deploy and unit/integration tests → if they pass, the PR
can be merged. A GitHub-hosted job validates the event without checkout or
environment secrets. Drafts and title/description-only edits run no static CI
and do not deploy; opening or reopening a ready PR, marking it ready, updating
its head, or retargeting it to `main` starts a fresh run.
PR runs use the separate `sandbox-release-gate` environment and always run
all stages with checkout pinned to the exact PR head SHA. Manual dispatch
retains `sandbox-deployment` and its stage selector, and does not run or wait
for static CI. Its `source_branch` input chooses which branch of this
repository to deploy: `vnext` (the default, matching earlier runs) or `main`
for released code. Both sources support every stage. The hosted selection job
rejects any other value before checkout or environment-secret access, then
checks out the branch tip as `refs/heads/<branch>`. The run name and summary
show the selected source, and the stage results report the deployed commit.
The input never affects release PR runs, and manual runs never publish or
satisfy the release statuses.
Both environments require `SANDBOX_BACKEND_HCL` and `SANDBOX_TFVARS_HCL`
and owner approval. Keep their deployment branch restrictions on `main`,
the trusted workflow context, and explicitly allow `pull_request_target`
and `workflow_dispatch` in an Actions event policy scoped only to
`.github/workflows/sandbox-deployment.yml`.

The workflow authenticates the sandbox providers only with GitHub OIDC:
`SANDBOX_TFVARS_HCL` must set `auth_mode = "oidc"` and `client_id` to the
OIDC deployment identity's client id, and preflight rejects any other mode.
Only the `sandbox` job has `id-token: write`. Before approving a run, the
operator grants the identity time-bound roles in the Azure portal; preflight
waits for them and refuses to start unless enough of the grant remains. The
state backend still uses the virtual machine's system-assigned identity. See
[Optional: Deployment Identity for OIDC Workflow Applies](#optional-deployment-identity-for-oidc-workflow-applies).

Before any approval request, a release PR run calls the six static CI
workflows (`ci-bash`, `ci-powershell`, `ci-docs`, `ci-actions`, `ci-secrets`,
and `ci-terraform`) as reusable workflows from the trusted `main` revision.
Each checks out the exact PR head SHA read-only, with no secrets, write
tokens, or caches, and applies its usual path filters to the **full release
diff**: everything `vnext` adds since its merge base with `main`, not just the
last commit. Each ends with a no-logic `release report` job that passes back
its raw job results. The hosted `Release static CI` job applies one rule to all
six: `pass` when every applicable check succeeded, or `not-applicable` when
change detection succeeded, proved no relevant files changed, and the
path-gated checks were skipped (`gitleaks` and both `terraform validate`
contexts always run and must succeed). Anything else fails. It requires a
`pass` or `not-applicable` verdict from every workflow, then rereads the live
PR and requires it to be open, not a draft, and unchanged in head, base, and
source. Only then does it
publish `release-static-ci = success` and let the environment-protected
deployment job request approval. A failed, cancelled, missing, or unexpected
result publishes `release-static-ci = failure` and no deployment is requested.
Static CI never depends on deployment-produced checks, and the organization's
CLA check is not part of it. Results from earlier topic-PR, push, or manual
CI runs are never reused.

After approval, and after any wait for the serialized runner, the deployment
job's first step rechecks the live PR and confirms this attempt still owns a
passing `release-static-ci` status, before checking out candidate code or
touching Azure. A PR that changed, closed, became a draft, or was superseded
in the meantime stops there.

Both entry paths share the existing concurrency group with active-run
cancellation disabled. Advancing `vnext` does not change an already captured
PR candidate or interrupt an active apply. The workflow does not implement
cleanup/recovery. The existing run-ID state keys and unused-state requirement
still apply. **Re-run failed jobs** is not supported for release PRs: a re-run
attempt doesn't own the PR statuses, so it stops before static CI is accepted
or any deployment starts. To retry after any failure, mark the PR as a draft
and then ready again, or close and reopen it, to start a fresh run.

Eligible PR runs publish `release-static-ci` and `sandbox-deployment-gate` as
pending on the exact head SHA before static CI starts. A separate
GitHub-hosted reporter publishes `sandbox-deployment-gate = success` only after
Preflight, Apply, Unit-test, stage reporting, and JSON artifact upload all
succeed. The validated JSON must also report native exit code zero,
`result = "pass"`, positive passing counts, and no failed tests or failed
suites. Native test-scope/optional-suite skip behavior is unchanged. Missing
evidence, skipped required stages, failures, and cancellations cannot produce
success. If cancellation or an API outage prevents final reporting, the status
can remain pending rather than falsely passing.

The deployment job waits for successful pending-status publication and static
CI on PR runs; an API failure at either point does not schedule an Azure
deployment. Manual runs explicitly skip the PR-only jobs without losing their
deployment. Metadata-only validation does not share the status-writer lock, so
it cannot displace a queued reporter.

Status writers have a separate per-SHA lock and attempt-specific run links;
an older attempt cannot overwrite the pending result of a newer attempt on
the same SHA, or deploy on the strength of it. Only the hosted status jobs
have status-write permission. Manual dispatch does not publish these PR
statuses. Drafts and metadata-only edits do not overwrite them, and no
workflow closes or merges a PR. Three rulesets on `main` require these checks,
all from GitHub Actions: `main-release-source` requires
`main-source-eligibility`, `main-release-static-ci` requires
`release-static-ci`, and `main-release-deployment` requires
`sandbox-deployment-gate` and the hosted `Publish release deployment status`
check. Failed checks block ordinary release merges without closing the PR.
Release deployments are approved by the `azuresandbox-owners` team. The
owners' PR-only emergency bypass is described in
[CONTRIBUTING.md](../../../CONTRIBUTING.md#emergency-merges); it never creates
a passing result or approves a deployment.

The deployment/monitor helpers replace the Python implementation
with Bash entrypoints and PowerShell 7.3+ stage logic. The helper test sources
and their `scripts/tests` directory are removed at the operator's request;
existing Sandbox unit/integration tests remain unchanged. Validation uses
existing CI gates and real executions.

* [Step 0: Login](#step-0-login)
* [Step 1: Clone the Repository](#step-1-clone-the-repository)
* [Step 2: Initialize Terraform](#step-2-initialize-terraform)
* [Step 3: Configure Variables](#step-3-configure-variables)
* [Step 4: Validate and Apply Configuration](#step-4-validate-and-apply-configuration)
* [Step 5: Complete Smoke Testing](#step-5-complete-smoke-testing)
* [Step 6: Use the Virtual Machine](#step-6-use-the-virtual-machine)
* [Step 7: Clean Up](#step-7-clean-up)

### Step 0: Login

Before you can provision this configuration interactively, you need to log in to your Azure account. Terraform authenticates as the user signed in to Azure CLI, so an Azure CLI login is always required. If you will use the PowerShell bootstrap script, also sign in with Azure PowerShell. Use the following steps to log in

* Open a terminal window and run the following command to log in to Azure CLI:

  ```bash
  az login --use-device-code
  ```

  If you will use the PowerShell bootstrap script, also run:

  ```pwsh
  Connect-AzAccount -UseDeviceAuthentication
  ```

* Check the terminal for a message like this:

  ```text
  To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code XXXXXXXXX to authenticate.
  ```

* Open a browser and navigate to the URL provided in the terminal. Enter the code displayed in the terminal to authenticate your Azure account.
* Sign in with an account that has an Azure RBAC `Owner` role assignment on the subscription you will be using to provision this configuration.
* Depending upon how your Entra ID tenant is configured, you may be prompted to enter your password and/or approve a sign-in request on your mobile device.
* Click **Continue** when asked if you are trying to sign in to Azure.
* Check the terminal for a prompt like this:

  ```text
  Retrieving tenants and subscriptions for the selection...

  [Tenant and subscription selection]

  No     Subscription name               Subscription ID                       Tenant
  -----  ------------------------------  ------------------------------------  ----------------
  [1] *  SUBSCRIPTION1-NAME-HERE         SUBSCRIPTION1-ID-HERE                 TENANT-NAME-HERE
  [2]    SUBSCRIPTION2-NAME-HERE         SUBSCRIPTION2-ID-HERE                 TENANT-NAME-HERE

  The default is marked with an *; the default tenant is 'TENANT-NAME-HERE' and subscription is 'SUBSCRIPTION1-NAME-HERE' (SUBSCRIPTION1-ID-HERE).

  Select a subscription and tenant (Type a number or Enter for no changes):
  ```

* Select the subscription you will be using to provision this configuration by entering the number next to it. If you only have one subscription, just press Enter.

### Step 1: Clone the Repository

Clone the Azure Sandbox repository to the Terraform execution environment using the following command:

```bash
git clone https://github.com/Azure-Samples/azuresandbox
```

### Step 2: Initialize Terraform

**WARNING:** By default this configuration assumes you will be using a local Terraform state file which includes sensitive information. This is by design since it is actually creating the storage account where Terraform state files are to be stored for other configurations. This chicken-and-egg bootstrap is the only scenario in this project that legitimately uses local state, and it runs on an interactive Terraform execution environment such as a workstation or Azure Cloud Shell. Configurations applied *after* the bootstrap - including CI/CD workflows running on `jumplinux2` as a self-hosted runner - should use the `azurerm` backend hosted in the storage account this configuration creates.

After cloning the repository, navigate to the `rg-devops-iac` directory and initialize Terraform. This step downloads the necessary provider plugins and modules.

```bash
cd azuresandbox/extras/configurations/rg-devops-iac
terraform init
```

### Step 3: Configure Variables

There many variables in this configuration. Defaults have been set for most of them so only a few need to be set in advance to provision this configuration. There are a few different ways to set variables in Terraform.

* **Environment Variables**: Set environment variables for sensitive information such as passwords and secrets used in the root module.
* **terraform.tfvars file**: Create a `terraform.tfvars` file in the root directory of the project to set variables for the root module.
* **main.tf file**: Override module default values in the `main.tf` file by customizing the module blocks.

Follow these steps to configure the variables for this configuration:

* Create a `terraform.tfvars` file in the root directory of the project. This file should set the necessary variables for your deployment. Here is an example of what the `terraform.tfvars` file might look like:

  ```hcl
  entra_tenant_id = "YOUR-ENTRA-TENANT-ID-HERE"
  location        = "YOUR-AZURE-REGION-HERE"
  subscription_id = "YOUR-AZURE-SUBSCRIPTION-ID-HERE"

  tags = {
    project     = "devops",
    costcenter  = "mycostcenter",
    environment = "dev"
  }
  ```

  Helper scripts are provided to generate the `terraform.tfvars` file:

  ```bash
  # Bash bootstrap script, run from the root directory of the project
  ./scripts/bootstrap.sh
  ```

  ```pwsh
  # PowerShell bootstrap script, run from the root directory of the project
  ./scripts/bootstrap.ps1
  ```

#### **Overriding Defaults**

The variable defaults set in this configuration can be overridden by customizing the `terraform.tfvars` file or modifying the module block in `main.tf`. For example, the default value for the `vm_jumpbox_linux_name` variable in the vm-jumpbox-linux module is `jumplinux2`. You can override this value by adding the following to the vnet-shared module block in `main.tf`:

```hcl
module "vm_jumpbox_linux" {
  source = "./modules/vm-jumpbox-linux"

  key_vault_id        = azurerm_key_vault.this.id
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  storage_account_id  = azurerm_storage_account.this.id
  subnet_id           = azurerm_subnet.this.id
  tags                = var.tags

  depends_on = [time_sleep.wait_for_roles]

  # Override defaults here
  vm_jumpbox_linux_name = "devopsagent1"
}
```

#### **Optional: GitHub Actions Self-Hosted Runner**

The Linux virtual machine can optionally be registered as a [GitHub Actions self-hosted runner](./modules/vm-jumpbox-linux/README.md#github-actions-self-hosted-runner) so it can run CI/CD workflows using the pre-installed IaC toolchain and the VM managed identity. This is **disabled by default**.

To enable it:

* Create a GitHub personal access token (PAT) with `administration:write` on the target repository, or `organization_self_hosted_runners:write` on the target organization. Set it using an environment variable so it is not stored in the `terraform.tfvars` file:

  ```bash
  # Set environment variable in bash
  export TF_VAR_github_runner_token=YOUR-GITHUB-PAT-HERE
  ```

  ```pwsh
  # Set environment variable in PowerShell
  $env:TF_VAR_github_runner_token = "YOUR-GITHUB-PAT-HERE"
  ```

* Add the following to the `terraform.tfvars` file:

  ```hcl
  enable_github_runner = true
  github_runner_url    = "https://github.com/YOUR-ORG-HERE/YOUR-REPO-HERE"
  github_runner_labels = ["azuresandbox"]
  ```

The token is stored as a **write-only** key vault secret, so it is never written to Terraform state, and it is read on the VM at provisioning time using the VM managed identity. When `enable_github_runner` is `false` no runner software is installed and the VM behaves exactly as it did before.

Workflows running on the runner should store Terraform state in the `azurerm` backend hosted in the storage account provisioned by this configuration, not in a local state file on the runner. See [Terraform State for CD Workflows](./modules/vm-jumpbox-linux/README.md#terraform-state-for-cd-workflows).

If the registration URL is a repository URL the runner is registered as a repository level runner and runner groups do not apply. See [Runner Scope](./modules/vm-jumpbox-linux/README.md#runner-scope).

By default the runner service account is granted command scoped passwordless `sudo` for the binaries used by the `vwan` point-to-site VPN integration tests. Review [Elevated Permissions for Integration Tests](./modules/vm-jumpbox-linux/README.md#elevated-permissions-for-integration-tests) and disable it if the runner will not execute those tests.

#### **Optional: Deployment Identity for Managed Identity Sandbox Applies**

The root Azure Sandbox configuration can authenticate with a managed identity instead of a service principal secret (`auth_mode = "managed_identity"`; see [Deployment Identity and Authentication](#deployment-identity-and-authentication)), for example from a CD workflow running on the self-hosted runner. That mode requires a **user-assigned** managed identity attached to the Terraform execution environment. This configuration can create one for you. This is **disabled by default**.

To enable it, add the following to the `terraform.tfvars` file:

```hcl
deployment_identity = "managed_identity"
```

When enabled, the identity is:

* Created in the resource group provisioned by this configuration.
* Assigned two roles at the subscription scope, as described in [Deployment Identity Permissions](#deployment-identity-permissions):
  * `Contributor`, to create and manage sandbox resources.
  * `Role Based Access Control Administrator`, with a condition that allows assigning and removing only the roles the sandbox assigns, listed in `local.deployment_identity_assignable_roles` in [`locals.tf`](./locals.tf). The identity cannot grant `Owner`, `User Access Administrator` or `Role Based Access Control Administrator`.

  This is still a standing, privileged identity. Contributor on the subscription also includes this configuration's own resource group, so anything running on `jumplinux2` that uses this identity can modify or delete it. When that list changes, re-apply this configuration to update the condition.
* Attached to `jumplinux2` **in addition to** the system-assigned identity. The system-assigned identity remains the VM's default identity, so cloud-init, the runner registration script, `az login --identity` and the `azurerm` state backend (`ARM_USE_MSI`) keep using it. Use the user-assigned identity explicitly by its client id, e.g. `az login --identity --client-id <client-id>` or `Connect-AzAccount -Identity -AccountId <client-id>`.

Enabling or disabling the identity on an existing deployment updates the VM in place. It does not replace the VM.

After the apply, use the `deployment_identity_client_id` output as `client_id` in the root sandbox `terraform.tfvars`, together with `auth_mode = "managed_identity"`.

If the sandbox will be deployed with the `mssql` module enabled, the identity also needs the Microsoft Graph `Group.Create`, `GroupMember.Read.All`, `User.Read.All` and `Application.Read.All` application permissions, which this configuration cannot grant. A Global Administrator or Privileged Role Administrator must grant them once, after the identity is created:

```bash
# Run from this configuration's directory, signed in to Azure CLI as a Privileged Role Administrator or Global Administrator
./scripts/grant-graph-permissions.sh
```

The script reads the identity from the `deployment_identity_principal_id` output (or takes a client id or object id as its first argument), and skips permissions that are already granted, so it is safe to re-run. It warns, and prints the removal command, if the identity still has `Group.ReadWrite.All` from an earlier setup. If you activated the Entra role just before running it, sign in again with `az login` so the new role is included in your token.

Managed identities have no app registration, so the Entra admin center **API permissions** steps used for a service principal do not apply. Use the script above instead. The grant is removed automatically if the identity is deleted.

#### **Optional: Deployment Identity for OIDC Workflow Applies**

The [Sandbox deployment workflow](../../../.github/workflows/sandbox-deployment.yml) authenticates the root sandbox providers with GitHub OIDC (`auth_mode = "oidc"`; see [Deployment Identity and Authentication](#deployment-identity-and-authentication)). It federates to a user-assigned managed identity that is **not** attached to any virtual machine, so code on `jumplinux2` can't get tokens for it from the managed identity endpoint. Only an approved workflow run in an allowed environment can. The identity holds standing `Reader` only. Before each run, the operator grants it time-bound deployment roles. This is **disabled by default**.

`deployment_identity` takes a single value, so this replaces the attached `managed_identity` identity. Switching an existing deployment from `managed_identity` to `oidc` keeps the same identity and client id, removes its standing deployment roles, and detaches it from `jumplinux2` in place.

To enable it, add the following to the `terraform.tfvars` file:

```hcl
deployment_identity = "oidc"
github_runner_url   = "https://github.com/OWNER/NAME" # a repository URL
```

The federated credentials trust workflows in that repository in the environments in `github_oidc_environments`. It defaults to the workflow's two environments, `sandbox-deployment` and `sandbox-release-gate`. The credentials identify the repository and its owner by numeric id, which doesn't change if either is renamed. Terraform looks the ids up from the GitHub API on each plan. The request is anonymous, because data source arguments are saved in state, so it works only for public repositories and is subject to GitHub's rate limit for unauthenticated requests. For a private repository, or to avoid the lookup, set both ids:

```hcl
github_repository_id       = "123456789" # gh api repos/OWNER/NAME --jq .id
github_repository_owner_id = "987654321" # gh api repos/OWNER/NAME --jq .owner.id
```

See [Root Module Input Variables](#root-module-input-variables).

When enabled, the identity is:

* Created in the resource group provisioned by this configuration.
* Assigned standing `Reader` at the subscription scope, so the workflow can sign in and check its own grant before it changes anything.
* Given one federated identity credential per environment, with issuer `https://token.actions.githubusercontent.com` and audience `api://AzureADTokenExchange`. Each subject combines the repository owner id, the repository id and the environment, for example `repository_owner_id:987654321:repository_id:123456789:environment:sandbox-deployment`. The `deployment_identity_github_subjects` output lists them.
* Not attached to `jumplinux2`. The state backend keeps using the virtual machine's system-assigned identity.

After the apply, complete these one-time steps:

1. If the sandbox will be deployed with the `mssql` module enabled, grant the Microsoft Graph application permissions with `./scripts/grant-graph-permissions.sh`, as described in [Optional: Deployment Identity for Managed Identity Sandbox Applies](#optional-deployment-identity-for-managed-identity-sandbox-applies). Microsoft Graph application permissions can't be time-bound, so they stay standing. Only approved workflow runs can use them.
1. Check the repository's OIDC subject claim template. The subjects above need a template with `include_claim_keys` set to `["repository_owner_id","repository_id","context"]`, which uses immutable ids instead of names:

   ```bash
   gh api repos/OWNER/NAME/actions/oidc/customization/sub
   ```

   If the response shows `"use_default":false` and those keys, the repository already uses the template, often because its organization requires it. Don't change it. If it shows `"use_default":true`, a repository administrator sets it once. Do this **after** the federated credentials exist, because it changes the subject of every OIDC token the repository issues:

   ```bash
   gh api --method PUT repos/OWNER/NAME/actions/oidc/customization/sub --input - <<'EOF'
   {"use_default":false,"include_claim_keys":["repository_owner_id","repository_id","context"]}
   EOF
   ```

   If the repository uses a different template, follow your organization's policy rather than overriding it. Any other workflow that federates to Azure from this repository must use subjects in the same format. If a sign-in fails with `AADSTS70021`, the error shows the subject GitHub presented. Compare it with the `deployment_identity_github_subjects` output.
1. In both the `sandbox-deployment` and `sandbox-release-gate` environments, update `SANDBOX_TFVARS_HCL` to set `auth_mode = "oidc"` and `client_id` to the `deployment_identity_client_id` output.
1. Optionally, set the `SANDBOX_JIT_MIN_REMAINING_MINUTES` repository or environment variable (default `150`, range `0`-`1440`, where `0` skips the remaining-time check).

Before approving each run, grant the identity its deployment roles just in time:

1. Activate your eligible subscription `Owner` assignment through PIM. See [Least-Privilege Operator Access with Privileged Identity Management](#least-privilege-operator-access-with-privileged-identity-management).
1. In the Azure portal, go to the subscription > *Access control (IAM)* > *Add* > *Add role assignment*. Select `Contributor`, then *Managed identity* > *User-assigned managed identity* > the deployment identity. Set *Assignment type* to *Active* and *Time bound*, with a 4-hour duration starting now. Review and assign.
1. Repeat for `Role Based Access Control Administrator`. On the *Conditions* tab, open the advanced condition editor's code view and paste the output of `terraform output -raw deployment_identity_jit_condition`. Without this condition the identity could assign any role, including `Owner`.
1. Approve the workflow run. Preflight waits up to 5 minutes for the roles to take effect. It fails if either role isn't active, or if less than `SANDBOX_JIT_MIN_REMAINING_MINUTES` remains on either assignment. It accepts a permanent assignment with a warning. Apply and unit-test check that both roles are still active before they start.
1. After the run, remove the assignments or let them expire.

The 4-hour grant and 2.5-hour minimum cover preflight, a full apply and unit testing. The workflow never destroys a sandbox. Tear down manually, from a terminal with your own access or while a grant is active.

If the portal doesn't offer the condition with a time-bound assignment, make the equivalent request with the Azure CLI, signed in as the operator with `Owner` active:

```bash
SUB=$(az account show --query id -o tsv)
BODY=$(jq -n \
  --arg principal "$(terraform output -raw deployment_identity_principal_id)" \
  --arg role "/subscriptions/$SUB/providers/Microsoft.Authorization/roleDefinitions/f58310d9-a9f6-439a-9e8d-f62e7b41a168" \
  --arg condition "$(terraform output -raw deployment_identity_jit_condition)" \
  '{properties: {principalId: $principal, roleDefinitionId: $role, requestType: "AdminAssign",
    condition: $condition, conditionVersion: "2.0",
    scheduleInfo: {startDateTime: (now | todate), expiration: {type: "AfterDuration", duration: "PT4H"}}}}')
az rest --method put --body "$BODY" \
  --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$(uuidgen)?api-version=2020-10-01"
```

Residual exposure:

* The subjects don't name a workflow file. Any workflow in the repository that runs in an allowed environment can federate to the identity. Restrict each environment to the `main` branch and require reviewers, so only reviewed workflows on `main` that an owner approves can use it.
* The identity's standing `Reader` role and Microsoft Graph permissions are usable by any approved run in the allowed environments.
* The time-bound roles belong to the identity, not to a single run. Another approved run during the same window can use them. The workflow's concurrency group runs one deployment at a time.
* During a run, the job's federated token is passed to Azure CLI on the runner's command line, where other processes on `jumplinux2` can see it.

### Step 4: Validate and Apply Configuration

Remember that Terraform will compare the state of existing resources in Azure with what it expects to be there when creating a plan. If the state of existing resources in Azure does not match what Terraform expects, the plan will modify existing resources to match the configuration. This can happen when resources are modified manually or via Policy outside of Terraform. This is known as "drift".

Follow these steps to validate and apply the configuration:

* First, validate that the configuration is syntactically correct:

  ```bash
  terraform validate
  ```

* Next, create a plan to see what resources will be created:

  ```bash
  terraform plan
  ```

  * **IMPORTANT:** If you are provisioning this configuration for the first time, you will see a lot of `+` signs in the output. This indicates that new resources will be created if this plan is applied. If you are updating this configuration after it has been provisioned, you may see `~` signs indicating that existing resources will be updated. If you see `-` signs, this indicates that existing resources will be deleted. Be careful with these operations as they may cause data loss.

* Finally, apply the configuration to create the resources:

  ```bash
  terraform apply
  ```

* Monitor the progress of the apply operation in the console. If errors occur, that may not be reflected in the console immediately. Terraform will try to apply as much of the plan as possible first, then will show the errors when it is done. It can take up to 15 minutes to provision this configuration. If everything goes well you should see a message like this:

  ```text
  Apply complete! Resources: XX added, XX changed, XX destroyed.
  ```

### Step 5: Complete Smoke Testing

After the configuration has been provisioned, complete the smoke testing procedures in the `vm-jumpbox-linux` module.

### Step 6: Use The Virtual Machine

You now have a fully provisioned DevOps IaC environment! You can use it as a Terraform execution environment interactively or via DevOps pipelines. For interactive use, connect with Visual Studio Code Remote-SSH through a Bastion tunnel using `./scripts/connect-jumplinux2.sh` or `./scripts/Connect-Jumplinux2.ps1`. See [Connection paths](./modules/vm-jumpbox-linux/README.md#connection-paths).

### Step 7: Clean Up

Don't forget to delete your DevOps IaC environment when you're done. You don't want to have to explain to your boss why you left an unused resources laying around that costs your company money. The quickest way to clean up is to delete the DevOps IaC resource group. Do this with care because data loss will occur, including any Terraform state files in the Azure Blob Storage container.

**NOTE:** If you enabled `enable_github_runner`, deleting the virtual machine does not deregister the self-hosted runner from GitHub. Either remove the runner from the VM before deleting it:

```bash
# Run on jumplinux2
sudo /opt/actions-runner/svc.sh stop
sudo /opt/actions-runner/svc.sh uninstall
sudo -u githubrunner /opt/actions-runner/config.sh remove --token YOUR-REMOVAL-TOKEN-HERE
```

...or delete the stale offline runner afterwards from GitHub > *Settings* > *Actions* > *Runners*.

If you only need to remove Terraform state file(s) from the Azure Blob Storage container without deleting the whole environment, use `scripts/delete-tfstate.sh`. It authenticates with Azure CLI / Microsoft Entra ID only (the storage account has shared access keys disabled) and relies on the built-in RBAC role assignments granted to the caller (e.g. jumplinux2's managed identity) to delete blobs over the storage account's private endpoint — it does not enable public network access, so it must be run from a host with private network connectivity to the storage account, such as jumplinux2. Run it with no arguments to list and select blob(s) interactively, or pass a blob name (e.g. `azuresandbox.tfstate`) to delete it directly:

```bash
./scripts/delete-tfstate.sh                       # list and select interactively
./scripts/delete-tfstate.sh azuresandbox.tfstate  # delete a specific blob
./scripts/delete-tfstate.sh --yes azuresandbox.tfstate  # skip confirmation prompt
```

## Deployment Identity and Authentication

This section is the reference for how the root sandbox configuration authenticates to Azure and Microsoft Entra ID. Most sandbox users deploy interactively with a service principal, as described in the root README's [Service Principal](../../../README.md#service-principal) prerequisites. The managed identity and OIDC modes below support secretless deployments from this configuration's Linux virtual machine, from a terminal and from the Sandbox deployment workflow, respectively.

This configuration itself does not use these modes. It always authenticates as the operator signed in to Azure CLI; see [Operator](#operator).

### Authentication Modes

The root configuration's `auth_mode` variable selects how Terraform authenticates the `azurerm`, `azapi` and `azuread` providers. Every provider uses the same settings, derived once in the `provider_auth` local in the root [`locals.tf`](../../../locals.tf).

`auth_mode` | Identity (`client_id`) | Credential | Typical use
--- | --- | --- | ---
`client_secret` (default) | Service principal `appId` | `client_secret`, supplied with the `TF_VAR_client_secret` environment variable | Interactive execution from any client. See [Service Principal](../../../README.md#service-principal) in the root README.
`managed_identity` | Client id of a user-assigned managed identity attached to the Terraform execution host | Managed identity endpoint of the host. No secret. | Secretless execution on the rg-devops-iac Linux virtual machine.
`oidc` | Client id of an unattached user-assigned managed identity with GitHub Actions federated identity credentials | GitHub Actions OIDC token, requested by the providers from the job's `ACTIONS_ID_TOKEN_REQUEST_URL`. No secret. | The [Sandbox deployment workflow](../../../.github/workflows/sandbox-deployment.yml) on the self-hosted runner. Works only inside a GitHub Actions job with `id-token: write`.

Variable | Description
--- | ---
`auth_mode` | `client_secret`, `managed_identity` or `oidc`. Defaults to `client_secret`.
`client_id` | The client id of the identity Terraform authenticates as.
`client_secret` | The service principal secret. Required only when `auth_mode` is `client_secret`. Set it with `TF_VAR_client_secret`; never store it in a file.
`entra_tenant_id` | The Microsoft Entra tenant id.

### Deployment Identity Permissions

The identity Terraform authenticates as needs the same permissions in every authentication mode. None of them is `Owner`. In `oidc` mode, the two Azure RBAC roles are time-bound grants the operator makes before each workflow run, on top of a standing `Reader` role. See [Optional: Deployment Identity for OIDC Workflow Applies](#optional-deployment-identity-for-oidc-workflow-applies).

Permission | Scope | Why
--- | --- | ---
`Contributor` Azure RBAC role | Sandbox subscription | Creates and manages the sandbox resources.
`Role Based Access Control Administrator` Azure RBAC role, with a condition | Sandbox subscription | Creates and removes the sandbox's role assignments. The condition allows only the roles listed in `ROLES` in the root README's [Service Principal](../../../README.md#service-principal) commands, so the identity cannot grant `Owner`, `User Access Administrator` or `Role Based Access Control Administrator`.
`Group.Create`, `GroupMember.Read.All`, `User.Read.All` and `Application.Read.All` Microsoft Graph application permissions | Microsoft Entra tenant | Creates the SQL administrators security group, with a user and a managed identity as members. The identity becomes the group's owner, which lets it manage and delete the group. Required only when the mssql module is enabled.

When you add a module that assigns a new Azure RBAC role, add the role to the `ROLES` list in the root README's [Service Principal](../../../README.md#service-principal) commands and to `deployment_identity_assignable_roles` in [`locals.tf`](./locals.tf). Then re-grant:

* **Service principal:** remove the existing assignment, then re-run the `Role Based Access Control Administrator` commands in [Service Principal](../../../README.md#service-principal):

  ```bash
  az role assignment delete --assignee "$SPN_APP_ID" --role "Role Based Access Control Administrator" --scope "$SCOPE"
  ```

* **Managed identity:** re-apply this configuration.
* **OIDC:** re-apply this configuration, then use the updated `deployment_identity_jit_condition` output for the next grant.

For `client_secret` mode, see [Service Principal](../../../README.md#service-principal) in the root README. For `managed_identity` mode, set `deployment_identity = "managed_identity"` in this configuration. It creates the user-assigned managed identity, assigns both Azure RBAC roles on the subscription, and attaches the identity to its Linux virtual machine. Use the `deployment_identity_client_id` output as `client_id`, and grant the Microsoft Graph permissions with `scripts/grant-graph-permissions.sh`. See [Optional: Deployment Identity for Managed Identity Sandbox Applies](#optional-deployment-identity-for-managed-identity-sandbox-applies). For `oidc` mode, set `deployment_identity = "oidc"`. See [Optional: Deployment Identity for OIDC Workflow Applies](#optional-deployment-identity-for-oidc-workflow-applies).

### Operator

The operator is the signed-in user who provisions a configuration. It is separate from the deployment identity.

* **This configuration:** Terraform authenticates as the operator signed in to Azure CLI (`use_cli = true` in [`providers.tf`](./providers.tf)), so the operator needs `Owner` on the subscription, or `Contributor` plus an unconditioned role-assignment role such as `User Access Administrator`, for the duration of the apply. The operator's identity is read from the Azure CLI sign-in and granted `Key Vault Secrets Officer` and `Storage Blob Data Contributor` on the resources this configuration creates, and `Virtual Machine Administrator Login` on `jumplinux2` for Microsoft Entra ID SSH sign-in.
* **Root sandbox:** `operator_object_id` is the Microsoft Entra object id of the operator. The operator is granted data-plane role assignments, such as Key Vault and Storage roles, on the sandbox resources. The root bootstrap scripts default it to the signed-in Azure CLI or Azure PowerShell user.

#### Least-Privilege Operator Access with Privileged Identity Management

Day-to-day use of `jumplinux2` doesn't need `Owner`. Connecting through Bastion needs only `Reader` on the virtual machine, its network interface and the Bastion host, plus the `Virtual Machine Administrator Login` role this configuration assigns. Use [Microsoft Entra Privileged Identity Management](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-configure) (PIM) so the operator holds `Owner` only while running `terraform plan` or `terraform apply`. The recommended end state is:

Access | How it's granted
--- | ---
Azure RBAC `Reader` on the subscription | Standing (active, permanent)
Azure RBAC `Owner` on the subscription | PIM eligible, activated just in time for `terraform plan` and `terraform apply`
Microsoft Entra directory roles, such as Global Administrator | PIM eligible
`User Access Administrator` at root scope (`/`) | Removed

Apply it in the Azure portal in this order, so you don't lock yourself out:

1. Confirm the prerequisites: Microsoft Entra ID P2, at least two multifactor authentication methods registered, and an [emergency access account](https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access) with permanent Global Administrator.
1. Go to *PIM* > *Azure resources* > your subscription > *Settings* > *Owner*. Set the activation duration to 4-8 hours, require multifactor authentication and a justification, don't require approval, and allow permanent eligible assignments.
1. Add an **eligible** `Owner` assignment for the operator on the subscription, and a standing `Reader` assignment.
1. Test activation and deactivation **before** removing any standing access.
1. Remove the operator's standing `Owner` assignment. Check inherited scopes too; it may be assigned on a management group such as the Tenant Root Group rather than on the subscription.
1. Remove the standing root-scope `User Access Administrator`: activate Global Administrator, then go to *Microsoft Entra ID* > *Properties* > *Access management for Azure resources* and select *No*. This grant persists after Global Administrator is deactivated, so it's easy to leave in place by accident.
1. Verify with read-only checks:

   ```bash
   OID=$(az ad signed-in-user show --query id -o tsv)
   SUB=$(az account show --query id -o tsv)
   az role assignment list --assignee "$OID" --scope "/subscriptions/$SUB" --include-inherited -o table
   az rest --method get --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Authorization/permissions?api-version=2022-04-01"
   ```

   With `Owner` active, the permissions output includes an `"actions": ["*"]` entry. With only standing access, the only entry is `*/read`.

Things to know:

* Activate Azure resource roles, such as subscription `Owner`, in the Azure portal under *PIM* > *My roles* > *Azure resources*. The Microsoft Entra admin center's PIM pages show only Microsoft Entra roles and groups.
* You don't need a new `az login` after activating an Azure RBAC role. Azure Resource Manager evaluates role assignments on each request, so allow about a minute for propagation. Microsoft Entra directory roles and PIM for Groups do need a new token.
* PIM may not prompt for multifactor authentication on activation if the portal session already has a multifactor authentication claim. Use a Conditional Access authentication context to require it on every activation.
* The *Check access* current view hides eligible assignments. Check the *Eligible assignments* tab.
* Recovery path: activate Global Administrator, turn on *Access management for Azure resources*, grant `Owner`, then turn it back off. The emergency access account is the last resort.
* Removing the operator's `Owner` assignment doesn't affect sandbox applies by a `managed_identity` deployment identity, which keeps standing `Contributor` plus the conditioned `Role Based Access Control Administrator` role. An `oidc` deployment identity has only standing `Reader`, so the operator activates `Owner` to grant its time-bound roles before each workflow run.
* In managed tenants, provider automation may re-add standing assignments, so check again after a day.

### State Backend Authentication

Provider authentication and state backend authentication are independent. Provider settings such as `auth_mode` affect only the providers. By default, Terraform state is stored locally. When an `azurerm` backend is configured in `backend.tf`, it authenticates with its own settings, for example the system-assigned managed identity of the rg-devops-iac Linux virtual machine (`use_msi = true` with `use_azuread_auth = true`).

## Documentation

This section provides documentation regarding the overall structure of the root module for this configuration. See the README.md files in each module directory for more information about that module.

* [Root Module Structure](#root-module-structure)
* [Root Module Input Variables](#root-module-input-variables)
* [Root Module Resources](#root-module-resources)
* [Child Modules](#child-modules)
* [Virtual Network Design](#virtual-network-design)
* [Dependencies](#dependencies)

### Root Module Structure

This configuration is organized into the following structure:

```plaintext
├── images/                               # 
│   └── rg-devops-iac-diagram.drawio.svg  # Architecture diagram
├── modules/                              # 
│   └── vm-jumpbox-linux/                 # Linux jumpbox virtual machine module
├── scripts/                              # 
│   ├── bootstrap.sh                      # Bash helper script for generating terraform.tfvars
│   ├── bootstrap.ps1                     # PowerShell helper script for generating terraform.tfvars
│   ├── cleanterraformtemp.sh             # Bash helper script for removing Terraform temp/local files
│   ├── connect-jumplinux2.sh             # Bash helper script for connecting to jumplinux2 through a Bastion tunnel with Entra ID
│   ├── Connect-Jumplinux2.ps1            # PowerShell helper script for connecting to jumplinux2 through a Bastion tunnel with Entra ID
│   ├── enable-public-access.sh           # Bash helper script for re-enabling public access on key vault/storage account (not the AMPLS or workspace)
│   ├── grant-graph-permissions.sh        # Bash helper script for granting Microsoft Graph permissions to a deployment identity
│   └── delete-tfstate.sh                 # Bash helper script for deleting Terraform state blob(s) from the storage backend
├── locals.tf                             # Local variables 
├── main.tf                               # Resource configurations
├── network.tf                            # Network resource blocks
├── outputs.tf                            # Output variables 
├── providers.tf                          # Provider configuration blocks
├── storage.tf                            # Storage resource blocks
├── terraform.tf                          # Terraform configuration block
└── variables.tf                          # Variable definitions
```

### Root Module Input Variables

This section lists input variables used in the root module. Defaults can be overridden by specifying a different value in terraform.tfvars.

Variable | Default | Description
--- | --- | ---
deployment_identity | `none` | The identity this configuration provisions for root sandbox deployments: `none`, `managed_identity` or `oidc`. `managed_identity` creates a user-assigned managed identity with standing `Contributor` and conditioned `Role Based Access Control Administrator` role assignments on the subscription and attaches it to `jumplinux2`, for root sandbox applies with `auth_mode = "managed_identity"`. See [Optional: Deployment Identity for Managed Identity Sandbox Applies](#optional-deployment-identity-for-managed-identity-sandbox-applies). `oidc` creates an unattached user-assigned managed identity with standing `Reader` on the subscription and GitHub Actions federated identity credentials, for workflow applies with `auth_mode = "oidc"` after the operator grants time-bound roles. See [Optional: Deployment Identity for OIDC Workflow Applies](#optional-deployment-identity-for-oidc-workflow-applies).
enable_github_runner | false | Set to true to install and register the GitHub Actions self-hosted runner agent on `jumplinux2`. See [vm-jumpbox-linux](./modules/vm-jumpbox-linux/README.md#github-actions-self-hosted-runner).
entra_tenant_id | | The Microsoft Entra tenant id.
github_oidc_environments | `["sandbox-deployment", "sandbox-release-gate"]` | The GitHub Actions environments allowed to federate to the deployment identity. One federated identity credential is created per environment. Only used when `deployment_identity` is `oidc`.
github_repository_id | | The numeric id of the repository whose workflows may federate to the deployment identity, e.g. from `gh api repos/OWNER/NAME --jq .id`. Only used when `deployment_identity` is `oidc`. When empty, it is looked up anonymously from the GitHub API using the repository in `github_runner_url`; set it for a private repository.
github_repository_owner_id | | The numeric id of the user or organization that owns the repository, e.g. from `gh api repos/OWNER/NAME --jq .owner.id`. Only used when `deployment_identity` is `oidc`. When empty, it is looked up anonymously from the GitHub API using the repository in `github_runner_url`; set it for a private repository.
github_runner_labels | `["azuresandbox"]` | Additional labels to apply to the GitHub Actions self-hosted runner. Only used when `enable_github_runner` is true.
github_runner_token | | A GitHub personal access token or runner registration token used to register the self-hosted runner. Set interactively or using an environment variable 'TF_VAR_github_runner_token'. Required when `enable_github_runner` is true.
github_runner_token_secret_version | 1 | Increment to write a new value for the GitHub runner token key vault secret.
github_runner_token_type | `pat` | The type of token supplied in `github_runner_token`, either `pat` or `registration`.
github_runner_url | | The GitHub repository or organization URL to register the self-hosted runner with, e.g. `https://github.com/myorg/myrepo`. Required when `enable_github_runner` is true. When `deployment_identity` is `oidc` and the repository ids are not set, it must be a repository URL; the ids are looked up from it.
location | | The name of the Azure Region where resources will be provisioned.
log_analytics_workspace_retention_days | 30 | The retention period in days for the Log Analytics workspace. Must be one of 30, 31, 60, 90, 120, 180, 270, 365, 550 or 730.
storage_access_tier | Hot | The access tier for the new storage account.
storage_replication_type | LRS | The type of replication for the new storage account.
subnet_bastion_address_prefix | 10.0.2.0/26 | The address prefix for the `AzureBastionSubnet`. Must be /26 or larger.
subnet_address_prefix | 10.0.0.0/24 | The address prefix for the miscellaneous subnet. The minimum size is /29.
subnet_name | snet-devops-01 | The name of the subnet to be created in the new virtual network.
subnet_privatelink_address_prefix | 10.0.1.0/24 | The address prefix for the PrivateLink subnet
subnet_privatelink_name | snet-privatelink-03 | The name of the subnet for PrivateLink endpoints
subscription_id | | The Azure subscription id used to provision resources.
storage_container_name | tfstate | The name of the storage container to be created in the new storage account.
tags | | The tags in map format to be used when creating new resources.
vm_jumpbox_linux_size | `Standard_D2ls_v6` | The size of the jumpbox virtual machine (`jumplinux2`).
vnet_address_space | 10.0.0.0/16 | The address space in CIDR notation for the new virtual network. The minimum size is /24.
vnet_name | devops | The name of the new virtual

### Root Module Resources

The root module includes a resource group, key vault and storage account used by the child modules. It also grants the operator who runs Terraform data-plane roles on the key vault and storage account.

Address | Name | Notes
--- | --- | ---
azapi_update_resource.ampls_disable_public_access | | Sets the AMPLS ingestion and query access modes to `PrivateOnly` after the AMPLS barrier.
azapi_update_resource.key_vault_disable_public_access | | Disables key vault public network access after the key vault barrier.
azapi_update_resource.log_analytics_disable_public_access | | Disables public ingestion and query on the Log Analytics workspace after the AMPLS barrier.
azapi_update_resource.storage_disable_public_access | | Disables storage account public network access after the storage barrier.
azurerm_bastion_host.this | snap-devops-dev | Azure Bastion host (Standard SKU, native client support enabled). The only inbound path to the Linux virtual machine.
azurerm_federated_identity_credential.deployment_identity_github[*] | github-sandbox-deployment, github-sandbox-release-gate | Trusts GitHub Actions OIDC tokens for the deployment identity, one per environment in `github_oidc_environments`. Created only when `deployment_identity` is `oidc`.
azurerm_key_vault.this | kv-devops-dev-xxx | Used to store secrets for the Linux virtual machine.
azurerm_log_analytics_workspace.this | log-devops-dev-xxx | Log Analytics workspace that receives diagnostic settings and Azure Monitor Agent data. Public ingestion and query are disabled by the AMPLS barrier.
azurerm_monitor_data_collection_endpoint.this | dce-devops-dev-xxx | Data collection endpoint used by the Azure Monitor Agent on `jumplinux2`. Scoped to the AMPLS.
azurerm_monitor_data_collection_rule.linux | dcr-devops-dev-linux | Linux data collection rule: syslog (`auth` and `authpriv` at `Info` and above, other facilities at `Warning` and above) and performance counters.
azurerm_monitor_diagnostic_setting.bastion | Diagnostic Logs | Sends `BastionAuditLogs` and metrics for the Bastion host to the workspace.
azurerm_monitor_diagnostic_setting.data_collection_rule_linux | Diagnostic Logs | Sends data collection errors (`allLogs`) and metrics for the Linux data collection rule to the workspace.
azurerm_monitor_diagnostic_setting.key_vault | Audit Logs | Sends key vault `audit` logs (including secret reads) and metrics to the workspace.
azurerm_monitor_diagnostic_setting.log_analytics | Diagnostic Logs | Sends workspace query `audit` logs and metrics to the workspace itself.
azurerm_monitor_diagnostic_setting.network_security_group_devops | Diagnostic Logs | Sends NSG event and rule counter logs (`allLogs`) to the workspace.
azurerm_monitor_diagnostic_setting.public_ip_bastion | Diagnostic Logs | Sends DDoS logs (`allLogs`) and metrics for the Bastion public IP to the workspace.
azurerm_monitor_diagnostic_setting.public_ip_nat | Diagnostic Logs | Sends DDoS logs (`allLogs`) and metrics for the NAT gateway public IP to the workspace.
azurerm_monitor_diagnostic_setting.storage_account | Diagnostic Logs | Sends storage account `Transaction` metrics to the workspace.
azurerm_monitor_diagnostic_setting.storage_blob | Diagnostic Logs | Sends blob service `StorageRead`, `StorageWrite` and `StorageDelete` logs (Terraform state access) and `Transaction` metrics to the workspace.
azurerm_monitor_diagnostic_setting.virtual_network | Diagnostic Logs | Sends virtual network logs (`allLogs`) and metrics to the workspace.
azurerm_monitor_private_link_scope.this | ampls-devops-dev | Azure Monitor Private Link Scope. Starts in `Open` mode and is set to `PrivateOnly` by the AMPLS barrier.
azurerm_monitor_private_link_scoped_service.dce | ampls-scope-dce | Adds the data collection endpoint to the AMPLS.
azurerm_monitor_private_link_scoped_service.log_analytics | ampls-scope-log-analytics | Adds the Log Analytics workspace to the AMPLS.
azurerm_nat_gateway.this | ng-devops-dev | NAT gateway for outbound internet connectivity.
azurerm_nat_gateway_public_ip_association.this | | Associates the NAT gateway with the public IP address.
azurerm_network_security_group.devops | nsg-devops-dev-snet-devops-01 | NSG that allows inbound SSH (port 22) to the Linux virtual machine only from the `AzureBastionSubnet`.
azurerm_private_dns_zone.ampls[*] | privatelink.monitor.azure.com, privatelink.oms.opinsights.azure.com, privatelink.ods.opinsights.azure.com, privatelink.agentsvc.azure-automation.net | Private DNS zones for the AMPLS private endpoint
azurerm_private_dns_zone.key_vault | privatelink.vaultcore.azure.net | Private DNS zone for Azure Key Vault
azurerm_private_dns_zone.storage_blob | privatelink.blob.core.windows.net | Private DNS zone for Azure blob storage
azurerm_private_dns_zone_virtual_network_link.ampls[*] | | Links the AMPLS private dns zones to azurerm_virtual_network.this
azurerm_private_dns_zone_virtual_network_link.key_vault | | Links private dns zone to azurerm_virtual_network.this
azurerm_private_dns_zone_virtual_network_link.storage_blob | | Links private dns zone to azurerm_virtual_network.this
azurerm_private_endpoint.ampls | pe-devops-dev-ampls | Private endpoint for the AMPLS (`azuremonitor` subresource)
azurerm_private_endpoint.key_vault | pe-devops-dev-key-vault | Private endpoint for Azure key vault
azurerm_private_endpoint.storage_blob | pe-devops-dev-storage-blob | Private endpoint for Azure blob storage
azurerm_public_ip.bastion | pip-devops-dev-bastion | Public IP address for the Bastion host.
azurerm_public_ip.this | pip-devops-dev-nat | Public IP address for the NAT gateway.
azurerm_resource_group.this | rg-devops-dev-xxx | Resource group for all resources in this configuration.
azurerm_role_assignment.key_vault_secrets_officer | | Assigns `Key Vault Secrets Officer` on the key vault to the operator signed in to Azure CLI.
azurerm_role_assignment.storage_blob_data_contributor | | Assigns `Storage Blob Data Contributor` on the storage account to the operator signed in to Azure CLI.
azurerm_role_assignment.deployment_identity_contributor[0] | | Assigns `Contributor` at the subscription scope to the deployment identity. Created only when `deployment_identity` is `managed_identity`.
azurerm_role_assignment.deployment_identity_rbac_admin[0] | | Assigns `Role Based Access Control Administrator` at the subscription scope to the deployment identity, with a condition that allows only the roles in `local.deployment_identity_assignable_roles`. Created only when `deployment_identity` is `managed_identity`.
azurerm_role_assignment.deployment_identity_reader[0] | | Assigns standing `Reader` at the subscription scope to the deployment identity. Created only when `deployment_identity` is `oidc`.
azurerm_storage_account.this | stdevopsdevxxx | Storage account for storing Terraform state files.
azurerm_storage_container.this | tfstate | Storage container for storing Terraform state files.
azurerm_subnet.bastion | AzureBastionSubnet | Subnet for the Bastion host. The name is required by Azure.
azurerm_subnet.devops | snet-devops-01 | Subnet for jumplinux2 VM
azurerm_subnet.privatelink | snet-privatelink-03 | Subnet for PrivateLink endpoints
azurerm_subnet_nat_gateway_association.devops | vnet-devops-dev-devops| Associates the NAT gateway with the subnet.
azurerm_subnet_network_security_group_association.this | | Associates the NSG with the subnet.
azurerm_user_assigned_identity.deployment[0] | uai-devops-dev-xxx | Deployment identity for root sandbox applies. Attached to `jumplinux2` when `deployment_identity` is `managed_identity`; unattached and federated with GitHub Actions when it is `oidc`. Not created when `deployment_identity` is `none`.
azurerm_virtual_network.this | vnet-devops-dev-devops | Virtual network for the Linux virtual machine.
terraform_data.ampls_access_barrier | | Waits for every Azure Monitor write (scoped services, private endpoint, DNS zone links, diagnostic settings, and the `jumplinux2` agent and associations) before the AMPLS and workspace are closed to public networks.
terraform_data.key_vault_access_barrier | | Waits for the key vault secret writes before key vault public access is disabled.
terraform_data.storage_access_barrier | | Waits for the storage container before storage account public access is disabled.

Diagnostic settings are not created for resources that don't support exporting logs or metrics through a diagnostic setting: the NAT gateway (its flow logs require the StandardV2 SKU), private endpoints, private DNS zones, the AMPLS, the data collection endpoint and the user-assigned managed identity. Their platform metrics remain available in Azure Monitor metrics explorer. The Linux virtual machine sends guest data through the Azure Monitor Agent instead of a diagnostic setting.

### Root Module Output Variables

This section includes a list of output variables returned by the root module.

Name | Comments
--- | ---
deployment_identity_client_id | The client id of the deployment identity, used as `client_id` for root sandbox applies with `auth_mode = "managed_identity"` or `"oidc"`, or `null` when `deployment_identity` is `none`.
deployment_identity_github_subjects | The GitHub OIDC subjects accepted by the deployment identity's federated identity credentials, keyed by environment, or an empty map unless `deployment_identity` is `oidc`.
deployment_identity_jit_condition | The condition (version 2.0) to apply to the deployment identity's time-bound `Role Based Access Control Administrator` assignment before each workflow run, or `null` unless `deployment_identity` is `oidc`.
deployment_identity_principal_id | The principal (object) id of the deployment identity, used to grant Microsoft Graph application permissions, or `null` when `deployment_identity` is `none`.
github_runner_name | The name the GitHub Actions self-hosted runner is registered with, or `null` when `enable_github_runner` is false.
resource_ids | A map of resource IDs for key resources in the configuration.
resource_names | A map of resource names for key resources in the configuration.

### Child Modules

The following [modules](./modules/) are included in this configuration:

Name | Required | Depends On | Description
--- | --- | --- | ---
[vm-jumpbox-linux](./modules/vm-jumpbox-linux/) | No | Root module | Creates a preconfigured Linux jumpbox VM in the DevOps virtual network.

### Virtual Network Design

This configuration implements a virtual network. Default address ranges are set artificially high for demos and readability and can be overridden with smaller ranges to meet specific requirements. An firewall is not included in this configuration by design as it may be used as an startup environment to provision a platform landing zone or sandbox that does include a firewall. The virtual network includes three subnets:

* A subnet for the Linux virtual machine. The subnet is configured with a NAT gateway for outbound internet connectivity and an NSG that allows inbound SSH only from the `AzureBastionSubnet`.
* A subnet for PrivateLink endpoints for Azure Key Vault, Azure Blob Storage and the Azure Monitor Private Link Scope (AMPLS)
* The `AzureBastionSubnet` for the Azure Bastion host, which is the only inbound path to the Linux virtual machine. The Linux virtual machine has no public IP address.

All private DNS zones are linked to the virtual network with `resolution_policy = "NxDomainRedirect"` (fallback to internet). This setting affects name resolution only: when a linked zone has no record for a name, Azure DNS resolves the name publicly instead of returning `NXDOMAIN`. It doesn't route traffic, and the target resource's own network settings still apply.

#### Observability network isolation

The AMPLS private endpoint changes how Azure Monitor endpoints resolve across the whole devops virtual network:

* Shared (global and regional) Azure Monitor endpoints, such as the `api` endpoint used for Log Analytics and Application Insights queries, have records in the `privatelink.monitor.azure.com` zone, so they always resolve to this AMPLS private endpoint.
* After the barrier sets the AMPLS to `PrivateOnly`, clients in the devops virtual network can reach only the Azure Monitor resources in this AMPLS through those shared endpoints.
* Names for Azure Monitor resources outside this AMPLS, such as a root sandbox workspace, fall back to public resolution and are governed by those resources' own public network settings.
* Don't link the AMPLS private DNS zones to any other virtual network, such as a root sandbox virtual network that has its own AMPLS.

After the barrier closes, the Log Analytics workspace accepts queries only from inside the devops virtual network, for example from `jumplinux2` using `az monitor log-analytics query`. Portal and Azure CLI queries from outside the virtual network fail. `./scripts/enable-public-access.sh` intentionally doesn't reopen the AMPLS or the workspace: it reopens only the key vault (secrets) and storage account (Terraform state). Terraform's Azure Monitor writes, such as diagnostic settings, use the Azure Resource Manager control plane and don't need public access.

**Cost note:** Log Analytics charges for data ingestion and for retention beyond the included period. The volume in this configuration is low: mostly key vault and blob audit events (every Terraform plan and apply reads the state blob), Bastion sign-ins, syslog and one-minute performance counters from one virtual machine. Use `log_analytics_workspace_retention_days` to control retention. See [Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/).

### Dependencies

This section covers the dependencies in this configuration.

* [Source Control](#source-control)
* [Terraform](#terraform)
* [Scripting Technologies](#scripting-technologies)
* [Continuous Integration / Continuous Delivery](#continuous-integration--continuous-delivery)
* [Configuration Management Technologies](#configuration-management-technologies)
* [Operating Systems](#operating-systems)

#### **Source Control**

The configuration is hosted on GitHub and uses Git for source control. The repository is organized into configurations and modules, making it easy to navigate and understand the structure of the project. The [vm-jumpbox-linux] module can be repurposed for use in other configurations.

#### **Terraform**

This project is built built using Terraform, a cross platform, open-source Infrastructure as Code (IaC) tool that allows users to define, provision and version cloud infrastructure using a declarative configuration language called HCL (HashiCorp Configuration Language).

* **Providers**: The following Terraform providers are used in the project:
  * **azurerm**: Used to manage Azure resources.
  * **cloudinit**: Used to configure Linux virtual machines.
  * **random**: Used to generate random values for resource attributes.
  * **time**: Used to implement wait cycles and other time based operations.
  * **tls**: Used to generate the break-glass SSH key pair for the Linux virtual machine's local admin account.
* **Modules**: The following Terraform modules are used in this project:
  * **Azure/naming**: A module for generating consistent and compliant Azure resource names.

#### **Scripting Technologies**

The following cross-platform scripting technologies are used in this project:

* **PowerShell**:  Used for general purpose scripting and to implement Terraform provisioners and Azure custom script extensions.
* **Az PowerShell Module**: Used to connect to and configure Azure resources from PowerShell scripts.
* **Bash**: Used for general purpose scripting.
* **Azure CLI**: Used for connecting to Azure resources from Bash scripts.

#### **Continuous Integration / Continuous Delivery**

* **GitHub Actions**: The Linux virtual machine can optionally be registered as a self-hosted runner so GitHub Actions workflows can execute Terraform from within the virtual network using the VM managed identity. Such workflows should store Terraform state in the `azurerm` backend hosted in the storage account provisioned by this configuration rather than in a local state file on the runner. See [vm-jumpbox-linux](./modules/vm-jumpbox-linux/README.md#github-actions-self-hosted-runner).

#### **Configuration Management Technologies**

The following configuration management technologies are used in this project to configure virtual machines:

* **cloud-init**: Used to configure Linux virtual machines.

#### **Operating Systems**

The following operating systems are used for the various virtual machines in the sandbox:

Virtual Machine | Role | Module | Operating System
--- | --- | --- | ---
jumplinux2 | Linux Jumpbox VM | vm-jumpbox-linux | Ubuntu Server LTS 24.04 (Nobel Numbat)
