#region data
data "azurerm_client_config" "current" {}

resource "terraform_data" "log_analytics_operations_complete" {
  input = {
    ampls_dns_zone_links           = join(",", [for l in azurerm_private_dns_zone_virtual_network_link.vnet_app_links_from_vnet_shared : l.id])
    app_insights                   = azurerm_application_insights.this.id
    app_insights_scoped_service    = azurerm_monitor_private_link_scoped_service.app_insights.id
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

# Workspace-based Application Insights linked to the shared Log Analytics workspace owned by
# vnet-shared. Local auth is disabled so SDKs must use Entra ID. Internet ingestion/query
# start enabled and are flipped to Disabled by the root azapi_update_resource after the
# AMPLS access barrier signals end-to-end wiring is complete (see root main.tf).
resource "azurerm_application_insights" "this" {
  name                          = module.naming.application_insights.name_unique
  location                      = var.location
  resource_group_name           = var.resource_group_name
  application_type              = "web"
  workspace_id                  = var.log_analytics_workspace_id
  local_authentication_disabled = true
  internet_ingestion_enabled    = true
  internet_query_enabled        = true

  lifecycle {
    ignore_changes = [internet_ingestion_enabled, internet_query_enabled]
  }
}

# Attach Application Insights to the vnet-shared-owned AMPLS so its ingestion/query traffic
# flows over the existing AMPLS private endpoint and resolves via privatelink.monitor.azure.com.
# The scoped-service attachment is a control-plane PATCH on the parent AMPLS and serializes
# server-side with sibling scoped-service writes -- if Terraform issues this concurrently with
# another scope mutation, Azure returns 409 AnotherOperationInProgress. depends_on enforces
# ordering relative to the App Insights resource; vnet-shared does not export individual
# sibling scoped-service IDs so a second `terraform apply` may be required if a 409 surfaces.
# The retry is idempotent. See AMPLS_IMPLEMENTATION_PLAN.md "Lessons from steps 1a-1g" #1.
resource "azurerm_monitor_private_link_scoped_service" "app_insights" {
  name                = "ampls-scope-app-insights"
  resource_group_name = var.resource_group_name
  scope_name          = var.monitor_private_link_scope_name
  linked_resource_id  = azurerm_application_insights.this.id

  depends_on = [
    azurerm_application_insights.this,
    var.monitor_private_link_scope_id,
  ]
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
