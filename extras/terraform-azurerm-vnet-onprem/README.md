# #AzureSandbox - terraform-azurerm-vnet-onprem

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Videos](#videos)
* [Troubleshooting](#troubleshooting)

## Architecture

![vnet-onprem-diagram](./vnet-onprem-diagram.drawio.svg)

## Overview

This configuration simulates connectivity to an on-premises network using a site-to-site VPN connection and Azure DNS private resolver ([Step-By-Step Video](https://youtu.be/S-Ma-sRkcN0)). It includes the following resources:

* Simulated on-premises environment
  * A [virtual network](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vnet) for hosting [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm).
  * A [VPN gateway site-to-site VPN](https://learn.microsoft.com/en-us/azure/vpn-gateway/design#s2smulti) connection to simulate connectivity from an on-premises network to Azure.
  * A Windows Server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) running [Active Directory Domain Services](https://learn.microsoft.com/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview) with a pre-configured domain and DNS server.
  * A Windows Server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) for use as a jumpbox.
* Azure Sandbox environment
  * A [Virtual WAN site-to-site VPN](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#s2s) connection to simulate connectivity from Azure to an on-premises network.
  * A [DNS private resolver](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview) is used to resolve DNS queries for private zones in both environments (on-premises and Azure) in a bi-directional fashion.

## Before you start

The following configurations must be provisioned before starting:

* [terraform-azurerm-vnet-shared](../../terraform-azurerm-vnet-shared/)
* [terraform-azurerm-vnet-app](../../terraform-azurerm-vnet-app/)
* [terraform-azurerm-vm-mssql](../../terraform-azurerm-vm-mssql/)
* [terraform-azurerm-mssql](../../terraform-azurerm-mssql/)
* [terraform-azurerm-mysql](../../terraform-azurerm-mysql/)
* [terraform-azurerm-vwan](../../terraform-azurerm-vwan/)

Make sure all virtual machines are started, and that Azure Automation DSC is reporting that all node registrations are `Compliant`.

## Getting started

This section describes how to provision this configuration using default settings ([Step-By-Step Video](https://youtu.be/yVhdhcelYMU)).

* Change the working directory.

  ```bash
  cd ~/azuresandbox/extras/terraform-azurerm-vnet-onprem
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

  `Apply complete! Resources: 24 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

This smoke testing is divided into two sections ([Step-By-Step Video](https://youtu.be/4t1oh-roSrg)):

* [Test connectivity from cloud to on-premises](#test-connectivity-from-cloud-to-on-premises)
* [Test connectivity from on-premises to cloud](#test-connectivity-from-on-premises-to-cloud)

### Test connectivity from cloud to on-premises

#### Test RDP (port 3389) connectivity to *jumpwin2* private endpoint (IaaS)

* Connect to *jumpwin1*.
  * From the client environment, navigate to *portal.azure.com* > *Virtual machines* > *jumpwin1*
  * Click *Connect*, then click *Connect via Bastion*
  * For *Authentication Type* choose `Password from Azure Key Vault`
  * For *username* enter the UPN of the domain admin, which by default is `bootstrapadmin@mysandbox.local`
  * For *Azure Key Vault Secret* specify the following values:
    * For *Subscription* choose the same Azure subscription used to provision the #AzureSandbox.
    * For *Azure Key Vault* choose the key vault provisioned by [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared/#bootstrap-script), e.g. `kv-xxxxxxxxxxxxxxx`
    * For *Azure Key Vault Secret* choose `adminpassword`
  * Click *Connect*

* Test cloud to on-premises private DNS zones from *jumpwin1*.
  * From a Windows PowerShell command prompt, run the following command:

    ```powershell
    Resolve-DnsName jumpwin2.myonprem.local
    ```

  * Verify the *IPAddress* returned is within the IP address prefix for *azurerm_subnet.vnet_shared_02_subnets["snet-misc-04"]*, e.g. `192.168.2.4`.

* Test cloud to on-premises RDP connectivity (port 3389) from *jumpwin1*
  * Navigate to *Start* > *Windows Accessories* > *Remote Desktop Connection*
  * For *Computer*, enter `jumpwin2.myonprem.local`
  * For *User name*, enter `boostrapadmin@myonprem.local`
  * Click *Connect*
  * For *Password*, enter the value of the *adminpassword* secret in key vault
  * Click *OK*

### Test connectivity from on-premises to cloud

This smoke testing uses the RDP connection to *jumpwin2* established previously from *jumpwin1* and is divided into the following sections:

* [Test SSH (port 22) connectivity to *jumplinux1* private endpoint (IaaS)](#test-ssh-port-22-connectivity-to-jumplinux1-private-endpoint-iaas)
* [Test SMB (port 445) connectivity to Azure Files private endpoint (PaaS)](#test-smb-port-445-connectivity-to-azure-files-private-endpoint-paas)
* [Test TDS (port 1433) connectivity to *mssqlwin1* private endpoint (IaaS)](#test-tds-port-1433-connectivity-to-mssqlwin1-private-endpoint-iaas)
* [Test TDS (port 1433) connectivity to Azure SQL Database private endpoint (PaaS)](#test-tds-port-1433-connectivity-to-azure-sql-database-private-endpoint-paas)
* [Test port 3306 connectivity to Azure MySQL Flexible Server private endpoint (PaaS)](#test-port-3306-connectivity-to-azure-mysql-flexible-server-private-endpoint-paas)

#### Test SSH (port 22) connectivity to *jumplinux1* private endpoint (IaaS)

* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  Resolve-DnsName jumplinux1.mysandbox.local
  ```

* Verify the *IP4Address* returned is within the IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-app-01"]*, e.g. `10.2.0.5`.
* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  ssh bootstrapadmin@mysandbox.local@jumplinux1.mysandbox.local
  ```

* Enter `yes` when prompted `Are you sure you want to continue connecting?`
* Enter the value of the *adminpassword* secret when prompted for a password.
* Enter `exit` to terminate the SSH session.

#### Test SMB (port 445) connectivity to Azure Files private endpoint (PaaS)

* From the client environment, Navigate to *portal.azure.com* > *Storage accounts* > *stxxxxxxxxxxxxxxx* > *Settings* > *Endpoints* > *File service* and copy the FQDN for the `File service`, e.g. `stxxxxxxxxxxxxx.file.core.windows.net`.
* From *jumpwin2*, run the following Windows PowerShell command:

  ```powershell
  # Replace FQDN with the value copied previously.
  Resolve-DnsName stxxxxxxxxxxxxx.file.core.windows.net
  ```

* Verify the *IP4Address* returned is within the IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  # Replace FQDN with the value copied previously.
  net use z: \\stxxxxxxxxxxx.file.core.windows.net\myfileshare /USER:bootstrapadmin@mysandbox.local
  ```

* For *Password*, enter the value of the *adminpassword* secret in key vault.
* Create some test files and folders on the newly mapped Z: drive.
* Unmap the z: drive using the following command:

  ```powershell
  net use z: /delete
  ```

#### Test TDS (port 1433) connectivity to *mssqlwin1* private endpoint (IaaS)

* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  # Replace FQDN with the value copied previously.
  Resolve-DnsName mssqlwin1.mysandbox.local
  ```

* Verify the *IP4Address* returned is within the IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-db-01"]*, e.g. `10.2.1.4`.
* Navigate to *Start* > *Microsoft SQL Server Tools 19* > *Microsoft SQL Server Management Studio 19*.
* Connect to the default instance of SQL Server installed on mssqlwin1 using the following values:
  * Server name: *mssqlwin1.mysandbox.local*
  * Authentication: *SQL Server Authentication*
    * Login: `sa`
    * Password: Use the value of the *adminpassword* secret in key vault.
* Close SQL Server Management Studio.

#### Test TDS (port 1433) connectivity to Azure SQL Database private endpoint (PaaS)

* From the client environment, navigate to *portal.azure.com* > *SQL Servers* > *mssql-xxxxxxxxxxxxxxxx* > *Properties* > *Server name* and copy the the FQDN, e.g. *mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net*.
* From *jumpwin2*, run the following Windows PowerShell command:

  ```powershell
  # Replace FQDN with the value copied previously.
  Resolve-DnsName mssql-xxxxxxxxxxxxxxxx.database.windows.net
  ```

* Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
* Navigate to *Start* > *Microsoft SQL Server Tools 18* > *Microsoft SQL Server Management Studio 18*
* Connect to the Azure SQL Database server private endpoint
  * Server name: `mssql-xxxxxxxxxxxxxxxx.database.windows.net`
  * Authentication: `SQL Server Authentication`
  * Login: `bootstrapadmin`
  * Password: Use the value stored in the *adminpassword* key vault secret
* Expand the *Databases* tab and verify you can see *testdb*.

#### Test port 3306 connectivity to Azure MySQL Flexible Server private endpoint (PaaS)

* From the client environment, navigate to *portal.azure.com* > *Azure Database for MySQL flexible servers* > *mysql-xxxxxxxxxxxxxxxx* > *Overview* > *Server name* and and copy the the FQDN, e.g. *mysql&#x2011;xxxxxxxxxxxxxxxx.mysql.database.azure.com*.
* From *jumpwin2*, run the following Windows PowerShell command:

  ```powershell
  # Replace FQDN with the value copied previously.
  Resolve-DnsName mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com
  ```

* Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
* Navigate to *Start* > *MySQL Workbench*
* Navigate to *Database* > *Connect to Database* and connect using the following values:
  * Connection method: `Standard (TCP/IP)`
  * Hostname: `mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com`
  * Port: `3306`
  * Uwername: `bootstrapadmin`
  * Schema: `testdb`
  * Click *OK* and when prompted for *password* use the value of the *adminpassword* secret in key vault.

## Documentation

This section provides additional information on various aspects of this configuration ([Step-By-Step Video](https://youtu.be/VJnWT6V5hPk)).

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a `terraform.tfvars` file for generating and applying Terraform plans. For simplified deployment, several runtime defaults are initialized using output variables stored in the `terraform.tfstate` files associated with the following configurations:

* [terraform-azurerm-vnet-shared](../../terraform-azurerm-vnet-shared/)
* [terraform-azurerm-vnet-app](../../terraform-azurerm-vnet-app/)
* [terraform-azurerm-vwan](../../terraform-azurerm-vwan/)

Output variable | Configuration | Sample value
--- | --- | ---
aad_tenant_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
adds_domain_name_cloud | terraform-azurerm-vnet-shared | "mysandbox.local"
admin_password_secret | terraform-azurerm-vnet-shared | "adminpassword"
admin_username_secret | terraform-azurerm-vnet-shared | "adminuser"
arm_client_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
automation_account_name | terraform-azurerm-vnet-shared | "auto-xxxxxxxxxxxxxxxx-01"
dns_server_cloud | terraform-azurerm-vnet-shared | "10.1.2.4"
key_vault_id | terraform-azurerm-vnet-shared | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.KeyVault/vaults/kv-xxxxxxxxxxxxxxx"
key_vault_name | terraform-azurerm-vnet-shared | "kv-xxxxxxxxxxxxxxx"
location | terraform-azurerm-vnet-shared | "centralus"
resource_group_name | terraform-azurerm-vnet-shared | "rg-sandbox-01"
subscription_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
tags | terraform-azurerm-vnet-shared | "tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )"
vnet_app_01_id | terraform-azurerm-vnet-app | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-app-01"
vnet_app_01_name | terraform-azurerm-vnet-app | "vnet-app-01"
vnet_shared_01_id | terraform-azurerm-vnet-shared | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-shared-01"
vnet_shared_01_name | terraform-azurerm-vnet-shared | "vnet-shared-01"
vnet_shared_01_subnets | terraform-azurerm-vnet-shared | Contains all the subnet definitions.
vwan_01_hub_01_id | terraform-azurerm-vwan | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualHubs/vhub-xxxxxxxxxxxxxxxx-01"
vwan_01_id | terraform-azurerm-vwan |"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualWans/vwan-xxxxxxxxxxxxxxxx-01"

### Terraform resources

This section describes the resources included in this configuration.

#### Network resources (on-premises)

The configuration for these resources can be found in [020-network-onprem.tf](./020-network-onprem.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_virtual_network.vnet_shared_02 (vnet&#x2011;onprem&#x2011;01) | By default this virtual network is configured with an address space of `192.168.0.0/16` and is configured with DNS server addresses of `192.168.2.4` (the private ip for *azurerm_windows_virtual_machine.vm_adds*) and [168.63.129.16](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16). See below for more information.
azurerm_subnet.vnet_shared_02_subnets["GatewaySubnet"] | This subnet is reserved for use by *azurerm_virtual_network_gateway.vnet_shared_02_gateway* and has a default IP address prefix of `192.168.0.0/24`. It is defined separately from *azurerm_subnet.vnet_shared_02_subnets* because gateway subnets have special behaviors in Azure such as the restriction on using network security groups.
azurerm_subnet.vnet_shared_02_subnets["snet-adds-02"] | This subnet is used by *azurerm_windows_virtual_machine.vm_adds* and has a default IP address prefix of `192.168.1.0/24`. A network security group is associated with this subnet that permits ingress and egress from virtual networks, and egress to the Internet.
azurerm_subnet.vnet_shared_02_subnets["snet-misc-03"] | This subnet is used by *azurerm_windows_virtual_machine.vm_jumpbox_win* and has a default IP address prefix of `192.168.2.0/24`. A network security group is associated with this subnet that permits ingress and egress from virtual networks, and egress to the Internet.
azurerm_virtual_network_gateway.vnet_shared_02_gateway (gw&#x2011;vnet&#x2011;onprem&#x2011;01) | VPN gateway used to connect on-premises network to cloud network.
azurerm_virtual_network_gateway_connection.onprem_to_cloud | Used by *azurerm_virtual_network_gateway.vnet_shared_02_gateway* to connect to cloud network.
azurerm_local_network_gateway.cloud_network | Configures the gateway address, ASN and BGP peering address of the cloud network used by *azurerm_virtual_network_gateway_connection.onprem_to_cloud*.
azurerm_public_ip.vnet_shared_02_gateway_ip (pip&#x2011;vnet&#x2011;onprem&#x2011;01) | Public ip used by *azurerm_virtual_network_gateway.vnet_shared_02_gateway*.

The virtual network `vnet-onprem-01` is used to simulate an on-premises network at `192.168.0.0/16`. It is configured with a virtual network gateway `gw-vnet-onprem-01` which is used to establish a site-to-site VPN gateway connection to the cloud network. The connection properties for the cloud network are configured using a local network gateway.  

#### Network resources (cloud)

The configuration for these resources can be found in [030-network-cloud.tf](./030-network-cloud.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_vpn_gateway.site_to_site_vpn_gateway_01 | Site to site VPN gateway deployed in the Azure Virtual WAN hub *azurerm_virtual_hub.vwan_01_hub_01*.
azurerm_vpn_gateway_connection.cloud_to_onprem | Used by *azurerm_vpn_gateway.site_to_site_vpn_gateway_01* to connect to on-premises network.
azurerm_vpn_site.vpn_site_onprem | Configures the gateway address, ASN and BGP peering address of the on-premises network used by *azurerm_vpn_gateway_connection.cloud_to_onprem*.
azurerm_private_dns_resolver.pdnsr_01 (pdnsr-xxxxxxxxxxxxxxxx-01) | The DNS private resolver used to resolve DNS queries for private zones in both environments (on-premises and Azure) in a bi-directional fashion.
azurerm_private_dns_resolver_inbound_endpoint.pdnsr_inbound_01 | The inbound endpoint for *azurerm_private_dns_resolver.pdnsr_01* used by conditional forwarders in the on-premises network.
azurerm_private_dns_resolver_outbound_endpoint.pdnsr_outbound_01 | The outbound endpoint for *azurerm_private_dns_resolver.pdnsr_01* used to conditionally forward DNS queries to private DNS zones defined by *azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01*.
azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01 (rset-pdnsr-xxxxxxxxxxxxxxxx-01) | The DNS forwarding ruleset used to forward DNS queries to private DNS zones associated with domain controllers in both the on-premises and cloud networks.
azurerm_private_dns_resolver_forwarding_rule.rule-cloud | Rule added to *azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01* for the `mysandbox.local` private DNS zone.
azurerm_private_dns_resolver_forwarding_rule.rule-onprem | Rule added to *azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01* for the `myonprem.local` private DNS zone.
azurerm_private_dns_resolver_virtual_network_link.vnet_app_01 | Links *azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01* to *vnet-app-01*.
azurerm_private_dns_resolver_virtual_network_link.vnet_shared_01 | Links *azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01* to *vnet-shared-01*.
random_id.random_id_pdnsr_01_name | Used to generate a random name for *azurerm_private_dns_resolver.pdnsr_01*.

#### AD DS domain controller VM

The configuration for these resources can be found in [040-vm-adds.tf](./040-vm-adds.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_windows_virtual_machine.vm_adds (adds2) | By default, provisions a [Standard_B2s](https://learn.microsoft.com/azure/virtual-machines/sizes-b-series-burstable) virtual machine for use as a domain controller and dns server. See below for more information.
azurerm_network_interface.vm_adds_nic_01 (nic-adds2-1) | The configured subnet is *azurerm_subnet.vnet_shared_02_subnets["snet-adds-02"]*.

This Windows Server VM is used as an [Active Directory Domain Services](https://learn.microsoft.com/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview) [Domain Controller](https://learn.microsoft.com/previous-versions/windows/it-pro/windows-server-2003/cc786438(v=ws.10)) and a DNS Server running in Active Directory-integrated mode.

* Guest OS: Windows Server 2022 Datacenter Core
* By default the [Patch orchestration mode](https://learn.microsoft.com/azure/virtual-machines/automatic-vm-guest-patching#patch-orchestration-modes) is set to `AutomaticByPlatform`.
* *admin_username* and *admin_password* are configured using the key vault secrets *adminuser* and *adminpassword*.
* This resource has a dependency on *azurerm_automation_account.automation_account_01*.
* This resource is configured using a [provisioner](https://www.terraform.io/docs/language/resources/provisioners/syntax.html) that runs [aadsc-register-node.ps1](./aadsc-register-node.ps1) which registers the node with *azurerm_automation_account.automation_account_01* and applies the configuration [OnPremDomainConfig](./OnPremDomainConfig.ps1) which includes the following:
  * The `AD-Domain-Services` feature (which includes DNS) is installed.
  * A new *myonprem.local* domain is configured
    * The domain admin credentials are configured using the *adminusername* and *adminpassword* key vault secrets.
    * The forest functional level is set to `WinThreshhold`
    * A DNS Server is automatically configured
      * *myonprem.local* DNS forward lookup zone configuration
        * Zone type: Primary / Active Directory-Integrated
        * Dynamic updates: Secure only
      * Forwarder: [168.63.129.16](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16).
        * Note: This ensures that any DNS queries that can't be resolved by the DNS server are forwarded to  Azure DNS as per [Name resolution for resources in Azure virtual networks](https://learn.microsoft.com/azure/virtual-network/virtual-networks-name-resolution-for-vms-and-role-instances).
      * Conditional forwarders are configured for the following private DNS zones and routed to the IP address of *azurerm_private_dns_resolver_inbound_endpoint.pdnsr_inbound_01*:
        * `mysandbox.local` (cloud network)
        * `file.core.windows.net` (Azure Files)
        * `database.windows.net` (Azure SQL Database)
        * `mysql.database.azure.com` (Azure MySQL Flexible Server)

#### Windows Server Jumpbox VM

The configuration for these resources can be found in [050-vm-jumpbox-win.tf](./050-vm-jumpbox-win.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_windows_virtual_machine.vm_jumpbox_win (jumpwin2) | By default, provisions a [Standard_B2s](https://learn.microsoft.com/azure/virtual-machines/sizes-b-series-burstable) virtual machine for use as a jumpbox. See below for more information.
azurerm_network_interface.vm_jumpbox_win_nic_01 (nic-jumpwin2-1) | The configured subnet is *azurerm_subnet.vnet_app_01_subnets["snet-misc-03"]*.

This Windows Server VM is used as a jumpbox for development and remote server administration.

* Guest OS: Windows Server 2022 Datacenter.
* By default the [patch orchestration mode](https://learn.microsoft.com/azure/virtual-machines/automatic-vm-guest-patching#patch-orchestration-modes) is set to `AutomaticByPlatform`.
* *admin_username* and *admin_password* are configured using the key vault secrets *adminuser* and *adminpassword*.
* This resource is configured using a [provisioner](https://www.terraform.io/docs/language/resources/provisioners/syntax.html) that runs [aadsc-register-node.ps1](./aadsc-register-node.ps1) which registers the node with *azurerm_automation_account.automation_account_01* and applies the configuration [JumpBoxConfig2](./JumpBoxConfig2.ps1).
  * The virtual machine is domain joined  and added to `JumpBoxes` security group.
  * The following [Remote Server Administration Tools (RSAT)](https://learn.microsoft.com/windows-server/remote/remote-server-administration-tools) are installed:
    * Active Directory module for Windows PowerShell (RSAT-AD-PowerShell)
    * Active Directory Administrative Center (RSAT-AD-AdminCenter)
    * AD DS Snap-Ins and Command-Line Tools (RSAT-ADDS-Tools)
    * DNS Server Tools (RSAT-DNS-Server)
    * Failover Cluster Management Tools (RSAT-Clustering-Mgmt)
    * Failover Cluster Module for for Windows PowerShell (RSAT-Clustering-PowerShell)
  * The following software packages are pre-installed using [Chocolatey](https://chocolatey.org/why-chocolatey):
    * [az.powershell](https://community.chocolatey.org/packages/az.powershell)
    * [vscode](https://community.chocolatey.org/packages/vscode)
    * [sql-server-management-studio](https://community.chocolatey.org/packages/sql-server-management-studio)
    * [microsoftazurestorageexplorer](https://community.chocolatey.org/packages/microsoftazurestorageexplorer)
    * [azcopy10](https://community.chocolatey.org/packages/azcopy10)
    * [azure-data-studio](https://community.chocolatey.org/packages/azure-data-studio)
    * [mysql.workbench](https://community.chocolatey.org/packages/mysql.workbench)

## Videos

Video | Section
--- | ---
[Azure Sandbox - On-premises Connectivity (Part 1)](https://youtu.be/S-Ma-sRkcN0) | [Overview](#overview)
[Azure Sandbox - On-premises Connectivity (Part 2)](https://youtu.be/yVhdhcelYMU) | [Getting started](#getting-started)
[Azure Sandbox - On-premises Connectivity (Part 3)](https://youtu.be/4t1oh-roSrg) | [Smoke testing](#smoke-testing)
[Azure Sandbox - On-premises Connectivity (Part 4)](https://youtu.be/VJnWT6V5hPk) | [Documentation](#documentation)

## Troubleshooting

* Azure Automation DSC issues
  * `DSC node configuration 'OnPremDomainConfig.adds2' RollupStatus is 'Bad'...` : This error may occur during `terraform apply` when the provisioner for *azurerm_windows_virtual_machine.vm_adds* (`adds2`) runs the script [aadsc-register-node.ps1](./aadsc-register-node.ps1). The script checks the status of all DSC node configurations, and if any of them are not `Compliant` it will fail. This is by design as the smoke testing for this configuration requires that all virtual machines in both the *cloud* environment and the *onprem* environment are properly configured. To resolve this issue, do the following:
    * Ensure all virtual machines are a `Compliant` state by checking that all existing virtual machines are started and Azure Automation DSC has had time to refresh the configuration status. If the status is still not `Compliant` try destroying and reapplying the configuration associated with the problematic virtual machine. Alternatively you can comment out the check in [aadsc-register-node.ps1](./aadsc-register-node.ps1) on lines 108-113.
    * Unregister *adds2* from Azure Automation DSC.
    * Delete compiled configurations `OnPremDomainConfig.adds2` and `JumpBoxConfig2.jumpwin2` from Azure Automation DSC.
    * Delete Configurations `OnPremDomainConfig` and `JumpBoxConfig2` from Azure Automation DSC.
    * Delete the virtual machine *adds2*.
    * Delete the Terraform state information for *adds2*: `terraform state rm azurerm_windows_virtual_machine.vm_adds`.
    * Rerun [bootstrap.sh](./bootstrap.sh).
    * Re-apply the Terraform configuration.
