# Linux Jumpbox Virtual Machine Module (vm-jumpbox-linux)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vm-jumpbox-linux-diagram](./images/vm-jumpbox-linux-diagram.drawio.svg)

## Overview

This module implements a stand-alone Linux virtual machine for use as a jumpbox or DevOps agent. The VM is configured using cloud-init and offers the following capabilities:

* Secure SSH access using a private SSH key stored in Azure Key Vault.
* Remote-ssh development capabilities using Visual Studio Code.
* Pre-installed software packages, including:
  * azure-cli
  * jp
  * powershell
  * python3-pip
  * terraform
* Pre-configured environment variables for using Azure Blob Storage as a Terraform state backend.

## Smoke Testing

This section describes how to test the module after deployment.

**IMPORTANT:** Wait for 5 minutes to proceed to allow time for cloud-init configurations to complete.

* [Download SSH private key from Azure Key Vault](#download-ssh-private-key-from-azure-key-vault)
* [Determine public IP address of *jumplinux2*](#determine-public-ip-address-of-jumplinux2)
* [Connect to *jumplinux2* using SSH](#connect-to-jumplinux2-using-ssh)
* [Connect to *jumplinux2* using Visual Studio Code](#connect-to-jumplinux2-using-visual-studio-code)

### Download SSH private key from Azure Key Vault

* Navigate to *portal.azure.com* > *Key Vaults* > *kv-devops-dev-xxxxxxxx*
* Click on *Secrets*
* Click on *jumplinux2-ssh-key-public*
* Click on the most current version to view the secret details.
* Click on *Show Secret Value* to view the public SSH key.
* Copy the public SSH key value to the clipboard.
* Paste the public SSH key value into a text editor and save it locally as:

  ```plaintext
  C:\Users\YOUR-USER-NAME-HERE\.ssh\devopsbootstrapadmin-ssh-key-public.txt
  ```

### Determine public IP address of *jumplinux2*

* Navigate to *portal.azure.com* > *Virtual machines* > *jumplinux2*
* Make a note of the *Public IP address* in the *Essentials* section

### Connect to *jumplinux2* using SSH

* Open a PowerShell terminal.
* Execute the following command to connect to *jumplinux1*:

  ```powershell
  ssh -i .\.ssh\devopsbootstrapadmin-ssh-key-private.txt devopsbootstrapadmin@PUBLIC-IP-ADDRESS-HERE
  ```

* Verify *jumplinux2* cloud-init configuration is complete using the following commands:

  ```bash
  # Check to see if cloud-init configuration is complete
  cloud-init status

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

### Connect to *jumplinux2* using Visual Studio Code

* Navigate to *Start* > *Visual Studio Code* > *Visual Studio Code*.
* Click on the blue *Open a Remote Window* icon in the lower left corner
* If you see *Select an option to open a Remote Window*, choose *SSH*
* Click on the blue *Open a Remote Window* icon in the lower left corner
* For *Select an option to open a Remote Window* choose *Connect to Host...*
* For *Select configured SSH host or enter user@host* choose *+ Add New SSH Host...*
* For *Enter SSH Connection Command* enter the following:

  ```plaintext  
  ssh devopsbootstrapadmin@PUBLIC-IP-ADDRESS-HERE
  ```

* Configure private SSH key for *jumplinux2*
  * Click on the blue *Open a Remote Window* icon in the lower left corner
  * Click *Connect to Host...*
  * Click *Configure SSH Hosts...*
  * Select `C:\users\YOUR-USER-NAME-HERE\.ssh\config
  * The config file will open in Visual Studio Code:

  ```yaml
  Host PUBLIC-IP-ADDRESS-HERE
    HostName PUBLIC-IP-ADDRESS-HERE
    User devopsbootstrapadmin
  ```

  * Update the config file as follows:

  ```yaml
  Host jumplinux2
    HostName PUBLIC-IP-ADDRESS-HERE
    User devopsbootstrapadmin
    IdentityFile C:\\Users\\YOUR-USER-NAME-HERE\\.ssh\\devopsbootstrapadmin-ssh-key-private.txt
  ```

* Save the file and close it.

* Connect to *jumplinux2*
  * Click on the blue *Open a Remote Window* icon in the lower left corner
  * For *Select an option to open a Remote Window* choose *Connect to Host...*
  * For *Select configured SSH host or enter user@host* choose *jumplinux2*
  * A new Visual Studio Code window will open.
  * For *Select the platform of the remote host "jumplinux2"* choose *Linux*
  * For *"jumplinux2" has fingerprint...* choose *Continue*
  * Verify that *SSH:jumplinux2* is displayed in the blue status section in the lower left corner.
  * Navigate to *View* > *Explorer*
  * Click *Open Folder*
  * For *Open Folder* select the default folder (home directory) and click *OK*.
  * Navigate to *View* > *Terminal*.
  * Inspect the configuration of *jumplinux2* by executing the following Bash commands:

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
|   ├── configure-powershell.ps1            # cloud-init shell script to configure PowerShell
|   └── configure-vm-jumpbox-linux.yaml     # cloud-init cloud-config file to configure the VM
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
admin_username_secret | adminuser | The name of the key vault secret that contains the user name for the admin account. Defined in the vnet-shared module.
enable_public_access | false | When enabled a public IP address is created for the VM. When disabled, the VM is only accessible via a private IP address.
key_vault_id | | The ID of the key vault defined in the root module.
location | | The Azure region where the resources will be created. Defined in the root module.
resource_group_name | | The name of the resource group defined in the root module.
storage_account_id | | The resource ID of of the storage account defined in the root module.
subnet_id | | The resource ID of the subnet where the VM will be deployed. Defined in the vnet-shared module.
tags | | The tags from the root module.
vm_jumpbox_linux_image_offer | `ubuntu-24_04-lts` | The offer type of the virtual machine image used to create the VM.
vm_jumpbox_linux_image_publisher | `Canonical` | The publisher for the virtual machine image used to create the VM.
vm_jumpbox_linux_image_sku | `server` | The SKU of the virtual machine image used to create the VM.
vm_jumpbox_linux_image_version | `Latest` | The version of the virtual machine image used to create the VM.
vm_jumpbox_linux_name | jumplinux2 | The name of the VM.
vm_jumpbox_linux_size | `Standard_B2ls_v2` | The size of the virtual machine.
vm_jumpbox_linux_storage_account_type | `Standard_LRS` | The storage type to be used for the VM's OS and data disks.

### Module Resources

This section lists the resources included in this configuration.

Address | Name | Notes
--- | --- | ---
module.vm_jumpbox_linux.azurerm_key_vault_secret.adminuser | adminuser | The Key Vault secret containing the admin username for the Linux virtual machine.
module.vm_jumpbox_linux[0].azurerm_key_vault_secret.ssh_private_key | jumplinux1&#8209;ssh&#8209;private&#8209;key | The private SSH key stored in Azure Key Vault.
module.vm_jumpbox_linux[0].azurerm_linux_virtual_machine.this | jumplinux2 | The Linux virtual machine resource.
module.vm_jumpbox_linux[0].azurerm_network_interface.this | nic&#8209;devops&#8209;dev&#8209;jumplinux2 | The network interface associated with the Linux virtual machine.
module.vm_jumpbox_linux.azurerm_public_ip.this[0] | pip&#8209;devops&#8209;dev&#8209;jumplinux2 | The public IP address associated with the Linux virtual machine, if `var.enable_public_access` is enabled.
module.vm_jumpbox_linux.azurerm_role_assignment.this | | Grants `Storage Blob Data Contributor` role to the managed identity of jumplinux2. This is intended to be used for accessing a Terraform state backend hosted in Azure Blob Storage.
module.vm_jumpbox_linux[0].tls_private_key.ssh_key | | The TLS private key used for SSH authentication.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Description
--- | ---
resource_ids | A map of resource IDs for key resources in the module.
resource_names | A map of resource names for key resources in the module.
