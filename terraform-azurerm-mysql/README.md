# \#AzureSandbox - terraform-azurerm-mysql

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

![mysql-diagram](./mysql-diagram.drawio.svg)

## Overview

This configuration implements a [PaaS](https://azure.microsoft.com/overview/what-is-paas/) database hosted in [Azure Database for MySQL - Flexible Server](https://learn.microsoft.com/azure/mysql/flexible-server/overview) with a private endpoint implemented using [PrivateLink](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-networking-private-link) ([Step-by-Step Video](https://youtu.be/MPYO-7HaFAQ)).

Activity | Estimated time required
--- | ---
Pre-configuration | ~5 minutes
Provisioning | ~10 minutes
Smoke testing | ~10 minutes

## Before you start

[terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app) must be provisioned first before starting. This configuration is optional and can be skipped to reduce costs. Proceed with [terraform-azurerm-vwan](../terraform-azurerm-vwan) if you wish to skip it.

## Getting started

This section describes how to provision this configuration using default settings ([Step-by-Step Video](https://youtu.be/yCzbmekoQLI)).

* Change the working directory.

  ```bash
  cd ~/azuresandbox/terraform-azurerm-mysql
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

Use the steps in this section to verify the configuration is working as expected ([Step-by-Step Video](https://youtu.be/AAOBooTgcus)).

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

This section provides additional information on various aspects of this configuration ([Step-by-Step Video](https://youtu.be/4oTJuFeBrdg)).

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a *terraform.tfvars* file for generating and applying Terraform plans. For simplified deployment, several runtime defaults are initialized using output variables stored in the *terraform.tfstate* file associated with the [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared;) and [terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app/) configurations, including:

Output variable | Sample value
--- | ---
aad_tenant_id | "00000000-0000-0000-0000-000000000000"
admin_password_secret | "adminpassword"
admin_username_secret | "adminuser"
arm_client_id | "00000000-0000-0000-0000-000000000000"
key_vault_id | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.KeyVault/vaults/kv-XXXXXXXXXXXXXXX"
key_vault_name | "kv-XXXXXXXXXXXXXXX"
location | "eastus"
resource_group_name | "rg-sandbox-01"
subscription_id | "00000000-0000-0000-0000-000000000000"
tags | tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )
private_dns_zones | Contains all the subnet definitions from this configuration including *snet-app-01*, *snet-db-01*, *snet-mysql-01* and *snet-privatelink-01*.
vnet_app_01_subnets | Contains all the subnet definitions including *snet-app-01*, *snet-db-01*, *snet-privatelink-01* and *snet-misc-03*.

### Terraform Resources

This section lists the resources included in this configuration.

#### Azure Database for MySQL Flexible Server

The configuration for these resources can be found in [020-mysql.tf](./020-mysql.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_mysql_flexible_server.mysql_server_01 (mysql-xxxxxxxxxxxxxxxx) | An [Azure Database for MySQL - Flexible Server](https://learn.microsoft.com/azure/mysql/flexible-server/overview) for hosting databases.
azurerm_mysql_flexible_database.mysql_database_01 | A MySQL Database named *testdb* for testing connectivity.
azurerm_private_endpoint.mysql_server_01 (pend-mysql-xxxxxxxxxxxxxxxx) | A private endpoint for the MySQL server.
azurerm_private_dns_a_record.mysql_server_01 | A private DNS A record for the MySQL server private endpoint.

## Next steps

Move on to the next configuration [terraform-azurerm-vwan](../terraform-azurerm-vwan).

## Videos

Video | Section
--- | ---
[Azure MySQL Flexible Server (Part 1)](https://youtu.be/MPYO-7HaFAQ) | [terraform-azurerm-mysql \| Overview](#overview)
[Azure MySQL Flexible Server (Part 2)](https://youtu.be/yCzbmekoQLI) | [terraform-azurerm-mysql \| Getting started](#getting-started)
[Azure MySQL Flexible Server (Part 3)](https://youtu.be/AAOBooTgcus) | [terraform-azurerm-mysql \| Smoke testing](#smoke-testing)
[Azure MySQL Flexible Server (Part 4)](https://youtu.be/4oTJuFeBrdg) | [terraform-azurerm-mysql \| Documentation](#documentation)
