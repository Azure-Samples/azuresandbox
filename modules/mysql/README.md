# Azure MySQL Database Module (mysql)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![mysql-diagram](./images/mysql-diagram.drawio.svg)

## Overview

This configuration implements a network isolated Azure SQL Database using private endpoints.

## Smoke Testing

This section describes how to test the module after deployment.

* Test DNS queries for Azure Database for MySQL private endpoint (PaaS)
  * From the client environment, navigate to *portal.azure.com* > *Azure Database for MySQL flexible servers* > *mysql-xxxxxxxxxxxxxxxx* > *Overview* > *Server name* and and copy the the FQDN, e.g. *mysql&#x2011;xxxxxxxxxxxxxxxx.mysql.database.azure.com*.
  * From *jumpwin1*, execute the following PowerShell command:
  
    ```powershell
    Resolve-DnsName mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"]*, e.g. `10.2.2.*`.
* From *jumpwin1*, test private MySQL connectivity using MySQL Workbench.
  * Navigate to *Start* > *MySQL Workbench*
  * Navigate to *Database* > *Connect to Database* and connect using the following values:
    * Connection method: `Standard (TCP/IP)`
    * Hostname: `mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com`
    * Port: `3306`
    * Username: `bootstrapadmin`
    * Schema: `testdb`
    * Click *OK* and when prompted for *password* use the value of the *adminpassword* secret in key vault.
    * Create a table, insert some data and run some sample queries to verify functionality.
* Optional: Enable internet access to Azure MySQL Flexible Server
  * From the client environment (not *jumpwin1*), verify that PrivateLink is not already configured on the network
    * Open a command prompt and run the following command:

      ```text
      ipconfig /all
      ```

    * Scan the results for *privatelink.mysql.database.azure.com* in *Connection-specific DNS Suffix Search List*.
      * If found, PrivateLink is already configured on the network.
        * If you are directly connected to a private network, skip this portion of the smoke testing.
        * If you are connected to a private network using a VPN, disconnect from it and try again.
          * If the *privatelink.database.windows.net* DNS Suffix is no longer listed, you can continue.
  * Execute the following PowerShell command:

    ```powershell
    Resolve-DnsName mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com
    ```

  * Make a note of the *IP4Address* returned. It is different from the private IP address returned previously in the smoke testing.
  * Navigate to [lookip.net](https://www.lookip.net/ip) and lookup the *IP4Address* from the previous step. Examine the *Technical details* and verify that the ISP for the IP Address is `Microsoft Azure` and the Company is `Microsoft Azure`.
  * Manually enable public access to Azure MySQL Flexible Server
    * Navigate to *portal.azure.com* > *Home* > *SQL Servers* > *mssql&#x2011;xxxxxxxxxxxxxxxx* > *Settings* > *Networking* > *Firewall rules*
    * Click *Add current client IP address*
    * Click *Save*
    * Verify the *Public access* tab, click *Selected networks*
    * In the *Firewall rules* section, click *Add your client IPv4 address*
    * Click *Save*
  * Test Internet connectivity to Azure MySQL Flexible Server
    * From the client environment (not *jumpwin1*) launch *MySQL Workbench*
    * Navigate to *Database* > *Connect to Database* and connect using the following values:
      * Connection method: `Standard (TCP/IP)`
      * Hostname: `mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com`
      * Port: `3306`
      * Username: `bootstrapadmin`
      * Schema: `testdb`
      * Click *OK* and when prompted for *password* use the value of the *adminpassword* secret in key vault.
      * Verify connection has been established by browsing the schema for `testdb`
      * Close *MySQL Workbench*
  * Disable public network access
    * Navigate to *portal.azure.com* > *Home* > *SQL Servers* > *mssql&#x2011;xxxxxxxxxxxxxxxx* > *Settings* > *Networking* > *Firewall rules*
    * Delete the row containing your client IP address.
    * Click *Save*
    * From the client environment (not *jumpwin1*) launch *MySQL Workbench*
    * Navigate to *Database* > *Connect to Database* and connect using the following values:
      * Connection method: `Standard (TCP/IP)`
      * Hostname: `mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com`
      * Port: `3306`
      * Username: `bootstrapadmin`
      * Schema: `testdb`
      * Click *OK*.
      * The connection should fail.
      * Close *MySQL Workbench*

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
admin_password_secret | adminpassword | The name of the key vault secret that contains the password for the admin account. Defined in the vnet-shared module.
admin_username_secret | adminuser | The name of the key vault secret that contains the user name for the admin account. Defined in the vnet-shared module.
key_vault_id | | The ID of the key vault defined in the root module.
location | | The name of the Azure Region where resources will be provisioned.
mysql_database_name | testdb | The name of the Azure MySQL Database to be provisioned.
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
