terraform {
  required_version = "~> 1.14.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.67.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8.1"
    }
  }
}
