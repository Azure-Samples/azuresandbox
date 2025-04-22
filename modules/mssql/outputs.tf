output "resource_ids" {
  value = {
    mssql_server = azurerm_mssql_server.this.id
    mssql_db     = azurerm_mssql_database.this.id
  }
}

output "resource_names" {
  value = {
    mssql_server = azurerm_mssql_server.this.name
    mssql_db     = azurerm_mssql_database.this.name
  }
}
