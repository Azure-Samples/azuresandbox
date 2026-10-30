#region resources
resource "azurerm_mssql_server" "this" {
  name                          = module.naming_unique.names["sql_server"].name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  azuread_administrator {
    azuread_authentication_only = true
    login_username              = var.sql_admin_login_name
    object_id                   = var.sql_admin_object_id
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

# Enables server-level auditing (remediates Defender for Cloud finding VA2061) by routing
# audit events to Azure Monitor. The diagnostic setting on the server's 'master' database
# completes the audit pipeline to the shared Log Analytics workspace.
resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  server_id              = azurerm_mssql_server.this.id
  log_monitoring_enabled = true
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "Audit Logs"
  target_resource_id         = "${azurerm_mssql_server.this.id}/databases/master"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }
}
#endregion 

#region modules
module "naming" {
  source        = "Azure/avm-utl-naming/azure"
  version       = "~> 0.3.0"
  suffix        = [var.tags["project"], var.tags["environment"]]
  unique_length = 0
}

# unique_seed comes from a resource in the root module, so it's unknown at plan time and can't be passed as the
# naming module's unique_seed input. Adding it to the suffix keeps names consistent with the resource group.
module "naming_unique" {
  source        = "Azure/avm-utl-naming/azure"
  version       = "~> 0.3.0"
  suffix        = [var.tags["project"], var.tags["environment"], substr(var.unique_seed, 0, 8)]
  unique_length = 0
}
#endregion
