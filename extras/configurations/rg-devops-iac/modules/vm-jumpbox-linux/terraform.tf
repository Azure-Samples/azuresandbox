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

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.4.1"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4.1"
    }
  }
}
