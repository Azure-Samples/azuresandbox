# #AzureSandbox - terraform-azurerm-aistudio

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Documentation](#documentation)

## Architecture

![vnet-onprem-diagram](./aistudio-diagram.drawio.svg)

## Overview

This configuration creates a new [Azure AI Studio](https://learn.microsoft.com/en-us/azure/ai-studio/what-is-ai-studio) hub and project, including:

* An [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) workspace.
* An [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro).
* An [Azure AI Studio Hub](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources#set-up-and-secure-a-hub-for-your-team).
* An [Azure AI Studio Project](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources)
* [Azure AI Services API access keys](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources#azure-ai-services-api-access-keys).
* A [private endpoint](https://learn.microsoft.com/azure/ai-studio/how-to/configure-private-link?tabs=cli#create-a-hub-that-uses-a-private-endpoint) used for network connectivity by the Azure AI Studio Hub.

## Before you start

The following configurations must be provisioned before starting:

* [terraform-azurerm-vnet-shared](../../terraform-azurerm-vnet-shared/)
* [terraform-azurerm-vnet-app](../../terraform-azurerm-vnet-app/)

## Getting started

This section describes how to provision this configuration using default settings ([Step-By-Step Video](https://youtu.be/yVhdhcelYMU)).

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

  `Apply complete! Resources: 9 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

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
location | terraform-azurerm-vnet-shared | "centralus"
private_dns_zones | terraform-azurerm-vnet-app | json payload
resource_group_name | terraform-azurerm-vnet-shared | "rg-sandbox-01"
storage_account_name | terraform-azurerm-vnet-shared | "stxxxxxxxxxxxxx"
subscription_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
tags | terraform-azurerm-vnet-shared | "tomap( { "costcenter" = "mycostcenter" "environment" = "dev" "project" = "#AzureSandbox" } )"
vnet_app_01_subnets | terraform-azurerm-vnet-app | json payload

### Terraform resources

This section describes the resources included in this configuration.

The configuration for these resources can be found in [020-aistudio.tf](./020-aistudio.af).

Resource name (ARM) | Notes
--- | ---
azapi_resource.ai_hub_01 (aih-xxxxxxxxxxxxxxxx) | An [Azure AI Studio Hub](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources#set-up-and-secure-a-hub-for-your-team).  
azapi_resource.ai_project_01 (aip-xxxxxxxxxxxxxxxx) | An [Azure AI Studio Project](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources)
azapi_resource.ai_services_01 | [Azure AI Services API access keys](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources#azure-ai-services-api-access-keys).
azurerm_application_insights.app_insights_01 (aic-xxxxxxxxxxxxxxxx) | An [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) workspace.
azurerm_container_registry.container_registry_01 (acrxxxxxxxxxxxxxxxx) | An [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro).
azurerm_private_endpoint.ai_hub_01 | A [private endpoint](https://learn.microsoft.com/azure/ai-studio/how-to/configure-private-link?tabs=cli#create-a-hub-that-uses-a-private-endpoint) used for network connectivity by the Azure AI Studio Hub.
random_id.aistudio_name | Random id used to name *azapi_resource.ai_hub_01*, *azapi_resource.ai_project_01* and *azapi_resource.ai_services_01*.
random_id.app_insights_01_name | Random id used to name *azurerm_application_insights.app_insights_01*.
random_id.container_registry_01_name | Random id used to name *azurerm_container_registry.container_registry_01*.

[Use Terraform to create an Azure AI Studio hub](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/create-hub-terraform?tabs=azure-cli) was used as a guide to provision the AI Studio hub and related resources. The Terraform [azapi](https://registry.terraform.io/providers/Azure/azapi/latest) provider is used to provision the AI Studio hub, project and API access keys since there is no corresponding resource in the Terraform [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest) provider.

[How to configure a private link for Azure AI Studio hubs](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/configure-private-link?tabs=cli) was used as a guide to implement network isolation using Private Link. This connectivity is dependent on the private DNS zones *privatelink.api.azureml.ms* and *privatelink.notebooks.azure.net* that are implemented in [terraform-azurerm-vnet-app](../../terraform-azurerm-vnet-app/).
