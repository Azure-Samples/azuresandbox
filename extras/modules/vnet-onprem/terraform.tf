terraform {
  required_version = "~> 1.12.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.34.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
  }
}
