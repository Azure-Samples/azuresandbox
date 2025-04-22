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
resource "azurerm_mssql_server" "this" {
  name                          = module.naming.sql_server.name_unique
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  administrator_login           = data.azurerm_key_vault_secret.adminuser.value
  administrator_login_password  = data.azurerm_key_vault_secret.adminpassword.value
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  lifecycle { 
    ignore_changes = [
      express_vulnerability_assessment_enabled
    ]
  }
}

resource "azurerm_mssql_database" "this" {
  name         = var.mssql_database_name
  server_id    = azurerm_mssql_server.this.id
  license_type = "BasePrice"
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
