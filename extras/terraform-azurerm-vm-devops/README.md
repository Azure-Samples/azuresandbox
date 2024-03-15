# \#AzureSandbox - terraform-azurerm-vm-devops

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vm-devops-diagram](./vm-devops-diagram.drawio.svg)

## Overview

This configuration implements a collection of identical [IaaS](https://azure.microsoft.com/overview/what-is-iaas/) [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) designed to be used as developer workstations. While it can be used with #AzureSandbox, it can also be used in your own Azure estate. Note this configuration is designed for a Windows client environment, and WSL is not required.

Activity | Estimated time required
--- | ---
Pre-configuration | ~5 minutes
Provisioning | ~10 minutes
Smoke testing | ~5 minutes

## Before you start

If you are using this configuration with #AzureSandbox, [terraform-azurerm-vnet-app](../../terraform-azurerm-vnet-app/) must be provisioned first before starting. If you are using this configuration with your own Azure estate, the following prerequisites are required:

* An Azure subscription.
* A resource group in the subscription where the VMs will be deployed.
* A subnet in a virtual network in the same subscription for where the VM network interfaces will be deployed.
* A storage account configured as follows:
  * A `scripts` blob container for hosting scripts to be used for virtual machine custom script extensions.
  * If you are using the storage firewall, add the IP address of the client running the bootstrap script as well as the vnet for the developer VMs to the storage account firewall.
* An automation account.
* A service principal with `Contributor` privileges on the Azure subscription. This can be done in CloudShell using Bash and the Azure CLI.

  ```bash
  az ad sp create-for-rbac --name SERVICE-PRINCIPAL-NAME-HERE --role contributor --scopes /subscriptions/GUID-HERE
  ```

  The output will look like this:

  ```json
  {
      "appId": "GUID-HERE",
      "displayName": "SERVICE-PRINCIPAL-NAME-HERE",
      "password": "PASSWORD-HERE",
      "tenant": "GUID-HERE"
  }
  ```

* A key vault configured as follows:
  * The service principal has been granted privileges to get secrets from the key vault, either via an access policy or an RBAC role assignment.
  * The following secrets exist in the key vault (Note: the secret names are configurable):
    * `adminuser`: The name for the local administrator account to configure on the developer VMs.
    * `adminpassword`: The password for the local administrator account to configure on the developer VMs.
    * `domainadminuser`: The username for the domain admin credential used to domain join the developer VMs.
    * `domainadminpassword`: The password for the domain admin credential used to domain join the developer VMs.
    * Storage account key (secret name is the same as the storage account).

## Getting started

This section describes how to provision this configuration.

* [Install Winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/#install-winget).
* [Install Git for Windows](https://git-scm.com/download/win).

  ```cmd
  winget install --id Git.Git --source winget
  ```

* [Install PowerShell](https://learn.microsoft.com/en-us/PowerShell/scripting/install/installing-PowerShell-on-windows?view=PowerShell-7.4) v7.4.1 or later.

  ```cmd
  winget install --id Microsoft.PowerShell --source winget
  ```
  
* Install Terraform for Windows.

  ```cmd
  winget install --id HashiCorp.Terraform --source winget
  ```

* Open a PowerShell 7 command prompt (not Windows PowerShell) as Administrator:
  * Install [Azure PowerShell Module](https://learn.microsoft.com/en-us/PowerShell/azure/install-azps-windows?view=azps-11.3.0&tabs=PowerShell&pivots=windows-psgallery#installation).
    * If you are using old versions of Azure PowerShell or AzureRM, you may want to [uninstall](https://learn.microsoft.com/en-us/PowerShell/azure/uninstall-az-ps?view=azps-11.3.0) them first as they can cause strange failures later.
    * Add a `-Scope AllUsers` parameter to the `Install-Module` command, otherwise the module files will get installed in your OneDrive.
  * Exit the PowerShell 7 command prompt.

* Open a normal PowerShell 7 command prompt, clone this repository and launch VS Code

  ```pwsh
  git clone https://github.com/Azure-Samples/azuresandbox
  cd .\azuresandbox\extras\terraform-azurerm-vm-devops
  code .
  ```

* In VS Code, create a new json configuration file in the `\azuresandbox\extras\terraform-azurerm-vm-devops` directory and set the defaults for all required variables. See [Bootstrap script](#bootstrap-script) for more information.

* Open a PowerShell 7 command prompt from inside VS Code.
  * Run the following commands:

    ```pwsh
    $env:TF_VAR_arm_client_secret = "YOUR-SERVICE-PRINCIPAL-PASSWORD-HERE"

    # Run bootstrap
    .\bootstrap.ps1 -JsonConfigFile "YOUR-CONFIG-FILE-HERE.json"

    # Apply terraform configuration
    terraform init
    terraform validate
    terraform plan
    terraform apply
    ```

## Smoke testing

Check State Configuration (DSC) dashboard in Azure Automation periodically for configuration status. It may be necessary to reboot VMs that are stuck in `Failed` due to a .NET framework installation issues. Wait for a while after reboot and nodes should report as `Compliant`. Wait 30 minutes after the Terraform configuration is applied before attempting reboots.

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

This configuration uses the script [bootstrap.ps1](./bootstrap.ps1) to configure Azure Automation and create a *terraform.tfvars* file for generating and applying Terraform plans.

Runtime variables are configured using a json configuration file which must be created in the same directory as [bootstrap.ps1](./bootstrap.ps1) and passed to the script using the `-JsonConfigFile` parameter. The following variables are required:

variable | category | notes
--- | --- | ---
aad_tenant_id | authentication | The ID for the Microsoft Entra ID tenant you are using for authentication.
adds_domain_name | authentication | The name of the domain to join the VMs to.
admin_password_secret | authentication | The name of the keyvault secret that is used to store the local admin username. Default is `adminpassword`.
admin_username_secret | authentication | The name of the keyvault secret that is used to store the local admin password. Default is `adminuser`.
automation_account_name | environment | The name of the automation account used for Azure Automation DSC.
arm_client_id | authentication | The `appId` for the service principal.
domain_admin_password_secret | authentication | The name of the keyvault secret that is used to store the local admin username. Default is `domainadminpassword`.
domain_admin_username_secret | authentication | The name of the keyvault secret that is used to store the local admin password. Default is `domainadminuser`.
key_vault_id | authentication | The resource ID of the keyvault used to store secrets.
location | environment | The Azure region where resources will be deployed.
resource_group_name | environment | The name of the resource group where the VMs will be deployed.
storage_account_name | environment | The name of the storage account used for downloading configuration scripts.
storage_container_name | environment | The name of the container where configuration scripts are stored.
subnet_id | environment | The resource ID of the subnet used to attach virtual machine NICs.
subscription_id | environment | The GUID of the Azure subscription where resources will be deployed.
tags | vm | A hashtable of tags to apply to resources.
vm_devops_win_config_script | vm | The file name of the configuration script run on DevOps VMs using custom script extension.
vm_devops_win_data_disk_size_gb | vm | The size of the data disk for the DevOps VMs. Value should conform to sizes listed in [Azure managed disk types](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types). If no data disk is needed set to `0`.
vm_devops_win_dsc_config | vm | The file name (excluding extension) of the DSC configuration to apply to the DevOps VMs.
vm_devops_win_image_offer |  vm | The offer of the Windows image used for the DevOps VM.
vm_devops_win_image_publisher | vm | The publisher of the Windows image used for the DevOps VM.
vm_devops_win_image_sku | vm | The SKU of the Windows image used for the DevOps VM.
vm_devops_win_image_version | vm | The version of the Windows image used for the DevOps VM.
vm_devops_win_instances | vm | The number of instances of the DevOps VM to deploy.
vm_devops_win_instances_start | vm | The starting base 0 number for the DevOps VM instance names. Must be between 0 and 999.
vm_devops_win_license_type | vm | The license type for the DevOps VMs. Use `Windows_Client` or `Windows_Server` for hybrid use rights or `None` for pay-as-you-go.
vm_devops_win_name | vm | The name prefix for the DevOps VMs.
vm_devops_win_os_disk_size_gb | vm | The size of the OS disk for the DevOps VMs. Minimum 128 GB.
vm_devops_win_patch_mode | vm | The patch mode for the DevOps VMs. Use `AutomaticByPlatform` or `AutomaticByOS` for automatic updates, or `Manual` for manual updates.
vm_devops_win_size | vm | The size of the DevOps VMs.
vm_devops_win_storage_account_type | vm | The storage account type for the DevOps VMs.

Here is an example of a json configuration file:

```json
{
  "aad_tenant_id": "GUID-HERE",
  "adds_domain_name": "DOMAIN-HERE",
  "admin_password_secret": "SECRET-NAME-HERE",
  "admin_username_secret": "SECRET-NAME-HERE",
  "automation_account_name": "AUTOMATION-ACCOUNT-NAME-HERE",
  "arm_client_id": "GUID-HERE",
  "domain_admin_password_secret": "SECRET-NAME-HERE",
  "domain_admin_username_secret": "SECRET-NAME-HERE",
  "key_vault_id": "/subscriptions/GUID-HERE/resourceGroups/RESOURCE-GROUP-NAME-HERE/providers/Microsoft.KeyVault/vaults/KEY-VAULT-NAME-HERE",
  "location": "LOCATION-HERE",
  "resource_group_name": "RESOURCE-GROUP-NAME-HERE",
  "storage_account_name": "STORAGE-ACCOUNT-NAME-HERE",
  "storage_container_name": "scripts",
  "subnet_id": "/subscriptions/GUID-HERE/resourceGroups/RESOURCE-GROUP-NAME-HERE/providers/Microsoft.Network/virtualNetworks/VNET-NAME-HERE/subnets/SUBNET-NAME-HERE",
  "subscription_id": "GUID-HERE",
  "tags": {
    "project": "PROJECT-NAME-HERE",
    "costcenter": "COST-CENTER-HERE",
    "environment": "ENVIRONMENT-HERE"
  },
  "vm_devops_win_config_script": "configure-vm-devops-win.ps1",
  "vm_devops_win_data_disk_size_gb": 64,
  "vm_devops_win_dsc_config": "DevopsVmWin",
  "vm_devops_win_image_offer": "windows-11",
  "vm_devops_win_image_publisher": "MicrosoftWindowsDesktop",
  "vm_devops_win_image_sku": "win11-22h2-ent",
  "vm_devops_win_image_version": "latest",
  "vm_devops_win_instances": 2,
  "vm_devops_win_instances_start": 1,
  "vm_devops_win_license_type": "Windows_Client",
  "vm_devops_win_name": "DEVOPSWIN",
  "vm_devops_win_os_disk_size_gb": 256,
  "vm_devops_win_patch_mode": "AutomaticByOS",
  "vm_devops_win_size": "Standard_B2s",
  "vm_devops_win_storage_account_type": "Standard_LRS"
}    
```

Configuration of [Azure Automation State Configuration (DSC)](https://learn.microsoft.com/azure/automation/automation-dsc-overview) is performed.

* Configures [Azure Automation shared resources](https://learn.microsoft.com/azure/automation/automation-intro#shared-resources) including:
  * [Modules](https://learn.microsoft.com/azure/automation/shared-resources/modules)
    * [PSDscResources](https://www.powershellgallery.com/packages/PSDscResources)
    * [xDSCDomainJoin](https://www.powershellgallery.com/packages/xDSCDomainjoin)
    * [cChoco](https://www.powershellgallery.com/packages/cChoco)
  * [Variables](https://learn.microsoft.com/azure/automation/shared-resources/variables)
    * `adds_domain_name`: The name of the domain to join the VMs to.
  * [Credentials](https://learn.microsoft.com/azure/automation/shared-resources/credentials)
    * `domainadmin`: The domain admin credentials required to domain join VMs.

* Imports [DSC Configurations](https://learn.microsoft.com/azure/automation/automation-dsc-getting-started#create-a-dsc-configuration) used in this configuration.
  * [DevopsVmWin.ps1](./DevopsVmWin.ps1): domain joins a Windows virtual machine and installs software using [Chocolatey](https://chocolatey.org/why-chocolatey). Note the name of the DSC configuration is configurable using the `vm_devops_win_dsc_config` variable.

* [Compiles DSC Configurations](https://learn.microsoft.com/azure/automation/automation-dsc-compile) so they can be used later to [Register a VM to be managed by State Configuration](https://learn.microsoft.com/azure/automation/tutorial-configure-servers-desired-state#register-a-vm-to-be-managed-by-state-configuration).

### Terraform Resources

This section lists the resources included in this configuration.

#### Windows developer workstations

The configuration for these resources can be found in [020-vm-devops-win.tf](./020-vm-devops-win.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_windows_virtual_machine.vm_devops_win[*] (DEVOPSWIN000) | A collection of Windows virtual machines for use as developer workstations. See below for more information.
azurerm_network_interface.vm_devops_win[*] (nic&#x2011;DEVOPSWIN000) | A collection of network interfaces for the Windows virtual machines attached to a configurable subnet.
azurerm_managed_disk.vm_devops_win[*] | A collection of disks for use as data disks for the developer workstations.
azurerm_virtual_machine_data_disk_attachment.vm_devops_win[*] | A collection of data disk attachments for the developer workstations.
azurerm_virtual_machine_extension.vm_devops_win[*] | A collection of virtual machine extensions for the developer workstations.

* The virtual machine names are configured as follows:
  * A virtual machine name prefix is set in the `vm_devops_win_name` variable (e.g. `DEVOPSWIN`).
  * The number of instances is set in the `vm_devops_win_instances` variable (e.g. `2`).
  * The starting base 0 number for the virtual machine names is set in the `vm_devops_win_instances_start` variable (e.g. `1`).
  * Using the examples above, the virtual machine names would be `DEVOPSWIN001` and `DEVOPSWIN002`.
* The resource group is set in the `resource_group_name` variable.
* The location is set in the `location` variable (e.g. `eastus`).
* The size of the virtual machines is set in the `vm_devops_win_size` variable (e.g. `Standard_B2s`).
* *admin_username* and *admin_password* are configured using key vault secrets `adminuser` and `adminpassword`. These are the local administrator credentials used for the virtual machine before it is domain joined.
* Automatic updates are enabled. The patch mode is set in the `vm_devops_win_patch_mode` variable (e.g. `AutomaticByOS`).
* The license type is set in the `vm_devops_win_license_type` variable (e.g. `Windows_Client`).
* A configurable set of tags is configured in the `tags` variable.
* The OS disk is configured as follows:
  * The storage account type is set in the `vm_devops_win_storage_account_type` variable (e.g. `Standard_LRS`).
  * The size of the OS disk is set in the `vm_devops_win_os_disk_size_gb` variable (e.g. `256`).
* The platform image used for the guest OS is configured as follows:
  * The publisher is set in the `vm_devops_win_image_publisher` variable (e.g. `MicrosoftWindowsDesktop`).
  * The offer is set in the `vm_devops_win_image_offer` variable (e.g. `windows-11`).
  * The SKU is set in the `vm_devops_win_image_sku` variable (e.g. `win11-22h2-ent`).
  * The version is set in the `vm_devops_win_image_version` variable (e.g. `latest`).
  * Both Windows client and server images are supported.
* The VM is configured using a [provisioner](https://www.terraform.io/docs/language/resources/provisioners/syntax.html) that runs [aadsc-register-node.ps1](./aadsc-register-node.ps1) which registers the node with Azure Automation and applies the configuration [DevopsVmWin.ps1](./DevopsVmWin.ps1). This DSC configuration can be customized to fit your needs.
  * The virtual machine is domain joined as follows:
    * The domain name is set in the `adds_domain_name` variable
    * The VM is domain joined using domain admin credentials which are configured using key vault secrets *domainadminuser* and *domainadminpassword*.
  * The following software packages are pre-installed using [Chocolatey](https://chocolatey.org/why-chocolatey):
    * [vscode](https://community.chocolatey.org/packages/vscode)
    * [sql-server-management-studio](https://community.chocolatey.org/packages/sql-server-management-studio)
* A single data disk is configured as follows:
  * The size of the data disk is set in the `vm_devops_win_data_disk_size_gb` variable (e.g. `64`). If this is set to `0`, no data disk is attached to the virtual machine.
  * The storage account type is set in the `vm_devops_win_storage_account_type` variable (e.g. `Standard_LRS`).
* This VM is configured by [configure-vm-devops-win.ps1](./configure-vm-devops-win.ps1) using a custom script extension. This script can be customized to fit your needs.
  * The OS disk is expanded to use any unallocated space on the disk.
  * Data disks are initialized, partitioned and formatted.
