terraform {
  required_version = "~> 1.14.8"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.9.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.69.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8.1"
    }
  }
}
