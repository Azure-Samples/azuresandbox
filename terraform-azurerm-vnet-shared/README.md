# #AzureSandbox - terraform-azurerm-vnet-shared

**Contents**

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Next steps](#next-steps)

## Architecture

![vnet-shared-diagram](./vnet-shared-diagram.drawio.svg)

## Overview

This configuration implements a virtual network with shared services used by all the configurations including:

* A [resource group](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#resource-group) which contains all resources.
* A [key vault](https://learn.microsoft.com/azure/key-vault/general/overview) for managing secrets.
* A [log analytics workspace](https://learn.microsoft.com/azure/azure-monitor/data-platform#collect-monitoring-data) for log data and metrics.
* A [storage account](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#storage-account) for blob storage.
* An [automation account](https://learn.microsoft.com/azure/automation/automation-intro) for configuration management.
* A [virtual network](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vnet) for hosting [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm).
* A [bastion](https://learn.microsoft.com/azure/bastion/bastion-overview) for secure RDP and SSH access to virtual machines.
* A Windows Server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) running [Active Directory Domain Services](https://learn.microsoft.com/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview) with a pre-configured domain and DNS server.

Activity | Estimated time required
--- | ---
Pre-configuration | ~10 minutes
Provisioning | ~20 minutes
Smoke testing | ~5 minutes

## Before you start

Before you start, make sure you have completed the following steps:

* All [Prerequisites](../README.md#Prerequisites) must be completed.
  * The Azure subscription owner must create a service principal with a *Contributor* Azure RBAC role assignment in advance.
  * The *appId* and *password* of the service principal must be known.
  * The sandbox user must also have a *Contributor* Azure RBAC role assignment on the Azure subscription.
* Complete the steps in [Configure client environment](../README.md#configure-client-environment).
  * Verify you can start a new Bash terminal session
  * Verify the Azure CLI is installed by running `az --version`
  * Verify PowerShell Core is installed by running `pwsh --version`
  * Verify you have cloned a copy of the GitHub repo with the latest release of the source code.

## Getting started

This section describes how to provision this configuration using default settings.

* Open a Bash terminal in your client environment and execute the following commands.

  ```bash
  # Log out of Azure and clear cached credentials (skip if using cloudshell)
  az logout

  # Clear cached credentials (skip if using cloudshell)
  az account clear

  # Log into Azure (skip if using cloudshell)
  az login
  ```

* Change the current directory to the correct configuration

  ```bash
  cd ~/azuresandbox/terraform-azurerm-vnet-shared
  ```

* Find and copy the *Subscription Id* to be used for the configurations.

  ```bash
  az account list -o table
  ```

* Set the default Azure subscription using the *Subscription Id* from the previous step.

  ```bash
  az account set -s 00000000-0000-0000-0000-000000000000
  ```

* Add an environment variable containing the password for your service principal.

  ```bash
  export TF_VAR_arm_client_secret=YourServicePrincipalSecret
  ```

* Run [bootstrap.sh](./bootstrap.sh) using the default settings or your own custom settings.

  ```bash
  ./bootstrap.sh
  ```

  * When prompted for *arm_client_id*, use the *appId* for the service principal created by the subscription owner.
  * When prompted for *resource_group_name* use a custom value if there are other sandbox users using the same subscription.
  * When prompted for *adminuser*, the default is *bootstrapadmin*.
    * *Important*: If you use a custom value, avoid using [restricted usernames](https://learn.microsoft.com/azure/virtual-machines/windows/faq#what-are-the-username-requirements-when-creating-a-vm-).
  * When prompted for *skip_admin_password_gen*, accept the default which is `no`.
    * *Important*: A strong password will be generated for you and stored in the *adminpassword* key vault secret.
* Apply the Terraform configuration.

  ```bash
  # Initialize providers
  terraform init
  
  # Check configuration for syntax errors
  terraform validate

  # Review plan output
  terraform plan

  # Apply plan
  terraform apply
  ```

* Monitor output. Upon completion, you should see a message similar to the following:

  `Apply complete! Resources: 29 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # Review provisioned resources
  terraform state list

  # Review output variables
  terraform output
  ```

## Smoke testing

* Explore your newly provisioned resources in the Azure portal.
  * Key vault
    * Navigate to *portal.azure.com* > *Key vaults* > *kv-xxxxxxxxxxxxxxx* > *Objects* > *Secrets* > *adminpassword* > *CURRENT VERSION* > *00000000-0000-0000-0000-000000000000* > *Show Secret Value*
    * Make a note of the *Secret value*. This is a strong password associated with the *adminuser* key vault secret. Together these credentials are used to set up initial administrative access to resources in \#AzureSandbox.
  * Bastion host
    * Navigate to *portal.azure.com* > *Bastions* > *bst-xxxxxxxxxxxxxxxx-1*.
    * Review the information in the *Overview* section.
* Verify *adds1* node configuration is compliant.
  * Wait for 15 minutes to proceed to allow time for DSC configurations to complete.
  * From the client environment, navigate to *portal.azure.com* > *Automation Accounts* > *auto-xxxxxxxxxxxxxxxx-01* > *Configuration Management* > *State configuration (DSC)*.
  * Refresh the data on the *Nodes* tab and verify that all nodes are compliant.
  * Review the data in the *Configurations* and *Compiled configurations* tabs as well.

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

The bootstrap script [bootstrap.sh](./bootstrap.sh) is used to initialize variables and to ensure that all dependencies are in place for the Terraform configuration to be applied. In most real world projects, Terraform configurations will need to reference resources that are not being managed by Terraform because they already exist. It is also sometimes necessary to provision resources in advance to avoid circular dependencies in your Terraform configurations. For this reason, this configuration provisions several resources in advance using [bootstrap.sh](./bootstrap.sh).

[bootstrap.sh](./bootstrap.sh) performs the following operations:

* Generates SSH keys for Linux Jumpbox VM
* Generates a [Mime Multi Part Archive](https://cloudinit.readthedocs.io/en/latest/topics/format.html#mime-multi-part-archive) containing the following files:
  * [configure-vm-jumpbox-linux.yaml](./configure-vm-jumpbox-linux.yaml) is [Cloud Config Data](https://cloudinit.readthedocs.io/en/latest/topics/format.html#cloud-config-data) used to configure the Linux Jumpbox VM.
  * [configure-vm-jumpbox-linux.sh](./configure-vm-jumpbox-linux.sh) is a [User-Data Script](https://cloudinit.readthedocs.io/en/latest/topics/format.html#user-data-script) used to configure the Linux Jumpbox VM.
* Creates a new resource group with the default name *rg-sandbox-01* used by all the configurations.
* Creates a storage account with a randomly generated 15-character name like *stxxxxxxxxxxxxx*.
  * The name is limited to 15 characters for compatibility with Active Directory Domain Services.
  * A new *scripts* container is created for configurations that leverage the Custom Script Extension for [Windows](https://learn.microsoft.com/azure/virtual-machines/extensions/custom-script-windows) or [Linux](https://learn.microsoft.com/azure/virtual-machines/extensions/custom-script-linux).
* Creates a key vault with a randomly generated name like *kv-xxxxxxxxxxxxxxx*.
  * The permission model is set to *Vault access policy*. *Azure role-based access control* is not used to ensure that sandbox users only require a *Contributor* Azure RBAC role assignment in order to complete the configurations.
  * Secrets are created that are used by all configurations. Note these secrets are static and will need to be manually updated if the values change.
    * *Log analytics workspace primary shared key*: The name of this secret is the same as the id of the log analytics workspace, e.g. *00000000-0000-0000-0000-000000000000*, and the value is the primary shared key which can be used to connect agents to the log analytics workspace.
    * *Storage account access key1*: The name of this secret is the same as the storage account, e.g. *stxxxxxxxxxxxxxxx*, and the value is access key 1.
    * *Storage account kerberos key1*: The name of this secret is the same as the storage account, e.g. *stxxxxxxxxxxxxxxx-kerb1*, and the value is kerberos key 1.
    * *adminpassword*: The password used for default administrator credentials when new resources are provisioned.
    * *adminuser*: The user name used for default administrator credentials when new resources are configured. The default value is *bootstrapadmin*.
    * *bootstrapadmin-ssh-key-private*: The private SSH key used to secure SSH access to Linux VMs created in the configurations. The value of the *adminpassword* secret is used as the pass phrase.
    * *bootstrapadmin-ssh-key-public*: The public SSH key used to secure SSH access to Linux VMs created in the configurations.
  * Access policies are created to enable the administration and retrieval of secrets.
    * *AzureSandboxSPN* is granted *Get* and *Set* secrets permissions.
    * The sandbox user is granted *Get*, *List* and *Set* secrets permissions.
* Creates a *terraform.tfvars* file for generating and applying Terraform plans.

The script is idempotent and can be run multiple times even after the Terraform configuration has been applied.

### Terraform Resources

This section lists the resources included in the Terraform configurations in this configuration.

#### Log Analytics Workspace

The configuration for these resources can be found in [020-loganalytics.tf](./020-loganalytics.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_log_analytics_workspace.log_analytics_workspace_01 (log&#x2011;xxxxxxxxxxxxxxxx&#x2011;01) | See below.
random_id.log_analytics_workspace_01_name | Used to generate a random unique name for *azurerm_log_analytics_workspace.log_analytics_workspace_01*.
azurerm_key_vault_secret.log_analytics_workspace_01_primary_shared_key | Secret used to access *azurerm_log_analytics_workspace.log_analytics_workspace_01*.

The log analytics workspace is for use with services like [Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/overview) and [Azure Security Center](https://learn.microsoft.com/azure/security-center/security-center-introduction).

#### Azure Automation Account

The configuration for these resources can be found in [030-automation.tf](./030-automation.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_automation_account.automation_account_01 (auto&#x2011;a9866e235174ab6a&#x2011;01) | See below.
random_id.automation_account_01_name | Used to generate a random unique name for *azurerm_automation_account.automation_account_01*

This configuration makes extensive use of [Azure Automation State Configuration (DSC)](https://learn.microsoft.com/azure/automation/automation-dsc-overview) to configure virtual machines using Terraform [Provisioners](https://www.terraform.io/docs/language/resources/provisioners/syntax.html).

* [configure-automation.ps1](./configure-automation.ps1): This script is run by a provisioner in the *azurerm_automation_account.automation_account_01* resource and does the following:
  * Configures [Azure Automation shared resources](https://learn.microsoft.com/azure/automation/automation-intro#shared-resources) including:
    * [Modules](https://learn.microsoft.com/azure/automation/shared-resources/modules)
      * Existing modules are updated to the most recent release where possible.
      * Imports new modules including the following:
        * [ActiveDirectoryDsc](https://github.com/dsccommunity/ActiveDirectoryDsc)
    * Bootstraps [Variables](https://learn.microsoft.com/azure/automation/shared-resources/variables)
    * Bootstraps [Credentials](https://learn.microsoft.com/azure/automation/shared-resources/credentials)
  * Configures [Azure Automation State Configuration (DSC)](https://learn.microsoft.com/azure/automation/automation-dsc-overview) which is used to configure Windows Server virtual machines used in the configurations.
    * Imports [DSC Configurations](https://learn.microsoft.com/azure/automation/automation-dsc-getting-started#create-a-dsc-configuration) used in this configuration.
      * [LabDomainConfig.ps1](./LabDomainConfig.ps1): configure a Windows Server virtual machine as an [Active Directory Domain Services](https://learn.microsoft.com/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview) [Domain Controller](https://learn.microsoft.com/previous-versions/windows/it-pro/windows-server-2003/cc786438(v=ws.10)).
    * [Compiles DSC Configurations](https://learn.microsoft.com/azure/automation/automation-dsc-compile) so they can be used later to [Register a VM to be managed by State Configuration](https://learn.microsoft.com/azure/automation/tutorial-configure-servers-desired-state#register-a-vm-to-be-managed-by-state-configuration).

#### Network resources

The configuration for these resources can be found in [040-network.tf](./040-network.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_virtual_network.vnet_shared_01 (vnet&#x2011;shared&#x2011;01) | By default this virtual network is configured with an address space of `10.1.0.0/16` and is configured with DNS server addresses of `10.1.1.4` (the private ip for *azurerm_windows_virtual_machine.vm_adds*) and [168.63.129.16](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16).
azurerm_subnet.vnet_shared_01_subnets["AzureBastionSubnet"] | The default address prefix for this subnet is 10.1.0.0/27 which includes the private ip addresses for *azurerm_bastion_host.bastion_host_01*. A network security group is associated with this subnet and is configured according to [Working with NSG access and Azure Bastion](https://learn.microsoft.com/azure/bastion/bastion-nsg).
azurerm_subnet.vnet_shared_01_subnets["snet-adds-01"] | The default address prefix for this subnet is 10.1.1.0/24 which includes the private ip address for *azurerm_windows_virtual_machine.vm_adds*. A network security group is associated with this subnet that permits ingress and egress from virtual networks, and egress to the Internet.
azurerm_bastion_host.bastion_host_01 (bst&#x2011;xxxxxxxxxxxxxxxx&#x2011;1) | Used for secure RDP and SSH access to VMs.
random_id.bastion_host_01_name | Used to generate a random name for *azurerm_bastion_host.bastion_host_01*.
azurerm_public_ip.bastion_host_01 (pip&#x2011;xxxxxxxxxxxxxxxx&#x2011;1) | Public ip used by *azurerm_bastion_host.bastion_host_01*.
random_id.public_ip_bastion_host_01_name | Used to generate a random name for *azurerm_public_ip.bastion_host_01*.

#### AD DS Domain Controller VM

The configuration for these resources can be found in [050-vm-adds.tf](./050-vm-adds.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_windows_virtual_machine.vm_adds (adds1) | By default, provisions a [Standard_B2s](https://learn.microsoft.com/azure/virtual-machines/sizes-b-series-burstable) virtual machine for use as a domain controller and dns server. See below for more information.
azurerm_network_interface.vm_adds_nic_01 (nic&#x2011;adds1&#x2011;1) | The configured subnet is *azurerm_subnet.vnet_shared_01_subnets["snet-adds-01"]*.

This Windows Server VM is used as an [Active Directory Domain Services](https://learn.microsoft.com/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview) [Domain Controller](https://learn.microsoft.com/previous-versions/windows/it-pro/windows-server-2003/cc786438(v=ws.10)) and a DNS Server running in Active Directory-integrated mode.

* Guest OS: Windows Server 2022 Datacenter Core
* By default the [Patch orchestration mode](https://learn.microsoft.com/azure/virtual-machines/automatic-vm-guest-patching#patch-orchestration-modes) is set to `AutomaticByPlatform`.
* *admin_username* and *admin_password* are configured using the key vault secrets *adminuser* and *adminpassword*.
* This resource has a dependency on *azurerm_automation_account.automation_account_01*.
* This resource is configured using a [provisioner](https://www.terraform.io/docs/language/resources/provisioners/syntax.html) that runs [aadsc-register-node.ps1](./aadsc-register-node.ps1) which registers the node with *azurerm_automation_account.automation_account_01* and applies the configuration [LabDomainConfig](./LabDomainConfig.ps1) which includes the following:
  * The `AD-Domain-Services` feature (which includes DNS) is installed.
  * A new *mysandbox.local* domain is configured
    * The domain admin credentials are configured using the *adminusername* and *adminpassword* key vault secrets.
    * The forest functional level is set to `WinThreshhold`
    * A DNS Server is automatically configured
      * Server configuration
        * Forwarder: [168.63.129.16](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16).
          * Note: This ensures that any DNS queries that can't be resolved by the DNS server are forwarded to the Azure recursive resolver as per [Name resolution for resources in Azure virtual networks](https://learn.microsoft.com/azure/virtual-network/virtual-networks-name-resolution-for-vms-and-role-instances).
      * *mysandbox.local* DNS forward lookup zone configuration
        * Zone type: Primary / Active Directory-Integrated
        * Dynamic updates: Secure only

### Terraform output variables

This section lists the output variables defined in the Terraform configurations in this sample. Some of these may be used for automation in other configurations.

Output variable | Sample value
--- | ---
aad_tenant_id | "00000000-0000-0000-0000-000000000000"
adds_domain_name | "mysandbox.local"
admin_password_secret | "adminpassword"
admin_username_secret | "adminuser"
arm_client_id | "00000000-0000-0000-0000-000000000000"
automation_account_name | "auto-9a633c2bba9351cc-01"
dns_server | "10.1.2.4"
key_vault_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.KeyVault/vaults/kv-XXXXXXXXXXXXXXX"
key_vault_name | "kv-XXXXXXXXXXXXXXX"
location | "eastus2"
log_analytics_workspace_01_name | "log-XXXXXXXXXXXXXXXX-01"
log_analytics_workspace_01_workspace_id | "00000000-0000-0000-0000-000000000000"
resource_group_name | "rg-sandbox-01"
storage_account_name | "stXXXXXXXXXXXXXXX"
storage_container_name | "scripts"
subscription_id | "00000000-0000-0000-0000-000000000000"
tags | tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )
vnet_shared_01_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-shared-01""
vnet_shared_01_name | "vnet-shared-01"

## Next steps

* Move on to the next configuration [terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app).
