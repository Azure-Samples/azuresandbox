# Linux Jumbox Virtual Machine Module (vm-jumpbox-linux)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vnet-app-diagram](./images/vm-jumpbox-linux-diagram.drawio.svg)

## Overview

This configuration implements a Linux virtual machine for use as a jumpbox. The VM is configured using cloud-init and offers the following capabilities:

* Secure SSH access via Bastion using a private SSH key stored in Azure Key Vault.
* Domain joined to the *mysandbox.local* Active Directory domain using winbind.
* Remote-ssh development capabilities using Visual Studio Code on *jumpwin1*.
* Secure AD integrated access to Azure Files SMB/cifs share automatically mounted by the VM.
* Pre-installed software packages, including:
  * autofs
  * azure-cli
  * cifs-utils
  * jp
  * keyutils
  * krb5-config
  * krb5-user
  * libnss-winbind
  * libpam-winbind
  * ntp
  * powershell
  * python3-pip
  * samba
  * terraform
  * winbind

## Smoke Testing

This section describes how to test the module after deployment.

* Wait for 5 minutes to proceed to allow time for cloud-init configurations to complete.

* Verify *jumplinux1* cloud-init configuration is complete.
  * From the client environment, navigate to *portal.azure.com* > *Virtual machines* > *jumplinux1*
  * Click *Connect*, then click *Connect via Bastion*
  * For *Authentication Type* choose *SSH Private Key from Azure Key Vault*
  * For *Username* enter the following:

    ```plaintext
    bootstrapadminlocal
    ```

  * For *Azure Key Vault Secret* specify the following values:
    * For *Subscription* choose the same Azure subscription used to provision the sandbox environment.
    * For *Azure Key Vault* choose the key vault associated with the sandbox environment, e.g. *kv-sand-dev-xxxxxxxx*.`
    * For *Azure Key Vault Secret* choose *jumplinux1-ssh-key-private*
  * Click *Connect*
  * Execute the following command:

    ```bash
    cloud-init status
    ```

  * Verify that cloud-init status is *done*.
  * Execute the following command:

    ```bash
    sudo cat /var/log/cloud-init-output.log | more
    ```

  * Review the log file output. Note the automated configuration management being performed including:
    * package updates and upgrades
    * reboots
    * user script executions
  * Execute the following command:

    ```bash
    exit
    ```

* From *jumpwin1*, inspect the *mysandbox.local* Active Directory domain
  * Navigate to *Start* > *Windows Tools* > *Active Directory Users and Computers*.
  * Navigate to *mysandbox.local* > *Computers* and verify that *jumplinux1* is listed.

* From *jumpwin1*, inspect the *mysandbox.local* DNS zone
  * Navigate to *Start* > *Windows Tools* > *DNS*
  * Connect to the DNS Server on *adds1*.
  * Click on *adds1* in the left pane
    * Navigate to *adds1* > *Forward Lookup Zones* > *mysandbox.local* and verify that there is a *Host (A)* record for *jumplinux1*.

* From *jumpwin1*, configure Visual Studio Code to do remote SSH development on *jumplinux1*
  * Navigate to *Start* > *Visual Studio Code* > *Visual Studio Code*.
  * Click on the blue *Open a Remote Window* icon in the lower left corner
  * For *Select an option to open a Remote Window* choose *SSH*
  * Click on the blue *Open a Remote Window* icon in the lower left corner
  * For *Select an option to open a Remote Window* choose *Connect to Host...*
  * For *Select configured SSH host or enter user@host* choose *+ Add New SSH Host...*
  * For *Enter SSH Connection Command* enter the following:
  
    ```plaintext  
    ssh bootstrapadmin@mysandbox.local@jumplinux1
    ```

  * For *Select SSH configuration file to update* choose *C:\Users\bootstrapadmin\.ssh\config*

* From *jumpwin1*, open a remote window to *jumplinux1*
  * From Visual Studio Code, click on the blue *Open a Remote Window* icon in the lower left corner
  * For *Select an option to open a Remote Window* choose *Connect to Host...*
  * For *Select configured SSH host or enter user@host* choose *jumplinux1*
  * A new Visual Studio Code window will open.
  * For *Select the platform of the remote host "jumplinux1"* choose *Linux*
  * For *"jumplinux1" has fingerprint...* choose *Continue*
  * For *Enter password...* enter the value of the *adminpassword* secret in the sandbox environment key vault.
  * Verify that *SSH:jumplinux1* is displayed in the blue status section in the lower left corner.
  * Navigate to *View* > *Explorer*
  * Click *Open Folder*
  * For *Open Folder* select the default folder (home directory) and click *OK*.
  * For *Enter password...* enter the value of the *adminpassword* secret in the sandbox environment key vault.
  * Select *Trust the authors of all files in the present folder 'home'*
  * Click *Yes, I trust the authors*
  * Navigate to *View* > *Terminal*.
  * Inspect the configuration of *jumplinux1* by executing the following Bash commands:

    ```bash
    # Verify Linux distribution
    cat /etc/*-release

    # Verify Azure CLI version
    az --version

    # Verify PowerShell version
    pwsh --version

    # Verify Terraform version
    terraform --version
    ```

  * Run the following Bash command to test SMB/cifs connectivity with Kerberos authentication to the Azure Files private endpoint:

    ```bash
    ll /fileshares/myfileshare/
    ```
  
  * Create some test folders and files on /fileshares/myfileshare.

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
* vnet-shared module
* vnet-app module

### Module Structure

This module is organized as follows:

```plaintext
├── images/
|   └── vm-jumpbox-linux-diagram.drawio.svg # Architecture diagram
├── scripts/
|   ├── configure-vm-jumpbox-linux.sh       # cloud-init shell script to configure the VM
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
adds_domain_name | mysandbox.local | The domain name defined in the vnet-shared module.
admin_username_secret | adminuser | The name of the key vault secret that contains the user name for the admin account. Defined in the vnet-shared module.
dns_server | `10.1.1.4` | The IP address of the DNS server used for the virtual network. Defined in the vnet-shared module.
key_vault_id | | The ID of the key vault defined in the root module.
key_vault_name | | The name of the key vault defined in the root module.
location | | The Azure region defined in the root module.
resource_group_name | | The name of the resource group defined in the root module.
storage_account_name | | The storage account name from the vnet-app module.
storage_share_name | | The Azure Files share name from the vnet-app module.
subnet_id | | The subnet ID from the vnet-app module.
tags | | The tags from the root module.
vm_jumpbox_linux_image_offer | `ubuntu-24_04-lts` | The offer type of the virtual machine image used to create the VM.
vm_jumpbox_linux_image_publisher | `Canonical` | The publisher for the virtual machine image used to create the VM.
vm_jumpbox_linux_image_sku | `server` | The SKU of the virtual machine image used to create the VM.
vm_jumpbox_linux_image_version | `Latest` | The version of the virtual machine image used to create the VM.
vm_jumpbox_linux_name | jumplinux1 | The name of the VM.
vm_jumpbox_linux_size | `Standard_B2ls_v2` | The size of the virtual machine.
vm_jumpbox_linux_storage_account_type | `Standard_LRS` | The storage type to be used for the VM's OS and data disks.

### Module Resources

This section lists the resources included in this configuration.

Address | Name | Notes
--- | --- | ---
module.vm_jumpbox_linux[0].azurerm_key_vault_secret.ssh_private_key | jumplinux1&#8209;ssh&#8209;private&#8209;key | The private SSH key stored in Azure Key Vault.
module.vm_jumpbox_linux[0].azurerm_linux_virtual_machine.this | jumplinux1 | The Linux virtual machine resource.
module.vm_jumpbox_linux[0].azurerm_network_interface.this | nic&#8209;sand&#8209;dev&#8209;jumplinux1 | The network interface associated with the Linux virtual machine.
module.vm_jumpbox_linux[0].azurerm_role_assignment.kv_secrets_user_vm_linux | | Role assignment for accessing Key Vault secrets from the Linux virtual machine.
module.vm_jumpbox_linux[0].tls_private_key.ssh_key | | The TLS private key used for SSH authentication.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Default | Comments
--- | --- | ---
resource_ids | | A map of resource IDs for key resources in the module.
resource_names | | A map of resource names for key resources in the module.
