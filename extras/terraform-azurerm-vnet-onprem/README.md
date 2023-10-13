# #AzureSandbox - terraform-azurerm-vnet-opnprem

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)
* [Smoke testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![vnet-onprem-diagram](./vnet-onprem-diagram.drawio.svg)

## Overview

This configuration simulates connectivity to an on-premises network using a site-to-site VPN connection and Azure DNS private resolver. It includes the following resources:

* Simulated on-premises environment
  * A [virtual network](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vnet) for hosting [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm).
  * A [VPN gateway site-to-site VPN](https://learn.microsoft.com/en-us/azure/vpn-gateway/design#s2smulti) connection to simulate connectivity from an on-premises network to Azure.
  * A [bastion](https://learn.microsoft.com/azure/bastion/bastion-overview) for secure RDP and SSH access to virtual machines.
  * A Windows Server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) running [Active Directory Domain Services](https://learn.microsoft.com/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview) with a pre-configured domain and DNS server.
  * A Windows Server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) for use as a jumpbox.
* Azure Sandbox environment
  * A [Virtual WAN site-to-site VPN](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#s2s) connection to simulate connectivity from Azure to an on-premises network.
  * A [DNS private resolver](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview) is used to resolve DNS queries for private zones in both environments (on-premises and Azure) in a bi-directional fashion.

## Before you start

[terraform-azurerm-vwan](../../terraform-azurerm-vwan/) must be provisioned first before starting.

## Getting started

This section describes how to provision this configuration using default settings.

* Change the working directory.

  ```bash
  cd ~/azuresandbox/extras/terraform-azurerm-vnet-onprem
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

  `Apply complete! Resources: 49 added, 0 changed, 0 destroyed.`

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
* [terraform-azurerm-vwan](../../terraform-azurerm-vwan/)

Output variable | Configuration | Sample value
--- | --- | ---
aad_tenant_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
adds_domain_name_cloud | terraform-azurerm-vnet-shared | "mysandbox.local"
admin_password_secret | terraform-azurerm-vnet-shared | "adminpassword"
admin_username_secret | terraform-azurerm-vnet-shared | "adminuser"
arm_client_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
automation_account_name | terraform-azurerm-vnet-shared | "auto-xxxxxxxxxxxxxxxx-01"
dns_server_cloud | terraform-azurerm-vnet-shared | "10.1.2.4"
key_vault_id | terraform-azurerm-vnet-shared | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.KeyVault/vaults/kv-xxxxxxxxxxxxxxx"
key_vault_name | terraform-azurerm-vnet-shared | "kv-xxxxxxxxxxxxxxx"
location | terraform-azurerm-vnet-shared | "eastus"
resource_group_name | terraform-azurerm-vnet-shared | "rg-sandbox-01"
subscription_id | terraform-azurerm-vnet-shared | "00000000-0000-0000-0000-000000000000"
tags | terraform-azurerm-vnet-shared | "tomap( { "costcenter" = "10177772" "environment" = "dev" "project" = "#AzureSandbox" } )"
vnet_app_01_id | terraform-azurerm-vnet-app | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-app-01"
vnet_app_01_name | terraform-azurerm-vnet-app | "vnet-app-01"
vnet_shared_01_id | terraform-azurerm-vnet-shared | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualNetworks/vnet-shared-01"
vnet_shared_01_name | terraform-azurerm-vnet-shared | "vnet-shared-01"
vnet_shared_01_subnets | terraform-azurerm-vnet-shared | Contains all the subnet definitions.
vwan_01_hub_01_id | terraform-azurerm-vwan | "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualHubs/vhub-xxxxxxxxxxxxxxxx-01"
vwan_01_id | terraform-azurerm-vwan |"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sandbox-01/providers/Microsoft.Network/virtualWans/vwan-xxxxxxxxxxxxxxxx-01"

### Terraform resources
