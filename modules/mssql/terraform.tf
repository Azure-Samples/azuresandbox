terraform {
  required_version = "~> 1.15.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.2.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}
