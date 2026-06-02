terraform {
  required_version = "~> 1.15.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.75.0"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3.0"
    }
  }
}
