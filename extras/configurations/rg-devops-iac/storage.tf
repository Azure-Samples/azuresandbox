#region resources
resource "azurerm_storage_account" "this" {
  name                      = module.naming.storage_account.name_unique
  resource_group_name       = azurerm_resource_group.this.name
  location                  = var.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  access_tier               = var.storage_access_tier
  account_replication_type  = var.storage_replication_type
  shared_access_key_enabled = false
  public_network_access     = "Enabled" # Note: The barrier pattern will disable this on apply.

  lifecycle {
    ignore_changes = [public_network_access]
  }
}

resource "azurerm_storage_container" "this" {
  name                  = var.storage_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "Transaction"
  }
}

# StorageRead, StorageWrite and StorageDelete record access to Terraform state blobs.
resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "Diagnostic Logs"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.this.id
}
#endregion
