# Provider authentication is selected by var.auth_mode and applied identically to every provider.
# The Terraform state backend (backend.tf, when used) authenticates independently of these settings.
#
# auth_mode        | client_id                          | credential
# ---------------- | ---------------------------------- | -------------------------------------------
# client_secret    | Service principal appId            | var.client_secret (TF_VAR_client_secret)
# managed_identity | User-assigned managed identity id  | Managed identity endpoint of the host
# oidc             | Federated identity client id       | GitHub Actions ID token (ACTIONS_ID_TOKEN_REQUEST_URL/TOKEN)
#
# use_msi and use_oidc are always set explicitly, so the providers don't fall back to ARM_USE_MSI, which the state
# backend on jumplinux2 uses.
provider "azuread" {
  tenant_id     = local.provider_auth.tenant_id
  client_id     = local.provider_auth.client_id
  client_secret = local.provider_auth.client_secret
  use_msi       = local.provider_auth.use_msi
  use_oidc      = local.provider_auth.use_oidc
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = local.provider_auth.tenant_id
  client_id       = local.provider_auth.client_id
  client_secret   = local.provider_auth.client_secret
  use_msi         = local.provider_auth.use_msi
  use_oidc        = local.provider_auth.use_oidc
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = local.provider_auth.tenant_id
  client_id                       = local.provider_auth.client_id
  client_secret                   = local.provider_auth.client_secret
  use_msi                         = local.provider_auth.use_msi
  use_oidc                        = local.provider_auth.use_oidc
  resource_provider_registrations = "extended"

  # The "extended" set does not include the resource providers required by some
  # optional modules. 'Microsoft.DesktopVirtualization' (avd) is only included in
  # the "all" set, and 'Microsoft.App' (petstore) is not included in any built-in
  # set, so both are registered explicitly here. Registering them additively is
  # preferred over using "all", which would still omit 'Microsoft.App' while
  # registering namespaces this configuration never uses.
  resource_providers_to_register = [
    "Microsoft.App",                  # Container Apps, used by the petstore module
    "Microsoft.DesktopVirtualization" # Azure Virtual Desktop, used by the avd module
  ]

  storage_use_azuread = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false # This is to handle policy driven resource creation.
    }
  }
}
