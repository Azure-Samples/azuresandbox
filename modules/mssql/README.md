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
  * From *jumpwin1*, run the Windows PowerShell command:
  
    ```powershell
    Resolve-DnsName YOUR-AZURE-SQL-SERVER-NAME-HERE.database.windows.net
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *vnet_app[0].subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
* From *jumpwin1*, test SQL Server Connectivity with SQL Server Management Studio (SSMS)
  * Navigate to *Start* > *Microsoft SQL Server Tools 20* > *Microsoft SQL Server Management Studio 20*
  * Connect to the network isolated Azure SQL Database server
    * Server properties:
      * Server name: *YOUR-AZURE-SQL-SERVER-NAME-HERE.database.windows.net*
      * Authentication: *SQL Server Authentication*
      * Login: *bootstrapadmin*
      * Password: Use the value stored in the *adminpassword* key vault secret
    * Connection security properties:
      * Encryption: *Strict (SQL Server 2022 and Azure SQL)*
  * Expand the *Databases* tab and verify you can see *testdb*

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
├── terraform.tf                  # Terraform configuration block
└── variables.tf                  # Input variables
```

### Input Variables

This section lists input variables used in this module. Defaults can be overridden by specifying a different value in the root module.

Variable | Default | Description
--- | --- | ---
admin_password_secret | adminpassword | The name of the key vault secret that contains the password for the admin account. Defined in the vnet-shared module.
admin_username_secret | adminuser | The name of the key vault secret that contains the user name for the admin account. Defined in the vnet-shared module.
key_vault_id | | The ID of the key vault defined in the root module.
location | | The name of the Azure Region where resources will be provisioned.
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
