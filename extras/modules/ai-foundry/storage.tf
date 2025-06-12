#region files
resource "azurerm_storage_share_directory" "this" {
  name             = "documents"
  storage_share_id = "${var.storage_file_endpoint}${var.storage_share_name}"

  depends_on = [time_sleep.wait_for_public_access]
}

resource "azurerm_storage_share_file" "documents" {
  for_each = toset(local.documents)

  name             = each.value
  storage_share_id = "${var.storage_file_endpoint}${var.storage_share_name}"
  path             = "documents"
  source           = "./${path.module}/documents/${each.value}"

  depends_on = [azurerm_storage_share_directory.this]
}
#endregion

#region utilities
resource "azapi_update_resource" "enable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = var.storage_account_id

  body = { properties = { publicNetworkAccess = "Enabled" } }

  lifecycle { ignore_changes = all }
}

resource "azapi_update_resource" "disable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = var.storage_account_id

  depends_on = [azurerm_storage_share_file.documents]

  body = { properties = { publicNetworkAccess = "Disabled" } }

  lifecycle { ignore_changes = all }
}

resource "time_sleep" "wait_for_public_access" {
  create_duration = "2m"
  depends_on      = [azapi_update_resource.enable_public_access]
}
#endregion
