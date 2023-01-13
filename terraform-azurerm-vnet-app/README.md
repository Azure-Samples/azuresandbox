# \#AzureSandbox - terraform-azurerm-vnet-app

![vnet-app-diagram](./vnet-app-diagram.drawio.svg)

## Contents

* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Next steps](#next-steps)

## Overview

This configuration implements a virtual network for applications including:

* A [virtual network](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vnet) for hosting for hosting [virtual machines](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm) and private endpoints implemented using [PrivateLink](https://docs.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview). [Virtual network peering](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview) with [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) is automatically configured.
* A Windows Server [virtual machine](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm) for use as a jumpbox.
* A Linux [virtual machine](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm) for use as a jumpbox.
* A [PaaS](https://azure.microsoft.com/en-us/overview/what-is-paas/) SMB file share hosted in [Azure Files](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-introduction) with a private endpoint implemented using [PrivateLink](https://docs.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview).

Activity | Estimated time required
--- | ---
Pre-configuration | ~5 minutes
Provisioning | ~30 minutes
Smoke testing | ~ 30 minutes

## Before you start

The following configurations must be deployed first before starting:

* [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared)

## Getting started

This section describes how to provision this configuration using default settings.

* Change the working directory.

  ```bash
  cd ~/azuresandbox/terraform-azurerm-vnet-app
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

  `Apply complete! Resources: 43 added, 0 changed, 0 destroyed.`

  *Note*: The script `aadsc-register-node-ps1` may report errors, but implements retry logic to ensure that Azure Automation Desired State Configuration node registration succeeds up to a maximum of 180 attempts.

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 

  # Review output variables
  terraform output
  ```

## Smoke testing

The following sections provide guided smoke testing of each resource provisioned in this configuration, and should be completed in the order indicated.

* [Windows Server jumpbox VM smoke testing](#windows-server-jumpbox-vm-smoke-testing)
* [Azure Files smoke testing](#azure-files-smoke-testing)

### Windows Server jumpbox VM smoke testing

* From the client environment, navigate to *portal.azure.com* > *Virtual machines* > *jumpwin1*
  * Click *Connect*, select the *Bastion* tab, then click *Use Bastion*
  * For *username* enter the UPN of the domain admin, which by default is *bootstrapadmin@mysandbox.local*.
  * For *password* use the value of the *adminpassword* secret in key vault.
  * Click *Connect*

* From *jumpwin1*, disable Server Manager
  * Navigate to *Server Manager* > *Manage* > *Server Manager Properties* and enable *Do not start Server Manager automatically at logon*
  * Close Server Manager

* From *jumpwin1*, Configure default browser
  * Navigate to *Settings* > *Apps* > *Default Apps* and set the default browser to *Microsoft Edge*.

* From *jumpwin1*, inspect the *mysandbox.local* Active Directory domain
  * Navigate to *Start* > *Windows Administrative Tools* > *Active Directory Users and Computers*.
  * Navigate to *mysandbox.local* and verify that a computer account exists in the root for the storage account, e.g. *stxxxxxxxxxxx*.
  * Navigate to *mysandbox.local* > *Computers* and verify that *jumpwin1*, *jumplinux1* and *mssqlwin1* are listed.
  * Navigate to *mysandbox.local* > *Domain Controllers* and verify that *adds1* is listed.

* From *jumpwin1*, inspect the *mysandbox.local* DNS zone
  * Navigate to *Start* > *Windows Administrative Tools* > *DNS*
  * Connect to the DNS Server on *adds1*.
  * Click on *adds1* in the left pane, then double-click on *Forwarders* in the right pane.
    * Verify that [168.63.129.16](https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16) is listed. This ensures that the DNS server will forward any DNS queries it cannot resolve to the Azure Recursive DNS resolver.
    * Click *Cancel*.
  * Navigate to *adds1* > *Forward Lookup Zones* > *mysandbox.local* and verify that there are *Host (A)* records for *adds1*, *jumpwin1*, *jumplinux1* and *mssqlwin1*.

* From *jumpwin1*, configure [Visual Studio Code](https://aka.ms/vscode) to do remote development on *jumplinux1*
  * Navigate to *Start* > *Visual Studio Code* > *Visual Studio Code*.
  * Install the [Remote-SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension.
    * Navigate to *View* > *Extensions*
    * Search for *Remote-SSH*
    * Click *Install*
  * Configure SSH
    * Navigate to *View* > *Command Palette...* and enter:

      ```text
      Remote-SSH: Add New SSH Host
      ```

    * When prompted for *Enter SSH Connection Command* enter:

      ```text
      ssh bootstrapadmin@mysandbox.local@jumplinux1
      ```

    * When prompted for *Select SSH configuration file to update* choose *C:\\Users\\bootstrapadmin\\.ssh\\config*.

  * Connect to SSH host
    * Navigate to *View* >  *Command Palette...* and enter:

      ```text
      Remote-SSH: Connect to Host
      ```

    * Select *jumplinux1*
      * A second Visual Studio Code window will open.
    * When prompted for *Select the platform of the remote host "jumplinux1"* select *Linux*.
    * When prompted for *"jumplinux1" has fingerprint...* select *Continue*.
    * When prompted for *Enter password* use the value of the *adminpassword* secret in key vault.
      * This will install Visual Studio code remote development binaries on *jumplinux1*.
    * Verify that *SSH:jumplinux1* is displayed in the green status section in the lower left hand corner.
    * Connect to remote file system
      * Navigate to *View* > *Explorer*
      * Click *Open Folder*
      * Accept the default folder (home directory) and click *OK*.
      * When prompted for *Enter password* use the value of the *adminpassword* secret in key vault.
      * When prompted with *Do you trust the authors of the files in this folder?* click *Yes, I trust the authors*.
      * Review the home directory structure displayed in Explorer.
    * Open a bash terminal
      * Navigate to *View* > *Terminal*. This will open up a new bash shell.
      * Inspect the configuration of *jumplinux1* by executing the following commands from the bash command prompt:
  
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
  * From the client environment, navigate to *portal.azure.com* > *Storage accounts* > *stxxxxxxxxxxx* > *File shares* > *myfileshare* > *Settings* > *Properties* and copy the the FQDN portion of the URL, e.g. *stxxxxxxxxxxx.file.core.windows.net*.
  * From *jumpwin1*, run the Windows PowerShell command:
  
    ```powershell
    Resolve-DnsName stxxxxxxxxxxx.file.core.windows.net
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
  * Note: This DNS query is resolved using the following resources:
    * *azurerm_private_dns_a_record.storage_account_01_file*
    * *azurerm_private_dns_zone.private_dns_zones["privatelink.file.core.windows.net"]*
    * *azurerm_private_dns_zone_virtual_network_link.private_dns_zone_virtual_network_links_vnet_app_01["privatelink.file.core.windows.net"]*

* From *jumpwin1*, test SMB connectivity with integrated Windows Authentication to Azure Files private endpoint (PaaS)
  * Open a Windows command prompt and enter the following command:
  
    ```text
    net use z: \\stxxxxxxxxxxx.file.core.windows.net\myfileshare
    ```

  * Create some test files and folders on the newly mapped Z: drive
  * Note: Integrated Windows Authentication was configured using [configure-storage-kerberos.ps1](./configure-storage-kerberos.ps1) which was run by *azurerm_virtual_machine_extension.vm_jumpbox_win_postdeploy_script*.
  * Note: SMB connectivity with storage key authentication to Azure Files via the Internet will not be tested because most ISP's block port 445.

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a *terraform.tfvars* file for generating and applying Terraform plans. For simplified deployment, several runtime defaults are initialized using output variables stored in the *terraform.tfstate* file associated with the [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared) configuration, including:

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

The following PowerShell scripts are uploaded to the *scripts* container in the storage account using the access key stored in the key vault secret *storage_account_key* so they can be referenced by virtual machine extensions:

* [configure-storage-kerberos.ps1](./configure-storage-kerberos.ps1)
* [configure-vm-jumpbox-win.ps1](./configure-vm-jumpbox-win.ps1)

Configuration of [Azure Automation State Configuration (DSC)](https://docs.microsoft.com/en-us/azure/automation/automation-dsc-overview) is performed by [configure-automation.ps1](./configure-automation.ps1) including the following:

* Configures [Azure Automation shared resources](https://docs.microsoft.com/en-us/azure/automation/automation-intro#shared-resources) including:
  * [Modules](https://docs.microsoft.com/en-us/azure/automation/shared-resources/modules)
    * Imports new modules including the following:
      * [cChoco](https://github.com/chocolatey/cChoco)
  * Imports [DSC Configurations](https://docs.microsoft.com/en-us/azure/automation/automation-dsc-getting-started#create-a-dsc-configuration) used in this configuration.
    * [JumpBoxConfig.ps1](./JumpBoxConfig.ps1): domain joins a Windows Server virtual machine and adds it to a `JumpBoxes` security group, then and configures it as jumpbox.
  * [Compiles DSC Configurations](https://docs.microsoft.com/en-us/azure/automation/automation-dsc-compile) so they can be used later to [Register a VM to be managed by State Configuration](https://docs.microsoft.com/en-us/azure/automation/tutorial-configure-servers-desired-state#register-a-vm-to-be-managed-by-state-configuration).

### Terraform Resources

This section lists the resources included in this configuration.

#### Network resources

The configuration for these resources can be found in [020-network.tf](./020-network.tf). Some resources are pre-provisioned for use in other configurations.

Resource name (ARM) | Configuration(s) | Notes
--- | --- | ---
azurerm_virtual_network . vnet_app_01 (vnet&#x2011;app&#x2011;01) | terraform-azurerm-vnet-app | By default this virtual network is configured with an address space of `10.2.0.0/16` and is configured with DNS server addresses of 10.1.2.4 (the private ip for *azurerm_windows_virtual_machine.vm_adds*) and [168.63.129.16](https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16).
azurerm_subnet . vnet_app_01_subnets ["snet-app-01"] | terraform-azurerm-vnet-app | The default address prefix for this subnet is `10.2.0.0/24` and is reserved for web, application and jumpbox servers. A network security group is associated with this subnet that permits ingress and egress from virtual networks, and egress to the Internet.
azurerm_subnet . vnet_app_01_subnets ["snet-db-01"] | terraform-azurerm-vm-mssql | The default address prefix for this subnet is `10.2.1.0/24` which includes the private ip address for *azurerm_windows_virtual_machine.vm_mssql_win*. A network security group is associated with this subnet that permits ingress and egress from virtual networks, and egress to the Internet.
azurerm_subnet .vnet_app_01_subnets ["snet-privatelink-01"] | terraform-azurerm-vnet-app, terraform-azurerm-mssql | The default address prefix for this subnet is `10.2.2.0/24`. *private_endpoint_network_policies_enabled* is enabled for use with [PrivateLink](https://docs.microsoft.com/en-us/azure/private-link/private-link-overview). A network security group is associated with this subnet that permits ingress and egress from virtual networks.
azurerm_subnet . vnet_app_01_subnets ["snet-mysql-01"] | terraform-azurerm-mysql | The default address prefix for this subnet is `10.2.3.0/24`. *service_delegation_name* is set to `Microsoft.DBforMySQL/flexibleServers` for use with [subnet delegation](https://docs.microsoft.com/en-us/azure/virtual-network/subnet-delegation-overview). A network security group is associated with this subnet that permits ingress and egress from virtual networks.
azurerm_virtual_network_peering . vnet_shared_01_to_vnet_app_01_peering | terraform-azurerm-vnet-app | Establishes the [virtual network peering](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview) relationship from *azurerm_virtual_network.vnet_shared_01* to *azurerm_virtual_network.vnet_app_01*.
azurerm_virtual_network_peering . vnet_app_01_to_vnet_shared_01_peering | terraform-azurerm-vnet-app |Establishes the [virtual network peering](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview) relationship from *azurerm_virtual_network.vnet_app_01* to *azurerm_virtual_network.vnet_shared_01*.
azurerm_private_dns_zone . private_dns_zones ["private.mysql.database.azure.com"] | terraform-azurerm-mysql | Creates a [private Azure DNS zone](https://docs.microsoft.com/en-us/azure/dns/private-dns-privatednszone) for using [Private Network Access for Azure Database for MySQL - Flexible Server](https://docs.microsoft.com/en-us/azure/mysql/flexible-server/concepts-networking-vnet).
azurerm_private_dns_zone . private_dns_zones ["privatelink.database.windows.net"] | terraform-azurerm-mssql | Creates a [private Azure DNS zone](https://docs.microsoft.com/en-us/azure/dns/private-dns-privatednszone) for using [Azure Private Link for Azure SQL Database](https://docs.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview).
azurerm_private_dns_zone . private_dns_zones ["privatelink.file.core.windows.net"] | terraform-azurerm-vnet-app | Creates a [private Azure DNS zone](https://docs.microsoft.com/en-us/azure/dns/private-dns-privatednszone) for using [Azure Private Link for Azure Files](https://docs.microsoft.com/en-us/azure/storage/common/storage-private-endpoints).
azurerm_private_dns_zone_virtual_network_link . private_dns_zone_virtual_network_links_vnet_app_01 [*] | terraform-azurerm-vnet-app, terraform-azurerm-mssql, terraform-azurerm-mysql | Links each of the private DNS zones with azurerm_virtual_network.vnet_app_01
azurerm_private_dns_zone_virtual_network_link . private_dns_zone_virtual_network_links_vnet_shared_01 [*] | terraform-azurerm-vnet-app, terraform-azurerm-mssql, terraform-azurerm-mysql | Links each of the private DNS zones with *var.remote_virtual_network_id*, which is the shared services virtual network.

#### Windows Server Jumpbox VM

The configuration for these resources can be found in [030-vm-jumpbox-win.tf](./030-vm-jumpbox-win.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_windows_virtual_machine.vm_jumpbox_win (jumpwin1) | By default, provisions a [Standard_B2s](https://docs.microsoft.com/en-us/azure/virtual-machines/sizes-b-series-burstable) virtual machine for use as a jumpbox. See below for more information.
azurerm_network_interface.vm_jumpbox_win_nic_01 (nic&#x2011;jumpwin1&#x2011;1) | The configured subnet is *azurerm_subnet.vnet_app_01_subnets["snet-app-01"]*.
azurerm_virtual_machine_extension.vm_jumpbox_win_postdeploy_script | Downloads [configure&#x2011;vm&#x2011;jumpbox-win.ps1](./configure-vm-jumpbox-win.ps1) and [configure&#x2011;storage&#x2011;kerberos.ps1](./configure-storage-kerberos.ps1), then executes [configure&#x2011;vm&#x2011;jumpbox-win.ps1](./configure-vm-jumpbox-win.ps1) using the [Custom Script Extension for Windows](https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows). See below for more details.

This Windows Server VM is used as a jumpbox for development and remote server administration.

* Guest OS: Windows Server 2022 Datacenter.
* By default the [patch orchestration mode](https://docs.microsoft.com/en-us/azure/virtual-machines/automatic-vm-guest-patching#patch-orchestration-modes) is set to `AutomaticByPlatform`.
* *admin_username* and *admin_password* are configured using the key vault secrets *adminuser* and *adminpassword*.
* This resource is configured using a [provisioner](https://www.terraform.io/docs/language/resources/provisioners/syntax.html) that runs [aadsc-register-node.ps1](./aadsc-register-node.ps1) which registers the node with *azurerm_automation_account.automation_account_01* and applies the configuration [JumpBoxConfig](./JumpBoxConfig.ps1).
  * The virtual machine is domain joined  and added to `JumpBoxes` security group.
  * The following [Remote Server Administration Tools (RSAT)](https://docs.microsoft.com/en-us/windows-server/remote/remote-server-administration-tools) are installed:
    * Active Directory module for Windows PowerShell (RSAT-AD-PowerShell)
    * Active Directory Administrative Center (RSAT-AD-AdminCenter)
    * AD DS Snap-Ins and Command-Line Tools (RSAT-ADDS-Tools)
    * DNS Server Tools (RSAT-DNS-Server)
  * The following software packages are pre-installed using [Chocolatey](https://chocolatey.org/why-chocolatey):
    * [az.powershell](https://community.chocolatey.org/packages/az.powershell)
    * [vscode](https://community.chocolatey.org/packages/vscode)
    * [sql-server-management-studio](https://community.chocolatey.org/packages/sql-server-management-studio)
    * [microsoftazurestorageexplorer](https://community.chocolatey.org/packages/microsoftazurestorageexplorer)
    * [azcopy10](https://community.chocolatey.org/packages/azcopy10)
    * [azure-data-studio](https://community.chocolatey.org/packages/azure-data-studio)
    * [mysql.workbench](https://community.chocolatey.org/packages/mysql.workbench)
* Post-deployment configuration is then performed using a custom script extension that runs [configure&#x2011;vm&#x2011;jumpbox&#x2011;win.ps1](./configure-vm-jumpbox-win.ps1).
  * [configure&#x2011;storage&#x2011;kerberos.ps1](./configure-storage-kerberos.ps1) is registered as a scheduled task then executed using domain administrator credentials. This script must be run on a domain joined Azure virtual machine, and configures the storage account for kerberos authentication with the Active Directory Domain Services domain used in the configurations.

#### Linux Jumpbox VM

The configuration for these resources can be found in [040-vm-jumpbox-linux.tf](./040-vm-jumpbox-linux.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_linux_virtual_machine.vm_jumpbox_linux (jumplinux1) | By default, provisions a [Standard_B2s](https://docs.microsoft.com/en-us/azure/virtual-machines/sizes-b-series-burstable) virtual machine for use as a Linux jumpbox virtual machine. See below for more details.
azurerm_network_interface.vm_jumbox_linux_nic_01 | The configured subnet is *azurerm_subnet.vnet_app_01_subnets["snet-app-01"]*.
azurerm_key_vault_access_policy.vm_jumpbox_linux_secrets_get | Allows the VM to get secrets from key vault using a system assigned managed identity.

This Linux VM is used as a jumpbox for development and remote administration.

* Guest OS: Ubuntu 20.04 LTS (Focal Fossa)
* By default the [patch orchestration mode](https://docs.microsoft.com/en-us/azure/virtual-machines/automatic-vm-guest-patching#patch-orchestration-modes) is set to `AutomaticByPlatform`.
* A system assigned [managed identity](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview) is configured by default for use in DevOps related identity and access management scenarios.
* Custom tags are added which are used by [cloud-init](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/using-cloud-init#:~:text=%20There%20are%20two%20stages%20to%20making%20cloud-init,is%20already%20configured%20to%20use%20cloud-init.%20More%20) [User-Data Scripts](https://cloudinit.readthedocs.io/en/latest/topics/format.html#user-data-script) to configure the virtual machine.
  * *keyvault*: Used in cloud-init scripts to determine which key vault to use for secrets.
  * *adds_domain_name*: Used in cloud-init scripts to join the domain.
* This VM is configured with [cloud-init](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/using-cloud-init#:~:text=%20There%20are%20two%20stages%20to%20making%20cloud-init,is%20already%20configured%20to%20use%20cloud-init.%20More%20) using a [Mime Multi Part Archive](https://cloudinit.readthedocs.io/en/latest/topics/format.html#mime-multi-part-archive) containing the following files:
  * [configure-vm-jumpbox-linux.yaml](./configure-vm-jumpbox-linux.yaml) is [Cloud Config Data](https://cloudinit.readthedocs.io/en/latest/topics/format.html#cloud-config-data) used to configure the VM.
    * The following packages are installed:
      * [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/what-is-azure-cli?view=azure-cli-latest)
      * [PowerShell Core](https://docs.microsoft.com/en-us/powershell/scripting/overview?view=powershell-7.1)
      * [Terraform](https://www.terraform.io/intro/index.html#what-is-terraform-)
      * [jp](https://packages.ubuntu.com/focal/jp)
      * [Kerberos](https://kerberos.org/software/mixenvkerberos.pdf) packages required to AD domain join a Linux host and enable dynamic DNS (DDNS) registration.
        * [krb5-user](https://packages.ubuntu.com/focal/krb5-user)
        * [samba](https://packages.ubuntu.com/focal/samba)
        * [sssd](https://packages.ubuntu.com/focal/sssd)
        * [sssd-tools](https://packages.ubuntu.com/focal/sssd-tools)
        * [libnss-sss](https://packages.ubuntu.com/focal/libnss-sss)
        * [libpam-sss](https://packages.ubuntu.com/focal/libpam-sss)
        * [ntp](https://packages.ubuntu.com/focal/ntp)
        * [ntpdate](https://packages.ubuntu.com/focal/ntpdate)
        * [realmd](https://packages.ubuntu.com/focal/realmd)
        * [adcli](https://packages.ubuntu.com/focal/adcli)
    * Package update and upgrades are performed.
    * The VM is rebooted if necessary.
  * [configure-vm-jumpbox-linux.sh](./configure-vm-jumpbox-linux.sh) is a [User-Data Script](https://cloudinit.readthedocs.io/en/latest/topics/format.html#user-data-script) used to configure the VM.
    * Runtime values are retrieved using [Instance Metadata](https://cloudinit.readthedocs.io/en/latest/topics/instancedata.html#instance-metadata)
      * The name of the key vault used for secrets is retrieved from the tag named *keyvault*.
      * The Active Directory domain name is retrieved from the tag named *adds_domain_name*.
      * An access token is generated using the VM's system assigned managed identity.
      * The access token is used to get secrets from key vault, including:
        * *adminuser*: The name of the administrative user account for configuring the VM (e.g. "bootstrapadmin" by default).
        * *adminpassword*: The password for the administrative user account.
      * The networking configuration of the VM is modified to enable domain joining the VM
        * The *hosts* file is updated to reference the newly configured host name and domain name.
        * The DHCP client configuration file *dhclient.conf* is updated to include the newly configured domain name.
      * The VM is domain joined
        * The *ntp.conf* file is updated to synchronize the time with the domain controller.
        * The *krb5.conf* file is updated to disable the *rdns* setting.
        * *dhclient* is run to refresh the DHCP settings using the new networking configuration.
        * *realm join* is run to join the domain
      * The VM is registered with the DNS server
        * A local *keytab* file is created and used to authenticate with the domain using *kinit*
        * A new A record is added to the DNS server using *nsupdate*.
      * Dynamic DNS registration is configured
        * A new DHCP client exit hook script named `/etc/dhcp/dhclient-exit-hooks.d/hook-ddns` is created which runs whenever the DHCP client exits.
          * The script uses *kinit* to authenticate with the domain using the previously created keytab file.
          * The old A record is deleted and a new A record is added to the DNS server using *nsupdate*.
      * Privileged access management is configured.
        * Automatic home directory creation is enabled.
        * The domain administrator account is configured.
          * Logins are permitted.
          * Sudo privileges are granted.
      * SSH server is configured for logins using Active Directory accounts.

#### Storage resources

The configuration for these resources can be found in [070-storage-share.tf](./070-storage-share.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_storage_share.storage_share_01 | An [Azure Files](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-introduction) SMB file share. See below for more information.
azurerm_private_endpoint.storage_account_01_file | A private endpoint for connecting to file service endpoint of the shared storage account.
azurerm_private_dns_a_record.storage_account_01_file | A DNS A record for resolving DNS queries to *azurerm_storage_share.storage_share_01* using PrivateLink. This resource has a dependency on the *azurerm_private_dns_zone.file_core_windows_net* resource.

* Hosted by the storage account created by [terraform-azurerm-vnet-shared/bootstrap.sh](../terraform-azurerm-vnet-shared/README.md#bootstrap-script).
* Connectivity using private endpoints is enabled. See [Use private endpoints for Azure Storage](https://docs.microsoft.com/en-us/azure/storage/common/storage-private-endpoints) for more information.
* Kerberos authentication is configured with the sandbox domain using a post-deployment script executed on *azurerm_windows_virtual_machine.vm_jumpbox_win*.

### Terraform output variables

This section lists the output variables defined in this configuration. Some of these may be used for automation in other configurations.

Output variable | Sample value
--- | ---
private_dns_zones | contains all the private dns zone definitions from this configuration including *privatelink.database.windows.net*, *privatelink.file.core.windows.net* and *private.mysql.database.azure.com*.
vnet_app_01_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-app-01"
vnet_app_01_name | "vnet-app-01"
vnet_app_01_subnets | Contains all the subnet definitions from this configuration including *snet-app-01*, *snet-db-01*, *snet-mysql-01* and *snet-privatelink-01*.

## Next steps

Move on to the next configuration [terraform-azurerm-vm-mssql](../terraform-azurerm-vm-mssql).
