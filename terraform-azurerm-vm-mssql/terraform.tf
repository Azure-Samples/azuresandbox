terraform {
  required_version = "~>1.11"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.26"
    }
    time = {
      source  = "hashicorp/time"
      version = "~>0.13"
    }
  }
}
