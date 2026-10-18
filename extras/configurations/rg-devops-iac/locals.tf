locals {
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

  key_vault_roles = {
    kv_secrets_officer_spn = {
      principal_id         = data.azurerm_client_config.current.object_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Key Vault Secrets Officer"
    }
    kv_secrets_officer_user = {
      principal_id         = var.operator_object_id
      principal_type       = "User"
      role_definition_name = "Key Vault Secrets Officer"
    }
  }

  storage_roles = {
    blob_data_contributor_spn = {
      principal_id         = data.azurerm_client_config.current.object_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Storage Blob Data Contributor"
    }
    blob_data_contributor_user = {
      principal_id         = var.operator_object_id
      principal_type       = "User"
      role_definition_name = "Storage Blob Data Contributor"
    }
  }
}
