# \#AzureSandbox extras - terraform-azurerm-rg-devops

## Contents

* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Next steps](#next-steps)

## Overview

This configuration implements a stand alone DevOps environment which can be accessed from your private network and used to develop and run Terraform configurations and provisioners, including:

* A [resource group](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#resource-group) which contains DevOps environment resources.
* A [key vault](https://learn.microsoft.com/azure/key-vault/general/overview) for managing secrets.
* A [storage account](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#storage-account) for use as a [Terraform azurerm backend](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm).
* A Linux [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) for use as a DevOps agent.

Activity | Estimated time required
--- | ---
Pre-configuration | ~5 minutes
Provisioning | ~5 minutes
Smoke testing | ~ 15 minutes

## Before you start

* A suitable client environment must be configured in order to provision this configuration. See [Configure client environment](../../README.md/#configure-client-environment) for more information.
* This configuration requires that a subnet be provisioned in advance on the same subscription with connectivity to your private network. The resource id for this subnet must be obtained in advance using the following format:

    ```text
    /subscriptions/SomeSubscriptionGuid
        /resourcegroups/SomeResourceGroupName
            /providers/Microsoft.Network/virtualNetworks/SomeVirtualNetworkName
                /subnets/SomeSubnetName
    ```

    **Note:** Line feeds and indents are included here for readability only and should be removed.

## Getting started

* Open a Bash terminal in your client environment and execute the following commands:

  ```bash
  # Log out of Azure and clear cached credentials (skip if using cloudshell)
  az logout

  # Clear cached credentials (skip if using cloudshell)
  az account clear

  # Log into Azure (skip if using cloudshell)
  az login
  ```

* Change the working directory.

  ```bash
  cd ~/azuresandbox/extras/terraform-azurerm-rg-devops
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

  `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

The following sections provide guided smoke testing of each resource provisioned in this configuration, and should be completed in the order indicated. Smoke testing should be completed from a Windows computer that has access to your private network.

* [Connect using SSH](#connect-using-ssh)
* [VS Code remote development over SSH](#vs-code-remote-development-over-ssh)

### Connect using SSH

* Locate the virtual machine `jumplinux1` in the Azure portal.
  * Start the virtual machine if it is not currently running.
  * Make a note of the private IP address which will be referred to subsequently as `PrivateIPAddress`
* Configure SSH identity file on SSH client
  * Copy the the value of the secret `bootstrapadmin-ssh-key-private` in key vault.
  * Paste the secret value into a new text file.
  * Save the new text file as `C:\Users\YourUserName\.ssh\bootstrapadmin-ssh-key-private.txt`.
* Open a PowerShell command prompt and execute the following commands:

    ```powershell
    # Change current directory to .ssh
    cd C:\Users\YourUserName\.ssh

    # Open SSH connection using identity file
    ssh -i .\bootstrapadmin-ssh-key-private.txt bootstrapadmin@PrivateIPAddress
    ```

* If prompted to continue connecting, answer `yes`.
* When prompted for the passphrase, enter the value of the `adminpassword` secret from key vault.
* Execute the following commands:

    ```bash
    # Verify Azure CLI is installed
    az --version

    # Verify Terraform is installed
    terraform --version

    # Verify PowerShell is installed
    pwsh --version

    # Verify Azure PowerShell modules are installed
    pwsh 0 -c "Get-Module -ListAvailable"
    ```

### VS Code remote development over SSH

* Review [Remote development over SSH](https://code.visualstudio.com/docs/remote/ssh-tutorial)
* Install [VS Code](https://aka.ms/vscode) on a computer that has access to your private network.
* Launch VS Code
* Install the [Remote-SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension.
* Navigate to *View > Command Palette...* and enter `Remote-SSH: Add New SSH Host`
  * When prompted for *Enter SSH Connection Command* enter `ssh bootstrapadmin@PrivateIPAddress`
  * When promoted for *Enter SSH configuration file to update* select `C:\Users\YourUserName\.ssh\config`.
* Navigate to *View > Command Palette...* and enter `Remote-SSH: Open SSH Configuration File...`
  * When prompted for *Select SSH configuration file to update* select `C:\Users\YourUserName\.ssh\config`.
  * Edit the configuration file as follows:

    ```text
    Host jumplinux1
        HostName PrivateIPAddress
        User bootstrapadmin
        IdentityFile C:\\Users\\YourUserName\\.ssh\\bootstrapadmin-ssh-key-private.txt
    ```

    * Save the modified configuration file.
* Navigate to *View > Command Palette...* and enter `Remote-SSH: Connect to Host...`.
  * Choose `jumplinux1` from the list.
  * When prompted for *Select the platform of the remote host "jumplinux1"* choose `Linux`
    * When prompted for *Enter passphrase for ssh key* enter the value of the `adminpassword` secret
* Navigate to *View > Explorer* and click `Open Folder`
  * Choose the default folder `/home/bootstrapadmin/`
  * When prompted for *Enter passphrase for ssh key* enter the value of the `adminpassword` secret in key vault
    * When prompted for *Do you trust the authors of the files in this folder?* enable the checkbox `Trust the authors of all files in the parent folder 'home'` and click `Yes, I trust the authors`.
* Navigate to *View > Terminal*
  * Execute the following commands:

    ```bash
    # Verify Azure CLI is installed
    az --version

    # Verify Terraform is installed
    terraform --version

    # Verify PowerShell is installed
    pwsh --version

    # Verify Azure PowerShell modules are installed
    pwsh -c "Get-Module -ListAvailable"
    ```

* Install any additional VS Code extensions required for [Remote development over SSH](https://code.visualstudio.com/docs/remote/ssh-tutorial).
  * [HashiCorp Terraform](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform)
  * [PowerShell](https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell)

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a `terraform.tfvars` file for generating and applying Terraform plans. The script is idempotent.

* User is prompted for input.
* An existing resource group is located or a new resource group is created
* Key vault operations
  * An existing key vault is located or a new key vault is created.
  * A Key vault access policy for managing secrets is set for to the security principal logged into the Azure CLI.
  * An `adminusername` secret is created with the default value "bootstrapadmin".
  * A strong password is generated.
  * An `adminpassword` secret is created with the value set to the generated strong password.
  * An SSH public/private key pair is generated
  * A `bootstrapadmin-ssh-key-public` is created with the value set to the public SSH key.
  * A `bootstrapadmin-ssh-key-private` is created with the value set to the private SSH key.
* A `terraform.tfvars` file is generated.

### Terraform resources

This section lists the resources included in this configuration.

#### Storage resources

The configuration for these resources can be found in [020-storage.tf](./020-storage.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_storage_account.st_tfm (stxxxxxxxxxxxxxxx) | Used to host containers to store Terraform state files
azurerm_storage_container.container_tfstate | Container for storing Terraform state files.
azurerm_key_vault_secret.storage_account_key | Key vault secret with the same name as the storage account with the value set to the storage account key.
random_id.random_id_st_tfm_name | Used to generate a random name for azurerm_storage_account.st_tfm.

#### Linux Jumpbox VM

The configuration for these resources can be found in [030-vm-jumpbox-linux.tf](./030-vm-jumpbox-linux.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_linux_virtual_machine.vm_jumpbox_linux (jumplinux1) | By default, provisions a [Standard_B2s](https://learn.microsoft.com/azure/virtual-machines/sizes-b-series-burstable) virtual machine for use as a Linux jumpbox virtual machine. See below for more details.
azurerm_network_interface.vm_jumpbox_linux_nic_01 | The configured subnet is `var.subnet_id`.
azurerm_key_vault_access_policy.vm_jumpbox_linux_secrets_reader | Allows the VM to get named secrets from key vault using a system assigned managed identity.

This Linux virtual machine is a stripped down down version of [jumplinux1](../../terraform-azurerm-vnet-app/README.md#linux-jumpbox-vm) from `#AzureSandbox` that can be used as a DevOps agent on your private network. The biggest difference is that it is not domain joined or registered with your private DNS, so SSH public key authentication to a private IP address is used for connectivity.

* Guest OS: Ubuntu 22.04 LTS (Jammy Jellyfish)
* By default the [patch orchestration mode](https://learn.microsoft.com/azure/virtual-machines/automatic-vm-guest-patching#patch-orchestration-modes) is set to `AutomaticByPlatform`.
* A system assigned [managed identity](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview) is configured by default for use in DevOps related identity and access management scenarios.
* Custom tags are added which can be used by [cloud-init](https://learn.microsoft.com/azure/virtual-machines/linux/using-cloud-init#:~:text=%20There%20are%20two%20stages%20to%20making%20cloud-init,is%20already%20configured%20to%20use%20cloud-init.%20More%20) [User-Data Scripts](https://cloudinit.readthedocs.io/en/latest/topics/format.html#user-data-script).
  * *keyvault*: Used in cloud-init scripts to determine which key vault to use for secrets.
* This VM is configured with [cloud-init](https://learn.microsoft.com/azure/virtual-machines/linux/using-cloud-init#:~:text=%20There%20are%20two%20stages%20to%20making%20cloud-init,is%20already%20configured%20to%20use%20cloud-init.%20More%20) using a [Mime Multi Part Archive](https://cloudinit.readthedocs.io/en/latest/topics/format.html#mime-multi-part-archive) containing the following files:
  * [configure-vm-jumpbox-linux.yaml](./configure-vm-jumpbox-linux.yaml) is [Cloud Config Data](https://cloudinit.readthedocs.io/en/latest/topics/format.html#cloud-config-data) used to configure the VM.
    * The following packages are installed:
      * [Azure CLI](https://learn.microsoft.com/cli/azure/what-is-azure-cli?view=azure-cli-latest)
      * [Terraform](https://www.terraform.io/intro/index.html#what-is-terraform-)
      * [PowerShell](https://learn.microsoft.com/powershell/scripting/overview?view=powershell-7.1)
      * [python3-pip](https://pypi.org/project/pip/)
      * [jp](https://packages.ubuntu.com/focal/jp)
    * Package updates are performed.
    * The VM is rebooted if necessary.
    * Add environment variables to instruct Terraform azurerm provider to use managed identities:
      * `ARM_USE_MSI=true`
      * `ARM_TENANT_ID=00000000-0000-0000-0000-000000000000`
  * [install-pyjwt.sh](./install-pyjwt.sh) is a [User-Data Script](https://cloudinit.readthedocs.io/en/latest/topics/format.html#user-data-script) used to configure the VM.
    * [pyjwt](https://pyjwt.readthedocs.io/en/latest/) Python package is installed.
  * [configure-powershell.ps1](./configure-powershell.ps1) is a [User-Data Script](https://cloudinit.readthedocs.io/en/latest/topics/format.html#user-data-script) that installs [Azure PowerShell](https://learn.microsoft.com/en-us/powershell/azure/what-is-azure-powershell?view=azps-9.5.0)

### Additional use cases

* **Bastion Connectivity**: This configuration is designed to enable SSH connectivity from client computers to [jumplinux1](#linux-jumpbox-vm) on your private network. Connectivity can also be enabled using a [bastion](https://learn.microsoft.com/azure/bastion/bastion-overview) with connectivity to `var.subnet_id`. See [Create an SSH connection to a Linux VM using Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/bastion-connect-vm-ssh-linux) and [Private key - Azure Key Vault](https://learn.microsoft.com/en-us/azure/bastion/bastion-connect-vm-ssh-linux#private-key---azure-key-vault) for more information.

### DevOps security

This section describes DevOps security best practices for development and deployment of Terraform configurations using [jumplinux1](#linux-jumpbox-vm), and in particular how to avoid the use of shared secrets via managed identities.

* Configure role assignments for [Managed identities](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview).
  * Add an Azure RBAC `Contributor` role assignment for the system-assigned managed identity associated with [jumplinux1](#linux-jumpbox-vm) to the appropriate Azure subscriptions.  
  * If use of service principals is required for a specific configuration, add an Azure Active Directory `DirectoryReader` role assignment for the system-assigned managed identity associated with [jumplinux1](#linux-jumpbox-vm).
* Authenticate using managed identities
  * **Azure CLI**: Use `az login --identity` to [Sign in with a managed identity](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli#sign-in-with-a-managed-identity).
  * **PowerShell**: Use `Connect-AzAccount -Identity` to [Sign in with a managed identity](https://learn.microsoft.com/en-us/powershell/azure/authenticate-azureps?view=azps-9.5.0#sign-in-using-a-managed-identity).
  * Update your Terraform configurations to support [Authenticating using Managed Identity](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/guides/managed_service_identity).
    * Note that `jumplinux1` is pre-configured with the Terraform environment variables `ARM_USE_MSI=true` and `ARM_TENANT_ID=00000000-0000-0000-0000-000000000000` to authenticate using a managed identity.
* [Store Terraform state in Azure Storage](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage?tabs=azure-cli)
  * `azurerm_storage_account.st_tfm` is pre-configured with a container `azurerm_storage_container.container_tfstate`.
  * Note this configuration does not use a Terraform state backend to avoid circular dependencies. Once you have provisioned this configuration, you can begin using `azurerm_storage_container.container_tfstate` as a Terraform state backend for other configurations.
  * The following configuration demonstrates how to use managed identities to authenticate with a Terraform backend hosted in Azure Storage.
    * Set up environment variables to instruct Terraform azurerm provider to use managed identities

    ```bash
    # Ensure 
    export ARM_USE_MSI=true
    export ARM_TENANT_ID=00000000-0000-0000-0000-000000000000
    ```

    * Write Terraform configuration to use Terraform azurerm backend for state and authenticate with managed identity.

    ```hcl
    terraform {
      required_providers {
        azurerm = {
          source = "hashicorp/azurerm"
          version = "=3.65.0"
        }
      }
    
      # Configure state backend to use managed identities
      backend "azurerm" {
        resource_group_name  = "rg-devops-tf"
        storage_account_name = "stxxxxxxxxxxxxxxxx"
        container_name       = "tfstate"
        key                  = "terraform.tfstate"
        use_msi              = true
        subscription_id      = "00000000-0000-0000-0000-000000000000"
      }
    }

    provider "azurerm" {
      features {}
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }

    resource "azurerm_resource_group" "state-demo-secure" {
      name     = "state-demo"
      location = "eastus"
    }
    ```

**Note**: See [Use GitHub Actions to connect to Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-portal%2Cwindows) to use OpenID Connect and federated credentials to authenticate. This is ideal for applying Terraform configurations in DevOps pipelines.

## Next steps

Start building and deploying your own Terraform configurations using the best practices detailed in [DevOps security](#devops-security).
