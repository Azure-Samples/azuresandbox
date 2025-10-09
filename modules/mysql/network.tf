resource "azurerm_private_endpoint" "this" {
  name                = "${module.naming.private_endpoint.name}-mysql-server"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id

  depends_on = [azurerm_mysql_flexible_database.this]

  private_service_connection {
    name                           = "azure_mysql_flexible_server"
    private_connection_resource_id = azurerm_mysql_flexible_server.this.id
    is_manual_connection           = false
    subresource_names              = ["mysqlServer"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
