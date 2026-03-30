#region storage-account
resource "azurerm_storage_account" "this" {
  name                            = module.naming.storage_account.name_unique
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  access_tier                     = "Hot"
  shared_access_key_enabled       = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = true # Centralized disable in root main.tf will set this to false after all modules complete
  allow_nested_items_to_be_public = false

  lifecycle {
    ignore_changes = [
      azure_files_authentication,   # Configured separately by ./scripts/Set-AzureFilesConfiguration.ps1
      public_network_access_enabled # Centralized disable in root main.tf will set this to false after all modules complete
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

  depends_on = [time_sleep.wait_for_roles]
}

resource "azurerm_storage_blob" "remote_scripts" {
  for_each = local.remote_scripts

  name                   = each.value.name
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = azurerm_storage_container.this.name
  type                   = "Block"
  source                 = "./${path.module}/scripts/${each.value.name}"

  depends_on = [time_sleep.wait_for_roles]
}
#endregion

#region storage-share
resource "azurerm_storage_share" "this" {
  name               = var.storage_share_name
  storage_account_id = azurerm_storage_account.this.id
  quota              = var.storage_share_quota_gb

  depends_on = [time_sleep.wait_for_roles]
}
#endregion

#region utility-resources
resource "terraform_data" "storage_operations_complete" {
  input = {
    share = azurerm_storage_share.this.id
    blobs = values(azurerm_storage_blob.remote_scripts)[*].id
  }
}

resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"

  triggers = {
    storage_account_id = azurerm_storage_account.this.id
  }

  depends_on = [azurerm_role_assignment.assignments_storage]
}
#endregion
