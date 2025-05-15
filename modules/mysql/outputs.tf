output "resource_ids" {
  value = {
    mysql_server = azurerm_mysql_flexible_server.this.id
    mysql_db     = azurerm_mysql_flexible_database.this.id
  }
}

output "resource_names" {
  value = {
    mysql_server = azurerm_mysql_flexible_server.this.name
    mysql_db     = azurerm_mysql_flexible_database.this.name
  }
}
