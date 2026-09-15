terraform {
  required_version = "~> 1.16.2"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.9.1"
    }

    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4.0"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.4.1"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.3.2"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.1"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4.0"
    }
  }
}
