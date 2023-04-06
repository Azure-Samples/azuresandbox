# \#AzureSandbox - terraform-azurerm-vm-devops

**Contents**

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Next steps](#next-steps)

## Architecture

![vm-devops-diagram](./vm-devops-diagram.drawio.svg)

## Overview

This configuration implements a collection of identical [IaaS](https://azure.microsoft.com/overview/what-is-iaas/) [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) designed to be used as DevOps agents by [Azure Pipelines](https://learn.microsoft.com/azure/devops/pipelines/get-started/what-is-azure-pipelines?view=azure-devops) or [Github Actions](https://docs.github.com/en/actions).

Activity | Estimated time required
--- | ---
Pre-configuration | ~5 minutes
Provisioning | ~10 minutes
Smoke testing | ~5 minutes

## Before you start

[terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app) must be provisioned first before starting. This configuration is optional and can be skipped to reduce costs. Proceed with [terraform-azurerm-vm-mssql](../terraform-azurerm-vm-mssql) if you wish to skip it.

## Getting started

This section describes how to provision this configuration using default settings.

* Change the working directory.

  ```bash
  cd ~/azuresandbox/terraform-azurerm-vm-devops
  ```

* Add an environment variable containing the password for the service principal.

  ```bash
  export TF_VAR_arm_client_secret=YourServicePrincipalSecret
  ```

* Run [bootstrap.sh](./bootstrap.sh) using the default settings or custom settings.

  ```bash
  ./bootstrap.sh
  ```

* Apply the Terraform configuration.

  ```bash
  # Initialize terraform providers
  terraform init

  # Validate configuration files
  terraform validate

  # Review plan output
  terraform plan

  # Apply configuration
  terraform apply
  ```

* Monitor output. Upon completion, you should see a message similar to the following:

  `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

* Verify *devopswin* node configurations are compliant.
  * Wait for 15 minutes to proceed to allow time for DSC configurations to complete.
  * From the client environment, navigate to *portal.azure.com* > *Automation Accounts* > *auto-xxxxxxxxxxxxxxxx-01* > *Configuration Management* > *State configuration (DSC)*.
  * Refresh the data on the *Nodes* tab and verify that all nodes are compliant.
  * Review the data in the *Configurations* and *Compiled configurations* tabs as well.
* From *jumpwin1*, test DNS queries for one or more of the DevOps agent VMs
  * Using Windows PowerShell, run the command:

    ```powershell
    Resolve-DnsName devopswin1
    ```

  * Verify the IPAddress returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-app-01"]*, e.g. `10.2.0.*`.
  * Note: This DNS query is resolved by the DNS Server running on *azurerm_windows_virtual_machine.vm_adds*.

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a *terraform.tfvars* file for generating and applying Terraform plans. For simplified deployment, several runtime defaults are initialized using output variables stored in the *terraform.tfstate* file associated with the [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared;) and [terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app/) configurations, including:

Output variable | Sample value
--- | ---
aad_tenant_id | "00000000-0000-0000-0000-000000000000"
adds_domain_name | "mysandbox.local"
admin_password_secret | "adminpassword"
admin_username_secret | "adminuser"
arm_client_id | "00000000-0000-0000-0000-000000000000"
automation_account_name | "auto-9a633c2bba9351cc-01"
key_vault_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.KeyVault/vaults/kv-XXXXXXXXXXXXXXX"
key_vault_name | "kv-XXXXXXXXXXXXXXX"
location | "eastus"
resource_group_name | "rg-sandbox-01"
storage_container_name | "scripts"
subscription_id | "00000000-0000-0000-0000-000000000000"
tags | tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )
vnet_app_01_subnets | Contains all the subnet definitions including *snet-app-01*, *snet-db-01*, *snet-mysql-01* and *snet-privatelink-01*.

Configuration of [Azure Automation State Configuration (DSC)](https://learn.microsoft.com/azure/automation/automation-dsc-overview) is performed by [configure-automation.ps1](./configure-automation.ps1) including the following:

* Configures [Azure Automation shared resources](https://learn.microsoft.com/azure/automation/automation-intro#shared-resources) including:
  * Imports [DSC Configurations](https://learn.microsoft.com/azure/automation/automation-dsc-getting-started#create-a-dsc-configuration) used in this configuration.
    * [DevOpsAgentConfig.ps1](./DevOpsAgentConfig.ps1): domain joins a Windows Server virtual machine and adds it to a `DevOpsAgents` security group, then configures it as a DevOps agent.
  * [Compiles DSC Configurations](https://learn.microsoft.com/azure/automation/automation-dsc-compile) so they can be used later to [Register a VM to be managed by State Configuration](https://learn.microsoft.com/azure/automation/tutorial-configure-servers-desired-state#register-a-vm-to-be-managed-by-state-configuration).

### Terraform Resources

This section lists the resources included in this configuration.

#### Devops agent virtual machines

The configuration for these resources can be found in [020-vm-devops-win.tf](./020-vm-devops-win.tf). There will can be multiple VMs and network interfaces provisioned depending upon user input in [bootstrap.sh](./bootstrap.sh)

Resource name (ARM) | Notes
--- | ---
azurerm_windows_virtual_machine . vm_devops_win["devopswin1"] (devopswin1) | By default, provisions a [Standard_B2s](https://learn.microsoft.com/azure/virtual-machines/sizes-b-series-burstable) virtual machine for use as a database server. See below for more information.
azurerm_network_interface . vm_devops_win_nic["devopswin1"] (nic&#x2011;devopswin1) | The configured subnet is *azurerm_subnet.vnet_app_01_subnets["snet-app-01"]*.

* [020-vm-devops-win.tf](./020-vm-devops-win.tf) can provision a configurable number of DevOps agent VMs.
* Guest OS: Windows Server 2022 Datacenter.
* By default the [patch orchestration mode](https://learn.microsoft.com/azure/virtual-machines/automatic-vm-guest-patching#patch-orchestration-modes) is set to `AutomaticByPlatform`.
* *admin_username* and *admin_password* are configured using key vault secrets *adminuser* and *adminpassword*.
* This resource is configured using a [provisioner](https://www.terraform.io/docs/language/resources/provisioners/syntax.html) that runs [aadsc-register-node.ps1](./aadsc-register-node.ps1) which registers the node with *azurerm_automation_account.automation_account_01* and applies the configuration [DevOpsAgentConfig.ps1](../terraform-azurerm-vnet-shared/DevOpsAgentConfig.ps1).
  * The virtual machine is domain joined and added to `DevOpsAgents` security group.
  * The following [Remote Server Administration Tools (RSAT)](https://learn.microsoft.com/windows-server/remote/remote-server-administration-tools) are installed:
    * Active Directory module for Windows PowerShell (RSAT-AD-PowerShell)
  * The following software packages are pre-installed using [Chocolatey](https://chocolatey.org/why-chocolatey):
    * [vscode](https://community.chocolatey.org/packages/vscode)
    * [microsoft-build-tools](https://community.chocolatey.org/packages/microsoft-build-tools)
    * [svn](https://community.chocolatey.org/packages/svn)
* Note that no [Azure Pipelines agents](https://learn.microsoft.com/azure/devops/pipelines/agents/agents?view=azure-devops&tabs=browser) are installed due to dependencies on Azure DevOps.
* Note that no [Self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners) are installed doe to dependencies on GitHub Actions.

## Next steps

Move on to the next configuration [terraform-azurerm-vm-mssql](../terraform-azurerm-vm-mssql).
