#region utilities
module "naming" {
  source        = "Azure/avm-utl-naming/azure"
  version       = "~> 0.3.0"
  suffix        = [var.tags["project"], var.tags["environment"]]
  unique_length = 0
}

# For globally or subscription unique names. unique_seed is unknown until apply, so it is added to the suffix rather
# than passed to the naming module's unique_seed input, which would break the module's count.
module "naming_unique" {
  source        = "Azure/avm-utl-naming/azure"
  version       = "~> 0.3.0"
  suffix        = [var.tags["project"], var.tags["environment"], substr(var.unique_seed, 0, 8)]
  unique_length = 0
}
#endregion

#region image-builder-identity
# UAMI used by the Azure VM Image Builder templates in compute.tf. It holds two built-in roles:
# - Compute Gallery Artifacts Publisher on the gallery: publish image versions to its image definitions.
# - Network Contributor on the VNet: join the build subnets.
# AIB gives the identity Contributor on each template's staging resource group itself, so no role is needed for staging.
# See https://learn.microsoft.com/azure/virtual-machines/linux/image-builder-permissions-cli
resource "azurerm_user_assigned_identity" "image_builder" {
  name                = "${module.naming.names["user_assigned_identity"].name}-image-builder"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "image_builder" {
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Compute Gallery Artifacts Publisher"
  scope                = azurerm_shared_image_gallery.this.id
}

resource "azurerm_role_assignment" "image_builder_network" {
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Network Contributor"
  scope                = var.virtual_network_id
}

# AIB checks the identity's permissions when a template is created, so wait for the role assignments to propagate.
resource "time_sleep" "wait_for_image_builder_roles" {
  create_duration = "2m"

  depends_on = [
    azurerm_role_assignment.image_builder,
    azurerm_role_assignment.image_builder_network,
  ]
}
#endregion

