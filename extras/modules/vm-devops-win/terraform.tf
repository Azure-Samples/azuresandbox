terraform {
  required_version = "~> 1.13.4"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.7.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.51.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
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
