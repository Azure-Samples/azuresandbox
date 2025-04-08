provider "azurerm" {
  subscription_id                 = var.subscription_id
  client_id                       = var.arm_client_id
  client_secret                   = var.arm_client_secret
  resource_provider_registrations = "extended"
  tenant_id                       = var.aad_tenant_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false # This is to handle policy driven resource creation.
    }
  }
}

