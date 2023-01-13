# \#AzureSandbox - terraform-azurerm-vwan  

![vnet-shared-diagram](./vwan-diagram.drawio.svg)

## Contents

* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Next steps](#next-steps)

## Overview

This configuration implements an [Azure Virtual WAN](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about) to connect /#AzureSandbox to remote users using [User VPN (point-to-site) connections](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#uservpn), including:

* A [virtual wan](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources).
* A [virtual wan hub](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources) with pre-configured [hub virtual network connections](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources) with [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) and [terraform-azurerm-vnet-app](./terraform-azurerm-vnet-app/). The hub is also pre-configured for [User VPN (point-to-site) connections](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#uservpn).

Activity | Estimated time required
--- | ---
Pre-configuration | ~5 minutes
Provisioning | ~60 minutes
Smoke testing | ~45 minutes

## Before you start

This configuration only supports the [Windows 10 with WSL](../README.md#windows-10-with-wsl) client environment. [Cloud shell](../README.md#cloud-shell) and [Linux / macOS](../README.md#linux--macos) client environments are not supported. The following configurations must be deployed first before starting:

* [terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app)

## Getting started

This section describes how to provision this configuration using default settings.

* From the client environment, generate self-signed certificates to use for P2S VPN certificate authentication.
  * Run [genp2svpncerts.ps1](./genp2svpncerts.ps1) from Windows Powershell (not from WSL / PowerShell core) to generate the certificates required for setting up a P2S VPN:
  
    ```powershell
    .\genp2svpncerts.ps1
    ```
  
    * Note: This script creates a root certificate in the registry, then uses that root certificate to create a self-signed client certificate in the registry. Both certificates are then exported to files, including:
      * `MyP2SVPNRootCert_DER_Encoded.cer`: This is a temporary file used to create a Base64 encoded version of the root certificate.
      * `MyP2SVPNRootCert_Base64_Encoded.cer`: This is the root certificate used to create a User VPN Configuration in Virtual WAN.
      * `MyP2SVPNChildCert.pfx`: This is an export of the client certificate protected with a password. You only need this if you want to configure the Azure VPN client on a different computer than the one used to generate the certificates.
  * Copy `MyP2SVPNRootCert_Base64_Encoded.cer` from Windows to WSL in the directory `~/azuresandbox/terraform-azurerm-vwan`.

* From a Bash terminal, change the working directory.

  ```bash
  cd ~/azuresandbox/terraform-azurerm-vwan
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

  `Apply complete! Resources: 58 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  terraform state list 
  ```

## Smoke testing

This smoke testing is designed to be performed from a [Windows 10 with WSL](../README.md#windows-10-with-wsl) client environment using a user (point-to-site) VPN connection to the Azure Virtual WAN Hub. Upon completion you will have tested connectivity using a variety of ports and protocols to Azure resources using private endpoints.

* [Install and configure VPN client](#install-and-configure-vpn-client)
* [Test user (point-to-site) VPN connectivity](#test-user-point-to-site-vpn-connectivity)

### Install and configure VPN client

* Download virtual hub user VPN profile
  * Navigate to *portal.azure.com* > *Virtual WANs* > *vwan-XXXX-01* > *Hubs* > *vhub-XXXX-01* > *User VPN (Point to site)*
  * Click *Download virtual hub user VPN profile*
    * Authentication type: *EAPTLS*
    * Click *Generate and download profile*
    * Extract the files from the archive and examine `AzureVPN\azurevpnconfig.xml`.
* Configure Azure VPN Client
  * Navigate to *Start* > *Azure VPN Client*
  * Navigate to *+ Add or Import a new VPN connection*
  * Click *Import*
  * Navigate to the `AzureVPN` folder from the previous step, and open `azurevpnconfig.xml`.
    * Client authentication
      * Authentication Type: *Certificate*
      * Certificate Information: `MyP2SVPNChildCert`
        * Note: If you do not see this certificate you need to import the .pfx created in [Getting started](#getting-started).
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
* [Test port 3306 connectivity to Azure Database for MySQL private endpoint (PaaS)](#test-port-3306-connectivity-to-azure-database-for-mysql-private-endpoint-paas)

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
  ssh bootstrapadmin@mysandbox.local@jumplinux1
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
  * Note: **Encryption must be disabled** because your client machine does not trust the `mysandbox.local` domain. See [SSL Security Error with Data Source](https://powerbi.microsoft.com/en-us/blog/ssl-security-error-with-data-source) for more details. IPSEC encryption is enabled at the network layer for the user (point-to-site) VPN connection.
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
  * Server name: `mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net`
  * Authentication: `SQL Server Authentication`
  * Login: `bootstrapadmin`
  * Password: Use the value stored in the *adminpassword* key vault secret
* Expand the *Databases* tab and verify you can see *testdb*.
* Navigate to *File* > *Exit*

#### Test port 3306 connectivity to Azure Database for MySQL private endpoint (PaaS)

* Navigate to *portal.azure.com* > *Azure Database for MySQL flexible servers* > *mysql-xxxxxxxxxxxxxxxx* > *Overview* > *Server name* and and copy the the FQDN, e.g. *mysql&#x2011;xxxxxxxxxxxxxxxx.mysql.database.azure.com*.
* Using Windows PowerShell, run the following command:

  ```powershell
  Resolve-DnsName mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com
  ```

* Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-mysql-01"]*, e.g. `10.2.3.*`.
* Navigate to *Start* > *MySQL Workbench*
* Navigate to *Database* > *Connect to Database* and connect using the following values:
  * Connection method: `Standard (TCP/IP)`
  * Hostname: `mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com`
  * Port: `3306`
  * Uwername: `bootstrapadmin`
  * Schema: `testdb`
  * Click *OK* and when prompted for *password* use the value of the *adminpassword* secret in key vault.
* Navigate to *File* > *Exit*.
* Navigate to *Start* > *Azure VPN Client* and click *Disconnect*.

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a *terraform.tfvars* file for generating and applying Terraform plans. For simplified deployment, several runtime defaults are initialized using output variables stored in the *terraform.tfstate* files associated with the [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared) and [terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app) configurations, including:

Output variable | Sample value
--- | ---
aad_tenant_id | "00000000-0000-0000-0000-000000000000"
arm_client_id | "00000000-0000-0000-0000-000000000000"
location | "eastus"
resource_group_name | "rg-sandbox-01"
subscription_id | "00000000-0000-0000-0000-000000000000"
tags | tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )
vnet_shared_01_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-shared-01"
vnet_shared_01_name | "vnet-shared-01"
vnet_app_01_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-app-01"
vnet_app_01_name | "vnet-app-01"

### Terraform Resources

This section lists the resources included in this configuration.

#### Network resources

The configuration for these resources can be found in [020-network.tf](./020-network.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_virtual_wan.vwan_01 (vwan-xxxxxxxxxxxxxxxx-01)| [Virtual wan](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about) to connect the shared services and application virtual networks to remote users.
azurerm_virtual_hub.vwan_01_hub_01 (vhub-xxxxxxxxxxxxxxxx-01) | [Virtual WAN hub](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources) associated with the virtual wan.
azurerm_virtual_hub_connection.vwan_01_hub_01_connections["vnet-shared-01"] | [Hub virtual network connection](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources) to *azurerm_virtual_network.vnet_shared_01*.
azurerm_virtual_hub_connection.vwan_01_hub_01_connections["vnet-app-01"] | [Hub virtual network connection](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources) to *azurerm_virtual_network.vnet_app_01*.
azurerm_point_to_site_vpn_gateway.point_to_site_vpn_gateway_01 | Enables [User VPN (point-to-site) connections](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#uservpn). See below for more details.
azurerm_vpn_server_configuration.vpn_server_configuration_01 | Defines the parameters for remote clients to connect to *azurerm_point_to_site_vpn_gateway.point_to_site_vpn_gateway_01*. See below for more details.

[User VPN (point-to-site) connections](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#uservpn) are enabled by generating a self-signed certificate in the client environment and using it to authenticate with a point-to-site VPN gateway provisioned in a [Virtual WAN hub](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources) that is connected to both the shared services and application virtual networks used in \#AzureSandbox.

## Next steps

You have provisioned all of the configurations included in \#AzureSandbox. Now it's time to use your sandbox environment to experiment with additional Azure services and capabilities.
