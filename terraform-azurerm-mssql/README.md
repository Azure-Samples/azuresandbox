# \#AzureSandbox - terraform-azurerm-mssql

![mssql-diagram](./mssql-diagram.drawio.svg)

## Contents

* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Next steps](#next-steps)

## Overview

This configuration implements a [PaaS](https://azure.microsoft.com/en-us/overview/what-is-paas/) database hosted in [Azure SQL Database](https://docs.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview) with a private endpoint implemented using [PrivateLink](https://docs.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview).

Activity | Estimated time required
--- | ---
Pre-configuration | ~5 minutes
Provisioning | ~5 minutes
Smoke testing | ~20 minutes

## Before you start

[terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app) must be provisioned first before starting. This configuration is optional and can be skipped to reduce costs. Proceed with [terraform-azurerm-mysql](../terraform-azurerm-mysql) if you wish to skip it.

## Getting started

This section describes how to provision this configuration using default settings.

* Change the working directory.

  ```bash
  cd ~/azuresandbox/terraform-azurerm-mssql
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

  `Apply complete! Resources: 5 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

* Test DNS queries for Azure SQL database private endpoint
  * From the client environment, navigate to *portal.azure.com* > *SQL Servers* > *mssql-xxxxxxxxxxxxxxxx* > *Overview* > *Server name* and and copy the the FQDN, e.g. *mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net*.
  * From *jumpwin1*, run the Windows PowerShell command:
  
    ```powershell
    Resolve-DnsName mssql-xxxxxxxxxxxxxxxx.database.windows.net
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
  * Note: This DNS query is resolved using the following resources:
    * *azurerm_private_dns_a_record.sql_server_01*
    * *azurerm_private_dns_zone.private_dns_zones["privatelink.database.windows.net"]*
    * *azurerm_private_dns_zone_virtual_network_link.private_dns_zone_virtual_network_links_vnet_app_01["privatelink.database.windows.net"]*

* From *jumpwin1*, test SQL Server Connectivity with SQL Server Management Studio (SSMS)
  * Navigate to *Start* > *Microsoft SQL Server Tools 18* > *Microsoft SQL Server Management Studio 18*
  * Connect to the Azure SQL Database server using PrivateLink
    * Server name: *mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net*
    * Authentication: *SQL Server Authentication*
    * Login: *bootstrapadmin*
    * Password: Use the value stored in the *adminpassword* key vault secret
  * Expand the *Databases* tab and verify you can see *testdb*
* Optional: Deny internet access to Azure SQL Database
  * From the client environment, test DNS configuration
    * Verify that PrivateLink is not already configured on the private network
      * Open a Windows command prompt and run the following command:

        ```text
        ipconfig /all
        ```

      * Scan the results for *privatelink.database.windows.net* in *Connection-specific DNS Suffix Search List*.
        * If found, PrivateLink is already configured on the private network.
          * If you are directly connected to a private network, skip this portion of the smoke testing.
          * If you are connected to a private network using a VPN, disconnect from it and try again.
            * If the *privatelink.database.windows.net* DNS Suffix is no longer listed, you can continue.
    * Using Windows PowerShell, run this command and make a note of the *IP4Address* returned:

      ```powershell
      Resolve-DnsName mssql-xxxxxxxxxxxxxxxx.database.windows.net
      ```

    * Navigate to [lookip.net](https://www.lookip.net/ip) and lookup the *IP4Address* from the previous step. Examine the *Technical details* and verify that the ISP for the IP Address is *Microsoft Corporation* and the Company is *Microsoft Azure*.
  * Add Azure SQL Database firewall rule for client IP
    * From the client environment, navigate to *portal.azure.com* > *Home* > *SQL Servers* > *mssql&#x2011;xxxxxxxxxxxxxxxx* > *Security* > *Networking*
    * Confirm *Public network access* is set to *Selected networks*.
    * Navigate to *Firewall rules* and click *+ Add your client client IPV4 address...*.
    * Verify a firewall rule was added to match your client IP address.
      * Note: Only IPv4 addresses will work, so replace any IPv6 addresses with IPv4 addresses. Use [whatismyhipaddress.com](https://whatismyipaddress.com) to determine your IPv4 address.
    * Click *Save*
  * Test Internet connectivity to Azure SQL Database
    * Launch *Microsoft SQL Server Management Studio* (SSMS)
    * Connect to the Azure SQL Database server using public endpoint
      * Server name: *mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net*
      * Authentication: *SQL Server Authentication*
      * Login: *bootstrapadmin*
      * Password: Use the value stored in the *adminpassword* key vault secret
    * Expand the *Databases* tab and verify you can see *testdb*
    * Disconnect from Azure SQL Database
  * Deny public network access
    * In Visual Studio code, navigate to line 14 of [060-mssql.tf](./060-mssql.tf)
    * Change `public_network_access_enabled` from `true` to `false` and save the changes.
    * In a bash terminal, run the following commands to apply changes to the configuration:

      ```bash
      # Verify plan will change one property on one resource only
      terraform plan

      # Apply the change
      terraform apply
      ```
  
  * Test Internet connectivity to Azure SQL Database
    * Launch *Microsoft SQL Server Management Studio* (SSMS)
    * Connect to the Azure SQL Database server using public endpoint
      * Server name: *mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net*
      * Authentication: *SQL Server Authentication*
      * Login: *bootstrapadmin*
      * Password: Use the value stored in the *adminpassword* key vault secret
    * Verify the connection was denied and examine the error message

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a *terraform.tfvars* file for generating and applying Terraform plans. For simplified deployment, several runtime defaults are initialized using output variables stored in the *terraform.tfstate* file associated with the [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared;) and [terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app/) configurations, including:

Output variable | Sample value
--- | ---
aad_tenant_id | "00000000-0000-0000-0000-000000000000"
adds_domain_name | "mysandbox.local"
admin_password_secret | "adminpassword"
admin_username_secret | "adminuser"
arm_client_id | "00000000-0000-0000-0000-000000000000"
automation_account_name | "auto-9a633c2bba9351cc-01"
key_vault_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.KeyVault/vaults/kv-XXXXXXXXXXXXXXX"
key_vault_name | "kv-XXXXXXXXXXXXXXX"
location | "eastus"
resource_group_name | "rg-sandbox-01"
subscription_id | "00000000-0000-0000-0000-000000000000"
tags | tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )
vnet_app_01_subnets | Contains all the subnet definitions including *snet-app-01*, *snet-db-01*, *snet-mysql-01* and *snet-privatelink-01*.

### Terraform Resources

This section lists the resources included in this configuration.

#### Azure SQL Database

The configuration for these resources can be found in [020-mssql.tf](./020-mssql.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_mssql_server.mssql_server_01 (mssql-xxxxxxxxxxxxxxxx) | An [Azure SQL Database logical server](https://docs.microsoft.com/en-us/azure/azure-sql/database/logical-servers) for hosting databases.
azurerm_mssql_database.mssql_database_01 | A [single database](https://docs.microsoft.com/en-us/azure/azure-sql/database/single-database-overview) named *testdb* for testing connectivity.
azurerm_private_endpoint.mssql_server_01 | A private endpoint for connecting to [Azure SQL Database using PrivateLink](https://docs.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview)
azurerm_private_dns_a_record.sql_server_01 | A DNS A record for resolving DNS queries to *azurerm_mssql_server.mssql_server_01* using PrivateLink. This resource has a dependency on the *azurerm_private_dns_zone.database_windows_net* resource.

## Next steps

Move on to the next configuration [terraform-azurerm-mysql](../terraform-azurerm-mysql).
