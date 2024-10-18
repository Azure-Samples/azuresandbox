# #AzureSandbox - terraform-azurerm-ai-callcenter

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Videos](#videos)

## Architecture

![ai-callcenter-diagram](./ai-callcenter-diagram.drawio.svg)

## Overview

This configuration adds additional infrastructure dependencies for running the [AI-Powered-Call-Center-Intelligence](https://github.com/pdas-codespace/AI-Powered-Call-Center-Intelligence) sample application in an #AzureSandbox, including:

* An [App Service Web Application](https://learn.microsoft.com/azure/app-service/overview)
  * [Vnet integration](https://learn.microsoft.com/azure/app-service/overview-vnet-integration) is enabled
* A [Cosmos Db](https://learn.microsoft.com/azure/cosmos-db/introduction) database using the [API for NoSQL](https://learn.microsoft.com/azure/cosmos-db/choose-api#api-for-nosql)

Activity | Estimated time required
--- | ---
Bootstrap | ~**TBD** minutes
Provisioning | ~**TBD** minutes
Smoke testing | ~**TBD** minutes

## Before you start

The following configurations must be provisioned before starting:

* [terraform-azurerm-vnet-shared](../../terraform-azurerm-vnet-shared/)
* [terraform-azurerm-vnet-app](../../terraform-azurerm-vnet-app/)
* [terraform-azurerm-mssql](../../terraform-azurerm-mssql/)
* [terraform-azurerm-aistudio](../terraform-azurerm-aistudio/)

## Getting started

This section describes how to provision this configuration using default settings ([Step-By-Step Video](https://youtu.be/Q1tyxXTlSdI)).

* Change the working directory.

  ```bash
  cd ~/azuresandbox/extras/terraform-azurerm-aistudio
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

  `Apply complete! Resources: XXX added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

## Documentation

This section provides additional information on various aspects of this configuration.

### Bootstrap script

This configuration uses the script [bootstrap.sh](./bootstrap.sh) to create a `terraform.tfvars` file for generating and applying Terraform plans. For simplified deployment, several runtime defaults are initialized using output variables stored in the `terraform.tfstate` files associated with the following configurations:

* [terraform-azurerm-vnet-shared](../../terraform-azurerm-vnet-shared/)
* [terraform-azurerm-vnet-app](../../terraform-azurerm-vnet-app/)

Output variable | Configuration | Sample value
--- | --- | ---
aad_tenant_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
arm_client_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
key_vault_id | terraform-azurerm-vnet-shared | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.KeyVault/vaults/kv-xxxxxxxxxxxxxxx"
key_vault_name | terraform-azurerm-vnet-shared | "kv-xxxxxxxxxxxxxxx"
location | terraform-azurerm-vnet-shared | "australiaeast"
private_dns_zones | terraform-azurerm-vnet-app | json payload
resource_group_name | terraform-azurerm-vnet-shared | "rg-sandbox-01"
storage_account_name | terraform-azurerm-vnet-shared | "stxxxxxxxxxxxxx"
storage_share_name | terraform-azurerm-vnet-app | "myfileshare"
subscription_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
tags | terraform-azurerm-vnet-shared | "tomap( { "costcenter" = "mycostcenter" "environment" = "dev" "project" = "#AzureSandbox" } )"
vnet_app_01_subnets | terraform-azurerm-vnet-app | json payload

### Terraform resources

This section describes the resources included in this configuration.

Resource name (ARM) | Notes
--- | ---

## Videos

Video | Section
--- | ---
