terraform {
  required_version = "~> 1.16.3"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.6.0"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.4.1"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.2"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4.1"
    }
  }
}
