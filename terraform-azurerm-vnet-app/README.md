# \#AzureSandbox - terraform-azurerm-vnet-app

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Next steps](#next-steps)
* [Videos](#videos)

## Architecture

![vnet-app-diagram](./vnet-app-diagram.drawio.svg)

## Overview

This configuration implements a virtual network for applications including ([Step-By-Step Video](https://youtu.be/J7jK-dxiFrA)):

* A [virtual network](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vnet) for hosting for hosting [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) and private endpoints implemented using [PrivateLink](https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview). [Virtual network peering](https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview) with [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) is automatically configured.
* A Windows Server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) for use as a jumpbox.
* A Linux [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) for use as a jumpbox.
* A [PaaS](https://azure.microsoft.com/overview/what-is-paas/) SMB file share hosted in [Azure Files](https://learn.microsoft.com/azure/storage/files/storage-files-introduction) with a private endpoint implemented using [PrivateLink](https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview).

Activity | Estimated time required
--- | ---
Bootstrap | ~5 minutes
Provisioning | ~30 minutes
Smoke testing | ~30 minutes

## Before you start

The following configurations must be deployed first before starting:

* [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared)

This configuration requires that the virtual machine *adds1* is running and available. You may experience failures if *adds1* is stopped or becomes unavailable during provisioning. It's a good idea to wait 30 minutes before attempting to provision this configuration to allow *adds1* adequate time to complete any post-provisioning patching and/or reboots.

## Getting started

This section describes how to provision this configuration using default settings ([Step-By-Step Video](https://youtu.be/seV-fT8QcO8)).

* Change the working directory.

  ```bash
  cd ~/azuresandbox/terraform-azurerm-vnet-app
  ```

* Add an environment variable containing the password for the service principal.

  ```bash
  export TF_VAR_arm_client_secret=YourServicePrincipalSecret
  ```

* Run [bootstrap.sh](./bootstrap.sh) using the default values or custom values.

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

  `Apply complete! Resources: 45 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 

  # Review output variables
  terraform output
  ```

## Smoke testing

The following sections provide guided smoke testing of each resource provisioned in this configuration, and should be completed in the order indicated ([Step-By-Step Video](https://youtu.be/J6QdXWtR_HU)).

* [Jumpbox smoke testing](#jumpbox-smoke-testing)
* [Azure Files smoke testing](#azure-files-smoke-testing)

### Jumpbox smoke testing

* Wait for 5 minutes to proceed to allow time for cloud-init configurations to complete. Note these steps assume default values were used when running [bootstrap.sh](./bootstrap.sh).

* Verify *jumplinux1* cloud-init configuration is complete.
  * From the client environment, navigate to *portal.azure.com* > *Virtual machines* > *jumplinux1*
  * Click *Connect*, then click *Connect via Bastion*
  * For *Authentication Type* choose `SSH Private Key from Azure Key Vault`
  * For *Username* enter `bootstrapadminlocal`
  * For *Azure Key Vault Secret* specify the following values:
    * For *Subscription* choose the same Azure subscription used to provision the #AzureSandbox.
    * For *Azure Key Vault* choose the key vault provisioned by [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared/#bootstrap-script), e.g. `kv-xxxxxxxxxxxxxxx`
    * For *Azure Key Vault Secret* choose `bootstrapadmin-ssh-key-private`
  * Expand *Advanced*
    * For *SSH Passphrase* enter the value of the *adminpassword* secret in key vault.
  * Click *Connect*
  * Execute the following command:

    ```bash
    cloud-init status
    ```

  * Verify that cloud-init status is `done`.
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

* Verify *jumpwin1* node configuration is compliant.
  * From the client environment, navigate to *portal.azure.com* > *Automation Accounts* > *auto-xxxxxxxxxxxxxxxx-01* > *Configuration Management* > *State configuration (DSC)*.
  * Refresh the data on the *Nodes* tab and verify that all nodes are compliant.
  * Review the data in the *Configurations* and *Compiled configurations* tabs as well.
  * Note: *jumplinux1* is configured using cloud-init, and is therefore not shown in the Azure Automation DSC *Nodes* tab.

* From the client environment, navigate to *portal.azure.com* > *Virtual machines* > *jumpwin1*
  * Click *Connect*, then click *Connect via Bastion*
  * For *Authentication Type* choose `Password from Azure Key Vault`
  * For *username* enter the UPN of the domain admin, which by default is `bootstrapadmin@mysandbox.local`
  * For *Azure Key Vault Secret* specify the following values:
    * For *Subscription* choose the same Azure subscription used to provision the #AzureSandbox.
    * For *Azure Key Vault* choose the key vault provisioned by [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared/#bootstrap-script), e.g. `kv-xxxxxxxxxxxxxxx`
    * For *Azure Key Vault Secret* choose `adminpassword`
  * Click *Connect*

* From *jumpwin1*, disable Server Manager
  * Navigate to *Server Manager* > *Manage* > *Server Manager Properties* and enable *Do not start Server Manager automatically at logon*
  * Close Server Manager

* From *jumpwin1*, inspect the *mysandbox.local* Active Directory domain
  * Navigate to *Start* > *Windows Administrative Tools* > *Active Directory Users and Computers*.
  * Navigate to *mysandbox.local* and verify that a computer account exists in the root for the storage account, e.g. *stxxxxxxxxxxx*.
  * Navigate to *mysandbox.local* > *Computers* and verify that *jumpwin1* and *jumplinux1* are listed.
  * Navigate to *mysandbox.local* > *Domain Controllers* and verify that *adds1* is listed.

* From *jumpwin1*, inspect the *mysandbox.local* DNS zone
  * Navigate to *Start* > *Windows Administrative Tools* > *DNS*
  * Connect to the DNS Server on *adds1*.
  * Click on *adds1* in the left pane
    * Double-click on *Forwarders* in the right pane.
    * Verify that [168.63.129.16](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16) is listed. This ensures that the DNS server will forward any DNS queries it cannot resolve to the Azure Recursive DNS resolver.
    * Click *Cancel*.
    * Navigate to *adds1* > *Forward Lookup Zones* > *mysandbox.local* and verify that there are *Host (A)* records for *adds1*, *jumpwin1* and *jumplinux1*.

* From *jumpwin1*, configure [Visual Studio Code](https://aka.ms/vscode) to do remote development on *jumplinux1*
  * Navigate to *Start* > *Visual Studio Code* > *Visual Studio Code*.
  * Click on the blue *Open a Remote Window* icon in the lower left corner
  * For *Select an option to open a Remote Window* choose `SSH`
  * For *Select configured SSH host or enter user@host* choose `+ Add New SSH Host...`
  * For *Enter SSH Connection Command* enter `ssh bootstrapadmin@mysandbox.local@jumplinux1`
  * For *Select SSH configuration file to update choose `C:\Users\bootstrapadmin\.ssh\config`

* From *jumpwin1*, open a remote window to *jumplinux1*
  * From Visual Studio Code, click on the blue *Open a Remote Window* icon in the lower left corner
  * For *Select an option to open a Remote Window* choose `Connect to Host...`
  * For *Select configured SSH host or enter user@host* choose `jumplinux1`
  * A new Visual Studio Code window will open.
  * For *Select the platform of the remote host "jumplinux1"* choose `Linux`
  * For *"jumplinux1" has fingerprint...* choose `Continue`
  * For *Enter password...* enter the value of the *adminpassword* secret in key vault.
  * Verify that *SSH:jumplinux1* is displayed in the blue status section in the lower left corner.
  * Navigate to *View* > *Explorer*
  * Click *Open Folder*
  * For *Open Folder* select the default folder (home directory) and click *OK*.
  * For *Enter password...* enter the value of the *adminpassword* secret in key vault.
  * If a Bash terminal is not visible, navigate to *View* > *Terminal*.
  * Inspect the configuration of *jumplinux1* by executing the following commands from Bash:

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

### Azure Files smoke testing

* Test DNS queries for Azure Files private endpoint
  * From the client environment, navigate to *portal.azure.com* > *Storage accounts* > *stxxxxxxxxxxx* > *File shares* > *myfileshare* and copy the the FQDN portion of the `Share URL`, e.g. *stxxxxxxxxxxx.file.core.windows.net*.
  * From *jumpwin1*, execute the following command from PowerShell:
  
    ```powershell
    Resolve-DnsName stxxxxxxxxxxx.file.core.windows.net
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.

* From *jumpwin1*, test SMB connectivity with integrated Windows Authentication to Azure Files private endpoint (PaaS)
  * Execute teh following command from PowerShell::
  
    ```powershell
    # Note: replace stxxxxxxxxxxxxx with the name of your storage account
    net use z: \\stxxxxxxxxxxx.file.core.windows.net\myfileshare
    ```

  * Create some test files and folders on the newly mapped Z: drive.

* From *jumplinux1*, verify SMB connectivity to Azure Files private endpoint (PaaS)
  * Execute the following commands Bash to verify access to the test files and folders you created from *jumpwin1*:

    ```bash
    ll /fileshares/myfileshare/
    ```

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a *terraform.tfvars* file for generating and applying Terraform plans ([Step-By-Step Video](https://youtu.be/EHxb01H4XSs)). For simplified deployment, several runtime defaults are initialized using output variables stored in the *terraform.tfstate* file associated with the [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared) configuration, including:

Output variable | Sample value
--- | ---
aad_tenant_id | "00000000-0000-0000-0000-000000000000"
adds_domain_name | "mysandbox.local"
admin_password_secret | "adminpassword"
admin_username_secret | "adminuser"
arm_client_id | "00000000-0000-0000-0000-000000000000"
automation_account_name | "auto-9a633c2bba9351cc-01"
dns_server | "10.1.1.4"
key_vault_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.KeyVault/vaults/kv-XXXXXXXXXXXXXXX"
key_vault_name | "kv-XXXXXXXXXXXXXXX"
location | "eastus"
resource_group_name | "rg-sandbox-01"
storage_account_name | "stXXXXXXXXXXXXXXX"
storage_container_name | "scripts"
subscription_id | "00000000-0000-0000-0000-000000000000"
tags | tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )
vnet_shared_01_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-shared-01"
vnet_shared_01_name | "vnet-shared-01"

Public internet access is temporarily enabled for the shared storage account so the following PowerShell scripts can be uploaded to the *scripts* container in the shared storage account using the access key stored in the key vault secret *storage_account_key*. These scripts are referenced by virtual machine extensions:

* [configure-storage-kerberos.ps1](./configure-storage-kerberos.ps1)
* [configure-vm-jumpbox-win.ps1](./configure-vm-jumpbox-win.ps1)

Public internet access is disabled again later during Terraform apply.

SSH keys are generated for use with [jumplinux1](#linux-jumpbox-vm). The private key is saved as a secret named `bootstrapadmin-ssh-key-private` in key vault. The secret is set to expire in 365 days.

Configuration of [Azure Automation State Configuration (DSC)](https://learn.microsoft.com/azure/automation/automation-dsc-overview) is performed by [configure-automation.ps1](./configure-automation.ps1) including the following:

* Configures [Azure Automation shared resources](https://learn.microsoft.com/azure/automation/automation-intro#shared-resources) including:
  * [Modules](https://learn.microsoft.com/azure/automation/shared-resources/modules)
    * Imports new modules including the following:
      * [cChoco](https://github.com/chocolatey/cChoco)
  * Imports [DSC Configurations](https://learn.microsoft.com/azure/automation/automation-dsc-getting-started#create-a-dsc-configuration) used in this configuration.
    * [JumpBoxConfig.ps1](./JumpBoxConfig.ps1): domain joins a Windows Server virtual machine and adds it to a `JumpBoxes` security group, then and configures it as jumpbox.
  * [Compiles DSC Configurations](https://learn.microsoft.com/azure/automation/automation-dsc-compile) so they can be used later to [Register a VM to be managed by State Configuration](https://learn.microsoft.com/azure/automation/tutorial-configure-servers-desired-state#register-a-vm-to-be-managed-by-state-configuration).

### Terraform resources

This section lists the resources included in this configuration.

#### Network resources

The configuration for these resources can be found in [020-network.tf](./020-network.tf). Some resources are pre-provisioned for use in other configurations ([Step-By-Step Video](https://youtu.be/5nxck-NXfk4)).

Resource name (ARM) | Configuration(s) | Notes
--- | --- | ---
azurerm_virtual_network . vnet_app_01 (vnet&#x2011;app&#x2011;01) | terraform-azurerm-vnet-app | By default this virtual network is configured with an address space of `10.2.0.0/16` and is configured with DNS server addresses of 10.1.2.4 (the private ip for *azurerm_windows_virtual_machine.vm_adds*) and [168.63.129.16](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16).
azurerm_subnet . vnet_app_01_subnets ["snet-app-01"] | terraform-azurerm-vnet-app | The default address prefix for this subnet is `10.2.0.0/24` and is reserved for web, application and jumpbox servers. A network security group is associated with this subnet that permits ingress and egress from virtual networks, and egress to the Internet.
azurerm_subnet . vnet_app_01_subnets ["snet-db-01"] | terraform-azurerm-vm-mssql | The default address prefix for this subnet is `10.2.1.0/24` which includes the private ip address for *azurerm_windows_virtual_machine.vm_mssql_win*. A network security group is associated with this subnet that permits ingress and egress from virtual networks, and egress to the Internet.
azurerm_subnet .vnet_app_01_subnets ["snet-privatelink-01"] | terraform-azurerm-vnet-app, terraform-azurerm-vm-mssql, terraform-azurerm-mssql | The default address prefix for this subnet is `10.2.2.0/24`. *private_endpoint_network_policies_enabled* is enabled for use with [PrivateLink](https://learn.microsoft.com/azure/private-link/private-link-overview). A network security group is associated with this subnet that permits ingress and egress from virtual networks.
azurerm_subnet . vnet_app_01_subnets ["snet-mysql-01"] | terraform-azurerm-mysql | The default address prefix for this subnet is `10.2.3.0/24`. *service_delegation_name* is set to `Microsoft.DBforMySQL/flexibleServers` for use with [subnet delegation](https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview). A network security group is associated with this subnet that permits ingress and egress from virtual networks.
azurerm_virtual_network_peering . vnet_shared_01_to_vnet_app_01_peering | terraform-azurerm-vnet-app | Establishes the [virtual network peering](https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview) relationship from *azurerm_virtual_network.vnet_shared_01* to *azurerm_virtual_network.vnet_app_01*.
azurerm_virtual_network_peering . vnet_app_01_to_vnet_shared_01_peering | terraform-azurerm-vnet-app |Establishes the [virtual network peering](https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview) relationship from *azurerm_virtual_network.vnet_app_01* to *azurerm_virtual_network.vnet_shared_01*.
azurerm_private_dns_zone . private_dns_zones ["privatelink.blob.core.windows.net"] | terraform-azurerm-vnet-app, terraform-azurerm-vm-mssql | Creates a [private Azure DNS zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) to use [Use private endpoints for Azure Storage](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints).
azurerm_private_dns_zone . private_dns_zones ["privatelink.database.windows.net"] | terraform-azurerm-mssql | Creates a [private Azure DNS zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) for using [Azure Private Link for Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview).
azurerm_private_dns_zone . private_dns_zones ["privatelink.file.core.windows.net"] | terraform-azurerm-vnet-app | Creates a [private Azure DNS zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) for using [Azure Private Link for Azure Files](https://learn.microsoft.com/azure/storage/common/storage-private-endpoints).
azurerm_private_dns_zone . private_dns_zones ["privatelink.mysql.database.azure.com"] | terraform-azurerm-mysql | Creates a [private Azure DNS zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) for using [Private Link for Azure Database for MySQL - Flexible Server](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-networking-private-link).
azurerm_private_dns_zone_virtual_network_link . private_dns_zone_virtual_network_links_vnet_app_01 [*] | terraform-azurerm-vnet-app, terraform-azurerm-mssql, terraform-azurerm-mysql | Links each of the private DNS zones with azurerm_virtual_network.vnet_app_01
azurerm_private_dns_zone_virtual_network_link . private_dns_zone_virtual_network_links_vnet_shared_01 [*] | terraform-azurerm-vnet-app, terraform-azurerm-mssql, terraform-azurerm-mysql | Links each of the private DNS zones with *var.remote_virtual_network_id*, which is the shared services virtual network.

#### Windows Server Jumpbox VM

The configuration for these resources can be found in [030-vm-jumpbox-win.tf](./030-vm-jumpbox-win.tf) ([Step-By-Step Video](https://youtu.be/J-Zz8EOCyi4)).

Resource name (ARM) | Notes
--- | ---
azurerm_windows_virtual_machine.vm_jumpbox_win (jumpwin1) | By default, provisions a [Standard_B2s](https://learn.microsoft.com/azure/virtual-machines/sizes-b-series-burstable) virtual machine for use as a jumpbox. See below for more information.
azurerm_network_interface.vm_jumpbox_win_nic_01 (nic&#x2011;jumpwin1&#x2011;1) | The configured subnet is *azurerm_subnet.vnet_app_01_subnets["snet-app-01"]*.
azurerm_virtual_machine_extension.vm_jumpbox_win_postdeploy_script | Downloads [configure&#x2011;vm&#x2011;jumpbox-win.ps1](./configure-vm-jumpbox-win.ps1) and [configure&#x2011;storage&#x2011;kerberos.ps1](./configure-storage-kerberos.ps1), then executes [configure&#x2011;vm&#x2011;jumpbox-win.ps1](./configure-vm-jumpbox-win.ps1) using the [Custom Script Extension for Windows](https://learn.microsoft.com/azure/virtual-machines/extensions/custom-script-windows). See below for more details.
azurerm_key_vault_access_policy.vm_jumpbox_win_secrets_get (jumpwin1) | Allows the VM to get secrets from key vault using a system assigned managed identity.

This Windows Server VM is used as a jumpbox for development and remote server administration.

* Guest OS: Windows Server 2022 Datacenter.
* By default the [patch assessment mode](https://learn.microsoft.com/en-us/azure/update-manager/assessment-options) is set to `AutomaticByPlatform` and `provision_vm_agent` is set to `true` to enable use of [Azure Update Manager Update or Patch Orchestration](https://learn.microsoft.com/en-us/azure/update-manager/updates-maintenance-schedules#update-or-patch-orchestration).
* *admin_username* and *admin_password* are configured using the key vault secrets *adminuser* and *adminpassword*.
* A system assigned managed identity is configured by default for use in DevOps related identity and access management scenarios.
* This resource is configured using a [provisioner](https://www.terraform.io/docs/language/resources/provisioners/syntax.html) that runs [aadsc-register-node.ps1](./aadsc-register-node.ps1) which registers the node with *azurerm_automation_account.automation_account_01* and applies the configuration [JumpBoxConfig](./JumpBoxConfig.ps1).
  * The virtual machine is domain joined  and added to `JumpBoxes` security group.
  * The following [Remote Server Administration Tools (RSAT)](https://learn.microsoft.com/windows-server/remote/remote-server-administration-tools) are installed:
    * Active Directory module for Windows PowerShell (RSAT-AD-PowerShell)
    * Active Directory Administrative Center (RSAT-AD-AdminCenter)
    * AD DS Snap-Ins and Command-Line Tools (RSAT-ADDS-Tools)
    * DNS Server Tools (RSAT-DNS-Server)
    * Failover Cluster Management Tools (RSAT-Clustering-Mgmt)
    * Failover Cluster Module for for Windows PowerShell (RSAT-Clustering-PowerShell)
  * The following software packages are pre-installed using [Chocolatey](https://chocolatey.org/why-chocolatey):
    * [vscode](https://community.chocolatey.org/packages/vscode)
    * [sql-server-management-studio](https://community.chocolatey.org/packages/sql-server-management-studio)
    * [microsoftazurestorageexplorer](https://community.chocolatey.org/packages/microsoftazurestorageexplorer)
    * [azcopy10](https://community.chocolatey.org/packages/azcopy10)
    * [azure-data-studio](https://community.chocolatey.org/packages/azure-data-studio)
    * [mysql.workbench](https://community.chocolatey.org/packages/mysql.workbench)
* Post-deployment configuration is then performed using a custom script extension that runs [configure&#x2011;vm&#x2011;jumpbox&#x2011;win.ps1](./configure-vm-jumpbox-win.ps1). For security, secrets are retrieved at runtime using system assigned managed identity.
  * [configure&#x2011;storage&#x2011;kerberos.ps1](./configure-storage-kerberos.ps1) is registered as a scheduled task then executed using domain administrator credentials. This script must be run on a domain joined Azure virtual machine, and configures the storage account for kerberos authentication with the Active Directory Domain Services domain used in the configurations. For security, secrets are retrieved at runtime using system assigned managed identity.

#### Linux Jumpbox VM

The configuration for these resources can be found in [040-vm-jumpbox-linux.tf](./040-vm-jumpbox-linux.tf) ([Step-By-Step Video](https://youtu.be/r0NzgE44BIg)).

Resource name (ARM) | Notes
--- | ---
azurerm_linux_virtual_machine.vm_jumpbox_linux (jumplinux1) | By default, provisions a [Standard_B2s](https://learn.microsoft.com/azure/virtual-machines/sizes-b-series-burstable) virtual machine for use as a Linux jumpbox virtual machine. See below for more details.
azurerm_network_interface.vm_jumpbox_linux_nic_01 | The configured subnet is *azurerm_subnet.vnet_app_01_subnets["snet-app-01"]*.
azurerm_key_vault_access_policy.vm_jumpbox_linux_secrets_get | Allows the VM to get secrets from key vault using a system assigned managed identity.

This Linux VM is used as a jumpbox for development and remote administration.

* Guest OS: Ubuntu 24.04 LTS (Noble Numbat)
* By default the [patch assessment mode](https://learn.microsoft.com/en-us/azure/update-manager/assessment-options) is set to `AutomaticByPlatform` and `provision_vm_agent` is set to `true` to enable use of [Azure Update Manager Update or Patch Orchestration](https://learn.microsoft.com/en-us/azure/update-manager/updates-maintenance-schedules#update-or-patch-orchestration).
* A system assigned [managed identity](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview) is configured by default for use in DevOps related identity and access management scenarios.
* A dependency on *azurerm_virtual_machine_extension.vm_jumpbox_win_postdeploy_script* is established. This custom script extension is used to run [configure-storage-kerberos.ps1](./configure-storage-kerberos.ps1) which is required in order to mount the Azure Files share using CIFS.
* This VM is configured with [cloud-init](https://learn.microsoft.com/azure/virtual-machines/linux/using-cloud-init#:~:text=%20There%20are%20two%20stages%20to%20making%20cloud-init,is%20already%20configured%20to%20use%20cloud-init.%20More%20) using a [Mime Multi Part Archive](https://cloudinit.readthedocs.io/en/latest/topics/format.html#mime-multi-part-archive) containing the following files:
  * [configure-vm-jumpbox-linux.yaml](./configure-vm-jumpbox-linux.yaml) is [Cloud Config Data](https://cloudinit.readthedocs.io/en/latest/topics/format.html#cloud-config-data) used to configure the VM.
    * Package updates are performed.
    * The following packages are installed:
      * [autofs](https://packages.ubuntu.com/jammy/autofs)
      * [azure-cli](https://learn.microsoft.com/cli/azure/what-is-azure-cli?view=azure-cli-latest)
      * [cifs-utils](https://packages.ubuntu.com/jammy/cifs-utils)
      * [jp](https://packages.ubuntu.com/jammy/jp)
      * [keyutils](https://packages.ubuntu.com/jammy/keyutils)
      * [krb5-config](https://packages.ubuntu.com/jammy/krb5-config)
      * [krb5-user](https://packages.ubuntu.com/jammy/krb5-user)
      * [libnss-winbind](https://packages.ubuntu.com/jammy/libnss-winbind)
      * [libpam-winbind](https://packages.ubuntu.com/jammy/libpam-winbind)
      * [ntp](https://packages.ubuntu.com/jammy/ntp)
      * [python3-pip](https://packages.ubuntu.com/jammy/python3-pip)
      * [samba](https://packages.ubuntu.com/jammy/samba)
      * [terraform](https://www.terraform.io/intro/index.html#what-is-terraform-)
      * [winbind](https://packages.ubuntu.com/jammy/winbind)
    * Packages are upgraded.
    * The VM is rebooted if necessary.
    * The file `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` is created to ensure that modifications to `/etc/netplan/50-cloud-init.yaml` are not overwritten after a reboot.
    * The file `/etc/azuresandbox-conf.json` is created to initialize variables in the [configure-vm-jumpbox-linux.sh](./configure-vm-jumpbox-linux.sh) script.
  * [configure-vm-jumpbox-linux.sh](./configure-vm-jumpbox-linux.sh) is a [User-Data Script](https://cloudinit.readthedocs.io/en/latest/topics/format.html#user-data-script) used to configure the VM. Runtime values are retrieved using [Instance Metadata](https://cloudinit.readthedocs.io/en/latest/topics/instancedata.html#instance-metadata).
    * Variables are initialized using the configuration file `/etc/azuresandbox-conf.json`.

      Variable | Sample value
      --- | ---
      adds_domain_name | `mysandbox.local`
      dns_server | `10.1.1.4`
      key_vault_name | `kv-xxxxxxxxxxxxxxx`
      storage_account_name" | `stxxxxxxxxxxxxxxx`
      storage_share_name | `myfileshare`

    * Secrets are retrieved from key vault using the VM's system assigned managed identity.
      * *adminuser*: The name of the administrative user account for configuring the VM (e.g. "bootstrapadmin" by default).
      * *adminpassword*: The password for the administrative user account.
    * The virtual machine is domain joined using winbind.
      * The SSH server is configured for logins using Active Directory accounts.
      * The *hosts* file is updated to reference the newly configured host name and domain name.
      * The netplan configuration is modified to configure DNS nameservers and IP addresses.
      * A new DHCP client exit hook script named `/etc/dhcp/dhclient-exit-hooks.d/hook-ddns` to implement dynamic DNS registration.
      * The *krb5.conf* file is modified to configure the domain name.
      * The *smb.conf* file is modified to configure the domain and workgroup names.
      * The virtual machine is domain joined.
      * The *ntp.conf* file is updated to synchronize the time with the domain controller.
      * The *nsswitch.conf* file is modified to look for users and groups using winbind.
      * Pluggable authentication modules are configured to use winbind and create home directories for domain users.
    * Dynamic mounting of the Azure Files share is enabled using autofs.
    * PowerShell and the Azure PowerShell Module are installed.

#### Storage resources

The configuration for these resources can be found in [070-storage-share.tf](./070-storage-share.tf) ([Step-By-Step Video](https://youtu.be/2-HwFEsIDJI)).

Resource name (ARM) | Notes
--- | ---
azurerm_storage_share.storage_share_01 | An [Azure Files](https://learn.microsoft.com/azure/storage/files/storage-files-introduction) SMB file share. See below for more information.
azurerm_private_endpoint.storage_account_01_blob | A private endpoint for connecting to the blob service endpoint of the shared storage account.
azurerm_private_dns_a_record.storage_account_01_blob | A DNS A record for resolving DNS queries to the blob endpoint of the shared storage account. This resource has a dependency on the *azurerm_private_dns_zone.private_dns_zones["privatelink.blob.core.windows.net"]* resource.
azurerm_private_endpoint.storage_account_01_file | A private endpoint for connecting to file service endpoint of the shared storage account.
azurerm_private_dns_a_record.storage_account_01_file | A DNS A record for resolving DNS queries to *azurerm_storage_share.storage_share_01* using PrivateLink. This resource has a dependency on the *azurerm_private_dns_zone.private_dns_zones["privatelink.file.core.windows.net"]* resource.
azapi_update_resource.update_storage_account | This resource is used to update the storage account to disable public network access which was temporarily enabled during the bootstrap process in order to upload scripts to the storage container.

* Hosted by the storage account created by [terraform-azurerm-vnet-shared/bootstrap.sh](../terraform-azurerm-vnet-shared/README.md#bootstrap-script).
* Connectivity using private endpoints is enabled. See [Use private endpoints for Azure Storage](https://learn.microsoft.com/azure/storage/common/storage-private-endpoints) for more information.
* Kerberos authentication is configured with the sandbox domain using a post-deployment script executed on *azurerm_windows_virtual_machine.vm_jumpbox_win*.

### Terraform output variables

This section lists the output variables defined in this configuration. Some of these may be used for automation in other configurations.

Output variable | Sample value
--- | ---
private_dns_zones | contains all the private dns zone definitions from this configuration including *privatelink.database.windows.net*, *privatelink.file.core.windows.net* and *privatelink.mysql.database.azure.com*.
storage_share_name | "myfileshare"
vnet_app_01_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-app-01"
vnet_app_01_name | "vnet-app-01"
vnet_app_01_subnets | Contains all the subnet definitions from this configuration including *snet-app-01*, *snet-db-01*, *snet-mysql-01* and *snet-privatelink-01*.

## Next steps

Move on to the next configuration [terraform-azurerm-vm-mssql](../terraform-azurerm-vm-mssql/).

## Videos

Video | Section
--- | ---
[Application virtual network (Part 1)](https://youtu.be/J7jK-dxiFrA) | [terraform-azurerm-vnet-app \| Overview](#overview)
[Application virtual network (Part 2)](https://youtu.be/seV-fT8QcO8) | [terraform-azurerm-vnet-app \| Getting started](#getting-started)
[Application virtual network (Part 3)](https://youtu.be/J6QdXWtR_HU) | [terraform-azurerm-vnet-app \| Smoke testing](#smoke-testing)
[Application virtual network (Part 4)](https://youtu.be/EHxb01H4XSs) | [terraform-azurerm-vnet-app \| Documentation \| Bootstrap script](#bootstrap-script)
[Application virtual network (Part 5)](https://youtu.be/5nxck-NXfk4) | [terraform-azurerm-vnet-app \| Documentation \| Network resources](#network-resources)
[Application virtual network (Part 6)](https://youtu.be/J-Zz8EOCyi4) | [terraform-azurerm-vnet-app \| Documentation \| Windows Server Jumpbox VM](#windows-server-jumpbox-vm)
[Application virtual network (Part 7)](https://youtu.be/r0NzgE44BIg) | [terraform-azurerm-vnet-app \| Documentation \| Linux Jumpbox VM](#linux-jumpbox-vm)
[Application virtual network (Part 8)](https://youtu.be/2-HwFEsIDJI) | [terraform-azurerm-vnet-app \| Documentation \| Storage resources](#storage-resources)
