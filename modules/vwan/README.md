# Point-to-site VPN Gateway Module (vwan)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vnet-shared-diagram](./images/vwan-diagram.drawio.svg)

## Overview

This module implements a point-to-site VPN gateway for secure remote connectivity to your sandbox environment from a remote Windows client.

## Smoke testing

This smoke testing is designed to be performed from a remote Windows client using a point-to-site VPN connection to an Azure Virtual WAN Hub that is connected to your sandbox environment. Upon completion you will have tested connectivity using a variety of ports and protocols to Azure resources in your sandbox environment using network isolated private endpoints.

Don't forget to disconnect from the point-to-site VPN when you are finished testing, and clean up the client certificates you installed on the remote Windows client when they are no longer needed.

**NOTE:** The remote Windows client can be your Terraform execution environment, or a different remote machine. If you are using a different machine, you will need to copy certificates to the remote Windows client.

* [Configure Certificates on Remote Client](#configure-certificates-on-remote-client)
* [Install and configure VPN client](#install-and-configure-vpn-client)
* [Test user (point-to-site) VPN connectivity](#test-user-point-to-site-vpn-connectivity)

### Configure Certificates on Remote Client

The point-to-site VPN gateway uses a self-signed root certificate to authenticate the remote client. This root certificate and a related client certificate must be installed on the remote client machine to authenticate the VPN connection.

* Perform the following steps from your Terraform execution environment:
  * Export the root certificate and client certificate.

    ```bash
    # Export certificates using bash helper script
    ./modules/vwan/scripts/export-certificates.sh
    ```

    ```pwsh
    # Export certificates using PowerShell helper script
    ./modules/vwan/scripts/Export-Certificates.ps1
    ```

  * Verify *client_cert.pfx* was created in the root module directory.
  * Copy *client_cert.pfx* the remote Windows client.

* Perform the following steps from the remote Windows client:
  * Import client certificate to Personal Certificates
    * Launch Microsoft Management Console by navigating to *Start* > *Run* and entering:

      ```plaintext
      certmgr.msc
      ```

    * Navigate to *Personal* > *Certificates*.
    * Right-click on the *Certificates* node and select *All Tasks* > *Import...*
    * Click *Next*, then click *Browse...*
    * Change the file type filter to *Personal Information Exchange*.
    * Locate and select the *client_cert.pfx* file you previously copied to the remote Windows client, then click *Open*, then click *Next*
    * Enter the password using the value of the *adminpassword* sandbox environment key vault secret, then click *Next*
    * Select the default option to *Place all certificates in the following store* in the *Personal* store, then click *Next*.
    * Click *Finish* to complete the import.
    * Click *OK* to close the *The import was successful* dialog.

### Install and configure VPN client

The Azure VPN Client must be installed on the remote Windows client. It is used to establish a point-to-site VPN connection to the VPN gateway connected to your sandbox environment. Perform these steps from remote Windows client:

* Download virtual hub user VPN profile
  * Navigate to *portal.azure.com* > *Virtual WANs* > *vwan-sand-dev* > *Hubs* > *vwan-sand-dev-hub* > *User VPN (Point to site)*
  * Click *Download virtual hub user VPN profile*
    * Authentication type: *EAPTLS*
    * Click *Generate and download profile*
    * Extract the files from the archive and examine *AzureVPN\azurevpnconfig.xml*.
* Configure Azure VPN Client
  * Navigate to *Start* > *Azure VPN Client*
  * Enlarge or maximize the Azure VPN Client window.
  * Click the *+* icon in the lower left corner and select *Import*
  * Locate and select and select the *AzureVPN\azurevpnconfig.xml* file, then click *Open*.
  * Review the settings.

    Section | Setting | Value
    --- | --- | ---
    Top | Connection Name | vwan-sand-dev_vwan-sand-dev-hub
    Top | VPN Server | hub0.xxxxxxxxxxxxxxxxxxxxxxxxx.vpn.azure.com
    Server Validation | Certificate Information | DigiCert Global Root B2
    Server Validation | Server Secret | Sensitive
    Client Authentication | Authentication Type | Certificate
    Client Authentication | Certificate Information | MyP2SVPNClientCert
    Client Authentication | Secondary Profile | None

  * Click *Save*
  * A new VPN connection named *vwan-sand-dev_vwan-sand-dev-hub* should now be visible in the Azure VPN Client. Select it, then click *Connect*.
  * When the connection is established, review *Connection Properties*

    Name | Value
    --- | ---
    Connection Name | vwan-sand-dev_vwan-sand-dev-hub
    VPN Server | hub0.xxxxxxxxxxxxxxxxxxxxxxxxx.vpn.azure.com
    Authentication Type | Certificate
    Connection Time | Timestamp
    VPN IP Address | IPv4 address assigned to the remote Windows client. Should be in the *client_address_pool* range, e.g. `10.4.*.*`.
    VPN DNS Server | DNS server IP addresses used for name resolution in the sandbox environment. Defaults are `10.1.1.4` (DNS server on *adds1*) and `168.63.129.16` (Azure DNS recursive resolver).
    VPN Routes | List of sandbox environment routes learned by the Azure VPN client, including `10.1.0.0/16` (vnet-shared), `10.2.0.0/16` (vnet-app), `10.3.0.0/16` (vwan hub).

  * Examine *Status Logs* for Azure VPN Client related events.

### Test user (point-to-site) VPN connectivity

Use the following sections to test secure VPN connectivity the remote Windows client to network isolated private endpoints for both IaaS and PaaS services in the sandbox environment.

* [Test RDP (port 3389) connectivity to *jumpwin1* private endpoint (IaaS)](#test-rdp-port-3389-connectivity-to-jumpwin1-private-endpoint-iaas)
* [Test SSH (port 22) connectivity to *jumplinux1* private endpoint (IaaS)](#test-ssh-port-22-connectivity-to-jumplinux1-private-endpoint-iaas)
* [Test SMB (port 445) connectivity to Azure Files private endpoint (PaaS)](#test-smb-port-445-connectivity-to-azure-files-private-endpoint-paas)
* [Test TDS (port 1433) connectivity to *mssqlwin1* private endpoint (IaaS)](#test-tds-port-1433-connectivity-to-mssqlwin1-private-endpoint-iaas)
* [Test TDS (port 1433) connectivity to Azure SQL Database private endpoint (PaaS)](#test-tds-port-1433-connectivity-to-azure-sql-database-private-endpoint-paas)
* [Test port 3306 connectivity to Azure Database for MySQL private endpoint (PaaS)](#test-port-3306-connectivity-to-azure-mysql-flexible-server-private-endpoint-paas)

#### **Test RDP (port 3389) connectivity to *jumpwin1* private endpoint (IaaS)**

* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  Resolve-DnsName jumpwin1.mysandbox.local
  ```

* Verify the IP address returned is in the *vnet_app[0].subnets["snet-app-01"]* subnet.
* Navigate to *Start* > *Remote Desktop Connection*, enter the following values and click *Connect*:
  * Computer:

  ```plaintext
  jumpwin1.mysandbox.local
  ```

  * User name:

  ```plaintext
  bootstrapadmin@mysandbox.local
  ```

  * When prompted for the password, use the value of the *adminpassword* secret in the sandbox environment key vault, then click *OK*.
* After the connection is established, disconnect the RDP session by navigating to *Start* > *bootstrapadmin* > *Sign out*.

#### **Test SSH (port 22) connectivity to *jumplinux1* private endpoint (IaaS)**

* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  Resolve-DnsName jumplinux1.mysandbox.local
  ```

* Verify the IP address returned is in the *vnet_app[0].subnets["snet-app-01"]* subnet.
* Run the following command from a Windows PowerShell command prompt to establish an SSH connection to *jumplinux1* using Kerberos authentication:

  ```powershell
  ssh bootstrapadmin@mysandbox.local@jumplinux1.mysandbox.local
  ```

  * When prompted *Are you sure you want to continue connecting (yes/no/[fingerprint])?* enter *yes*.
  * When prompted for a password, use the value of the *adminpassword* secret in key vault.

* End the SSH session by entering the following command:

  ```bash
  exit
  ```

#### **Test SMB (port 445) connectivity to Azure Files private endpoint (PaaS)**

* From a Windows PowerShell command prompt run the following command:

  ```powershell
  Resolve-DnsName YOUR-SANDBOX-STORAGE-ACCOUNT-NAME-HERE.file.core.windows.net
  ```

* Verify the *IP4Address* returned is in the *vnet_app[0].subnets["snet-privatelink-01"]* subnet.
* From a Windows PowerShell command prompt run the following command:

  ```powershell
  net use z: \\YOUR-SANDBOX-STORAGE-ACCOUNT-NAME-HERE.file.core.windows.net\myfileshare /USER:bootstrapadmin@mysandbox.local
  ```

  * When prompted for a password, use the value of the *adminpassword* secret in sandbox environment key vault.
* Create some test files and folders on the newly mapped Z: drive.
* Unmap the z: drive using the following command:

  ```powershell
  net use z: /d
  ```
  
#### **Test TDS (port 1433) connectivity to *mssqlwin1* private endpoint (IaaS)**

In order to complete this smoke test, SQL Server Management Studio must be installed on the remote Windows client, and you will need to enable SQL authentication on the default SQL Server instance on *mssqlwin1*. This is because the remote Windows client is not domain joined to the *mysandbox.local* domain, and therefore cannot use Windows authentication.

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

* Perform the following steps from the remote Windows client
  * From a Windows PowerShell command prompt run the following command:

    ```powershell
    Resolve-DnsName mssqlwin1.mysandbox.local
    ```

  * Verify the IP4Address returned is in the *vnet_app[0].subnets["snet-db-01"]* subnet.
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

#### **Test TDS (port 1433) connectivity to Azure SQL Database private endpoint (PaaS)**

In order to complete this smoke test, SQL Server Management Studio must be installed on the remote Windows client.

* From a Windows PowerShell command prompt run the following command:

  ```powershell
  Resolve-DnsName YOUR-MSSQL-SERVER-NAME-HERE.database.windows.net
  ```

* Verify the *IP4Address* returned is in the *vnet_app[0].subnets["snet-privatelink-01"]* subnet.
* Navigate to *Start* > *Microsoft SQL Server Tools 20* > *Microsoft SQL Server Management Studio 20*
* Connect to the Azure SQL Database server private endpoint
  * Server name:
  
    ```plaintext
    YOUR-MSSQL-SERVER-NAME-HERE.database.windows.net
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

#### **Test port 3306 connectivity to Azure MySQL Flexible Server private endpoint (PaaS)**

In order to complete this smoke test, MySQL Workbench must be installed on the remote Windows client.

* Using Windows PowerShell, run the following command:

  ```powershell
  Resolve-DnsName YOUR-MYSQL-SERVER-NAME-HERE.mysql.database.azure.com
  ```

* Verify the *IP4Address* returned is in the *vnet_app[0].subnets["snet-privatelink-01"]* subnet.
* Navigate to *Start* > *MySQL Workbench*
* Navigate to *Database* > *Connect to Database* and connect using the following values:
  * Connection method: *Standard (TCP/IP)*
  * Hostname:
  
    ```plaintext
    YOUR-MYSQL-SERVER-NAME-HERE.mysql.database.azure.com
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

* Root module
* vnet-shared module
* vnet-app module

### Module Structure

The module is organized as follows:

```plaintext
├── images/
|   └── vwan-diagram.drawio.svg # Architecture diagram
├── scripts/
|   |── Export-Certificates.ps1 # Helper script to export the root and client certificates for P2S VPN client
|   └── export-certificates.sh  # Helper script to export the root and client certificates for P2S VPN client
├── locals.tf                   # Local variables
├── main.tf                     # Resource configurations
├── network.tf                  # Network resource configurations
├── outputs.tf                  # Output variables
├── terraform.tf                # Terraform configuration block
└── variables.tf                # Input variables
```

### Input Variables

This section lists input variables used in this module. Defaults can be overridden by specifying a different value in the root module.

Variable | Default | Description
--- | --- | ---
client_address_pool | `10.4.0.0/16` | The address range used for point-to-site VPN clients.
dns_server | `10.1.1.4` | The IP address of the DNS server used for the virtual network. Defined in the vnet-shared module.
key_vault_id | | The ID of the key vault defined in the root module.
location | | The Azure region defined in the root module.
resource_group_name | | The name of the resource group defined in the root module.
tags | | The tags defined in the root module..
virtual_networks | | The resource ids for the virtual networks to be connected to the vwan hub. Defined in the vnet-shared and vnet-app modules.
vwan_hub_address_prefix | `10.3.0.0/16` | The address prefix in CIDR notation for the new spoke virtual wan hub.

### Module Resources

This section lists the resources included in this configuration.

Address | Name | Notes
--- | --- | ---
module.vwan[0].azurerm_key_vault_secret.this | p2svpn&#8209;client&#8209;private&#8209;key&#8209;pem | Key vault secret used to secure the private key for the client certificate.
module.vwan[0].azurerm_point_to_site_vpn_gateway.this | vpngw&#8209;sand&#8209;dev | The Azure Virtual WAN point-to-site VPN gateway.
module.vwan[0].azurerm_virtual_hub.this | vwan&#8209;sand&#8209;dev&#8209;hub | The Azure Virtual WAN hub.
module.vwan[0].azurerm_virtual_hub_connection.connections[*] | | The Azure Virtual WAN hub connections to the virtual networks.
module.vwan[0].azurerm_virtual_wan.this | vwan&#8209;sand&#8209;dev | The Azure Virtual WAN.
module.vwan[0].azurerm_vpn_server_configuration.this | | The Azure Virtual WAN VPN server configuration.
module.vwan[0].tls_cert_request.client_cert_request | | The certificate request for the client certificate.
module.vwan[0].tls_locally_signed_cert.client_cert | | The locally signed client certificate. This is used to create the client certificate pfx file.
module.vwan[0].tls_private_key.client_cert_key | | The private key for the client certificate. This is used to create the client certificate pfx file.
module.vwan[0].tls_private_key.root_cert_key | | The private key for the root certificate.
module.vwan[0].tls_self_signed_cert.root_cert | | The self-signed root certificate used in the VPN server configuration for authentication. This needs to be installed on the client machine.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Default | Comments
--- | --- | ---
client_cert_pem | | The client certificate in PEM format. This can be combined with tls_private_key.client_cert_key.private_key_pem and root_cert_pem to create a pfx file using OpenSSL.
resource_ids | | A map of resource IDs for key resources in the module.
resource_names | | A map of resource names for key resources in the module.
root_cert_pem | | The root certificate in PEM format. This can be combined with tls_private_key.client_cert_key.private_key_pem and client_cert_pem to create a pfx file using OpenSSL.
