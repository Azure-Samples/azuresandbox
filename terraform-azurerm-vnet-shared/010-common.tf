terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.50.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "=3.4.3"
    }
  }
}

# Providers
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.arm_client_id
  client_secret   = var.arm_client_secret
  tenant_id       = var.aad_tenant_id
}

provider "random" {}

# Secrets
data "azurerm_key_vault_secret" "adminpassword" {
  name         = var.admin_password_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "adminuser" {
  name         = var.admin_username_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "storageaccountkeykerb" {
  name         = var.storage_account_key_kerb_secret
  key_vault_id = var.key_vault_id
}

# Output variables
output "aad_tenant_id" {
  value = var.aad_tenant_id
}

output "adds_domain_name" {
  value = var.adds_domain_name
}

output "admin_password_secret" {
  value = var.admin_password_secret
}

output "admin_username_secret" {
  value = var.admin_username_secret
}

output "arm_client_id" {
  value = var.arm_client_id
}

output "dns_server" {
  value = var.dns_server
}

output "key_vault_id" {
  value = var.key_vault_id
}

output "key_vault_name" {
  value = var.key_vault_name
}

output "location" {
  value = var.location
}

output "resource_group_name" {
  value = var.resource_group_name
}

output "storage_account_name" {
  value = var.storage_account_name
}

output "storage_container_name" {
  value = var.storage_container_name
}

output "subscription_id" {
  value = var.subscription_id
}

output "tags" {
  value = var.tags
}
