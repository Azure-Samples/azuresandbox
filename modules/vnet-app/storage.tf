#region storage-account
resource "azurerm_storage_account" "this" {
  name                          = module.naming.storage_account.name_unique
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_kind                  = "StorageV2"
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  access_tier                   = "Hot"
  shared_access_key_enabled     = false
  https_traffic_only_enabled    = true
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = false

  lifecycle {
    ignore_changes = [
      azure_files_authentication,   # Configured separately by ./scripts/Set-AzureFilesConfiguration.ps1
      public_network_access_enabled # Avoid triggering recreation of resources in dependent modules if public access is temporarily enabled for terraform plan / apply operations
    ]
  }
}

resource "azurerm_role_assignment" "assignments_storage" {
  for_each = local.storage_roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = azurerm_storage_account.this.id
}
#endregion

#region storage-container
resource "azurerm_storage_container" "this" {
  name                  = var.storage_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"

  depends_on = [time_sleep.wait_for_roles_and_public_access]
}

resource "azurerm_storage_blob" "remote_scripts" {
  for_each = local.remote_scripts

  name                   = each.value.name
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = azurerm_storage_container.this.name
  type                   = "Block"
  source                 = "./${path.module}/scripts/${each.value.name}"

  depends_on = [time_sleep.wait_for_roles_and_public_access]
}
#endregion

#region storage-share
resource "azurerm_storage_share" "this" {
  name               = var.storage_share_name
  storage_account_id = azurerm_storage_account.this.id
  quota              = var.storage_share_quota_gb

  depends_on = [time_sleep.wait_for_roles_and_public_access]
}
#endregion

#region utility-resources
resource "azapi_update_resource" "storage_account_enable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = azurerm_storage_account.this.id

  body = { properties = { publicNetworkAccess = "Enabled" } }

  lifecycle { ignore_changes = all }
}

resource "azapi_update_resource" "storage_account_disable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = azurerm_storage_account.this.id

  depends_on = [azurerm_storage_blob.remote_scripts, azurerm_storage_share.this]

  body = { properties = { publicNetworkAccess = "Disabled" } }

  lifecycle { ignore_changes = all }
}

resource "time_sleep" "wait_for_roles_and_public_access" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.assignments_storage, azapi_update_resource.storage_account_enable_public_access]
}
#endregion
