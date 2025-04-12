terraform {
  required_version = "~>1.11"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~>2.3"
    }

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
