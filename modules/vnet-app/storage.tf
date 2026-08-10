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

# Routes storage write/delete logs and transaction metrics for the blob and file services
# to the shared Log Analytics workspace owned by the vnet-shared module, mirroring the
# observability wiring used by the container registry (see main.tf). The blob and file
# sub-services are targeted (StorageWrite/StorageDelete logs live at the sub-service scope,
# not the account scope); the account only uses blob and file, so queue and table services
# are intentionally omitted.
#
# StorageRead is intentionally NOT enabled: most storage accounts serve high-volume
# workloads where read logging (every GetBlob/list/property/metadata read) dominates Log
# Analytics ingestion cost while adding little security value beyond the Transaction metric.
# Mutations (writes/deletes) are the security-relevant events and are low volume by
# comparison. To audit data access on a low-volume account where read logging is a defined
# requirement, add an `enabled_log { category = "StorageRead" }` block to each setting below.
resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "Diagnostic Logs"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_file" {
  name                       = "Diagnostic Logs"
  target_resource_id         = "${azurerm_storage_account.this.id}/fileServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
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

  name                 = each.value.name
  storage_container_id = azurerm_storage_container.this.id
  type                 = "Block"
  source               = "./${path.module}/scripts/${each.value.name}"

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
resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"

  triggers = {
    storage_account_id = azurerm_storage_account.this.id
  }

  depends_on = [azurerm_role_assignment.assignments_storage]
}
#endregion
