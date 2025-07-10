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

#region resources
resource "azurerm_mysql_flexible_server" "this" {
  name                   = module.naming.mysql_server.name_unique
  resource_group_name    = var.resource_group_name
  location               = var.location
  administrator_login    = data.azurerm_key_vault_secret.adminuser.value
  administrator_password = data.azurerm_key_vault_secret.adminpassword.value
  sku_name               = var.mysql_sku_name
}

resource "azurerm_mysql_flexible_database" "this" {
  name                = var.mysql_database_name
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}
#endregion

#region modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.2"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-seed            = var.unique_seed
  unique-include-numbers = true
  unique-length          = 8
}
#endregion
