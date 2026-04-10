# Developer Virtual Machine Module (vm-devops-win)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vm-devops-diagram](./images/vm-devops-win-diagram.drawio.svg)

## Overview

This module implements a collection of identical Windows developer virtual machines with the following features:

* Configurable OS disk size
* Optional data disk with configurable size
* Pre-installed developer tools including:
  * PowerShell Az Module
  * Visual Studio Code
  * SQL Server Management Studio
  * MySQL Workbench

## Smoke Testing

* Connect to one of the developer virtual machines using Azure Bastion with the following credentials:

  ```plaintext
  bootstrapadmin@mysandbox.local
  ```

* The password is stored in the Azure Key Vault secret *adminpassword*.
* Verify the following software is installed:
  * Visual Studio Code
  * SQL Server Management Studio
  * MySQL Workbench
* Open File Explorer and confirm the following:
  * the OS disk is expanded to use all available space
  * The data disk is initialized, partitioned and formatted

## Documentation

This section provides additional information on various aspects of this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Output Variables](#output-variables)

### Dependencies

This module depends upon resources provisioned in the following modules:

* Root
* vnet-shared
* vnet-app

### Module Structure

This module is organized as follows:

```plaintext
├── images/
|   └── vm-devops-win-diagram.drawio.svg        # Architecture diagram
├── scripts/
|   ├── Register-DscNode.ps1                    # Registers VM with Azure Automation DSC
|   ├── Set-AutomationAccountConfiguration.ps1  # Configures Azure Automation account
|   ├── Set-VmDevopsWinConfiguration.ps1        # VM configuration script
|   └── VmDevopsWinConfiguration.ps1            # DSC configuration for VMs 
├── compute.tf                                  # Compute resource configurations
├── locals.tf                                   # Local variables
├── main.tf                                     # Resource configurations  
├── network.tf                                  # Network resource configurations  
├── outputs.tf                                  # Output variables
├── storage.tf                                  # Storage resource configurations
├── terraform.tf                                # Terraform configuration block
└── variables.tf                                # Input variables
```

### Input Variables

This section lists the input variables and default values used in this module. Defaults can be overridden by specifying a different value in the root module.

Variable | Default | Description
--- | --- | ---
admin_password | | A strong password used when provisioning administrator accounts. Defined in vnet-shared module.
admin_username | bootstrapadmin | The user name used when provisioning administrator accounts. Defined in vnet-shared module.
arm_client_secret | | The password for the service principle. Provided interactively or by setting the TF_VAR_arm_client_secret environment variable.
automation_account_name |  | The name of the Azure Automation Account used for state configuration (DSC).
key_vault_id |  | The existing key vault where secrets are stored
location |  | The name of the Azure Region where resources will be provisioned.
resource_group_name |  | The name of the existing resource group for provisioning resources.
storage_account_id |  | The ID of the existing storage account where the remote scripts are stored.
storage_account_name |  | The name of the shared storage account.
storage_blob_endpoint |  | The storage account blob endpoint.
storage_container_name |  | The name of the storage container where remote scripts are stored.
subnet_id |  | The ID of the existing subnet where the nics will be provisioned.
tags |  | The tags in map format to be used when creating new resources.
vm_devops_win_data_disk_size_gb | 32 | The size of the virtual machine data disk in GB. If set to 0 no data disk will be created.
vm_devops_win_image_offer | WindowsServer | The offer type of the virtual machine image used to create the devops VM
vm_devops_win_image_publisher | MicrosoftWindowsServer | The publisher for the virtual machine image used to create the devops VM
vm_devops_win_image_sku | 2025-datacenter-azure-edition | The sku of the virtual machine image used to create the devops VM
vm_devops_win_image_version | Latest | The version of the virtual machine image used to create the devops VM
vm_devops_win_instances | 1 | The number of developer VMs to provision.
vm_devops_win_license_type | None | The license type for the virtual machine
vm_devops_win_name | DEVOPSWIN | The prefix for the name of the developer VMs.
vm_devops_win_os_disk_size_gb | 127 | The size of the virtual machine OS disk in GB. If set larger than 127, the OS disk will be expanded to use all available space.
vm_devops_win_patch_mode | AutomaticByPlatform | The patch mode for the virtual machine
vm_devops_win_size | Standard_B2ls_v2 | The size of the virtual machine
vm_devops_win_storage_account_type | Standard_LRS | The storage replication type to be used for VM disks.

### Module Resources

Address | Name | Notes
--- | --- | ---
module.vm_devops_win[0].azurerm_managed_disk.disks[*] | disk-sand-dev-DEVOPSWINXXX | Data disks for the virtual machines.
module.vm_devops_win[0].azurerm_network_interface.nics[*] | nic-sand-dev-DEVOPSWINXXX | Network interfaces for the virtual machines.
module.vm_devops_win[0].azurerm_role_assignment.assignments[*] | | `Storage Blob Data Reader` role assignments for the virtual machines.
module.vm_devops_win[0].azurerm_storage_blob.this | Set-VmDevopsWinConfiguration.ps1 | PowerShell script for configuring the VM disks.
module.vm_devops_win[0].azurerm_virtual_machine_data_disk_attachment.attachments[*] | | Attaches data disks to the virtual machines.
module.vm_devops_win[0].azurerm_virtual_machine_extension.extensions[*] | | Custom script extension for running the `Set-VmDevopsWinConfiguration.ps1` script on the virtual machines.
module.vm_devops_win[0].azurerm_windows_virtual_machine.virtual_machines[*] | DEVOPSWINXXX | Developer VMs.
module.vm_devops_win[0].null_resource.this | | Used to configure the Automation Account by running `Set-AutomationAccountConfiguration.ps1`

### Output Variables

This section includes a list of output variables returned by the module.

Name | Comments
--- | ---
resource_ids | A map of resource IDs for key resources in the module.
resource_names | A map of resource names for key resources in the module.
