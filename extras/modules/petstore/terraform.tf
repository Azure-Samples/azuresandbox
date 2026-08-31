terraform {
  required_version = "~> 1.15.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.3.0"
    }
  }
}
