terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "=2.0.1"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.9.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "=3.6.3"
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
