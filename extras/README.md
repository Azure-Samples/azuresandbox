# Extras

## Contents

* [Overview](#overview)
* [Configurations](#configurations)
* [Demo videos](#demo-videos)

## Overview

Contains additional Terraform configurations and supporting resources.

## Configurations

This section describes additional Terraform configurations that can be added to #AzureSandbox. These configurations are not required to use #AzureSandbox, but may be useful for learning or testing purposes.

* [terraform-azurerm-rg-devops](./extras/terraform-azurerm-rg-devops/) includes the following:
  * A [resource group](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#resource-group) which contains DevOps environment resources.
  * A [key vault](https://learn.microsoft.com/azure/key-vault/general/overview) for managing secrets.
  * A [storage account](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#storage-account) for use as a [Terraform azurerm backend](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm).
  * A Linux [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) for use as a DevOps agent.
* [terraform-azurerm-vm-devops](./terraform-azurerm-vm-devops/) implements a collection of identical [IaaS](https://azure.microsoft.com/overview/what-is-iaas/) [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) designed to be used as Windows Developer Workstations.
* [terraform-azurerm-vnet-onprem](./terraform-azurerm-vnet-onprem/) simulates connectivity to an on-premises network using a site-to-site VPN connection and Azure DNS private resolver.

## Demo videos

This section contains an index of demo videos that were built using aspects of #AzureSandbox.

* [Accessing Azure Files over HTTPS](https://youtu.be/6ft5rxET8Pc) (October 2023)
* [Fixing a PowerShell script bug with GitHub Copilot](https://youtu.be/xRgdzc_Rl9w) (August 2023)
