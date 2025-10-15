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

* [rg-devops-iac](./configurations/rg-devops-iac/) This configuration provides a minimal set of resources to function as a Terraform execution environment which is often a critical part of a DevOps pipeline. It is a useful starting point for DevOps / Infrastructure-As-Code (IaC) projects that require a secure and isolated environment for deploying and managing infrastructure using Terraform.

## Modules

This section describes additional Terraform modules that can be added to Azure Sandbox. These modules are not required to use Azure Sandbox, but may be useful for learning or testing purposes.

* [ai-foundry](./modules/ai-foundry/) enables the use of an [Azure AI Foundry hub](https://learn.microsoft.com/en-us/azure/ai-foundry/concepts/ai-resources) in a sandbox environment.
* [vm-devops-win](./modules/vm-devops-win/) implements a collection of identical Windows developer VMs.
* [vnet-onprem](./modules/vnet-onprem/) simulates connectivity to an on-premises network using a site-to-site VPN connection and Azure DNS private resolver.
* [petstore](./modules/petstore/) deploys a sample RESTful API application using Azure Container Apps.

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
