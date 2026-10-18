locals {
  # The roles the deployment identity may assign, shared with scripts/grant-deployment-identity-roles.sh.
  deployment_identity_assignable_roles = [
    for line in split("\n", file("${path.module}/../../../scripts/deployment-identity-roles.txt")) :
    trimspace(line) if trimspace(line) != "" && !startswith(trimspace(line), "#")
  ]

  deployment_identity_rbac_condition = trimspace(templatefile("${path.module}/../../../scripts/deployment-identity-rbac-condition.tftpl", {
    role_ids = join(", ", [for role in local.deployment_identity_assignable_roles : data.azurerm_role_definition.deployment_identity_assignable[role].role_definition_id])
  }))

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
