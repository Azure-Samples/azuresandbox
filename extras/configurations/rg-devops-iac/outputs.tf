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
    module.vm_jumpbox_linux.resource_names
  )
}

output "deployment_identity_client_id" {
  value       = var.deployment_identity != "none" ? azurerm_user_assigned_identity.deployment[0].client_id : null
  description = "The client id of the deployment identity, used as 'client_id' for root sandbox applies with auth_mode = \"managed_identity\" or \"oidc\", or null when var.deployment_identity is none."
}

output "deployment_identity_github_subjects" {
  value       = local.github_oidc_subjects
  description = "The GitHub OIDC subjects accepted by the deployment identity's federated identity credentials, keyed by environment, or an empty map unless var.deployment_identity is oidc."
}

output "deployment_identity_jit_condition" {
  value       = var.deployment_identity == "oidc" ? local.deployment_identity_rbac_condition : null
  description = "The condition (version 2.0) the operator applies to the deployment identity's time-bound 'Role Based Access Control Administrator' assignment before each workflow run, or null unless var.deployment_identity is oidc."
}

output "deployment_identity_principal_id" {
  value       = var.deployment_identity != "none" ? azurerm_user_assigned_identity.deployment[0].principal_id : null
  description = "The principal (object) id of the deployment identity, used to grant Microsoft Graph application permissions, or null when var.deployment_identity is none."
}

output "github_runner_name" {
  value       = module.vm_jumpbox_linux.github_runner_name
  description = "The name the GitHub Actions self-hosted runner is registered with, or null when var.enable_github_runner is false."
}
