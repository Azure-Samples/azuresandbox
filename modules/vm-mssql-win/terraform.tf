terraform {
  required_version = "~> 1.15.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0.1"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }


    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.0"
    }
  }
}
