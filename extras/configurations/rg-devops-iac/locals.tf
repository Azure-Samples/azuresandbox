locals {
  # The roles the deployment identity may assign, shared with scripts/grant-deployment-identity-roles.sh.
  deployment_identity_assignable_role_ids = [
    for line in split("\n", file("${path.module}/../../../scripts/deployment-identity-roles.txt")) :
    split(" ", trimspace(line))[0] if trimspace(line) != "" && !startswith(trimspace(line), "#")
  ]

  deployment_identity_rbac_condition = trimspace(templatefile("${path.module}/../../../scripts/deployment-identity-rbac-condition.tftpl", {
    role_ids = join(", ", local.deployment_identity_assignable_role_ids)
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
