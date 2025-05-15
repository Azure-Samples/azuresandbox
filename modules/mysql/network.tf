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
}

resource "azurerm_private_dns_a_record" "this" {
  name                = azurerm_mysql_flexible_server.this.name
  zone_name           = "privatelink.mysql.database.azure.com"
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.this.private_service_connection[0].private_ip_address]
}
