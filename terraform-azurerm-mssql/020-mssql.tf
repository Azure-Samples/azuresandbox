# Azure SQL Database logical server
resource "random_id" "random_id_mssql_server_01_name" {
  byte_length = 8
}

resource "azurerm_mssql_server" "mssql_server_01" {
  name                          = "mssql-${random_id.random_id_mssql_server_01_name.hex}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  administrator_login           = data.azurerm_key_vault_secret.adminuser.value
  administrator_login_password  = data.azurerm_key_vault_secret.adminpassword.value
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  tags                          = var.tags
}

# Azure SQL Database test database
resource "azurerm_mssql_database" "mssql_database_01" {
  name         = var.mssql_database_name
  server_id    = azurerm_mssql_server.mssql_server_01.id
  license_type = "LicenseIncluded"
  tags         = var.tags
}

# Private endpoint for Azure SQL Database logical server
resource "azurerm_private_endpoint" "mssql_server_01" {
  name                = "pend-${azurerm_mssql_server.mssql_server_01.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.vnet_app_01_subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = "azure_sql_database_logical_server"
    private_connection_resource_id = azurerm_mssql_server.mssql_server_01.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }
}

resource "azurerm_private_dns_a_record" "sql_server_01" {
  name                = azurerm_mssql_server.mssql_server_01.name
  zone_name           = "privatelink.database.windows.net"
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.mssql_server_01.private_service_connection[0].private_ip_address]
}
