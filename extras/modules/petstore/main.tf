resource "azurerm_container_registry" "this" {
  name                          = module.naming.container_registry.name_unique
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.container_registry_sku
  admin_enabled                 = true # TODO: change this to false before publishing
  public_network_access_enabled = true # TODO: change this to false before publishing
  quarantine_policy_enabled     = false
  trust_policy_enabled          = false
  zone_redundancy_enabled       = false
  export_policy_enabled         = true

  identity {
    type = "SystemAssigned"
  }
}

#region modules
module "naming" {
  source      = "Azure/naming/azurerm"
  version     = "~> 0.4.2"
  suffix      = [var.tags["project"], var.tags["environment"]]
  unique-seed = var.unique_seed
}
#endregion
