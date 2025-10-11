# Private endpoint for Container Apps Environment (requires Consumption + Dedicated)
resource "azurerm_private_endpoint" "this" {
  name                = "${module.naming.container_app_environment.name_unique}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${module.naming.container_app_environment.name_unique}-psc"
    private_connection_resource_id = azurerm_container_app_environment.this.id
    is_manual_connection           = false
    subresource_names              = ["managedEnvironments"]
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
