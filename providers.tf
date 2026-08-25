provider "azuread" {
  tenant_id     = var.aad_tenant_id
  client_id     = var.arm_client_id
  client_secret = var.arm_client_secret
}

provider "azapi" {
  subscription_id = var.subscription_id
  client_id       = var.arm_client_id
  client_secret   = var.arm_client_secret
  tenant_id       = var.aad_tenant_id
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  client_id                       = var.arm_client_id
  client_secret                   = var.arm_client_secret
  tenant_id                       = var.aad_tenant_id
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
