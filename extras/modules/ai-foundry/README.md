# AI Foundry Module (ai-foundry)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![aistudio-diagram](./images/ai-foundry-diagram.drawio.svg)

## Overview

This module adds an implementation of [Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/) to Azure Sandbox, including:

* An [Azure AI Foundry hub](https://learn.microsoft.com/en-us/azure/ai-foundry/concepts/ai-resources) configured for [network isolation](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/configure-managed-network). The hub is connected to the shared services storage account and key vault.
  * An [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) workspace connected to the hub.
  * An [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro) connected to the hub.
* Additional AI services are also connected to the hub, including:
  * An [Azure AI Services](https://learn.microsoft.com/azure/ai-services/what-are-ai-services) resource.
  * An [Azure AI Search](https://learn.microsoft.com/en-us/azure/search/search-what-is-azure-search) resource.

**IMPORTANT**: Your sandbox environment must be provisioned in a region that supports the Azure OpenAI Service to use this module. The author tested this module in the `West US` region.

## Smoke testing

Follow the steps in this section to test the functionality of AI Foundry hubs, projects and services.

* [Verify Network Isolation](#verify-network-isolation)
* [Connect to Jumpbox](#connect-to-jumpbox)
* [Explore AI Foundry hub](#explore-ai-foundry-hub)
* [Open a Project](#open-a-project)
* [Create a Model Deployment](#create-a-model-deployment)
* [Transcribe a Call](#transcribe-a-call)
* [Summarize a Transcript](#summarize-a-transcript)

**NOTE:** These smoke testing steps not only verify the functionality of the AI Foundry hub, but also demonstrate how to use the hub to create a project, deploy a model, and use AI services such as speech transcription and chat summarization. More steps will be added in the future to demonstrate additional AI Foundry capabilities.

### Verify Network Isolation

* From the client environment, navigate to *portal.azure.com* > *Azure AI Foundry* > *Use with AI Foundry* > *AI Hubs* > *aif-sand-dev-xxx*
* Click *Launch Azure AI Foundry*
* Observe the error message *Error loading Azure AI hub*. This is expected since the AI Foundry hub is network isolated and can only be accessed from the private network.

### Connect to Jumpbox

* From the client environment, navigate to *portal.azure.com* > *Virtual machines* > *jumpwin1*
  * Click *Connect*, then click *Connect via Bastion*
  * For *Authentication Type* choose *VM Password*
  * For *username* enter the UPN of the domain admin, which by default is:
  
    ```plaintext
    bootstrapadmin@mysandbox.local
    ```

  * For *VM Password*, enter the value of the *adminpassword* secret stored in the Azure Key Vault associated with the sandbox environment.
  * Click *Connect*
  * If you see a prompt for allowing access to the clipboard, click *Allow*.
* From *jumpwin1*, map a network drive to Azure Files
  * Execute the following command from PowerShell:
  
    ```pwsh
    net use z: \\<storage-account-name-here>.file.core.windows.net\myfileshare
    ```

### Explore AI Foundry hub

* From *jumpwin1*, sign in to AI Foundry and open a hub.
  * Launch Edge
  * Edit Edge settings to disable secure DNS
    * Navigate to *Settings* > *Privacy, search, and services* > *Security*
    * Disable *Use secure DNS to specify how to lookup the network address for websites*
  * Navigate to `https://ai.azure.com`
  * Click *Sign in*
  * Click *View all resources*
  * Click *aif-sand-dev-xxx* to open the AI Foundry hub.
* Explore the hub
  * Examine the hub *Overview* page
  * Navigate *Users* and examine both the *Users* tab and the *Inherited access* tab.
  * Navigate to *Connected resources* and examine the connected resources.

### Open a Project

* From the hub *Overview* page, locate the project *api-sand-dev-xxx*.
* Click on the project to open it.
* Click *Go to project* to leave the hub management center and start working with the project.

### Create a Model Deployment

* From the project, create a model deployment.
  * Navigate to *Project* > *My assets* > *Models + endpoints*
  * From the *Model deployments* tab, Click on *Deploy model* > *Deploy base model*
  * Search for `gpt-4.1` and select it.
  * Review the description, then click *Confirm*.
  * Examine the deployment details, then click *Customize*.
  * Adjust the settings as follows:

    Setting | Value
    --- | ---
    Deployment name | gpt-4.1
    Deployment type | `Global Standard`
    Model version | `2025-04-14`
    Connected AI resource | ais-sand-dev-xxx_aoai
    Tokens per Minute Rate Limit | 150K
    Content filter | `DefaultV2`
  
  * Click *Deploy*
  * When deployment completes, verify that the *Provisioning state* is `Succeeded`.

### Transcribe a Call

* From the project, use Azure AI Speech to transcribe a call center audio file.
  * Navigate to *AI Services* > *Speech* > *Try all Speech capabilities* > *Real-time transcription*
  * Navigate to *Configure* > *Show advanced options* and enable `Speaker diarization`
  * Navigate to *Upload files* > *browse files*
  * Locate `z:\documents\CallScriptAudio.mp3` and click *Open* and click the *Play* button immediately to listen to the audio file while it is being transcribed.
  * Observe the file being uploaded and transcribed in real time.

### Summarize a Transcript

* From the project, test the deployment in the chat playground.
  * Navigate to *Playgrounds* and click *Try the Chat playground*
  * Confirm the *Deployment* is set to `gpt-4o`.
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

  * Paste the call transcript from `Z:\documents\Claim-Reporting-Script-Prompts.PropertyMgmt.pdf` into the chat window after the previously entered text and click *Send*.
  * Review the response for accuracy and quality.

## Documentation

This section provides additional information on various aspects of this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Output Variables](#output-variables)

### Dependencies

This module depends upon resources provisioned in the following modules:

* Root
* vnet-shared
* vnet-app

### Module Structure

This module is organized as follows:

```plaintext
├── documents/
|   ├── CallScriptAudio.mp3                             # Audio recording of a call center interaction
|   ├── Claim-Reporting-Script-Prompts.PropertyMgmt.pdf # Demo script containing prompts    
|   ├── OmniServe_Agent_Performance.pdf                 # Call center agent performance metrics
|   ├── OmniServe_Agent_Training.pdf                    # Call center agent training manual
|   ├── OmniServe_Compliance_Policy.pdf                 # Compliance and regulatory policy manual 
|   └── Set-OmniServe_CSAT_Guidelines.pdf               # Customer satisfaction guidelines 
├── images/
|   └── ai-foundry-diagram.drawio.svg                   # Architecture diagram
domain
├── locals.tf                                           # Local variables
├── main.tf                                             # Resource configurations  
├── network.tf                                          # Network resource configurations  
├── outputs.tf                                          # Output variables
├── storage.tf                                          # Storage resource configurations
├── terraform.tf                                        # Terraform configuration block
└── variables.tf                                        # Input variables
```

### Input Variables

This section lists the default values for the input variables used in this module. Defaults can be overridden by specifying a different value in the root module.

Variable | Default | Description
--- | --- | ---
ai_search_sku | basic | The sku name of the Azure AI Search service to create. Choose from: Free, Basic, Standard, StorageOptimized.
ai_services_sku | S0 | The sku name of the AI Services sku. Choose from: S0, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10.
container_registry_sku | Premium | The sku name of the Azure Container Registry to create. Choose from: Basic, Standard, Premium. Premium is required for use with AI Studio hubs.
key_vault_id |  | The existing key vault where secrets are stored
location |  | The name of the Azure Region where resources will be provisioned.
private_dns_zones |  | The existing private dns zones defined in the application virtual network.
resource_group_id |  | The id of the existing resource group for provisioning resources.
resource_group_name |  | The name of the existing resource group for provisioning resources.
storage_account_name |  | The name of the shared storage account.
storage_account_id |  | The id of the shared storage account.
storage_file_endpoint |  | The endpoint of the Azure Files share.
storage_share_name |  | The name of the Azure Files share.
subnets |  | The existing subnets defined in the application virtual network.
tags |  | The tags in map format to be used when creating new resources.
unique_seed |  | A unique seed to be used for generating unique names for resources.
user_object_id |  | The object id of the interactive user.

### Module Resources

This section lists the resources included in this module.

Address | Name | Notes
--- | --- | ---
module.ai_foundry[0].azapi_resource.ai_services_connection | | Connects the AI Services resource to the AI Foundry hub.
module.ai_foundry[0].azapi_resource.search_service_connection | | Connects the AI Search resource to the AI Foundry hub.
module.ai_foundry[0].azurerm_ai_foundry.this | aif-sand-dev-xxx | The AI Foundry hub resource.
module.ai_foundry[0].azurerm_ai_services.this | ais-sand-dev-xxx | The Azure AI Services resource.
module.ai_foundry[0].azurerm_application_insights.this | appi-sand-dev-xxx | The Application Insights workspace connected to the AI Foundry hub.
module.ai_foundry[0].azurerm_container_registry.this | acrsanddevxxx | The Azure Container Registry connected to the AI Foundry hub.
module.ai_foundry[0].azurerm_private_endpoint.ai_foundry | pe-sand-dev-foundry | The private endpoint for the AI Foundry hub.
module.ai_foundry[0].azurerm_private_endpoint.ai_services | pe-sand-dev-ais | The private endpoint for the Azure AI Services resource.
module.ai_foundry[0].azurerm_private_endpoint.container_registry | pe-sand-dev-acr | The private endpoint for the Azure Container Registry.
module.ai_foundry[0].azurerm_private_endpoint.search_service | pe-sand-dev-srch | The private endpoint for the Azure AI Search resource.
module.ai_foundry[0].azurerm_role_assignment.ai_services[*] | | Role assignments for the Azure AI Services resource as defined in the *locals.tf* file.
module.ai_foundry[0].azurerm_role_assignment.search_service[*] | | Role assignments for the Azure AI Search resource as defined in the *locals.tf* file.
module.ai_foundry[0].azurerm_search_service.this | srch-sand-dev-xxx | The Azure AI Search resource connected to the AI Foundry hub.
module.ai_foundry[0].azurerm_storage_share_directory.this | documents | The Azure Files share directory for storing documents.
module.ai_foundry[0].azurerm_storage_share_file.documents[*] | | Various documents for smoke testing and demonstration purposes.

### Output Variables

This section includes a list of output variables returned by the module.

Name | Comments
--- | ---
resource_ids | A map of resource IDs for key resources in the module.
resource_names | A map of resource names for key resources in the module.
