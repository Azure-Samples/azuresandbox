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

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1.0"
    }
  }
}
