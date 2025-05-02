# Point-to-site VPN Gateway Module (vwan)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vnet-shared-diagram](./images/vwan-diagram.drawio.svg)

## Overview

This module implements a point-to-site VPN gateway for secure remote connectivity to your sandbox environment from your local computer.

## Smoke testing

This smoke testing is designed to be performed from a [Windows Subsystem for Linux](../README.md#windows-subsystem-for-linux) client environment using a user (point-to-site) VPN connection to the Azure Virtual WAN Hub. Upon completion you will have tested connectivity using a variety of ports and protocols to Azure resources using private endpoints ([Step-By-Step Video](https://youtu.be/pUUUiUnchCw)).

* [Configure Certificates on Remote Client](#configure-certificates-on-remote-client)
* [Install and configure VPN client](#install-and-configure-vpn-client)
* [Test user (point-to-site) VPN connectivity](#test-user-point-to-site-vpn-connectivity)

### Configure Certificates on Remote Client

The point-to-site VPN gateway uses a self-signed root certificate to authenticate the remote client. This root certificate and a related client certificate must be installed on the remote client machine to authenticate the VPN connection.

* Perform the following steps from the Terraform execution environment:
  * Export the root certificate and client certificate.

    ```bash
    # Export certificates using bash helper script
    ./modules/vwan/scripts/export-certificates.sh
    ```

    ```pwsh
    # Export certificates using PowerShell helper script
    ./modules/vwan/scripts/Export-Certificates.ps1
    ```

  * Verify `root_cert.pem` and `client_cert.pfx` files were created in the root module directory.
  * Copy these files to the remote client machine.

* Perform the following steps from the remote client machine:
  * Import self-signed root certificate to Trusted Root Certification Authorities
    * Launch Microsoft Management Console by navigating to *Start* > *Run* and entering `certmgr.msc`.
    * Expand the *Certificates- Current User* node and navigate to *Trusted Root Certification Authorities* > *Certificates*.
    * Right-click on the *Certificates* node and select *All Tasks* > *Import...*
    * Click *Next>* and select the `root_cert.pem` file created in the previous step.
    * Click *Next>* and select the *Place all certificates in the following store* option.
    * Click *Finish* to complete the import.
    * Click *OK* to close the *The import was successful* dialog.
  * Import client certificate to Personal Certificates
    * Navigate to *Personal* > *Certificates*.
    * Right-click on the *Certificates* node and select *All Tasks* > *Import...*
    * Click *Next>* and select the `client_cert.pfx` file created in the previous step.
    * Click *Next>* and enter the password using the value of the `adminpassword` key vault secret.
    * Click *Next>* and select the *Place all certificates in the following store* option.
    * Select the option to place the certificate in the Personal store.
    * Click *Finish* to complete the import.
    * Click *OK* to close the *The import was successful* dialog.

### Install and configure VPN client

The Azure VPN Client is used to establish a point-to-site VPN connection to the VPN gateway. Perform these steps from the remote client machine.

* Download virtual hub user VPN profile
  * Navigate to *portal.azure.com* > *Virtual WANs* > *vwan-sand-dev* > *Hubs* > *vwan-sand-dev-hub* > *User VPN (Point to site)*
  * Click *Download virtual hub user VPN profile*
    * Authentication type: *EAPTLS*
    * Click *Generate and download profile*
    * Extract the files from the archive and examine `AzureVPN\azurevpnconfig.xml`.
* Configure Azure VPN Client
  * Navigate to *Start* > *Azure VPN Client*
  * Navigate to *+* > *Import* and select `AzureVPN\azurevpnconfig.xml`.
  * Click *Import*
  * Navigate to the `AzureVPN` folder from the previous step, and open `azurevpnconfig.xml`.
    * Client authentication
      * Authentication Type: *Certificate*
      * Certificate Information: `MyP2SVPNClientCert`
  * Click *Save*, then click *Connect*.
  * Inspect *Connection Properties* > *VPN routes* which should show the following routes:
    * `10.1.0.0/16`: Shared services virtual network
    * `10.2.0.0/16`: Application virtual network

### Test user (point-to-site) VPN connectivity

Use the following sections to test user VPN (point-to-site) connectivity to private endpoints for both IaaS and PaaS services. When smoke testing is completed, don't forget to disconnect the user (point-to-site) VPN connection in the *Azure VPN Client*.

* [Test RDP (port 3389) connectivity to *jumpwin1* private endpoint (IaaS)](#test-rdp-port-3389-connectivity-to-jumpwin1-private-endpoint-iaas)
* [Test SSH (port 22) connectivity to *jumplinux1* private endpoint (IaaS)](#test-ssh-port-22-connectivity-to-jumplinux1-private-endpoint-iaas)
* [Test SMB (port 445) connectivity to Azure Files private endpoint (PaaS)](#test-smb-port-445-connectivity-to-azure-files-private-endpoint-paas)
* [Test TDS (port 1433) connectivity to *mssqlwin1* private endpoint (IaaS)](#test-tds-port-1433-connectivity-to-mssqlwin1-private-endpoint-iaas)
* [Test TDS (port 1433) connectivity to Azure SQL Database private endpoint (PaaS)](#test-tds-port-1433-connectivity-to-azure-sql-database-private-endpoint-paas)
* [Test port 3306 connectivity to Azure Database for MySQL private endpoint (PaaS)](#test-port-3306-connectivity-to-azure-mysql-flexible-server-private-endpoint-paas)

#### Test RDP (port 3389) connectivity to *jumpwin1* private endpoint (IaaS)

* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  Resolve-DnsName jumpwin1.mysandbox.local
  ```

* Verify the IP address returned is in the *azurerm_subnet.vnet_app_01_subnets["snet-app-01"]* subnet.
* Navigate to *Start* > *Remote Desktop Connection* and connect to `jumpwin1.mysandbox.local` using the credentials `bootstrapadmin@mysandbox.local`. Use the password associated with the *adminpassword* secret in key vault.
* End the RDP session by navigating to *Start* > *bootstrapadmin* > *Sign out*.

#### Test SSH (port 22) connectivity to *jumplinux1* private endpoint (IaaS)

* From a Windows PowerShell command prompt, run the following command:

  ```powershell
  Resolve-DnsName jumplinux1.mysandbox.local
  ```

* Verify the IP address returned is in the *azurerm_subnet.vnet_app_01_subnets["snet-app-01"]* subnet.
* Run the following command from a Windows PowerShell command prompt to establish an SSH connection to *jumplinux1*:

  ```powershell
  ssh bootstrapadmin@mysandbox.local@jumplinux1.mysandbox.local
  ```

  * When prompted for a password, use the value of the *adminpassword* secret in key vault.
  * When prompted `Are you sure you want to continue connecting (yes/no/[fingerprint])?` enter `yes`.
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

* End the SSH session by entering the following command:

  ```bash
  exit
  ```

#### Test SMB (port 445) connectivity to Azure Files private endpoint (PaaS)

* Navigate to *portal.azure.com* > *Storage accounts* > *stxxxxxxxxxxx* > *File shares* > *myfileshare* > *Settings* > *Properties* and copy the the FQDN portion of the URL, e.g. *stxxxxxxxxxxx.file.core.windows.net*.
* From a Windows PowerShell command prompt run the following command:

  ```powershell
  Resolve-DnsName stxxxxxxxxxxx.file.core.windows.net
  ```

* Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
* From a Windows PowerShell command prompt run the following command:

  ```powershell
  net use z: \\stxxxxxxxxxxx.file.core.windows.net\myfileshare /USER:bootstrapadmin@mysandbox.local
  ```

  * When prompted for a password, use the value of the *adminpassword* secret in key vault.
* Create some test files and folders on the newly mapped Z: drive.
* Unmap the z: drive using the following command:

  ```powershell
  net use z: /d
  ```
  
#### Test TDS (port 1433) connectivity to *mssqlwin1* private endpoint (IaaS)

* From a Windows PowerShell command prompt run the following command:

  ```powershell
  Resolve-DnsName mssqlwin1.mysandbox.local
  ```

* Verify the IP4Address returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-db-01"]*, e.g. `10.2.1.*`.
* Navigate to *Start* > *Microsoft SQL Server Tools 18* > *Microsoft SQL Server Management Studio 18*
* Connect to the default instance of SQL Server installed on *mssqlwin1* using the following values:
  * Server name: *mssqlwin1.mysandbox.local*
  * Authentication: *SQL Server Authentication*
    * Login: `sa`
    * Password: Use the value of the `adminpassword` secret in key vault.
    * Options:
      * Encrypt connection: disabled
  * Note: **Windows Authentication cannot be used** because your client machine is not domain joined to the `mysandbox.local` domain.
  * Note: **Encryption must be disabled** because your client machine does not trust the `mysandbox.local` domain. See [SSL Security Error with Data Source](https://powerbi.microsoft.com/blog/ssl-security-error-with-data-source) for more details. IPSEC encryption is enabled at the network layer for the user (point-to-site) VPN connection.
* Expand the *Databases* tab and verify you can see *testdb*.
* Navigate to *File* > *Exit*.

#### Test TDS (port 1433) connectivity to Azure SQL Database private endpoint (PaaS)

* Navigate to *portal.azure.com* > *SQL Servers* > *mssql-xxxxxxxxxxxxxxxx* > *Properties* > *Server name* and copy the the FQDN, e.g. *mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net*.
* From a Windows PowerShell command prompt run the following command:

  ```powershell
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
* Navigate to *File* > *Exit*

#### Test port 3306 connectivity to Azure MySQL Flexible Server private endpoint (PaaS)

* Navigate to *portal.azure.com* > *Azure Database for MySQL flexible servers* > *mysql-xxxxxxxxxxxxxxxx* > *Overview* > *Server name* and and copy the the FQDN, e.g. *mysql&#x2011;xxxxxxxxxxxxxxxx.mysql.database.azure.com*.
* Using Windows PowerShell, run the following command:

  ```powershell
  Resolve-DnsName mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com
  ```

* Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
* Navigate to *Start* > *MySQL Workbench*
* Navigate to *Database* > *Connect to Database* and connect using the following values:
  * Connection method: `Standard (TCP/IP)`
  * Hostname: `mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com`
  * Port: `3306`
  * Username: `bootstrapadmin`
  * Schema: `testdb`
  * Click *OK* and when prompted for *password* use the value of the *adminpassword* secret in key vault.
* Navigate to *File* > *Exit*.
* Navigate to *Start* > *Azure VPN Client* and click *Disconnect*.

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
module.vwan[0].azurerm_key_vault_secret.this | p2svpn&#8209;client&#8209;private&#8209;key&#8209;pem | Key vault secret used to secure the client certificate private key.
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
client_cert_pem | | The client certificate in PEM format. This can be combined with tls_private_key.client_cert_key.private_key_pem to create a pfx file using OpenSSL.
resource_ids | | A map of resource IDs for key resources in the module.
resource_names | | A map of resource names for key resources in the module.
root_cert_pem | | The root certificate in PEM format. This needs to be installed on the client machine.
