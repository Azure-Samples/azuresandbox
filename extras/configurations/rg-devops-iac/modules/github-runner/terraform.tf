terraform {
  required_version = "~> 1.17.1"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.6.2"
    }
  }
}
