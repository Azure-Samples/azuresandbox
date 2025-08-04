terraform {
  required_version = "~> 1.12.2"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.5.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.38.1"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1.0"
    }
  }
}
