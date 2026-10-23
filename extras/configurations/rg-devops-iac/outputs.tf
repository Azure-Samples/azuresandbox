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
    var.deployment_identity == "oidc" ? {
      runner_power_state_identity = azurerm_user_assigned_identity.runner_power_state[0].id
    } : {},
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
    var.deployment_identity == "oidc" ? {
      runner_power_state_identity = azurerm_user_assigned_identity.runner_power_state[0].name
    } : {},
    module.vm_jumpbox_linux.resource_names
  )
}

# The deployment identity, or null when var.deployment_identity is none.
#   client_id:       Used as 'client_id' for Azure Sandbox applies with auth_mode = "managed_identity" or "oidc".
#   github_subjects: The GitHub OIDC subjects accepted by its federated identity credentials, keyed by environment.
#                    An empty map unless var.deployment_identity is oidc.
#   jit_condition:   The condition (version 2.0) the operator applies to its time-bound 'Role Based Access Control Administrator' assignment before each workflow run.
#                    Null unless var.deployment_identity is oidc.
#   principal_id:    The principal (object) id, used to grant Microsoft Graph application permissions.
output "deployment_identity" {
  value = var.deployment_identity != "none" ? {
    client_id       = azurerm_user_assigned_identity.deployment[0].client_id
    github_subjects = local.github_oidc_subjects
    jit_condition   = var.deployment_identity == "oidc" ? local.deployment_identity_rbac_condition : null
    principal_id    = azurerm_user_assigned_identity.deployment[0].principal_id
  } : null
}

# The GitHub Actions self-hosted runner, or null when var.enable_github_runner is false.
#   name:                                The name the runner is registered with.
#   power_state_identity_client_id:      The client id of the runner power state identity, which the Sandbox deployment workflow uses to start and deallocate the VM.
#                                        Null unless var.deployment_identity is oidc.
#   power_state_identity_github_subject: The GitHub OIDC subject accepted by the runner power state identity's federated identity credential.
#                                        Null unless var.deployment_identity is oidc.
output "github_runner" {
  value = var.enable_github_runner ? {
    name                                = module.vm_jumpbox_linux.resource_names["virtual_machine_jumplinux2"]
    power_state_identity_client_id      = var.deployment_identity == "oidc" ? azurerm_user_assigned_identity.runner_power_state[0].client_id : null
    power_state_identity_github_subject = local.github_runner_power_state_subject
  } : null
}
