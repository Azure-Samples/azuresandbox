terraform {
  required_version = "~> 1.14"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.66"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }


    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
