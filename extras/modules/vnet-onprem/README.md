# On-premises Virtual Network Module (vnet-onprem)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vnet-onprem-diagram](./images/vnet-onprem-diagram.drawio.svg)

## Overview

This configuration simulates connectivity between the sandbox environment and an on-premises network including:

* A separate virtual network used to simulate an on-premises network, including:
  * A NAT gateway for outbound internet connectivity.
  * A VPN gateway connection to the sandbox environment.
  * A Windows Server virtual machine (adds2) for use as a domain controller and DNS server for a separate *myonprem.local* domain.
  * A Windows Server virtual machine (jumpwin2) for use as a jumpbox.
* Updates to the existing sandbox environment including:
  * A site-to-site VPN gateway connection to the simulated on-premises network.
  * A DNS private resolver for the following use cases:
    * Resolve DNS queries from *mysandbox.local* to *myonprem.local* and vice versa.
    * Resolve DNS queries from *myonprem.local* to private DNS zones in the sandbox environment.

## Smoke testing

This smoke testing is divided into two sections:

* [Test connectivity from cloud to on-premises](#test-connectivity-from-cloud-to-on-premises)
* [Test connectivity from on-premises to cloud](#test-connectivity-from-on-premises-to-cloud)

### Test connectivity from cloud to on-premises

#### Test RDP (port 3389) connectivity to *jumpwin2* private endpoint (IaaS)

* From the client environment, navigate to *portal.azure.com* > *Virtual machines* > *jumpwin1*
  * Click *Connect*, then click *Connect via Bastion*
  * For *Authentication Type* choose *Password from Azure Key Vault*
  * For *username* enter the UPN of the domain admin, which by default is:
  
    ```plaintext
    bootstrapadmin@mysandbox.local
    ```

  * For *Azure Key Vault Secret* specify the following values:
    * For *Subscription* choose the same Azure subscription used to provision the sandbox environment.
    * For *Azure Key Vault* choose the key vault associated with the sandbox environment, e.g. *kv-sand-dev-xxxxxxxx*.
    * For *Azure Key Vault Secret* choose *adminpassword*
  * Click *Connect*
  * If you see a prompt for allowing access to the clipboard, click *Allow*.

* Test cloud to on-premises private DNS zones from *jumpwin1*.
  * From a Windows PowerShell command prompt, run the following command:

    ```powershell
    Resolve-DnsName jumpwin2.myonprem.local
    ```

  * Verify the *IPAddress* returned is within the IP address prefix for the subnet *snet-misc-04*, e.g. `192.168.2.4`.

* Test cloud to on-premises RDP connectivity (port 3389) from *jumpwin1*
  * Navigate to *Start* > *Windows Accessories* > *Remote Desktop Connection*
  * For *Computer*, enter the following value:
  
    ```plaintext
    jumpwin2.myonprem.local
    ```

  * For *User name*, enter the following value:
  
    ```plaintext
    onprembootstrapadmin@myonprem.local
    ```

  * Click *Connect*
  * For *Password*, enter the value of the *adminpassword* secret in key vault
  * Click *Yes*

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

* Verify the *IP4Address* returned is within the IP address prefix for the subnet *snet-app-01ss*, e.g. `10.2.0.5`.
* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  ssh bootstrapadmin@mysandbox.local@jumplinux1.mysandbox.local
  ```

* Enter `yes` when prompted `Are you sure you want to continue connecting?`
* Enter the value of the *adminpassword* secret when prompted for a password.
* End the SSH session by entering the following command:

  ```bash
  exit
  ```

#### Test SMB (port 445) connectivity to Azure Files private endpoint (PaaS)

* From a Windows PowerShell command prompt run the following command:

  ```powershell
  Resolve-DnsName <your-storage-account-name>.file.core.windows.net
  ```

* Verify the *IP4Address* returned is in the *snet-privatelink-01* subnet, e.g. `10.2.2.5`.

* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  # Replace FQDN with the value copied previously.
  net use z: \\<your-storage-account-name>.file.core.windows.net\myfileshare /USER:bootstrapadmin@mysandbox.local
  ```

* For *Password*, enter the value of the *adminpassword* secret in key vault.
* Create some test files and folders on the newly mapped Z: drive.
* Unmap the z: drive using the following command:

  ```powershell
  net use z: /delete
  ```

#### Test TDS (port 1433) connectivity to *mssqlwin1* private endpoint (IaaS)

* Perform the following steps from *jumpwin1*
  * Launch SQL Server Management Studio
  * Connect to the default instance of SQL Server on *mssqlwin1*
  * Right click in *mssqlwin1* in the object explorer and select *Properties*
  * Select the *Security* tab
  * Select the *SQL Server and Windows Authentication mode* option, then click "OK"
  * Disconnect from *mssqlwin1*
  * Restart *mssqlwin1* VM from the Azure portal.
  * Wait for the restart to complete, then connect to *mssqlwin1* again from SQL Server Management Studio.
  * Navigate to *Security* > *Logins* and add a new login
  * Right click on *Logins* and select *New Login...*
    * Set the Login name to:

      ```plaintext
      bootstrapadmin
      ```
  
    * Select *SQL Server authentication*
    * Set the password to the value of the *adminpassword* secret in the sandbox environment key vault.
    * Disable the *User must change password at next login* option.
    * Add the login to the *sysadmin* server role.
    * Click *OK* to create the new login.

* From *jumpwin2*, test connectivity to the default SQL Server instance on *mssqlwin1*.
  * From a Windows PowerShell command prompt, run the following command:

    ```powershell
    # Replace FQDN with the value copied previously.
    Resolve-DnsName mssqlwin1.mysandbox.local
    ```

  * Verify the *IP4Address* returned is within the IP address prefix for the *snet-db-01* subnet, e.g. `10.2.1.4`.
    * Verify the SQL Server Management studio is installed.
  * Navigate to *Start* > *Microsoft SQL Server Tools 20* > *Microsoft SQL Server Management Studio 20*
  * Connect to the default instance of SQL Server installed on *mssqlwin1* using the following values:
    * Server name:

      ```plaintext
      mssqlwin1.mysandbox.local
      ```

    * Authentication: *SQL Server Authentication*
    * Login:

      ```plaintext
      bootstrapadmin
      ```

    * Password: Use the value of the *adminpassword* secret in the sandbox environment key vault.
    * Encryption: *Optional*
  * Click *Connect* and examine the SQL instance in object explorer.
  * Disconnect from the SQL instance.

* From *jumpwin1*, revert the SQL Server instance to use Windows Authentication only.

#### Test TDS (port 1433) connectivity to Azure SQL Database private endpoint (PaaS)

In order to complete this smoke test, SQL Server Management Studio must be installed on *jumpwin2*.

* From a Windows PowerShell command prompt run the following command:

  ```powershell
  Resolve-DnsName <your-mssql-server-name-here>.database.windows.net
  ```

* Verify the *IP4Address* returned is in the *snet-privatelink-01* subnet.
* Navigate to *Start* > *Microsoft SQL Server Tools 20* > *Microsoft SQL Server Management Studio 20*
* Connect to the Azure SQL Database server private endpoint
  * Server name:
  
    ```plaintext
    <your-mssql-server-name-here>.database.windows.net
    ```

  * Authentication: *SQL Server Authentication*
    * Login:

      ```plaintext
      bootstrapadmin
      ```

  * Password: Use the value of the *adminpassword* secret in the sandbox environment key vault.
  * Encryption: *Strict*
* Click *Connect*
* Expand the *Databases* tab and verify you can see *testdb*.
* Disconnect from Azure SQL Database.

#### Test port 3306 connectivity to Azure MySQL Flexible Server private endpoint (PaaS)

In order to complete this smoke test, MySQL Workbench must be installed on *jumpwin2*.

* Using Windows PowerShell, run the following command:

  ```powershell
  Resolve-DnsName <your-mysql-server-name-here>.mysql.database.azure.com
  ```

* Verify the *IP4Address* returned is in the *snet-privatelink-01* subnet, e.g. `10.2.2.7`.
* Navigate to *Start* > *MySQL Workbench*
* Navigate to *Database* > *Connect to Database* and connect using the following values:
  * Connection method: *Standard (TCP/IP)*
  * Hostname:
  
    ```plaintext
    <your-mysql-server-name-here>.mysql.database.azure.com
    ```

  * Port: *3306*
  * Username:
  
    ```plaintext
    bootstrapadmin
    ```

  * Default Schema:
  
    ```plaintext
    testdb
    ```

* Click *OK* and when prompted for *password* use the value of the *adminpassword* secret in sandbox environment key vault.
* Browse the *testdb* database schema.
* Exit MySQL Workbench.

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
* vm-mssql-win
* mssql
* mysql
* vwan

### Module Structure

This module is organized as follows:

```plaintext
├── images/
|   └── vnet-onprem-diagram.drawio.svg          # Architecture diagram
├── scripts/
|   ├── DomainControllerConfiguration2.ps1      # DSC configuration for Windows domain controller VM
|   ├── JumpBoxConfiguration2.ps1               # DSC configuration for Windows jumpbox VM    
|   ├── Register-DscNode.ps1                    # Registers a VM with Azure Automation DSC
|   └── Set-AutomationAccountConfiguration.ps1  # Configures Azure Automation settings
├── compute.tf                                  # Compute resource configurations   
├── locals.tf                                   # Local variables
├── main.tf                                     # Resource configurations  
├── network.tf                                  # Network resource configurations  
├── outputs.tf                                  # Output variables
├── terraform.tf                                # Terraform configuration block
└── variables.tf                                # Input variables
```

### Input Variables

This section lists the default values for the input variables used in this module. Defaults can be overridden by specifying a different value in the root module.

Variable | Default | Description
--- | --- | ---
adds_domain_name | myonprem.local | The AD DS domain name for the simulated on-premises environment.
adds_domain_name_cloud | mysandbox.local | The AD DS domain name for the cloud sandbox environment.
admin_password | | Strong password for admin accounts. Defined in vnet-shared module.
admin_username | bootstrapadmin | The username used for provisioning administrator accounts. *onprem* is prepended to differentiate the accounts in this module.
arm_client_secret | | The password for the service principal used to authenticate with Azure. Defined interactively or using TF_VAR_arm_client_secret environment variable.
automation_account_name | aa-sand-dev | The name of the Azure Automation Account used for state configuration (DSC).
dns_server_cloud | `10.1.1.4` | The IP address of the sandbox DNS server.
key_vault_id |  | The ID of the key vault defined in the root module.
key_vault_name |  | The name of the key vault defined in the root module.
location |  | The Azure region defined in the root module.
resource_group_name |  | The name of the resource group defined in the root module.
subnet_adds_address_prefix | `192.168.1.0/24` | The address prefix for the AD Domain Services subnet in the simulated on-premises network.
subnet_GatewaySubnet_address_prefix | `192.168.0.0/24` | The address prefix for the GatewaySubnet subnet in the simulated on-premises network.
subnet_misc_address_prefix | `192.168.2.0/24` | The address prefix for the miscellaneous subnet in the simulated on-premises network.
subnets_cloud |  | The subnets in the shared services virtual network in the cloud sandbox environment.
tags |  | The tags defined in the root module.
virtual_networks_cloud |  | The names and resource ids of the virtual networks in the cloud sandbox environment.
vm_adds_image_offer | WindowsServer | The offer type of the virtual machine image used to create the VM.
vm_adds_image_publisher | MicrosoftWindowsServer | The publisher for the virtual machine image used to create the VM.
vm_adds_image_sku | 2025-datacenter-azure-edition-core | The sku of the virtual machine image used to create the VM.
vm_adds_image_version | Latest | The version of the virtual machine image used to create the VM.
vm_adds_name | adds2 | The name of the VM.
vm_adds_size | Standard_B2ls_v2 | The size of the virtual machine.
vm_adds_storage_account_type | Standard_LRS | The storage replication type to be used for the VMs OS and data disks.
vm_jumpbox_win_image_offer | WindowsServer | The offer type of the virtual machine image used to create the VM.
vm_jumpbox_win_image_publisher | MicrosoftWindowsServer | The publisher for the virtual machine image used to create the VM.
vm_jumpbox_win_image_sku | 2025-datacenter-azure-edition | The sku of the virtual machine image used to create the VM.
vm_jumpbox_win_image_version | Latest | The version of the virtual machine image used to create the VM.
vm_jumpbox_win_name | jumpwin2 | The name of the VM.
vm_jumpbox_win_size | Standard_B2ls_v2 | The size of the virtual machine.
vm_jumpbox_win_storage_account_type | Standard_LRS | The storage replication type to be used for the VMs OS and data disks.
vnet_address_space | `192.168.0.0/16` | The address space in CIDR notation for the new virtual network used to simulate an on-premises network.
vnet_asn | 65123 | The ASN for the on premises network.
vnet_name | onprem | The name of the virtual network used to simulate the on-premises network.
vwan_hub_id |  | The id of the virtual wan hub for the cloud sandbox environment.
vwan_id |  | The id of the virtual wan for the cloud sandbox environment.

### Module Resources

This section lists the resources included in this configuration.

Address | Name | Notes
--- | --- | ---
module.vnet_onprem[0].azurerm_local_network_gateway.this | lgw-sand-dev | Local network gateway for the simulated on-premises network.
module.vnet_onprem[0].azurerm_nat_gateway.this | nat-sand-dev-onprem | NAT gateway for the simulated on-premises network.
module.vnet_onprem[0].azurerm_nat_gateway_public_ip_association.this | | Public IP address association for the NAT gateway in the simulated on-premises network.
module.vnet_onprem[0].azurerm_network_interface.vm_adds | nic-sand-dev-adds2 | Network interface for the adds2 VM.
module.vnet_onprem[0].azurerm_network_interface.vm_jumpbox_win | nic-sand-dev-jumpwin2 | Network interface for the jumpwin2 VM.
module.vnet_onprem[0].azurerm_private_dns_resolver.this | pdnsr-sand-dev | Private DNS resolver for the cloud sandbox environment.
module.vnet_onprem[0].azurerm_private_dns_resolver_dns_forwarding_ruleset.this | rset-sand-dev | DNS forwarding ruleset for the private DNS resolver.
module.vnet_onprem[0].azurerm_private_dns_resolver_forwarding_rule.rule_cloud | | Forwarding rule for DNS queries from the simulated on-premises network to the cloud sandbox environment.
module.vnet_onprem[0].azurerm_private_dns_resolver_forwarding_rule.rule_onprem | | Forwarding rule for DNS queries from the cloud sandbox environment to the simulated on-premises network.
module.vnet_onprem[0].azurerm_private_dns_resolver_inbound_endpoint.this | | Inbound endpoint for the private DNS resolver.
module.vnet_onprem[0].azurerm_private_dns_resolver_outbound_endpoint.this | | Outbound endpoint for the private DNS resolver.
module.vnet_onprem[0].azurerm_private_dns_resolver_virtual_network_link.vnet_app | | Virtual network link for the app virtual network in the cloud sandbox environment.
module.vnet_onprem[0].azurerm_private_dns_resolver_virtual_network_link.vnet_shared | | Virtual network link for the shared services virtual network in the cloud sandbox environment.
module.vnet_onprem[0].azurerm_public_ip.nat | pip-sand-dev-nat | Public IP address for the NAT gateway in the simulated on-premises network.
module.vnet_onprem[0].azurerm_public_ip.vpn | pip-sand-dev-vpn | Public IP address for the VPN gateway in the simulated on-premises network.
module.vnet_onprem[0].azurerm_subnet.subnets["GatewaySubnet"] | | Gateway subnet for the VPN gateway in the simulated on-premises network.
module.vnet_onprem[0].azurerm_subnet.subnets["snet-adds-02"] | | Subnet for the adds2 VM in the simulated on-premises network.
module.vnet_onprem[0].azurerm_subnet.subnets["snet-misc-04"] | | Miscellaneous subnet for the jumpbox VM in the simulated on-premises network.
module.vnet_onprem[0].azurerm_subnet_nat_gateway_association.associations["snet-adds-02"] | | NAT gateway association for the adds2 subnet.
module.vnet_onprem[0].azurerm_subnet_nat_gateway_association.associations["snet-misc-04"] | | NAT gateway association for the miscellaneous subnet.
module.vnet_onprem[0].azurerm_virtual_network.this | vnet-sand-dev-onprem | Virtual network for the simulated simulated on-premises network.
module.vnet_onprem[0].azurerm_virtual_network_gateway.this | | VPN gateway for the simulated on-premises network.
module.vnet_onprem[0].azurerm_virtual_network_gateway_connection.this | | VPN gateway connection to the cloud sandbox environment.
module.vnet_onprem[0].azurerm_vpn_gateway.this | | Site-to-site VPN gateway for the cloud sandbox environment.
module.vnet_onprem[0].azurerm_vpn_gateway_connection.this | | Site-to-site VPN gateway connection to the simulated on-premises network.
module.vnet_onprem[0].azurerm_vpn_site.this | | VPN site for the simulated on-premises network.
module.vnet_onprem[0].azurerm_windows_virtual_machine.vm_adds | adds2 | Windows domain controller / DNS server VM in the simulated on-premises network.
module.vnet_onprem[0].azurerm_windows_virtual_machine.vm_jumpbox_win | jumpwin2 | Windows jumpbox VM in the simulated on-premises network.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Comments
--- | ---
resource_ids | A map of resource IDs for key resources in the module.
resource_names | A map of resource names for key resources in the module.
