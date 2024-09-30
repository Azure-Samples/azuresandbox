# #AzureSandbox - terraform-azurerm-aistudio

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vnet-onprem-diagram](./aistudio-diagram.drawio.svg)

## Overview

This configuration creates a new [Azure AI Studio](https://learn.microsoft.com/en-us/azure/ai-studio/what-is-ai-studio) hub and project, including:

* An [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) workspace.
* An [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro).
* A network isolated [Azure AI Studio Hub](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources#set-up-and-secure-a-hub-for-your-team).
* An [Azure AI Studio Project](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources)
* [Azure AI Services API access keys](https://learn.microsoft.com/azure/ai-studio/concepts/ai-resources#azure-ai-services-api-access-keys).
* A [private endpoint](https://learn.microsoft.com/azure/ai-studio/how-to/configure-private-link?tabs=cli#create-a-hub-that-uses-a-private-endpoint) used for network connectivity by the Azure AI Studio Hub.

## Before you start

Note that this configuration requires that #AzureSandbox be provisioned in a region where both the Azure Virtual Machine SKUs used in #AzureSandbox and Azure AI Services are available. At the time of writing, the author used `australiaeast`. The following configurations must be provisioned before starting:

* [terraform-azurerm-vnet-shared](../../terraform-azurerm-vnet-shared/)
* [terraform-azurerm-vnet-app](../../terraform-azurerm-vnet-app/)

Review [Azure OpenAI Service quotas and limits](https://learn.microsoft.com/azure/ai-services/openai/quotas-limits) to ensure that the Azure OpenAI models you wish to leverage are available in the region where #AzureSandbox is provisioned. See [Manage and increase quotas for resources with Azure AI Studio](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/quota) to ensure your subscription has the necessary quotas to provision the resources in this configuration.

## Getting started

This section describes how to provision this configuration using default settings.

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

  `Apply complete! Resources: 10 added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

Follow the steps in this section to test the functionality of AIStudio hubs, projects and services.

* Verify that the *adds1* and *jumpwin1* virtual machines are running.
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
* From *jumpwin1*, sign in to AIStudio and open a hub.
  * Launch Edge
  * Edit Edge settings to disable secure DNS
    * Navigate to *Settings* > *Privacy, search, and services* > *Security*
    * Disable `Use secure DNS to specify how to lookup the network address for websites`
  * Navigate to `https://ai.azure.com`
  * Click *Sign in*
  * Authenticate using a Microsoft Entra ID account that has an Azure RBAC `Owner` role assignment to the sandbox subscription.
  * Click *All resources & projects*
  * Locate the resource with the type `Hub` and click on it (e.g. `aihxxx`).
  * Examine the *Hub properties* and *Users* panels.
* From the AI Studio hub, configure AI Services connection.
  * Locate the *Connected resources* pane and click *New connection*
  * Click on *Azure AI services*
  * Locate the AI Services resource provisioned in this configuration (e.g. `aisxx`) and click *Add connection*
  * Wait util the status is `Connected`, then click *Close*.
  * Refresh the browser window and verify that two AI Services connection are listed:
    * Azure OpenAI (e.g. `aisxx_aoai`)
    * AIServices (e.g. `aisxx`)
* From the AIStudio hub, configure Azure AI Search connection.
  * Locate the *Connected resources* pane and click *New connection*
  * Click on *Azure AI Search*
  * Locate the AI Search resource provisioned in this configuration (e.g. `searchxx`) and click *Add connection*
  * Wait util the status is `Connected`, then click *Close*.
  * Refresh the browser window and verify that the AI Search connection is listed.
* From the AIStudio hub, create a project.
  * Locate the *Projects* pane and click *New project*
  * Enter a name for the project (e.g. `aipxx`)
  * Click *Create a project*
  * When the project is created, examine the *Overview* page.
* From the AIStudio project, create a deployment.
  * Navigate to *Components* > *Deployments*
  * Click on *Deploy model* > *Deploy base model*
  * Search for `gpt-4o` and select it. Scroll through the description and verify the version is `2024-08-06`.
  * Click *Confirm* then click *Deploy*.
  * When deployment completes, verify that the *Provisioning state* is `Succeeded`.
* From the AIStudio project, set up a content filter to manage inappropriate content.
  * Navigate to *Components* > *Content filters*
  * Click *Crete content filter*
  * Enter a name for the filter (e.g. `filterxx`)
  * Set the *Connection* to the Azure AI Services connection (e.g. `aisxx`) and click *Next*
  * Input filter: Set your desired thresholds for each category of inappropriate content and click *Next*
    * Enable the *Blocklist* if desired and choose the desired block list (e.g. `Profanity`).
  * Click *Next*
  * Output filter: Set your desired thresholds for each category of inappropriate content.
    * Enable the *Blocklist* if desired and choose the desired block list (e.g. `Profanity`).
  * Click *Next*
  * Deployment: Select the `gpt-4o` deployment and click *Next* and click *Replace*.
  * Review the filter settings and click *Create filter*.
* From the AIStudio project, test the deployment in the chat playground.
  * Navigate to *Project playground* > *Chat*
  * Confirm the *Deployment* is set to `gpt-4o`.
  * Enter the following in *Give the model instructions and context*
    * `You are an AI assistant to help analyze call center transcripts.`
  * Click on *Apply changes* and click *Continue*.
  * Paste the following prompt into the chat window and click *Send*.

      ```text
      Please summarize this call center interaction between an agent and the caller (customer):
      Agent: Thank you for calling Contoso Property Management. My name is Jaime Basilico. How may I help you today? 
      Customer: Hi, I've got a leaky roof in my apartment. I'm calling to report the issue and see what can be done about it. 
      Agent: Oh, I am so sorry to hear that you're experiencing this problem. Just to confirm, has anyone been injured as a result of the leak? 
      Customer: No, nobody's been injured, but there's water damage, and I'm worried it might get worse. 
      Agent: I'm relieved to hear there are no injuries. Can I have your name, please? 
      Customer: Yes, my name is Sean Sweeny. 
      Agent: Thank you, Mr. Sweeny. Can you verify your date of birth for me, please? 
      Customer: Sure, it's April 14th, 1989. 
      Agent: One moment while I pull up your information. Please hold on. 
      (Pause) 
      Agent: I have your details here. You're in apartment 3A at 525 Oak Street, is that correct? 
      Customer: That's right. 
      Agent: Great, and could you please confirm your phone number for me? 
      Customer: Yes, it's 312-555-1234. 
      Agent: Thank you. Can you tell me when you first noticed the leak? 
      Customer: I noticed it last night. There was a heavy storm, and water started dripping from the ceiling in the living room. 
      Agent: I understand. Have you managed to take any pictures of the damage? 
      Customer: Yes, I've taken several pictures of the ceiling and where the water was coming in. 
      Agent: Perfect. I'm going to file a maintenance request for you right now. Please hold on. 
      (Pause) 
      Agent: I've created a service ticket for your leaky roof, and our maintenance team will be in touch to arrange a time to inspect the damage and carry out the 
      necessary repairs. We'll also send you a link via email where you can upload the pictures you've taken. 
      Agent: Is there anything else I can assist you with today? 
      Customer: No, that should be it. Thank you for your help. 
      Agent: My pleasure, Mr. White. We'll get this sorted out for you as quickly as possible. Have a great day!
      ```

  * Review the response for accuracy and quality.

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

Public internet access is temporarily enabled for the shared storage account so the following documents scripts can be uploaded to the *myfileshare* share in the shared storage account using the access key stored in the key vault secret *storage_account_key*. These documents are used to build an index in AI Studio:

* [Claim-Reporting-Script-Prompts.PropertyMgmt.pdf](./documents/Claim-Reporting-Script-Prompts.PropertyMgmt.pdf)
* [OmniServe_Agent_Performance.pdf](./documents/OmniServe_Agent_Performance.pdf
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
