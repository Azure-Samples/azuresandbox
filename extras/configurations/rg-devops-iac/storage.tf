resource "azurerm_storage_account" "this" {
  name                      = module.naming.storage_account.name_unique
  resource_group_name       = azurerm_resource_group.this.name
  location                  = var.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  access_tier               = var.storage_access_tier
  account_replication_type  = var.storage_replication_type
  shared_access_key_enabled = false
}

resource "azurerm_storage_container" "this" {
  name                  = var.storage_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
