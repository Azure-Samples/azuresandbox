# \#AzureSandbox - terraform-azurerm-mssql

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

![mssql-diagram](./images/mssql-diagram.drawio.svg)

## Overview

This configuration implements a [PaaS](https://azure.microsoft.com/overview/what-is-paas/) database hosted in [Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/sql-database-paas-overview) with a private endpoint implemented using [PrivateLink](https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview) ([Step-By-Step Video](https://youtu.be/bkgyYhHfoKg)).

Activity | Estimated time required
--- | ---
Pre-configuration | ~5 minutes
Provisioning | ~5 minutes
Smoke testing | ~20 minutes

## Before you start

[terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app) must be provisioned first before starting. This configuration is optional and can be skipped to reduce costs. Proceed with [terraform-azurerm-mysql](../terraform-azurerm-mysql) if you wish to skip it.

## Getting started

This section describes how to provision this configuration using default settings ([Step-By-Step Video](https://youtu.be/atq1GXv_Jlg)).

* Change the working directory.

  ```bash
  cd ~/azuresandbox/terraform-azurerm-mssql
  ```

* Add an environment variable containing the password for the service principal.

  ```bash
  export TF_VAR_arm_client_secret=YOUR-SERVICE-PRINCIPAL-PASSWORD
  ```

* Run [bootstrap.sh](./scripts/bootstrap.sh) using the default settings or custom settings.

  ```bash
  ./scripts/bootstrap.sh
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

  `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

Use the steps in this section to smoke test the configuration ([Step-By-Step Video](https://youtu.be/pLYKU50Z014))

* Test DNS queries for Azure SQL database private endpoint
  * From the client environment, navigate to *portal.azure.com* > *SQL Servers* > *mssql-xxxxxxxxxxxxxxxx* > *Overview* > *Server name* and and copy the the FQDN, e.g. *mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net*.
  * From *jumpwin1*, run the Windows PowerShell command:
  
    ```powershell
    Resolve-DnsName mssql-xxxxxxxxxxxxxxxx.database.windows.net
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
* From *jumpwin1*, test SQL Server Connectivity with SQL Server Management Studio (SSMS)
  * Navigate to *Start* > *Microsoft SQL Server Tools 19* > *Microsoft SQL Server Management Studio 19*
  * Connect to the Azure SQL Database server using PrivateLink
    * Server name: *mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net*
    * Authentication: *SQL Server Authentication*
    * Login: *bootstrapadmin*
    * Password: Use the value stored in the *adminpassword* key vault secret
  * Expand the *Databases* tab and verify you can see *testdb*
* Optional: Enable internet access to Azure SQL Database
  * From the client environment (not *jumpwin1*), verify that PrivateLink is not already configured on the network
    * Open a command prompt and run the following command:

      ```text
      ipconfig /all
      ```

    * Scan the results for *privatelink.database.windows.net* in *Connection-specific DNS Suffix Search List*.
      * If found, PrivateLink is already configured on the network.
        * If you are directly connected to a private network, skip this portion of the smoke testing.
        * If you are connected to a private network using a VPN, disconnect from it and try again.
          * If the *privatelink.database.windows.net* DNS Suffix is no longer listed, you can continue.
  * Execute the following PowerShell command:

    ```powershell
    Resolve-DnsName mssql-xxxxxxxxxxxxxxxx.database.windows.net
    ```

  * Make a note of the *IP4Address* returned. It is different from the private IP address returned previously in the smoke testing.
  * Navigate to [lookip.net](https://www.lookip.net/ip) and lookup the *IP4Address* from the previous step. Examine the *Technical details* and verify that the ISP for the IP Address is `Microsoft Corporation` and the Company is `Microsoft Azure`.
  * Manually enable public access to Azure SQL Database
    * Navigate to *portal.azure.com* > *Home* > *SQL Servers* > *mssql&#x2011;xxxxxxxxxxxxxxxx* > *Security* > *Networking*
    * On the *Public access* tab, click *Selected networks*
    * In the *Firewall rules* section, click *Add your client IPv4 address*
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
  * Disable public network access
    * From the client environment, execute the following Bash commands:

      ```bash
      # Change the working directory
      cd ~/azuresandbox/terraform-azurerm-mssql
      
      # Verify plan will change one property on one resource only
      terraform plan

      # Apply the change
      terraform apply
      ```

  * Verify public network access is disabled
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

This configuration uses the script [bootstrap.sh](./scripts/bootstrap.sh) to create a *terraform.tfvars* file for generating and applying Terraform plans ([Step-By-Step Video](https://youtu.be/sD6ySES0fJQ)). For simplified deployment, several runtime defaults are initialized using output variables stored in the *terraform.tfstate* file associated with the [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared;) and [terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app/) configurations, including:

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
location | "centralus"
random_id | "xxxxxxxxxxxxxxx"
resource_group_name | "rg-sandbox-01"
subscription_id | "00000000-0000-0000-0000-000000000000"
tags | tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )
vnet_app_01_subnets | Contains all the subnet definitions including *snet-app-01*, *snet-db-01*, *snet-mysql-01* and *snet-privatelink-01*.

### Terraform Resources

This section lists the resources included in this configuration ([Step-By-Step Video](https://youtu.be/-nuc-Q6N430)).

#### Azure SQL Database

The configuration for these resources can be found in [main.tf](./main.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_mssql_server.mssql_server_01 (mssql-xxxxxxxxxxxxxxxx) | An [Azure SQL Database logical server](https://learn.microsoft.com/azure/azure-sql/database/logical-servers) for hosting databases.
azurerm_mssql_database.mssql_database_01 | A [single database](https://learn.microsoft.com/azure/azure-sql/database/single-database-overview) named *testdb* for testing connectivity.
azurerm_private_endpoint.mssql_server_01 | A private endpoint for connecting to [Azure SQL Database using PrivateLink](https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview)
azurerm_private_dns_a_record.sql_server_01 | A DNS A record for resolving DNS queries to *azurerm_mssql_server.mssql_server_01* using PrivateLink. This resource has a dependency on the *azurerm_private_dns_zone.database_windows_net* resource.

## Next steps

Move on to the next configuration [terraform-azurerm-mysql](../terraform-azurerm-mysql).

## Videos

Video | Section
--- | ---
[Azure SQL Database (Part 1)](https://youtu.be/bkgyYhHfoKg) | [terraform-azurerm-mssql \| Overview](#overview)
[Azure SQL Database (Part 2)](https://youtu.be/atq1GXv_Jlg) | [terraform-azurerm-mssql \| Getting started](#getting-started)
[Azure SQL Database (Part 3)](https://youtu.be/pLYKU50Z014) | [terraform-azurerm-mssql \| Smoke testing](#smoke-testing)
[Azure SQL Database (Part 4)](https://youtu.be/sD6ySES0fJQ) | [terraform-azurerm-mssql \| Documentation \| Bootstrap script](#bootstrap-script)
[Azure SQL Database (Part 5)](https://youtu.be/-nuc-Q6N430) | [terraform-azurerm-mssql \| Documentation \| Terraform resources](#terraform-resources)
