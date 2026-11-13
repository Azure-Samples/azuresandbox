#region data
data "azurerm_client_config" "current" {}

# Looks up the role definition ID (GUID) for each allow-listed role name.
data "azurerm_role_definition" "deployment_identity_assignable" {
  for_each = toset(local.deployment_identity_assignable_roles)

  name  = each.value
  scope = "/subscriptions/${var.subscription_id}"
}

# Looks up the numeric repository and owner ids used in the GitHub OIDC subjects, when they aren't set in variables.
# The request is anonymous, because a token would be saved in state, so it works only for public repositories and is rate-limited.
# For a private repository, set github_repository_id and github_repository_owner_id in terraform.tfvars.
data "http" "github_repository" {
  count = local.github_repository_lookup ? 1 : 0

  url = "https://api.github.com/repos/${trimprefix(var.github_runner_url, "https://github.com/")}"

  request_headers = {
    Accept                 = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Could not look up ${var.github_runner_url} anonymously (HTTP ${self.status_code}). For a private repository, or if the GitHub API rate limit is exceeded, set github_repository_id and github_repository_owner_id."
    }
  }
}
#endregion

#region deployment-identity

# User-assigned managed identity (UAMI) used by the Azure Sandbox configuration's azurerm, azapi and azuread providers.
# The VM's (jumplinux2) system-assigned managed identity, not the UAMI, is used for the Terraform state backend.
# The UAMI and its roles depend on the deployment_identity setting:
# - "none" (default): no deployment UAMI is created.
# - "managed_identity": the deployment UAMI is attached to jumplinux2 and used by Terraform running there, from a terminal or a GitHub Actions job on its self-hosted runner.
# - "oidc": the deployment UAMI is NOT attached to jumplinux2. Instead, it is used by approved GitHub Actions jobs on jumplinux2's self-hosted runner through federated identity credentials.
# In both modes it holds no standing Azure RBAC role. Before each apply, the operator grants time-bound Contributor and Role Based Access Control Administrator,
# restricted by the allow-list ABAC condition (scripts/grant-jit-roles.sh).
resource "azurerm_user_assigned_identity" "deployment" {
  count = var.deployment_identity != "none" ? 1 : 0

  name                = "${module.naming.names["user_assigned_identity"].name}-deployment"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Trusts GitHub Actions OIDC tokens for the oidc deployment identity, one credential per subject in local.github_oidc_subjects.
# A workflow job can exchange its GitHub token for an Azure token only if the token's issuer, audience and subject exactly match a credential.
# This limits sign-in to jobs from this repository that run in one of the allowed GitHub environments, with no stored secret.
resource "azurerm_federated_identity_credential" "deployment_identity_github" {
  for_each = local.github_oidc_subjects

  name                      = "github-${each.key}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value
  user_assigned_identity_id = azurerm_user_assigned_identity.deployment[0].id
}
#endregion

#region runner-power-state-identity

# UAMI used by the Azure Sandbox deployment workflow's start_runner and stop_runner jobs, which run on GitHub-hosted runners, to start jumplinux2 before an approved run and deallocate it afterwards.
# Created only when deployment_identity is "oidc"; jumplinux2 stays deallocated between runs to reduce cost and exposure.
# The UAMI isn't attached to any VM and is reachable only from jobs in its own GitHub environment, which must differ from the deployment identity's environments, so neither identity's credentials match the other's subjects.
# It holds a standing 'Desktop Virtualization Power On Off Contributor' role assignment scoped to jumplinux2, which allows reading the VM and changing its power state but not running commands, changing extensions or deleting it.
resource "azurerm_user_assigned_identity" "runner_power_state" {
  count = var.deployment_identity == "oidc" ? 1 : 0

  name                = "${module.naming.names["user_assigned_identity"].name}-runner"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "runner_power_state" {
  count = var.deployment_identity == "oidc" ? 1 : 0

  principal_id         = azurerm_user_assigned_identity.runner_power_state[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Desktop Virtualization Power On Off Contributor"
  scope                = var.virtual_machine_id
}

# Trusts GitHub Actions OIDC tokens for the runner power state UAMI.
# Only one credential is needed, because the UAMI accepts one subject: local.github_runner_power_state_subject, for var.github_runner_power_state_environment.
# A workflow job can exchange its GitHub token for an Azure token only if the token's issuer, audience and subject exactly match the credential.
# This limits sign-in to jobs from this repository that run in the runner power state environment, with no stored secret.
resource "azurerm_federated_identity_credential" "runner_power_state_github" {
  count = var.deployment_identity == "oidc" ? 1 : 0

  name                      = "github-${var.github_runner_power_state_environment}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = local.github_runner_power_state_subject
  user_assigned_identity_id = azurerm_user_assigned_identity.runner_power_state[0].id
}
#endregion

#region modules
module "naming" {
  source        = "Azure/avm-utl-naming/azure"
  version       = "~> 0.3.0"
  suffix        = [var.tags["project"], var.tags["environment"]]
  unique_length = 0
}
#endregion

#region checks
# The runner token is needed only when the runner is registered, so a missing token is a warning, not an error.
check "github_runner_token" {
  assert {
    condition     = !var.enable_github_runner || var.github_runner_token != ""
    error_message = "github_runner_token is empty. It is required to register the GitHub Actions runner (on first deployment or when github_runner_token_version changes): run 'source modules/github-runner/scripts/new-runner-registration-token.sh'. Ignore this warning if the runner is already registered."
  }
}
#endregion
