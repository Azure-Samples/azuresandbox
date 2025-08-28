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
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "assignments_acr" {
  for_each = local.container_registry_roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = azurerm_container_registry.this.id
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
