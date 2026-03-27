terraform {
  required_version = "~> 1.14"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.66"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.2"
    }
  }
}
