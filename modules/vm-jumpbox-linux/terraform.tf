terraform {
  required_version = "~> 1.16.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5.0"
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
