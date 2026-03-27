terraform {
  required_version = "~> 1.14"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.9"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.66"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.2"
    }
  }
}
