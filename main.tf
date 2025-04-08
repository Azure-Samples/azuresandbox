module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "0.4.2"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-include-numbers = true
  unique-length          = 8
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name_unique
  location = var.location
  tags     = var.tags
}

resource "azurerm_key_vault" "this" {
  name                          = module.naming.key_vault.name_unique
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = var.aad_tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  public_network_access_enabled = true # Note:Required to demo sandbox using internet connection
}

resource "azurerm_role_assignment" "kv_secrets_officer_spn" {
  principal_id         = var.arm_client_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Key Vault Secrets Officer"
  scope                = azurerm_key_vault.this.id
}

resource "azurerm_role_assignment" "kv_secrets_officer_user" {
  principal_id         = var.user_object_id
  principal_type       = "User"
  role_definition_name = "Key Vault Secrets Officer"
  scope                = azurerm_key_vault.this.id
}
