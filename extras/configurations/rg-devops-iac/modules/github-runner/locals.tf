locals {
  # Allow-list of Azure RBAC roles the deployment identity may assign or remove using it's 
  # "Role Based Access Control Administrator" role assignment. Names must match built-in role names exactly. 
  # This set is specific to the Azure Sandbox configuration, grouped by the module that first needs each role. 
  # You can replace it with the roles your configuration assigns.
  deployment_identity_assignable_roles = [
    # vnet_shared
    "Key Vault Secrets Officer",

    # vnet_app
    "Key Vault Secrets User",
    "Monitoring Reader",
    "Storage Account Contributor",
    "Storage Blob Data Contributor",
    "Storage Blob Data Reader",
    "Storage File Data Privileged Contributor",

    # vm_jumpbox_linux, vm_mssql_win, mssql, mysql, vwan: no additional roles

    # avd (extra module)
    "Desktop Virtualization User",
    "Virtual Machine User Login",

    # petstore (extra module)
    "AcrPull",
    "AcrPush",
    "Monitoring Metrics Publisher",

    # vnet_onprem (extra module): no additional roles
  ]

  deployment_identity_role_ids = join(", ", [
    for role in local.deployment_identity_assignable_roles : data.azurerm_role_definition.deployment_identity_assignable[role].role_definition_id
  ])

  # ABAC condition on the deployment identity's Role Based Access Control Administrator assignment. It restricts the
  # roles the identity can assign or remove to the allow-list above, so it can't grant privileged roles such as Owner.
  deployment_identity_rbac_condition = join(" AND ", [
    "((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/write'}) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployment_identity_role_ids}}))",
    "((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployment_identity_role_ids}}))",
  ])

  # Numeric ids of the GitHub repository and its owner, used in the OIDC subjects below.
  # Each id comes from its variable (var.github_repository_id, var.github_repository_owner_id) when set.
  # If either is empty, the missing id is looked up from the GitHub API on each plan, using the repository in var.github_runner_url.
  # The lookup is anonymous, so it works only for public repositories; set both variables for a private repository.
  github_repository_lookup   = var.deployment_identity == "oidc" && (var.github_repository_id == "" || var.github_repository_owner_id == "")
  github_repository          = local.github_repository_lookup ? jsondecode(data.http.github_repository[0].response_body) : null
  github_repository_id       = var.github_repository_id != "" ? var.github_repository_id : try(tostring(local.github_repository.id), "")
  github_repository_owner_id = var.github_repository_owner_id != "" ? var.github_repository_owner_id : try(tostring(local.github_repository.owner.id), "")

  # A GitHub OIDC subject identifies which repository and environment a GitHub Actions job runs in.
  # Each subject becomes a federated identity credential so matching jobs can sign in to Azure without a stored secret.
  # The repository must use the subject claim template {"use_default":false,"include_claim_keys":["repository_owner_id","repository_id","context"]}.
  # The template can be set on the repository itself or inherited from its organization.
  # For a job in an environment, "context" is "environment:<name>", so each subject is this prefix followed by the environment name.
  github_oidc_subject_prefix = "repository_owner_id:${local.github_repository_owner_id}:repository_id:${local.github_repository_id}:environment:"

  # The oidc deployment identity accepts one subject for each environment in var.deployment_identity_github_environments.
  github_oidc_subjects = var.deployment_identity == "oidc" ? {
    for environment in var.deployment_identity_github_environments : environment => "${local.github_oidc_subject_prefix}${environment}"
  } : {}

  # The runner power state identity accepts one subject, for var.github_runner_power_state_environment.
  github_runner_power_state_subject = var.deployment_identity == "oidc" ? "${local.github_oidc_subject_prefix}${var.github_runner_power_state_environment}" : null

  github_runner_home = "/opt/actions-runner"
}
