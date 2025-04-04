terraform {
  required_version = "~> 1.11"
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~>2.3"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.26"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~>2.3"
    }

    time = {
      source  = "hashicorp/time"
      version = "~>0.13"
    }
  }
}

# Providers
provider "azapi" {
  subscription_id = var.subscription_id
  client_id       = var.arm_client_id
  client_secret   = var.arm_client_secret
  tenant_id       = var.aad_tenant_id
}

provider "azurerm" {
  subscription_id = var.subscription_id
  client_id       = var.arm_client_id
  client_secret   = var.arm_client_secret
  tenant_id       = var.aad_tenant_id

  features {}
}

provider "cloudinit" {}

provider "time" {}

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
