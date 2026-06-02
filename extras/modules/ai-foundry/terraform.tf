terraform {
  required_version = "~> 1.15.5"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.10.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.75.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}
