terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "=2.3.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.23.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "=3.7.1"
    }
  }
}

# Providers
provider "azapi" {
  subscription_id = var.subscription_id
  client_id       = var.arm_client_id
  client_secret   = var.arm_client_secret
  tenant_id       = var.aad_tenant_id
}

provider "azurerm" {
  subscription_id = var.subscription_id
  client_id       = var.arm_client_id
  client_secret   = var.arm_client_secret
  tenant_id       = var.aad_tenant_id

  features {}
}

provider "random" {}
