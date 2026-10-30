terraform {
  required_version = "~> 1.17.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }


    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.2"
    }
  }
}
