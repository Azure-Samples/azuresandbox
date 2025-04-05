#region data
data "azurerm_key_vault_secret" "adminpassword" {
  name         = var.admin_password_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "adminuser" {
  name         = var.admin_username_secret
  key_vault_id = var.key_vault_id
}
#endregion 

#region mysql-flexible-server
resource "azurerm_mysql_flexible_server" "mysql_server_01" {
  name                   = "mysql-${var.random_id}"
  resource_group_name    = var.resource_group_name
  location               = var.location
  administrator_login    = data.azurerm_key_vault_secret.adminuser.value
  administrator_password = data.azurerm_key_vault_secret.adminpassword.value
  sku_name               = "B_Standard_B1s"
}

resource "azurerm_private_endpoint" "mysql_server_01" {
  name = "pend-${azurerm_mysql_flexible_server.mysql_server_01.name}"
  resource_group_name = var.resource_group_name
  location = var.location
  subnet_id = var.vnet_app_01_subnets["snet-privatelink-01"].id
  tags = var.tags
  depends_on = [ azurerm_mysql_flexible_database.mysql_database_01 ]

  private_service_connection {
    name = "azure_mysql_flexible_server"
    private_connection_resource_id = azurerm_mysql_flexible_server.mysql_server_01.id
    is_manual_connection = false
    subresource_names = ["mysqlServer"]
  }
}

resource "azurerm_private_dns_a_record" "mysql_server_01" {
  name = azurerm_mysql_flexible_server.mysql_server_01.name
  zone_name = "privatelink.mysql.database.azure.com"
  resource_group_name = var.resource_group_name
  ttl = 300
  records = [azurerm_private_endpoint.mysql_server_01.private_service_connection[0].private_ip_address]
}
#endregion

#region mysql-flexible-database
resource "azurerm_mysql_flexible_database" "mysql_database_01" {
  name                = var.mysql_database_name
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.mysql_server_01.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}
#endregion
