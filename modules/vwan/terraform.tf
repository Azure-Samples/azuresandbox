terraform {
  required_version = "~> 1.13.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.6.1"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.41.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1.0"
    }
  }
}
