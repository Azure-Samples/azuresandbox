#region resources
resource "azurerm_mssql_server" "this" {
  name                          = module.naming.sql_server.name_unique
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  azuread_administrator {
    azuread_authentication_only = true
    login_username              = var.user_name
    object_id                   = var.user_object_id
  }

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
