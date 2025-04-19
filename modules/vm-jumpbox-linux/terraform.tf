terraform {
  required_version = "~> 1.11.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.26.0"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~>2.3.6"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.1"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.6"
    }
  }
}
