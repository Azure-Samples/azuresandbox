terraform {
  required_version = "~> 1.16.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4.0"
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
