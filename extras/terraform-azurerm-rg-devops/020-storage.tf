# Storage account
resource "random_id" "random_id_st_tfm_name" {
  byte_length = 8
}

resource "azurerm_storage_account" "st_tfm" {
  name                     = "st${random_id.random_id_st_tfm_name.hex}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  access_tier              = var.storage_access_tier
  account_replication_type = var.storage_replication_type
  tags                     = var.tags
}

# Container for terraform state backend storage 
resource "azurerm_storage_container" "container_tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.st_tfm.name
  container_access_type = "private"
}

resource "azurerm_key_vault_secret" "storage_account_key" {
  name         = azurerm_storage_account.st_tfm.name
  value        = azurerm_storage_account.st_tfm.primary_access_key
  key_vault_id = var.key_vault_id
}
