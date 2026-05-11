terraform {
  required_version = "~> 1.15.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.72.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8.1"
    }
  }
}
