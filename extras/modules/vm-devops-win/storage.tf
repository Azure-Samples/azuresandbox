#region resources
resource "azurerm_storage_blob" "this" {
  name                   = local.remote_scripts["configuration"].name
  storage_account_name   = var.storage_account_name
  storage_container_name = var.storage_container_name
  type                   = "Block"
  source                 = "./${path.module}/scripts/${local.remote_scripts["configuration"].name}"

  depends_on = [time_sleep.wait_for_public_access]
}
#endregion

#region utility-resources
resource "azapi_update_resource" "enable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = var.storage_account_id

  body = { properties = { publicNetworkAccess = "Enabled" } }

  lifecycle { ignore_changes = all }
}

resource "azapi_update_resource" "disable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = var.storage_account_id

  depends_on = [azurerm_storage_blob.this]

  body = { properties = { publicNetworkAccess = "Disabled" } }

  lifecycle { ignore_changes = all }
}

resource "time_sleep" "wait_for_public_access" {
  create_duration = "2m"
  depends_on      = [azapi_update_resource.enable_public_access]
}
#endregion
