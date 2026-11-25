#region data
data "azurerm_client_config" "current" {}
#endregion

#region locals
locals {
  server_identity_id = var.mysql_entra_identity_id != null ? var.mysql_entra_identity_id : azurerm_user_assigned_identity.this[0].id
}
#endregion

#region resources
resource "azurerm_user_assigned_identity" "this" {
  count               = var.mysql_entra_identity_id == null ? 1 : 0
  name                = "${module.naming.names["user_assigned_identity"].name}-mysql"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_mysql_flexible_server" "this" {
  name                   = module.naming_unique.names["db_for_my_sql_server"].name
  resource_group_name    = var.resource_group_name
  location               = var.location
  administrator_login    = var.admin_username
  administrator_password = var.admin_password
  sku_name               = var.mysql_sku_name
  public_network_access  = "Disabled"

  identity {
    type         = "UserAssigned"
    identity_ids = [local.server_identity_id]
  }
}

resource "azurerm_mysql_flexible_server_active_directory_administrator" "this" {
  server_id   = azurerm_mysql_flexible_server.this.id
  identity_id = local.server_identity_id
  login       = var.mysql_admin_login_name
  object_id   = var.mysql_admin_object_id
  tenant_id   = data.azurerm_client_config.current.tenant_id
}

# aad_auth_only is read-only until an Entra administrator is configured on the server.
resource "azurerm_mysql_flexible_server_configuration" "aad_auth_only" {
  name                = "aad_auth_only"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  value               = "ON"

  depends_on = [azurerm_mysql_flexible_server_active_directory_administrator.this]
}

resource "azurerm_mysql_flexible_database" "this" {
  name                = var.mysql_database_name
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  # utf8 is a deprecated alias that MySQL 8.0 normalizes to utf8mb3, which causes a
  # perpetual force-new diff. utf8mb4 is the canonical modern default and is reported
  # back unchanged by the API.
  charset   = "utf8mb4"
  collation = "utf8mb4_unicode_ci"
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
