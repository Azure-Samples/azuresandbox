locals {
  key_vault_roles = {
    kv_secrets_officer_spn = {
      principal_id         = data.azurerm_client_config.current.object_id
      principal_type       = "ServicePrincipal"
      role_definition_name = "Key Vault Secrets Officer"
    }
    kv_secrets_officer_user = {
      principal_id         = var.user_object_id
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
      principal_id         = var.user_object_id
      principal_type       = "User"
      role_definition_name = "Storage Blob Data Contributor"
    }
  }
}
