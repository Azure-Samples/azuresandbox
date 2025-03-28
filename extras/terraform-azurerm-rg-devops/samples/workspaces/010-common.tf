terraform {
  backend "azurerm" {
    use_azuread_auth     = true
    tenant_id            = "YOUR-TENANT-ID-HERE"
    storage_account_name = "YOUR-STORAGE-ACCOUNT-FOR-TFSTATE-HERE" 
    container_name       = "workspaces-tfstate" 
    key                  = "terraform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.25.0"
    }
  }
}

# Providers
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
