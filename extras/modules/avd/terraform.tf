terraform {
  required_version = "~> 1.14"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.66"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
