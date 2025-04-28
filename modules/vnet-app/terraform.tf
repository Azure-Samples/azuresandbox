terraform {
  required_version = "~> 1.11.4"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.3.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.27.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13.0"
    }
  }
}
