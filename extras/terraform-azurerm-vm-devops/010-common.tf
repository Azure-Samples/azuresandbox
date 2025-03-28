terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.25.0"
    }
  }
}

# Providers
provider "azurerm" {
  subscription_id            = var.subscription_id
  client_id                  = var.arm_client_id
  client_secret              = var.arm_client_secret
  tenant_id                  = var.aad_tenant_id

  features {}
}

# Secrets
data "azurerm_key_vault_secret" "adminpassword" {
  name         = var.admin_password_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "adminuser" {
  name         = var.admin_username_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "storage_account_key" {
  name         = var.storage_account_name
  key_vault_id = var.key_vault_id
}
