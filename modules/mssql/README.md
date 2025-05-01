# Azure SQL Database Module (mssql)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![mssql-diagram](./images/mssql-diagram.drawio.svg)

## Overview

This configuration implements a network isolated Azure SQL Database using private endpoints.

## Smoke Testing

This section describes how to test the module after deployment.

* Test DNS queries for Azure SQL database private endpoint
  * From the client environment, navigate to *portal.azure.com* > *SQL Servers* > *mssql-xxxxxxxxxxxxxxxx* > *Overview* > *Server name* and and copy the the FQDN, e.g. *mssql&#x2011;xxxxxxxxxxxxxxxx.database.windows.net*.
  * From *jumpwin1*, run the Windows PowerShell command:
  
    ```powershell
    Resolve-DnsName mssql-xxxxxxxxxxxxxxxx.database.windows.net
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *vnet_app.subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
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
|   └── mssql-diagram.drawio.svg  # Architecture diagram
├── main.tf                       # Resource configurations
├── network.tf                    # Network resource configurations
├── outputs.tf                    # Output variables
├── storage.tf                    # Storage resource configurations
├── terraform.tf                  # Terraform configuration block
└── variables.tf                  # Input variables
```

### Input Variables

This section lists input variables used in this module. Defaults can be overridden by specifying a different value in the root module.

Variable | Default | Description
--- | --- | ---
admin_password_secret | adminpassword | The name of the key vault secret that contains the password for the admin account. Defined in the vnet-shared module.
admin_username_secret | adminuser | The name of the key vault secret that contains the user name for the admin account. Defined in the vnet-shared module.
key_vault_id | N/A | The ID of the key vault defined in the root module.
location | N/A | The name of the Azure Region where resources will be provisioned.
mssql_database_name | testdb | The name of the Azure SQL Database to be provisioned.
resource_group_name | | The name of the resource group defined in the root module.
subnet_id | | The subnet ID defined in the vnet-app module.
tags | |  The tags from the root module.
unique_seed | | The unique seed used to generate unique names for resources. Defined in the root module.

### Module Resources

This section lists the resources included in this module.

Address | Name | Notes
--- | --- | ---
module.mssql[0].azurerm_mssql_database.this | testdb | The Azure SQL Database.
module.mssql[0].azurerm_mssql_server.this | sql&#8209;sand&#8209;dev&#8209;xxxxxxxx | The Azure SQL logical server.
module.mssql[0].azurerm_private_dns_a_record.this | | The A record for the Azure SQL logical server.
module.mssql[0].azurerm_private_endpoint.this | pe&#8209;sand&#8209;dev&#8209;mssql&#8209;server | The private endpoint for the Azure SQL logical server.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Default | Comments
--- | --- | ---
resource_ids | | A map of resource IDs for key resources in the module.
resource_names | | A map of resource names for key resources in the module.
