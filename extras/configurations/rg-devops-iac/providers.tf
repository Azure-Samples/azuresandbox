# Providers authenticate as the operator signed in to Azure CLI (az login).
# This configuration is run manually by an operator by design.
# The configuration creates a terraform state backend so local state is used intentionally.
provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = var.entra_tenant_id
  use_cli                         = true
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
  tenant_id       = var.entra_tenant_id
  use_cli         = true
}
