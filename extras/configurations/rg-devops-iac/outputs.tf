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
    var.deployment_identity != "none" ? { deployment_identity = azurerm_user_assigned_identity.deployment[0].id } : {},
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
    var.deployment_identity != "none" ? { deployment_identity = azurerm_user_assigned_identity.deployment[0].name } : {},
    length(module.github_runner) > 0 ? module.github_runner[0].resource_names : {},
    var.enable_image_gallery ? module.image_gallery[0].resource_names : {},
    module.vm_jumpbox_linux.resource_names
  )
}

# The deployment identity, or null when var.deployment_identity is none.
#   client_id:       Used as 'client_id' for Azure Sandbox applies with auth_mode = "managed_identity" or "oidc".
#   github_subjects: The GitHub OIDC subjects accepted by its federated identity credentials, keyed by environment.
#                    An empty map unless var.deployment_identity is oidc.
#   principal_id:    The principal (object) id, used by grant-jit-roles.sh and grant-graph-permissions.sh.
output "deployment_identity" {
  value = var.deployment_identity != "none" ? {
    client_id       = azurerm_user_assigned_identity.deployment[0].client_id
    github_subjects = length(module.github_runner) > 0 ? module.github_runner[0].github_subjects : {}
    principal_id    = azurerm_user_assigned_identity.deployment[0].principal_id
  } : null
}

# The GitHub Actions self-hosted runner, or null when var.enable_github_runner is false. See the github-runner module's github_runner output.
output "github_runner" {
  value = length(module.github_runner) > 0 ? module.github_runner[0].github_runner : null
}
