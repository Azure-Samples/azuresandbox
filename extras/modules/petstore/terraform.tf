terraform {
  required_version = "~> 1.16.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7.0"
    }
  }
}
