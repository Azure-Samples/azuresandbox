terraform {
  required_version = "~> 1.15.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.74.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}
