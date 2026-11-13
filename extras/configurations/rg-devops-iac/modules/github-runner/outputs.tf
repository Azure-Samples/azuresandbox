output "resource_ids" {
  value = merge(
    var.deployment_identity != "none" ? { deployment_identity = azurerm_user_assigned_identity.deployment[0].id } : {},
    var.deployment_identity == "oidc" ? {
      runner_power_state_identity = azurerm_user_assigned_identity.runner_power_state[0].id
    } : {}
  )
}

output "resource_names" {
  value = merge(
    var.deployment_identity != "none" ? { deployment_identity = azurerm_user_assigned_identity.deployment[0].name } : {},
    var.deployment_identity == "oidc" ? {
      runner_power_state_identity = azurerm_user_assigned_identity.runner_power_state[0].name
    } : {}
  )
}

# The deployment identity, or null when var.deployment_identity is none.
#   client_id:       Used as 'client_id' for Azure Sandbox applies with auth_mode = "managed_identity" or "oidc".
#   github_subjects: The GitHub OIDC subjects accepted by its federated identity credentials, keyed by environment.
#                    An empty map unless var.deployment_identity is oidc.
#   jit_condition:   The condition (version 2.0) the operator applies to its time-bound 'Role Based Access Control Administrator' assignment before each apply.
#   principal_id:    The principal (object) id, used to grant Microsoft Graph application permissions.
output "deployment_identity" {
  value = var.deployment_identity != "none" ? {
    client_id       = azurerm_user_assigned_identity.deployment[0].client_id
    github_subjects = local.github_oidc_subjects
    jit_condition   = local.deployment_identity_rbac_condition
    principal_id    = azurerm_user_assigned_identity.deployment[0].principal_id
  } : null
}

# The deployment identity's resource id, or null when var.deployment_identity is none.
# The root module attaches it to jumplinux2 when var.deployment_identity is managed_identity.
output "deployment_identity_id" {
  value = var.deployment_identity != "none" ? azurerm_user_assigned_identity.deployment[0].id : null
}

# The GitHub Actions self-hosted runner, or null when var.enable_github_runner is false.
#   name:                                The name the runner is registered with.
#   power_state_identity_client_id:      The client id of the runner power state identity, which the Sandbox deployment workflow uses to start and deallocate the VM.
#                                        Null unless var.deployment_identity is oidc.
#   power_state_identity_github_subject: The GitHub OIDC subject accepted by the runner power state identity's federated identity credential.
#                                        Null unless var.deployment_identity is oidc.
output "github_runner" {
  value = var.enable_github_runner ? {
    name                                = var.virtual_machine_name
    power_state_identity_client_id      = var.deployment_identity == "oidc" ? azurerm_user_assigned_identity.runner_power_state[0].client_id : null
    power_state_identity_github_subject = local.github_runner_power_state_subject
  } : null
}
