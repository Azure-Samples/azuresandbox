#region resources
resource "azurerm_mysql_flexible_server" "this" {
  name                   = module.naming.mysql_server.name_unique
  resource_group_name    = var.resource_group_name
  location               = var.location
  administrator_login    = var.admin_username
  administrator_password = var.admin_password
  sku_name               = var.mysql_sku_name
  public_network_access  = "Disabled"
}

resource "azurerm_mysql_flexible_database" "this" {
  name                = var.mysql_database_name
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}

# Server parameters that must be enabled for the diagnostic categories below to produce data.
resource "azurerm_mysql_flexible_server_configuration" "slow_query_log" {
  name                = "slow_query_log"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  value               = "ON"
}

resource "azurerm_mysql_flexible_server_configuration" "audit_log_enabled" {
  name                = "audit_log_enabled"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  value               = "ON"
}

resource "azurerm_mysql_flexible_server_configuration" "audit_log_events" {
  name                = "audit_log_events"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  value               = "CONNECTION,DML,DDL,DCL"
}

# Routes MySQL slow/audit logs and metrics to the shared Log Analytics workspace owned by
# the vnet-shared module. Depends on the server parameters above so the categories emit data.
resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_mysql_flexible_server.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "MySqlSlowLogs"
  }

  enabled_log {
    category = "MySqlAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }

  depends_on = [
    azurerm_mysql_flexible_server_configuration.slow_query_log,
    azurerm_mysql_flexible_server_configuration.audit_log_enabled,
    azurerm_mysql_flexible_server_configuration.audit_log_events
  ]
}
#endregion

#region modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.3"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-seed            = var.unique_seed
  unique-include-numbers = true
  unique-length          = 8
}
#endregion
