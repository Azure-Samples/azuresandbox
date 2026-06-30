terraform {
  required_version = "~> 1.15.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.79.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }
  }
}
