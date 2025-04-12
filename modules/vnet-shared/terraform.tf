terraform {
  required_version = "~>1.11"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.26"
    }

    random = {
      source  = "hashicorp/random"
      version = "~>3.7"
    }
  }
}
