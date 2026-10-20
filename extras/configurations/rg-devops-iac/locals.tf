locals {
  # Private DNS zones used by the Azure Monitor Private Link Scope (AMPLS) private endpoint.
  ampls_private_dns_zones = [
    "privatelink.agentsvc.azure-automation.net", # Legacy agent service channel
    "privatelink.monitor.azure.com",             # Global endpoints, AMA configuration (DCE) and ingestion
    "privatelink.ods.opinsights.azure.com",      # Log Analytics data ingestion
    "privatelink.oms.opinsights.azure.com",      # Log Analytics agent onboarding
  ]

  # Roles the sandbox assigns, grouped by module. Each role is listed once, under the first module that needs it.
  # Keep in sync with the ROLES list in the root README's Service Principal commands.
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

  # The identity can create (write) or remove (delete) a role assignment only if the role is in the list above.
  # This prevents it from assigning highly privileged roles such as Owner, User Access Administrator or
  # Role Based Access Control Administrator. Keep in sync with the CONDITION in the root README's Service Principal commands.
  deployment_identity_rbac_condition = join(" AND ", [
    "((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/write'}) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployment_identity_role_ids}}))",
    "((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployment_identity_role_ids}}))",
  ])

  # GitHub OIDC subjects accepted by the oidc deployment identity, keyed by environment. They match the subject claim
  # template {"use_default":false,"include_claim_keys":["repository_owner_id","repository_id","context"]}, which the
  # repository gets from its organization's template or its own. For a job in an environment, "context" is
  # "environment:<name>". The ids come from the variables when set, otherwise from the GitHub API.
  github_repository_lookup   = var.deployment_identity == "oidc" && (var.github_repository_id == "" || var.github_repository_owner_id == "")
  github_repository          = local.github_repository_lookup ? jsondecode(data.http.github_repository[0].response_body) : null
  github_repository_id       = var.github_repository_id != "" ? var.github_repository_id : try(tostring(local.github_repository.id), "")
  github_repository_owner_id = var.github_repository_owner_id != "" ? var.github_repository_owner_id : try(tostring(local.github_repository.owner.id), "")

  github_oidc_subjects = var.deployment_identity == "oidc" ? {
    for environment in var.github_oidc_environments :
    environment => "repository_owner_id:${local.github_repository_owner_id}:repository_id:${local.github_repository_id}:environment:${environment}"
  } : {}
}
