# Linux Jumpbox Virtual Machine Module (vm-jumpbox-linux)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [GitHub Actions Self-Hosted Runner](#github-actions-self-hosted-runner)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vm-jumpbox-linux-diagram](./images/vm-jumpbox-linux-diagram.drawio.svg)

## Overview

This module implements a stand-alone Linux virtual machine for use as a jumpbox or DevOps agent. The VM is configured using cloud-init and offers the following capabilities:

* No public IP address. Access is through Azure Bastion using Microsoft Entra ID sign-in with short-lived OpenSSH certificates (`AADSSHLoginForLinux` extension). A local admin SSH key is stored in Azure Key Vault for break-glass use only.
* Automatic swapfile provisioning sized to the VM's memory (larger VMs get no swap).
* Remote-ssh development capabilities using Visual Studio Code through a Bastion tunnel.
* Azure PowerShell is installed from the latest GitHub release offline bundle, with Microsoft Artifact Registry as a fallback. Installation metadata points to PSGallery for subsequent PowerShell 7 upgrades using `Update-PSResource -Name Az -Scope AllUsers`.
* Pre-installed software packages, including:
  * azure-cli
  * jp
  * powershell
  * python3-pip
  * terraform
* Pre-configured environment variables for using Azure Blob Storage as a Terraform state backend.
* Security patching using `unattended-upgrades`. A full package upgrade is not performed during provisioning, so provisioning does not depend on every package on the image being downloadable and does not trigger a mid-provisioning reboot.
* Apt is pinned to the Canonical `archive.ubuntu.com` and `security.ubuntu.com` servers rather than the Azure regional mirror.
* Optional registration as a [GitHub Actions self-hosted runner](#github-actions-self-hosted-runner), disabled by default.
* Azure Monitor Agent (`AzureMonitorLinuxAgent` extension) associated with the root module's Linux data collection rule and data collection endpoint, sending syslog (including SSH sign-in and `sudo` activity) and performance counters to the root module's Log Analytics workspace through the AMPLS private endpoint. The agent is installed after the `AADSSHLoginForLinux` extension, so the two installs don't contend for the apt and dpkg locks.

## GitHub Actions Self-Hosted Runner

This module can optionally install and register the [GitHub Actions runner](https://github.com/actions/runner) agent on the VM so it can be used as a self-hosted runner for CI/CD workflows. This capability is **disabled by default**: when `enable_github_runner` is `false` nothing is installed and the VM behaves exactly as it did before.

When `enable_github_runner` is `true`:

* The GitHub personal access token (PAT) or runner registration token is stored as a **write-only** key vault secret (`value_wo`), so it is never written to Terraform state. It is also never written to the VM custom data.
* The VM managed identity is granted the `Key Vault Secrets User` role, and cloud-init reads the secret from key vault at provisioning time using that managed identity.
* When `github_runner_token_type` is `pat` (the default), the PAT is exchanged on the VM for a short lived runner registration token using the GitHub REST API. Use `registration` instead if you already have a registration token.
* The runner agent is installed to `/opt/actions-runner`, registered with the configured repository or organization URL and labels, then installed as a **systemd service** (`actions.runner.*`) so it starts automatically after a reboot.
* The service runs under a non-root local service account (`githubrunner` by default). The pre-installed toolchain (`terraform`, `az`, `pwsh` with Az modules) is on the runner `PATH`, and `ARM_USE_MSI` / `ARM_TENANT_ID` are set in the runner service environment file (`/opt/actions-runner/.env`) so workflows authenticate to Azure with the VM managed identity. No Azure secrets are stored on the VM.

### Terraform State for CD Workflows

Workflows running on this self-hosted runner should **always** use the `azurerm` backend hosted in the
storage account provisioned by the root module. A runner is disposable infrastructure, so a local
state file on it is an anti-pattern:

* **Locking.** The `azurerm` backend takes a blob lease, so concurrent workflow runs - or a workflow
  run and an interactive `terraform apply` on the same VM - cannot corrupt state. A local state file
  has no lock beyond a single Terraform invocation.
* **Durability.** The VM is replaceable. Resizing, reimaging or recreating it destroys anything held
  only on the OS disk, including a local state file. Blob storage supports versioning and soft delete.
* **Secrets at rest.** Terraform state contains sensitive values. In the backend it is encrypted,
  scoped by Azure RBAC and reachable only over the storage account private endpoint. On the VM it is a
  plain file readable by the runner service account and by anything that compromises a workflow job.
* **Shared source of truth.** Interactive runs on the VM and CD runs operate on the same state instead
  of diverging.

The VM managed identity is already granted `Storage Blob Data Contributor` on the storage account, so
no secrets are required:

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

```yaml
- uses: actions/checkout@v5

- run: terraform init

- run: terraform apply -auto-approve
```

Because the runner always uses a remote backend, this module deliberately does **not** provision a
persistent local state directory on the VM. Nothing a workflow writes to the runner work directory is
guaranteed to survive the next job, since `actions/checkout` cleans the workspace by default.

Local state is only used during the **bootstrap apply of this configuration**, which is a separate
concern: that apply creates the storage account, so the backend does not exist yet and the state file
has to live on the Terraform execution environment running the apply - a workstation or an existing
Terraform execution environment, never this runner, which does not exist until that apply completes.
See the root [README](../../README.md) for details.

### Token Permissions

Use a *fine-grained* personal access token. Classic personal access tokens are legacy, cannot be scoped as narrowly, and may be blocked by organization or enterprise policy.

The PAT supplied in `github_runner_token` is only used to obtain a registration token and requires:

* For a repository runner: *Repository permissions* -> **Administration: Read and write** (`administration:write`), with *Repository access* set to *Only select repositories* and the target repository selected.
* For an organization runner: *Organization permissions* -> **Self-hosted runners: Read and write** (`organization_self_hosted_runners:write`) on the target organization.

A token that is missing these permissions returns `403 Resource not accessible by personal access token` when exchanging the PAT for a registration token.

Grant no other permissions. The PAT is stored as a write-only key vault secret, read at boot by the virtual machine's managed identity, and exchanged for a short lived registration token. The runner agent itself never uses the PAT. Note that the PAT is long lived and must be rotated manually.

### Runner Scope

The registration scope is derived from `github_runner_url`:

Scope | Example `github_runner_url` | Notes
--- | --- | ---
Repository | `https://github.com/myorg/myrepo` | Runner groups are not supported, so `github_runner_group` is ignored.
Organization | `https://github.com/myorg` | `github_runner_group` is passed to the registration and must already exist.

Runner groups are an organization and enterprise feature. Passing a runner group when registering a repository level runner fails with `Could not find any self-hosted runner group named ...`, so the configuration script omits it automatically for repository runners.

### Elevated Permissions for Integration Tests

The runner service account is unprivileged. The `vwan` integration tests in [Test-Integration-VwanConnectivity.ps1](../../../../../scripts/Test-Integration-VwanConnectivity.ps1) establish a point-to-site VPN tunnel, which requires root to create the `tun` device and update the routing table.

When `github_runner_enable_vwan_sudoers` is true (the default), the configuration script installs a command scoped sudoers drop-in at `/etc/sudoers.d/azuresandbox-github-runner` granting the runner service account passwordless `sudo` for only the binaries those tests invoke: `openvpn`, `cat`, `tail`, `kill` and `pkill`. The drop-in is written with `0440` permissions, owned by `root`, and validated with `visudo -cf` before it takes effect. If validation fails it is removed and cloud-init fails rather than leaving `sudo` broken.

**IMPORTANT:** This is a privilege grant. Passwordless root `cat`, `tail`, `kill` and `pkill` allow the runner service account to read any file on the VM and signal any process, which means any workflow job that runs on this runner inherits that capability. Set `github_runner_enable_vwan_sudoers` to `false` if the runner will not execute the `vwan` integration tests.

## Smoke Testing

This section describes how to connect to *jumplinux2* and test the module after deployment.

* [Connection paths](#connection-paths)
  * [1. Azure Bastion with Microsoft Entra ID](#1-azure-bastion-with-microsoft-entra-id)
  * [2. SSH and Visual Studio Code through a Bastion tunnel with Microsoft Entra ID](#2-ssh-and-visual-studio-code-through-a-bastion-tunnel-with-microsoft-entra-id)
  * [3. Break-glass: Azure Bastion with the local admin account](#3-break-glass-azure-bastion-with-the-local-admin-account)
* [Verify the cloud-init configuration](#verify-the-cloud-init-configuration)
* [Verify the GitHub Actions self-hosted runner](#verify-the-github-actions-self-hosted-runner)

### Connection paths

*jumplinux2* has no public IP address. All access goes through the Azure Bastion host (Standard SKU, native client support enabled) provisioned by the root module, and the network security group only allows SSH from the `AzureBastionSubnet`. Operators sign in as their own Microsoft Entra ID identity using short-lived OpenSSH certificates. The local admin account (`devopsbootstrapadmin`) and its SSH key in Key Vault are reserved for break-glass use.

Use the connection paths in the following order of preference.

Prerequisites on the client:

* Azure CLI signed in with `az login`, with the `bastion` and `ssh` extensions installed:

  ```bash
  az extension add --name bastion
  az extension add --name ssh
  ```

* The *Virtual Machine Administrator Login* role on *jumplinux2*, which this module assigns to the operator that applies the configuration, and at least *Reader* on the VM, its network interface and the Bastion host. Users with *Virtual Machine Administrator Login* can run `sudo` without a password. Microsoft Entra ID authentication happens at `az login`, including multifactor authentication and Conditional Access, before the SSH certificate is issued.
* The resource names used below are available from the root module outputs, for example `terraform output -json resource_names` and `terraform output -json resource_ids`.

Operators sign in with their Microsoft Entra user principal name, and a home directory is created on first sign-in. Use `sudo` for root access.

#### 1. Azure Bastion with Microsoft Entra ID

Opens an interactive terminal session directly, with no tunnel or `~/.ssh/config` to manage:

```bash
az network bastion ssh \
  --name BASTION-NAME-HERE \
  --resource-group RESOURCE-GROUP-NAME-HERE \
  --target-resource-id VM-RESOURCE-ID-HERE \
  --auth-type AAD
```

Microsoft Entra ID authentication requires targeting the VM resource ID; IP-based Bastion connections are not supported.

#### 2. SSH and Visual Studio Code through a Bastion tunnel with Microsoft Entra ID

This is the path for Visual Studio Code Remote-SSH and any other OpenSSH client. Run the helper script from the root module directory: [connect-jumplinux2.sh](../../scripts/connect-jumplinux2.sh) on Linux, macOS or WSL, or [Connect-Jumplinux2.ps1](../../scripts/Connect-Jumplinux2.ps1) on Windows:

```bash
./scripts/connect-jumplinux2.sh
```

```powershell
./scripts/Connect-Jumplinux2.ps1
```

The script:

* Reads the Bastion host, resource group and VM resource ID from the Terraform outputs. Override them with `--bastion-name`, `--resource-group` and `--vm-id` (`-BastionName`, `-ResourceGroupName` and `-VmId` in PowerShell) when the state isn't available locally.
* Requests a Microsoft Entra ID OpenSSH certificate with `az ssh cert`, using a dedicated RSA key pair in `~/.ssh/az_ssh_config/jumplinux2/`.
* Writes a managed `Host jumplinux2` block to `~/.ssh/config` pointing at `127.0.0.1` on the local tunnel port (default `2222`). Re-running the script replaces the block rather than duplicating it.
* Opens `az network bastion tunnel` to the VM in the foreground.

**Keep the script's terminal open while connected, because it hosts the Bastion tunnel.** Press *Ctrl+C* to close the tunnel. Certificates are valid for about an hour, so the script renews the certificate about every 50 minutes while the tunnel is up. Sessions that are already connected keep working when a certificate expires. If renewal fails, for example because the `az login` session expired, run `az login` and restart the script.

Then connect from another terminal or from Visual Studio Code:

* Terminal: `ssh jumplinux2`
* Visual Studio Code:
  * Click on the blue *Open a Remote Window* icon in the lower left corner.
  * Choose *Connect to Host...* and select *jumplinux2*.
  * For *Select the platform of the remote host "jumplinux2"* choose *Linux*.
  * For *"jumplinux2" has fingerprint...* choose *Continue*.
  * Verify that *SSH: jumplinux2* is displayed in the status bar, then use *View* > *Explorer* > *Open Folder* to open your home directory.

The host key is stored in `known_hosts` under the alias `jumplinux2`. If the VM is redeployed, remove the stale entry with `ssh-keygen -R jumplinux2` before reconnecting.

To set up the tunnel manually instead of using the script, run `az network bastion tunnel --name BASTION-NAME-HERE --resource-group RESOURCE-GROUP-NAME-HERE --target-resource-id VM-RESOURCE-ID-HERE --resource-port 22 --port 2222`, then in another terminal run `az ssh cert --file ~/.ssh/jumplinux2/id_rsa-cert.pub`, which generates a key pair in the same directory, and connect with `ssh -p 2222 -i ~/.ssh/jumplinux2/id_rsa -o CertificateFile=~/.ssh/jumplinux2/id_rsa-cert.pub YOUR-UPN-HERE@127.0.0.1`.

##### Integration tests that need `sudo`

The `vwan` point-to-site VPN integration tests run privileged commands (`openvpn`, `cat`, `tail`, `kill`, `pkill`) and probe for passwordless `sudo` with `sudo -n cat /dev/null`. An operator signed in through Microsoft Entra ID with *Virtual Machine Administrator Login* already has passwordless `sudo`, so interactive `Invoke-UnitTests.ps1` runs with `vwan` enabled work without the hand-made `/etc/sudoers.d/azuresandbox-vwan` drop-in, which was only needed for the local admin account. The runner service account's drop-in, installed by cloud-init when `github_runner_enable_vwan_sudoers` is true, is unchanged. See [Elevated Permissions for Integration Tests](#elevated-permissions-for-integration-tests).

#### 3. Break-glass: Azure Bastion with the local admin account

Use this path only when Microsoft Entra ID sign-in fails, for example if the `AADSSHLoginForLinux` extension is broken or Microsoft Entra ID is unavailable. The username and SSH private key for the local admin account are stored in Key Vault as the `adminuser` and `jumplinux2-ssh-private-key` secrets.

Key Vault public network access is disabled by the root module after each apply, so retrieving the secrets requires reopening it, which needs an elevated (for example PIM-activated) role:

1. From the root module directory, run `./scripts/enable-public-access.sh`.
1. Retrieve the secrets:

   ```bash
   KV_NAME=KEY-VAULT-NAME-HERE
   ADMIN_USER=$(az keyvault secret show --vault-name "$KV_NAME" --name adminuser --query value -o tsv)
   (umask 077 && az keyvault secret show --vault-name "$KV_NAME" --name jumplinux2-ssh-private-key --query value -o tsv > ~/.ssh/jumplinux2-break-glass.pem)
   ```

1. Connect through Bastion:

   ```bash
   az network bastion ssh \
     --name BASTION-NAME-HERE \
     --resource-group RESOURCE-GROUP-NAME-HERE \
     --target-resource-id VM-RESOURCE-ID-HERE \
     --auth-type ssh-key \
     --username "$ADMIN_USER" \
     --ssh-key ~/.ssh/jumplinux2-break-glass.pem
   ```

1. When finished, delete the local key file (`rm ~/.ssh/jumplinux2-break-glass.pem`) and run `terraform apply` from the root module to disable Key Vault public network access again.

The key vault secrets expire one year after creation. The key is not rotated automatically; `admin_ssh_key` is set when the VM is created, so generating a new key (`terraform apply -replace=module.vm_jumpbox_linux.tls_private_key.ssh_key` with an incremented `ssh_private_key_version`) also replaces the VM. Audit logging and alerting for break-glass key retrieval are tracked in [#896](https://github.com/Azure-Samples/azuresandbox/issues/896).

If Bastion itself is unavailable, use the Azure-native recovery options instead: reset access with `az vm user update` (VMAccess extension), run commands with `az vm run-command invoke`, or use the Serial Console.

### Verify the cloud-init configuration

After connecting, verify the *jumplinux2* cloud-init configuration is complete using the following commands:

```bash
# Check software versions
lsb_release -a
az --version
terraform --version
pwsh --version
pwsh -c "Get-InstalledModule Az"

# Check Terraform environment variables
echo $ARM_USE_MSI
echo $ARM_TENANT_ID
```

### Verify the GitHub Actions self-hosted runner

Only applicable when `enable_github_runner` is set to `true`.

* Connect to *jumplinux2* using one of the [connection paths](#connection-paths) described above.
* Verify the runner agent was installed and registered:

  ```bash
  # Review the cloud-init output for the runner configuration script
  sudo grep configure-github-runner /var/log/cloud-init-output.log

  # Confirm the runner is registered
  sudo cat /opt/actions-runner/.runner

  # Confirm the runner service is installed and running
  sudo systemctl status 'actions.runner.*'

  # Confirm the runner service environment
  sudo cat /opt/actions-runner/.env
  ```

* Navigate to the target repository or organization on GitHub > *Settings* > *Actions* > *Runners* and verify that a runner named *jumplinux2* is listed with an *Idle* status and the expected labels.

## Documentation

This section provides additional information on various aspects of this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Output Variables](#output-variables)

### Dependencies

This module depends upon resources provisioned in the following modules:

* Root module

### Module Structure

This module is organized as follows:

```plaintext
├── images/
|   └── vm-jumpbox-linux-diagram.drawio.svg # Architecture diagram
├── scripts/
|   ├── configure-github-runner.sh          # cloud-init shell script to install/register the GitHub Actions runner
|   ├── configure-github-runner.yaml        # cloud-init cloud-config file with GitHub Actions runner settings
|   ├── configure-powershell.ps1            # cloud-init shell script to configure PowerShell
|   ├── configure-vm-jumpbox-linux.yaml     # cloud-init cloud-config file to configure the VM
|   └── wait-for-cloud-init.sh              # Managed Run Command completion and package-manager wait
├── compute.tf                              # Compute resource configurations
├── main.tf                                 # Resource configurations
├── network.tf                              # Network resource configurations
├── outputs.tf                              # Output variables
├── terraform.tf                            # Terraform configuration block
└── variables.tf                            # Input variables
```

### Input Variables

This section lists the default values for the input variables used in this module. Defaults can be overridden by specifying a different value in the root module.

Variable | Default | Description
--- | --- | ---
admin_username | `devopsbootstrapadmin` | The user name for the admin account on the VM.
admin_username_secret | adminuser | The name of the key vault secret that contains the user name for the break-glass admin account.
data_collection_endpoint_id | | The ID of the data collection endpoint (DCE) defined in the root module, associated with the VM.
data_collection_rule_linux_id | | The ID of the Linux data collection rule (DCR) defined in the root module, associated with the VM.
enable_github_runner | false | When enabled the GitHub Actions self-hosted runner agent is installed on the VM and registered with the repository or organization specified in `github_runner_url`. When disabled nothing is installed.
github_runner_enable_vwan_sudoers | `true` | Set to true to grant the runner service account command scoped passwordless sudo for the binaries used by the `vwan` point-to-site VPN integration tests. Only used when `enable_github_runner` is true.
github_runner_group | `Default` | The name of the GitHub Actions runner group to register the runner with. Ignored for repository level runners, which do not support runner groups. Only used when `enable_github_runner` is true.
github_runner_labels | `["azuresandbox"]` | Additional labels to apply to the self-hosted runner. Only used when `enable_github_runner` is true.
github_runner_name | | The name to register the runner with. Defaults to the VM name when left empty. Only used when `enable_github_runner` is true.
github_runner_service_account | `githubrunner` | The name of the non-root local service account the runner runs under. Only used when `enable_github_runner` is true.
github_runner_token | | A GitHub personal access token or runner registration token used to register the runner. Set using an environment variable `TF_VAR_github_runner_token`. Required when `enable_github_runner` is true. Stored as a write-only key vault secret so it never lands in Terraform state.
github_runner_token_secret | `github-runner-token` | The name of the key vault secret used to pass the GitHub registration token to the VM at provisioning time.
github_runner_token_secret_version | 1 | Increment to write a new value for the `github_runner_token` key vault secret.
github_runner_token_type | `pat` | The type of token supplied in `github_runner_token`. Use `pat` for a personal access token, which is exchanged for a short lived registration token on the VM, or `registration` for a registration token obtained from the GitHub API.
github_runner_url | | The GitHub repository or organization URL to register the runner with, e.g. `https://github.com/myorg/myrepo`. Required when `enable_github_runner` is true.
github_runner_version | `2.338.0` | The version of the GitHub Actions runner agent to install, without the leading `v`.
key_vault_id | | The ID of the key vault defined in the root module.
key_vault_name | | The name of the key vault defined in the root module. Used by cloud-init to read secrets from the VM using the managed identity.
location | | The Azure region where the resources will be created. Defined in the root module.
log_analytics_workspace_id | | The ID of the Log Analytics workspace defined in the root module. Receives the network interface metrics.
resource_group_name | | The name of the resource group defined in the root module.
ssh_private_key_version | 1 | Increment to rewrite the break-glass `ssh_private_key` key vault secret, for example after replacing `tls_private_key.ssh_key`.
storage_account_id | | The resource ID of of the storage account defined in the root module.
subnet_id | | The resource ID of the subnet where the VM will be deployed. Defined in the vnet-shared module.
tags | | The tags from the root module.
user_assigned_identity_ids | `[]` | The resource ids of user-assigned managed identities to attach to the VM in addition to its system-assigned identity, which remains the default identity on the VM.
vm_jumpbox_linux_image_offer | `ubuntu-24_04-lts` | The offer type of the virtual machine image used to create the VM.
vm_jumpbox_linux_image_publisher | `Canonical` | The publisher for the virtual machine image used to create the VM.
vm_jumpbox_linux_image_sku | `server` | The SKU of the virtual machine image used to create the VM.
vm_jumpbox_linux_image_version | `Latest` | The version of the virtual machine image used to create the VM.
vm_jumpbox_linux_name | jumplinux2 | The name of the VM.
vm_jumpbox_linux_size | | The size of the virtual machine.
vm_jumpbox_linux_storage_account_type | `StandardSSD_LRS` | The storage type to be used for the VM's OS disk. Standard HDD (`Standard_LRS`) is not permitted because Azure is retiring Standard HDD OS disks on September 8, 2028.

### Module Resources

This section lists the resources included in this configuration.

Address | Name | Notes
--- | --- | ---
module.vm_jumpbox_linux.azurerm_key_vault_secret.adminuser | adminuser | The Key Vault secret containing the break-glass admin username for the Linux virtual machine.
module.vm_jumpbox_linux.azurerm_key_vault_secret.github_runner_token[0] | github&#8209;runner&#8209;token | The write-only Key Vault secret containing the GitHub registration token, created only when `var.enable_github_runner` is enabled. The value is never stored in Terraform state.
module.vm_jumpbox_linux.azurerm_key_vault_secret.ssh_private_key | jumplinux2&#8209;ssh&#8209;private&#8209;key | The break-glass private SSH key for the admin account, stored in Azure Key Vault.
module.vm_jumpbox_linux[0].azurerm_linux_virtual_machine.this | jumplinux2 | The Linux virtual machine resource.
module.vm_jumpbox_linux[0].azurerm_network_interface.this | nic&#8209;devops&#8209;dev&#8209;jumplinux2 | The network interface associated with the Linux virtual machine.
module.vm_jumpbox_linux.azurerm_monitor_data_collection_rule_association.dce | configurationAccessEndpoint | Associates the VM with the data collection endpoint so the Azure Monitor Agent retrieves its configuration through the AMPLS private endpoint.
module.vm_jumpbox_linux.azurerm_monitor_data_collection_rule_association.dcr | dcr&#8209;devops&#8209;dev&#8209;jumplinux2&#8209;association | Associates the VM with the Linux data collection rule.
module.vm_jumpbox_linux.azurerm_monitor_diagnostic_setting.network_interface | Diagnostic Logs | Sends network interface metrics to the Log Analytics workspace.
module.vm_jumpbox_linux.azurerm_role_assignment.operator_vm_admin_login | | Grants `Virtual Machine Administrator Login` role on jumplinux2 to the operator applying the configuration, enabling Microsoft Entra ID SSH sign-in with passwordless `sudo`.
module.vm_jumpbox_linux.azurerm_role_assignment.github_runner_key_vault[0] | | Grants `Key Vault Secrets User` role to the managed identity of jumplinux2 so cloud-init can read the GitHub registration token. Created only when `var.enable_github_runner` is enabled.
module.vm_jumpbox_linux.azurerm_role_assignment.this | | Grants `Storage Blob Data Contributor` role to the managed identity of jumplinux2. This is intended to be used for accessing a Terraform state backend hosted in Azure Blob Storage.
module.vm_jumpbox_linux.azurerm_virtual_machine_extension.aad_ssh_login | | The `AADSSHLoginForLinux` extension that enables Microsoft Entra ID SSH sign-in. Installed after `wait_for_cloud_init` to avoid apt lock contention.
module.vm_jumpbox_linux.azurerm_virtual_machine_extension.ama | AzureMonitorLinuxAgent | The Azure Monitor Agent. Installed after `aad_ssh_login` to avoid apt lock contention.
module.vm_jumpbox_linux.azurerm_virtual_machine_run_command.wait_for_cloud_init | | Waits for cloud-init termination and dpkg/apt idle checks, with or without the optional runner.
module.vm_jumpbox_linux.terraform_data.log_analytics_operations_complete | | Dependency signal for the root module's AMPLS barrier.
module.vm_jumpbox_linux.tls_private_key.ssh_key | | The break-glass SSH key pair for the admin account.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Description
--- | ---
github_runner_name | The name the GitHub Actions self-hosted runner is registered with, or `null` when `var.enable_github_runner` is false.
log_analytics_operations_complete | Dependency signal: the Azure Monitor Agent, the data collection rule and endpoint associations, and the network interface diagnostic setting are complete. Consumed by the root module's `ampls_access_barrier`.
resource_ids | A map of resource IDs for key resources in the module.
resource_names | A map of resource names for key resources in the module.
