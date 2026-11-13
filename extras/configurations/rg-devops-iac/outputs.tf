output "resource_ids" {
  value = merge(
    {
      bastion_host               = azurerm_bastion_host.this.id
      data_collection_endpoint   = azurerm_monitor_data_collection_endpoint.this.id
      data_collection_rule_linux = azurerm_monitor_data_collection_rule.linux.id
      key_vault                  = azurerm_key_vault.this.id
      log_analytics_workspace    = azurerm_log_analytics_workspace.this.id
      monitor_private_link_scope = azurerm_monitor_private_link_scope.this.id
      resource_group             = azurerm_resource_group.this.id
      storage_account            = azurerm_storage_account.this.id
      virtual_network            = azurerm_virtual_network.this.id
    },
    length(module.github_runner) > 0 ? module.github_runner[0].resource_ids : {},
    var.enable_image_gallery ? module.image_gallery[0].resource_ids : {},
    module.vm_jumpbox_linux.resource_ids
  )
}

output "resource_names" {
  value = merge(
    {
      bastion_host               = azurerm_bastion_host.this.name
      data_collection_endpoint   = azurerm_monitor_data_collection_endpoint.this.name
      data_collection_rule_linux = azurerm_monitor_data_collection_rule.linux.name
      key_vault                  = azurerm_key_vault.this.name
      log_analytics_workspace    = azurerm_log_analytics_workspace.this.name
      monitor_private_link_scope = azurerm_monitor_private_link_scope.this.name
      resource_group             = azurerm_resource_group.this.name
      storage_account            = azurerm_storage_account.this.name
      virtual_network            = azurerm_virtual_network.this.name
    },
    length(module.github_runner) > 0 ? module.github_runner[0].resource_names : {},
    var.enable_image_gallery ? module.image_gallery[0].resource_names : {},
    module.vm_jumpbox_linux.resource_names
  )
}

# The deployment identity, or null when var.deployment_identity is none. See the github-runner module's deployment_identity output.
output "deployment_identity" {
  value = length(module.github_runner) > 0 ? module.github_runner[0].deployment_identity : null
}

# The GitHub Actions self-hosted runner, or null when var.enable_github_runner is false. See the github-runner module's github_runner output.
output "github_runner" {
  value = length(module.github_runner) > 0 ? module.github_runner[0].github_runner : null
}
