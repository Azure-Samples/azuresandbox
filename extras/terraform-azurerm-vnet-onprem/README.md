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

  `Apply complete! Resources: xx added, 0 changed, 0 destroyed.`

* Inspect `terraform.tfstate`.

  ```bash
  # List resources managed by terraform
  terraform state list 
  ```

## Smoke testing

## Documentation
