terraform {
  required_version = "~> 1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4.0"
    }
  }
}
