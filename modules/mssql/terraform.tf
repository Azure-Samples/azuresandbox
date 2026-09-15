terraform {
  required_version = "~> 1.16.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.1"
    }
  }
}
