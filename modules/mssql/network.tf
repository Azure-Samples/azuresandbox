resource "azurerm_private_endpoint" "this" {
  name                = "${module.naming.private_endpoint.name}-mssql-server"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "azure_sql_database_logical_server"
    private_connection_resource_id = azurerm_mssql_server.this.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }
}

resource "azurerm_private_dns_a_record" "this" {
  name                = azurerm_mssql_server.this.name
  zone_name           = "privatelink.database.windows.net"
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.this.private_service_connection[0].private_ip_address]
}
