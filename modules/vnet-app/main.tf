#region data
data "azurerm_client_config" "current" {}
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

resource "null_resource" "this" {
  provisioner "local-exec" {
    command     = "$params = @{ ${join(" ", local.local_scripts["configure_automation"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["configure_automation"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
} # Configures the automation account for the Windows jumpbox VM
#endregion

#region modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.2"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-seed            = var.unique_seed
  unique-include-numbers = true
  unique-length          = 8
}
#endregion
