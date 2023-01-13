terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.37.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "=3.4.3"
    }
  }
}

# Providers
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.arm_client_id
  client_secret   = var.arm_client_secret
  tenant_id       = var.aad_tenant_id
}

provider "random" {}
