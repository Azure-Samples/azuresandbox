# \#AzureSandbox - terraform-azurerm-mysql

![mysql-diagram](./mysql-diagram.drawio.svg)

## Contents

* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Next steps](#next-steps)

## Overview

This configuration implements a [PaaS](https://azure.microsoft.com/en-us/overview/what-is-paas/) database hosted in [Azure Database for MySQL - Flexible Server](https://docs.microsoft.com/en-us/azure/mysql/flexible-server/overview) with a private endpoint implemented using [subnet delegation](https://docs.microsoft.com/en-us/azure/virtual-network/subnet-delegation-overview)..

Activity | Estimated time required
--- | ---
Pre-configuration | ~5 minutes
Provisioning | ~20 minutes
Smoke testing | ~10 minutes

## Before you start

[terraform-azurerm-vnet-app](../terraform-azurerm-vnet-app) must be provisioned first before starting. This configuration is optional and can be skipped to reduce costs. Proceed with [terraform-azurerm-vwan](../terraform-azurerm-vwan) if you wish to skip it.

## Getting started

This section describes how to provision this configuration using default settings.

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

  `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

* Test DNS queries for Azure Database for MySQL private endpoint (PaaS)
  * From the client environment, navigate to *portal.azure.com* > *Azure Database for MySQL flexible servers* > *mysql-xxxxxxxxxxxxxxxx* > *Overview* > *Server name* and and copy the the FQDN, e.g. *mysql&#x2011;xxxxxxxxxxxxxxxx.mysql.database.azure.com*.
  * From *jumpwin1*, run the following Windows PowerShell command:
  
    ```powershell
    Resolve-DnsName mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com
    ```

  * Verify the *IP4Address* returned is within the subnet IP address prefix for *azurerm_subnet.vnet_app_01_subnets["snet-mysql-01"]*, e.g. `10.2.3.*`.
  * Note: This DNS query is resolved using the following resources:
    * A DNS A record is added for the MySQL server automatically by the provisioning process. This can be verified in the Azure portal by navigating to *Private DNS zones* > *private.mysql.database.azure.com* and viewing the A record listed.
    * *azurerm_private_dns_zone.private_dns_zones["private.mysql.database.azure.com"]*
    * *azurerm_private_dns_zone_virtual_network_link.private_dns_zone_virtual_network_links_vnet_app_01["private.mysql.database.azure.com"]*

* From *jumpwin1*, test private MySQL connectivity using MySQL Workbench.
  * Navigate to *Start* > *MySQL Workbench*
  * Navigate to *Database* > *Connect to Database* and connect using the following values:
    * Connection method: `Standard (TCP/IP)`
    * Hostname: `mysql-xxxxxxxxxxxxxxxx.mysql.database.azure.com`
    * Port: `3306`
    * Uwername: `bootstrapadmin`
    * Schema: `testdb`
    * Click *OK* and when prompted for *password* use the value of the *adminpassword* secret in key vault.
    * Create a table, insert some data and run some sample queries to verify functionality.
    * Note: Internet connectivity will not be tested because Azure Database for MySQL can only be configured for access via private endpoints or public endpoints, but not both simultaneously.

## Documentation

This section provides additional information on various aspects of this configuration.

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
vnet_app_01_subnets | Contains all the subnet definitions including *snet-app-01*, *snet-db-01*, *snet-mysql-01* and *snet-privatelink-01*.

### Terraform Resources

This section lists the resources included in this configuration.

#### Azure Database for MySQL Flexible Server

The configuration for these resources can be found in [020-mysql.tf](./020-mysql.tf).

Resource name (ARM) | Notes
--- | ---
azurerm_mysql_flexible_server.mysql_server_01 (mysql-xxxxxxxxxxxxxxxx) | An [Azure Database for MySQL - Flexible Server](https://docs.microsoft.com/en-us/azure/mysql/flexible-server/overview) for hosting databases. Note that a private endpoint is automatically created during provisioning and a corresponding DNS A record is automatically added to the corresponding private DNS zone.
azurerm_mysql_flexible_database.mysql_database_01 | A MySQL Database named *testdb* for testing connectivity.

## Next steps

Move on to the next configuration [terraform-azurerm-vwan](../terraform-azurerm-vwan).
