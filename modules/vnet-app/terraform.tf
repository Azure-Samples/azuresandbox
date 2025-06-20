terraform {
  required_version = "~> 1.12.2"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.34.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13.1"
    }
  }
}
