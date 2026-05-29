terraform {
  required_version = "~> 1.15.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.74.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3.0"
    }
  }
}
