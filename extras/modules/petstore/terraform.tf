terraform {
  required_version = "~> 1.17.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13.0"
    }
  }
}
