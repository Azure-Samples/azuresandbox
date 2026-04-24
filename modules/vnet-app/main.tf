#region data
data "azurerm_client_config" "current" {}

resource "terraform_data" "log_analytics_operations_complete" {
  input = {
    ampls_dns_zone_links           = join(",", [for l in azurerm_private_dns_zone_virtual_network_link.vnet_app_links_from_vnet_shared : l.id])
    container_registry_diagnostics = azurerm_monitor_diagnostic_setting.container_registry.id
    jumpwin1_ama                   = azurerm_virtual_machine_extension.ama.id
    jumpwin1_dcr_association       = azurerm_monitor_data_collection_rule_association.jumpwin1_dcr.id
    jumpwin1_dce_association       = azurerm_monitor_data_collection_rule_association.jumpwin1_dce.id
  }
}

resource "terraform_data" "storage_operations_complete" {
  input = {
    share = azurerm_storage_share.this.id
    blobs = values(azurerm_storage_blob.remote_scripts)[*].id
  }
}
#endregion

#region resources
resource "azurerm_container_registry" "this" {
  name                          = module.naming.container_registry.name_unique
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.container_registry_sku
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  data_endpoint_enabled         = true
  export_policy_enabled         = false
  network_rule_bypass_option    = "AzureServices"
  public_network_access_enabled = false
  quarantine_policy_enabled     = false
  retention_policy_in_days      = 7
  trust_policy_enabled          = false
  zone_redundancy_enabled       = false

  lifecycle {
    ignore_changes = [public_network_access_enabled]
  }
}

resource "azurerm_monitor_diagnostic_setting" "container_registry" {
  name                       = "AllMetrics and ContainerRegistryRepositoryEvents"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
#endregion

#region modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.3"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-seed            = var.unique_seed
  unique-include-numbers = true
  unique-length          = 8
}
#endregion
