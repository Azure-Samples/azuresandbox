# Provider authentication is selected by var.auth_mode and applied identically to every provider.
# The Terraform state backend (backend.tf, when used) authenticates independently of these settings.
#
# auth_mode        | client_id                          | credential
# ---------------- | ---------------------------------- | -------------------------------------------
# client_secret    | Service principal appId            | var.client_secret (TF_VAR_client_secret)
# managed_identity | User-assigned managed identity id  | Managed identity endpoint of the host
locals {
  provider_auth = {
    client_id     = var.client_id
    client_secret = var.auth_mode == "client_secret" ? var.client_secret : null
    tenant_id     = var.entra_tenant_id
    use_msi       = var.auth_mode == "managed_identity"
  }
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = local.provider_auth.tenant_id
  client_id                       = local.provider_auth.client_id
  client_secret                   = local.provider_auth.client_secret
  use_msi                         = local.provider_auth.use_msi
  resource_provider_registrations = "extended"
  storage_use_azuread             = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false # This is to handle policy driven resource creation.
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = local.provider_auth.tenant_id
  client_id       = local.provider_auth.client_id
  client_secret   = local.provider_auth.client_secret
  use_msi         = local.provider_auth.use_msi
}
