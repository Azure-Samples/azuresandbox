# Azure MySQL Database Module (mysql)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![mysql-diagram](./images/mysql-diagram.drawio.svg)

## Overview

This configuration implements a network isolated Azure Database for MySQL  using private endpoints.

## Smoke Testing

This section describes how to test the module after deployment.

* Test DNS queries for Azure Database for MySQL private endpoint
  * From *jumpwin1*, execute the following PowerShell command:
  
    ```powershell
    Resolve-DnsName <mysql-server-name-here>.mysql.database.azure.com
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *vnet_app[0].subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
* From *jumpwin1*, test network isolated MySQL connectivity using MySQL Workbench.
  * Navigate to *Start* > *MySQL Workbench*
  * Navigate to *Database* > *Connect to Database* and connect using the following values:
    * Connection method: Standard (TCP/IP)
    * Hostname: *<mysql-server-name-here>.mysql.database.azure.com*
    * Port: *3306*
    * Username: *bootstrapadmin*
    * Schema: *testdb*
    * Click *OK* and when prompted for *password* use the value of the *adminpassword* secret in the sandbox environment key vault.
    * Create a table, insert some data and run some sample queries to verify functionality.

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
|   └── mysql-diagram.drawio.svg  # Architecture diagram
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
admin_password |  | A strong password used for admin accounts. Defined in the vnet-shared module.
admin_username | bootstrapadmin | The user name used for admin accounts. Defined in the vnet-shared module.
location | | The name of the Azure Region where resources will be provisioned. Defined in the root module.
mysql_database_name | testdb | The name of the Azure MySQL Database to be provisioned.
mysql_sku_name | B_Gen5_1 | The SKU name for the Azure MySQL Flexible Server.
resource_group_name | | The name of the resource group defined in the root module.
subnet_id | | The subnet ID defined in the vnet-app module.
tags | | The tags from the root module.
unique_seed | | The unique seed used to generate unique names for resources. Defined in the root module.

### Module Resources

This section lists the resources included in this module.

Address | Name | Notes
--- | --- | ---
module.mysql[0].azurerm_mysql_flexible_database.this | testdb | The Azure MySQL Database.
module.mysql[0].azurerm_mysql_flexible_server.this | mysql&#8209;sand&#8209;dev&#8209;xxxxxxxx | The Azure MySQL flexible server.
module.mysql[0].azurerm_private_dns_a_record.this | | The A record for the Azure MySQL flexible server.
module.mysql[0].azurerm_private_endpoint.this | pe&#8209;sand&#8209;dev&#8209;mysql&#8209;server | The private endpoint for the Azure MySQL flexible server.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Default | Comments
--- | --- | ---
resource_ids | | A map of resource IDs for key resources in the module.
resource_names | | A map of resource names for key resources in the module.
