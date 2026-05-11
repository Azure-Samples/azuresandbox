terraform {
  required_version = "~> 1.15.2"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.9.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.72.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8.1"
    }
  }
}
