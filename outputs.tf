output "resource_names" {
  value = merge(
    {
      key_vault               = azurerm_key_vault.this.name
      log_analytics_workspace = azurerm_log_analytics_workspace.this.name
      resource_group          = azurerm_resource_group.this.name
    },
    module.vnet_shared.resource_names,                                   # Merging resource names from the vnet_shared module
    length(module.vnet_app) > 0 ? module.vnet_app[0].resource_names : {} # Check if vnet_app exists
  )
}

output "resource_ids" {
  value = merge(
    {
      key_vault               = azurerm_key_vault.this.id
      log_analytics_workspace = azurerm_log_analytics_workspace.this.id
      resource_group          = azurerm_resource_group.this.id
    },
    module.vnet_shared.resource_ids,                                   # Merging resource IDs from the vnet_shared module
    length(module.vnet_app) > 0 ? module.vnet_app[0].resource_ids : {} # Check if vnet_app exists
  )
}
