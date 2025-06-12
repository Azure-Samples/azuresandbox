# Extras

## Contents

* [Overview](#overview)
* [Configurations](#configurations)
* [Modules](#modules)
* [Demo videos](#demo-videos)

## Overview

Contains additional Terraform modules, configurations and supporting resources.

## Disclaimer

Code and content in this section may be incomplete, outdated or not fully functional.

## Configurations

This section describes additional Terraform configurations that can be added to Azure Sandbox. These configurations are not required to use Azure Sandbox, but may be useful for learning or testing purposes.

* [rg-devops](./configurations/rg-devops/) includes the following:
  * A [resource group](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#resource-group) which contains DevOps environment resources.
  * A [key vault](https://learn.microsoft.com/azure/key-vault/general/overview) for managing secrets.
  * A [storage account](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#storage-account) for use as a [Terraform azurerm backend](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm).
  * A Linux [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) for use as a DevOps agent.
* [vm-devops](./configurations/vm-devops/) implements a collection of identical [IaaS](https://azure.microsoft.com/overview/what-is-iaas/) [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) designed to be used as Windows Developer Workstations.

## Modules

This section describes additional Terraform modules that can be added to Azure Sandbox. These modules are not required to use Azure Sandbox, but may be useful for learning or testing purposes.

* [ai_foundry](./modules/ai_foundry/) enables the use of [Azure AI Studio](https://learn.microsoft.com/en-us/azure/ai-studio/what-is-ai-studio) in Azure Sandbox, including:
  * An [Azure AI Studio hub](https://learn.microsoft.com/en-us/azure/ai-studio/concepts/ai-resources) configured for [network isolation](https://learn.microsoft.com/azure/ai-studio/how-to/configure-managed-network). The hub is connected to the shared services storage account and key vault.
    * An [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) workspace connected to the hub.
    * An [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro) connected to the hub.
  * Additional AI services which can be [connected](https://learn.microsoft.com/azure/ai-studio/concepts/connections) to the hub, including:
    * An [Azure AI Services](https://learn.microsoft.com/azure/ai-services/what-are-ai-services) resource.
    * An [Azure AI Search](https://learn.microsoft.com/en-us/azure/search/search-what-is-azure-search) resource.
* [vnet-onprem](./modules/vnet-onprem/) simulates connectivity to an on-premises network using a site-to-site VPN connection and Azure DNS private resolver.

## Demo videos

This section contains an index of demo videos that were built using aspects of Azure Sandbox.

* [Improving your security posture with Azure Update Manager (June 2024)](https://youtu.be/QjDE-JdbRD8)
* Improving your security posture with Microsoft Defender for Cloud (May 2024)

  Video | Description
  --- | ---
  [Defender for Cloud (Part 1)](https://youtu.be/G4QPSFIV6qQ) | This video provides an introduction to Microsoft Defender for Cloud.
  [Defender for Cloud (Part 2)](https://youtu.be/buXWnMrkXGE) | This video covers free Foundational Cloud Security Posture Management capabilities.
  [Defender for Cloud (Part 3)](https://youtu.be/rbtH9FyDrP8) | This video covers how to enable paid Defender for Cloud CSPM plans.
  [Defender for Cloud (Part 4)](https://youtu.be/Qynm6h7Yp6k) | This video covers remediating security recommendations for Azure Storage.
  [Defender for Cloud (Part 5)](https://youtu.be/mcdDRLBlLEg) | This video covers remediating security recommendations for Azure SQL Database.
  [Defender for Cloud (Part 6)](https://youtu.be/GA9ts3pSsvg) | This video covers remediating security recommendations for Windows Server.
  [Defender for Cloud (Part 7)](https://youtu.be/AxfKPxXkzA4) | This video covers remediating security recommendations for Ubuntu Server.
  [Defender for Cloud (Part 8)](https://youtu.be/h9AAFFdvCX4) | This video covers remediating additional security recommendations for Ubuntu Server.
  [Defender for Cloud (Part 9)](https://youtu.be/BzZxv4i9SK8) | This video covers remediating security recommendations for Key Vault.
  [Defender for Cloud (Part 10)](https://youtu.be/kYDhGpeM04Y) | This video covers remediating security recommendations for Azure Backup.
  [Defender for Cloud (Part 11)](https://youtu.be/O4mNKNuwN44) | This video covers miscellaneous low risk security recommendations.

* [Accessing Azure Files over HTTPS](https://youtu.be/6ft5rxET8Pc) (October 2023)
* [Fixing a PowerShell script bug with GitHub Copilot](https://youtu.be/xRgdzc_Rl9w) (August 2023)
