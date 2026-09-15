terraform {
  required_version = "~> 1.16.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5.0"
    }
  }
}
