terraform {
  required_version = "~> 1.16.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4.1"
    }
  }
}
