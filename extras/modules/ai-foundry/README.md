# #AzureSandbox - terraform-azurerm-aistudio

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)
* [Videos](#videos)

## Architecture

![aistudio-diagram](./aistudio-diagram.drawio.svg)

## Overview

This configuration enables the use of [Azure AI Studio](https://learn.microsoft.com/en-us/azure/ai-studio/what-is-ai-studio) in #AzureSandbox, including ([Step-By-Step Video](https://youtu.be/Fl0y5N2vdyw)):

* An [Azure AI Studio hub](https://learn.microsoft.com/en-us/azure/ai-studio/concepts/ai-resources) configured for [network isolation](https://learn.microsoft.com/azure/ai-studio/how-to/configure-managed-network). The hub is connected to the shared services storage account and key vault.
  * An [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) workspace connected to the hub.
  * An [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro) connected to the hub.
* Additional AI services which can be [connected](https://learn.microsoft.com/azure/ai-studio/concepts/connections) to the hub, including:
  * An [Azure AI Services](https://learn.microsoft.com/azure/ai-services/what-are-ai-services) resource.
  * An [Azure AI Search](https://learn.microsoft.com/en-us/azure/search/search-what-is-azure-search) resource.

Activity | Estimated time required
--- | ---
Bootstrap | ~5 minutes
Provisioning | ~10 minutes
Smoke testing | ~30 minutes

## Before you start

Note that this configuration requires that #AzureSandbox be provisioned in a region where both the Azure Virtual Machine SKUs used in #AzureSandbox and Azure AI Services are available. At the time of writing, the author used `westus`. The following configurations must be provisioned before starting:

* [terraform-azurerm-vnet-shared](../../terraform-azurerm-vnet-shared/)
* [terraform-azurerm-vnet-app](../../terraform-azurerm-vnet-app/)

Review [Azure OpenAI Service quotas and limits](https://learn.microsoft.com/azure/ai-services/openai/quotas-limits) to ensure that the Azure OpenAI models you wish to leverage are available in the region where #AzureSandbox is provisioned. See [Manage and increase quotas for resources with Azure AI Studio](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/quota) to ensure your subscription has the necessary quotas to provision the resources in this configuration.

The user running [bootstrap.sh](./bootstrap.sh) is assumed to be the same user who will be using AI Studio interactively, and must have an `Owner` Azure RBAC role assignment for the sandbox subscription. The same user must also have the Azure CLI authenticated to the sandbox subscription. This is due to the requirement for Azure RBAC role assignments to be added to support interactive use of the AI Studio hub's integration with the shared services storage account.

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

  `Apply complete! Resources: 21 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

Follow the steps in this section to test the functionality of AIStudio hubs, projects and services ([Step-By-Step Video](https://youtu.be/yJIjYepGHEw)).

* Verify that the *adds1* and *jumpwin1* virtual machines are running.
* Make a note of the shared services storage account name
  * Navigate to *portal.azure.com* > *Home* > *Storage accounts*
  * Make a note of the storage account name, e.g. `stxxxxxxxxxxxxx`
* Verify network isolation of AI Studio hub
  * From the client environment, navigate to *portal.azure.com* > *Azure AI Studio* > *aihxxxxxxxxxxxxxxxx*
  * Click *Launch Azure AI Studio*
  * Observe the error message `Error loading Azure AI hub`. This is expected since the AI Studio hub is network isolated and can only be accessed from the private network.
* From the client environment, navigate to *portal.azure.com* > *Virtual machines* > *jumpwin1*
  * Click *Connect*, then click *Connect via Bastion*
  * For *Authentication Type* choose `Password from Azure Key Vault`
  * For *username* enter the UPN of the domain admin, which by default is `bootstrapadmin@mysandbox.local`
  * For *Azure Key Vault Secret* specify the following values:
    * For *Subscription* choose the same Azure subscription used to provision the #AzureSandbox.
    * For *Azure Key Vault* choose the key vault provisioned by [terraform-azurerm-vnet-shared](../terraform-azurerm-vnet-shared/#bootstrap-script), e.g. `kv-xxxxxxxxxxxxxxx`
    * For *Azure Key Vault Secret* choose `adminpassword`
  * Click *Connect*
* From *jumpwin1*, map a network drive to Azure Files
  * Execute the following command from PowerShell:
  
    ```powershell
    # Note: replace stxxxxxxxxxxxxx with the name of the shared services storage account
    net use z: \\stxxxxxxxxxxxxx.file.core.windows.net\myfileshare
    ```

* From *jumpwin1*, sign in to AIStudio and open a hub.
  * Launch Edge
  * Edit Edge settings to disable secure DNS
    * Navigate to *Settings* > *Privacy, search, and services* > *Security*
    * Disable `Use secure DNS to specify how to lookup the network address for websites`
  * Navigate to `https://ai.azure.com`
  * Click *Sign in*
* From the AIStudio hub, create a project.
  * Click *Create project*
  * Enter a name for the project (e.g. `aipxx`)
  * Select the AI hub from the dropdown (e.g. `aihxx`)
  * Click *Create*
* Explore the hub
  * From the project, navigate to *Management center* > *AI hubs + projects*
  * Click on the AI hub (e.g. `aihxx`)
  * Examine the hub *Overview* page
  * Navigate to *Hub (aihxx) > Users* and examine both the *Users* tab and the *Inherited access* tab.
  * Navigate to *Hub (aihxx) > Connected resources* and examine the connected resources.
  * Navigate to *Management center* > *All hubs + projects*
  * Click on the project (e.g. `aipxx`)
  * Navigate to *Go to project*
* From the project, create a model deployment.
  * Navigate to *My assets* > *Models + endpoints*
  * From the *Model deployments* tab, Click on *Deploy model* > *Deploy base model*
  * Search for `gpt-4o` and select it.
  * Review the description, then click *Confirm*.
  * Examine the deployment details, then click *Customize*.
  * Adjust the settings as follows:

    Setting | Value
    --- | ---
    Deployment name | gpt-4o-2024-08-06
    Deployment type | `Global Standard`
    Model version | `2024-08-06`
    Connected AI resource | aisxxx
    Tokens per Minute Rate Limit | 66K
    Content filter | `DefaultV2`
  
  * Click *Deploy*
  * When deployment completes, verify that the *Provisioning state* is `Succeeded`.
* From the project, use Azure AI Speech to transcribe a call center audio file.
  * Note: Due to [Issue 120](https://github.com/Azure-Samples/azuresandbox/issues/120) you must temporarily enable public access to AI Services to perform these steps.
  * Navigate to *AI Services* > *Speech* > *Try all Speech capabilities* > *Real-time speech to text*
  * Navigate to *Configure* > *Show advanced options* and enable `Speaker diarization`
  * Navigate to *Upload files* > *browse files*
  * Locate `\\stxxxxxxxxxxxxx.file.core.windows.net\myfileshare\documents\CallScriptAudio.mp3` and click *Open*
  * Observe the file being uploaded and transcribed in real time.
  * When the transcription is complete, review the results and click *Copy to clipboard*.
  * Paste the transcription into *Notepad* for use later in this exercise.
* From the project, test the deployment in the chat playground.
  * Navigate to *Playgrounds* and click *Try the Chat playground*
  * Confirm the *Deployment* is set to `gpt-4o-2024-08-06`.
  * Enter the following in *Give the model instructions and context*

      ```text
      You are an AI assistant to help analyze call center transcripts.
      ```

  * Click on *Apply changes* and click *Continue*.
  * Navigate to *Chat playground* > *Setup* > *Parameters* and adjust the following settings:

    Setting | Default value | New value
    --- | --- | ---
    Max response | 800 | 1000
    Temperature | 0.7 | 0.3

  * Enter the following text into the chat window:

      ```text
      Please summarize this call center interaction between an agent and the caller (customer):
      ```

  * Paste the call transcript text you previously saved in *Notepad* into the chat window after the previously entered text and click *Send*.
  * Review the response for accuracy and quality.

## Documentation

This section provides additional information on various aspects of this configuration ([Step-By-Step Video](https://youtu.be/xQcNNfQFE50)).

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
location | terraform-azurerm-vnet-shared | "westus"
private_dns_zones | terraform-azurerm-vnet-app | json payload
resource_group_name | terraform-azurerm-vnet-shared | "rg-sandbox-01"
storage_account_name | terraform-azurerm-vnet-shared | "stxxxxxxxxxxxxx"
storage_share_name | terraform-azurerm-vnet-app | "myfileshare"
subscription_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
tags | terraform-azurerm-vnet-shared | "tomap( { "costcenter" = "mycostcenter" "environment" = "dev" "project" = "#AzureSandbox" } )"
vnet_app_01_subnets | terraform-azurerm-vnet-app | json payload

Public internet access and shared key access are temporarily enabled for the shared storage account so the following files can be uploaded to the *myfileshare* share in the shared storage account using the access key stored in the key vault secret *storage_account_key*. These files are used AI Studio demos:

* [CallScriptAudio.mp3](./documents/CallScriptAudio.mp3)
* [Claim-Reporting-Script-Prompts.PropertyMgmt.pdf](./documents/Claim-Reporting-Script-Prompts.PropertyMgmt.pdf)
* [OmniServe_Agent_Performance.pdf](./documents/OmniServe_Agent_Performance.pdf)
* [OmniServe_Agent_Training.pdf](./documents/OmniServe_Agent_Training.pdf)
* [OmniServe_Compliance_Policy.pdf](./documents/OmniServe_Compliance_Policy.pdf)
* [OmniServe_CSAT_Guidelines.pdf](./documents/OmniServe_CSAT_Guidelines.pdf)

The `terraform.tfvars` file is generated and echoed back to the console.

### Terraform resources

This section describes the resources included in this configuration.

The configuration for these resources can be found in [020-aistudio.tf](./020-aistudio.af).

Resource name (ARM) | Notes
--- | ---
azapi_resource.ai_hub_01 (aihxxxxxxxxxxxxxxxx) | An [Azure AI Studio hub](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources#set-up-and-secure-a-hub-for-your-team) deployed in network isolation mode.  
azapi_resource.ai_services_01 (aisxxxxxxxxxxxxxxxx) | [Azure AI Studio services](https://learn.microsoft.com/azure/ai-services/what-are-ai-services).
azurerm_application_insights.app_insights_01 (aiwxxxxxxxxxxxxxxxx) | An [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) workspace connected to the AI Studio hub.
azurerm_container_registry.container_registry_01 (acrxxxxxxxxxxxxxxxx) | An [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro) connected to the AI Studio hub.
azurerm_private_endpoint.ai_hub_01 | A [private endpoint](https://learn.microsoft.com/azure/ai-studio/how-to/configure-private-link?tabs=cli#create-a-hub-that-uses-a-private-endpoint) used for isolated network connectivity to the Azure AI Studio Hub.
azurerm_private_endpoint.ai_service_01 | A [private endpoint](https://learn.microsoft.com/azure/ai-studio/how-to/configure-private-link?tabs=cli#create-a-hub-that-uses-a-private-endpoint) used for isolated network connectivity to Azure AI services.
azurerm_private_endpoint.container_registry_01 | A [private endpoint](https://learn.microsoft.com/azure/ai-studio/how-to/configure-private-link?tabs=cli#create-a-hub-that-uses-a-private-endpoint) used for isolated network connectivity to Azure Container Registry.
azurerm_private_endpoint.search_service_01 | A [private endpoint](https://learn.microsoft.com/azure/ai-studio/how-to/configure-private-link?tabs=cli#create-a-hub-that-uses-a-private-endpoint) used for isolated network connectivity Azure AI Search.
azurerm_search_service.search_service_01 (searchxx) | An [Azure AI Search](https://learn.microsoft.com/azure/search/search-what-is-azure-search) resource.
random_id.aistudio_name | Random id used to name resources in this configuration.

This configuration provisions an [Azure AI Studio hub](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources#set-up-and-secure-a-hub-for-your-team) in network isolated mode. The AI Studio hub is connected to the existing shared services storage account and key vault. The hub is also connected to a new [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) workspace and [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro). A new [Azure AI Search](https://learn.microsoft.com/azure/search/search-what-is-azure-search) resource is created as well for use in Azure AI Studio.

The following Azure RBAC role assignments are implemented based upon the guidance in [Use your data securely within the Azure AI Studio playground](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/secure-data-playground).

Number | Scope | Role | Principal | Notes
--- | --- | --- | --- | ---
1 | Shared storage account | `Contributor` | Interactive user | Azure CLI authenticated user is `Owner`
2 | Shared storage account | `Storage Blob Data Contributor` | Interactive user | Azure CLI authenticated user, implemented in [terraform-azurerm-vnet-shared/boostrap.sh](../../terraform-azurerm-vnet-shared/bootstrap.sh)
3 | Shared storage account | `Storage BLob Data Contributor` | Service principal | Implemented in [terraform-azurerm-vnet-shared/boostrap.sh](../../terraform-azurerm-vnet-shared/bootstrap.sh)
4 | Shared storage account | `Storage Blob Data Contributor` | AI Services managed identity | Implemented in [020-aistudio.tf](./020-aistudio.tf)
5 | Shared storage account | `Storage Blob Data Contributor` | AI Search managed identity | Implemented in [020-aistudio.tf](./020-aistudio.tf)
6 | Shared storage account | `Storage File Data Privileged Contributor` | Interactive user | Implemented in [terraform-azurerm-vnet-shared/boostrap.sh](../../terraform-azurerm-vnet-shared/bootstrap.sh)
7 | Shared storage account | `Storage File Data Privileged Contributor` | Service principal | Implemented in [terraform-azurerm-vnet-shared/boostrap.sh](../../terraform-azurerm-vnet-shared/bootstrap.sh)
8 | AI Services | `Cognitive Services OpenAI Contributor` | Interactive user | Implemented in [020-aistudio.tf](./020-aistudio.tf)
9 | AI Services | `Cognitive Services OpenAI Contributor` | AI Search managed identity | Implemented in [020-aistudio.tf](./020-aistudio.tf)
10 | AI Services | `Cognitive Services User` | Interactive user | Implemented in [020-aistudio.tf](./020-aistudio.tf)
11 | AI Search | `Contributor` | Interactive user | Azure CLI authenticated user is `Owner`
12 | AI Search | `Search Index Data Contributor` | Interactive user | Implemented in [020-aistudio.tf](./020-aistudio.tf)
13 | AI Search | `Search Index Data Contributor` | AI Services managed identity | Implemented in [020-aistudio.tf](./020-aistudio.tf)
14 | AI Search | `Search Index Data Reader` | AI Services managed identity | Implemented in [020-aistudio.tf](./020-aistudio.tf)
15 | AI Search | `Search Service Contributor` | AI Services managed identity | Implemented in [020-aistudio.tf](./020-aistudio.tf)

### Terraform output variables

This section lists the output variables defined in the Terraform configurations in this sample. Some of these may be used for automation in other configurations.

Output variable | Sample value
--- | ---
ai_services_01_name | `aisxxxxxxxxxxxxxxxx`
app_insights_01_name | `aiwxxxxxxxxxxxxxxxx`
container_registry_01_name | `acrxxxxxxxxxxxxxxxx`
search_service_01_name | `searchxxxxxxxxxxxxxxxx`

## Videos

Video | Section
--- | ---
[Azure Sandbox Extras - Azure AI Studio (Part 1)](https://youtu.be/Fl0y5N2vdyw) | [Overview](#overview)
[Azure Sandbox Extras - Azure AI Studio (Part 2)](https://youtu.be/Q1tyxXTlSdI) | [Getting started](#getting-started)
[Azure Sandbox Extras - Azure AI Studio (Part 3)](https://youtu.be/yJIjYepGHEw) | [Smoke testing](#smoke-testing)
[Azure Sandbox Extras - Azure AI Studio (Part 4)](https://youtu.be/xQcNNfQFE50) | [Documentation](#documentation)
