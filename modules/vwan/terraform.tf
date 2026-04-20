terraform {
  required_version = "~> 1.14.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.69.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.2.1"
    }
  }
}
