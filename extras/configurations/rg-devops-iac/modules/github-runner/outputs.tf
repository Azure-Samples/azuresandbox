output "resource_ids" {
  value = var.deployment_identity == "oidc" ? {
    runner_power_state_identity = azurerm_user_assigned_identity.runner_power_state[0].id
  } : {}
}

output "resource_names" {
  value = var.deployment_identity == "oidc" ? {
    runner_power_state_identity = azurerm_user_assigned_identity.runner_power_state[0].name
  } : {}
}

# The GitHub OIDC subjects accepted by the deployment identity's federated identity credentials, keyed by environment.
# An empty map unless var.deployment_identity is oidc. The root module includes it in its deployment_identity output.
output "github_subjects" {
  value = local.github_oidc_subjects
}

# The GitHub Actions self-hosted runner.
#   name:                                The name the runner is registered with.
#   power_state_identity_client_id:      The client id of the runner power state identity, which the Sandbox deployment workflow uses to start and deallocate the VM.
#                                        Null unless var.deployment_identity is oidc.
#   power_state_identity_github_subject: The GitHub OIDC subject accepted by the runner power state identity's federated identity credential.
#                                        Null unless var.deployment_identity is oidc.
output "github_runner" {
  value = {
    name                                = var.virtual_machine_name
    power_state_identity_client_id      = var.deployment_identity == "oidc" ? azurerm_user_assigned_identity.runner_power_state[0].client_id : null
    power_state_identity_github_subject = local.github_runner_power_state_subject
  }
}
