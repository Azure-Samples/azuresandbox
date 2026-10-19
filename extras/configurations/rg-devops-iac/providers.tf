# Providers authenticate as the operator signed in to Azure CLI (az login). This configuration is a one-time
# bootstrap run by a person with Owner on the subscription, so it needs no service principal or client secret.
# The Terraform state backend (backend.tf, when used) authenticates independently of these settings.
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
