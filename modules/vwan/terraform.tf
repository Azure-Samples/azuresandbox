terraform {
  required_version = "~> 1.15.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.72.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.2.1"
    }
  }
}
