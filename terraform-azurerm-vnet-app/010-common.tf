terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.100.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "=3.6.0"
    }

    cloudinit = {
      source = "hashicorp/cloudinit"
      version = "=2.3.3"
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

provider "random" {}

provider "cloudinit" {}

# Secrets
data "azurerm_key_vault_secret" "adminpassword" {
  name         = var.admin_password_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "adminuser" {
  name         = var.admin_username_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "storage_account_kerb_key" {
  name         = "${var.storage_account_name}-kerb1"
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "storage_account_key" {
  name         = var.storage_account_name
  key_vault_id = var.key_vault_id
}
