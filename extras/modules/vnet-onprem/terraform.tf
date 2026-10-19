terraform {
  required_version = "~> 1.16.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.2"
    }
  }
}
