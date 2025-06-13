terraform {
  required_version = "~> 1.12.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.33.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1.0"
    }
  }
}
