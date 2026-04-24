#region data
data "azurerm_client_config" "current" {}
#endregion

#region key-vault
resource "azurerm_key_vault" "this" {
  name                          = module.naming.key_vault.name_unique
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = true

  lifecycle {
    ignore_changes = [public_network_access_enabled] # Centralized disable in root main.tf will set this to false after all modules complete
  }
}

resource "azurerm_role_assignment" "roles" {
  for_each = local.key_vault_roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "spn_password" {
  name             = data.azurerm_client_config.current.client_id
  value_wo         = var.arm_client_secret
  value_wo_version = var.arm_client_secret_version
  key_vault_id     = azurerm_key_vault.this.id
  expiration_date  = timeadd(timestamp(), "8760h")
  depends_on       = [time_sleep.wait_for_roles]

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_key_vault_secret" "adminpassword" {
  name             = var.admin_password_secret
  value_wo         = local.admin_password
  value_wo_version = var.admin_password_secret_version
  key_vault_id     = azurerm_key_vault.this.id
  expiration_date  = timeadd(timestamp(), "8760h")
  depends_on       = [time_sleep.wait_for_roles]

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_key_vault_secret" "adminusername" {
  name            = var.admin_username_secret
  value           = var.admin_username
  key_vault_id    = azurerm_key_vault.this.id
  expiration_date = timeadd(timestamp(), "8760h")
  depends_on      = [time_sleep.wait_for_roles]

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "Audit Logs"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "audit"
  }

  lifecycle {
    ignore_changes = [metric]
  }
}
#endregion

#region azure-monitor
resource "azurerm_log_analytics_workspace" "this" {
  name                       = module.naming.log_analytics_workspace.name_unique
  location                   = var.location
  resource_group_name        = var.resource_group_name
  sku                        = "PerGB2018"
  retention_in_days          = var.log_analytics_workspace_retention_days
  internet_ingestion_enabled = true # Starts enabled; root main.tf barrier disables after all modules complete
  internet_query_enabled     = true # Starts enabled; root main.tf barrier disables after all modules complete

  lifecycle {
    ignore_changes = [internet_ingestion_enabled, internet_query_enabled]
  }
}

resource "azurerm_monitor_private_link_scope" "this" {
  name                  = "ampls-${var.tags["project"]}-${var.tags["environment"]}"
  resource_group_name   = var.resource_group_name
  ingestion_access_mode = "Open" # Starts open; root main.tf barrier disables after all modules complete
  query_access_mode     = "Open" # Starts open; root main.tf barrier disables after all modules complete

  lifecycle {
    ignore_changes = [ingestion_access_mode, query_access_mode]
  }
}

resource "azurerm_monitor_private_link_scoped_service" "log_analytics" {
  name                = "ampls-scope-log-analytics"
  resource_group_name = var.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = azurerm_log_analytics_workspace.this.id
}

resource "azurerm_monitor_private_link_scoped_service" "dce" {
  name                = "ampls-scope-dce"
  resource_group_name = var.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = azurerm_monitor_data_collection_endpoint.this.id
}

resource "azurerm_monitor_data_collection_endpoint" "this" {
  name                = module.naming.monitor_data_collection_endpoint.name_unique
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Windows" # Kind is informational on DCE; DCRs carry the actual platform binding.
}

resource "azurerm_monitor_data_collection_rule" "windows" {
  name                        = "${module.naming.monitor_data_collection_rule.name}-windows"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this.id
  kind                        = "Windows"

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
      name                  = "law-destination"
    }
  }

  data_flow {
    streams      = ["Microsoft-Event", "Microsoft-Perf"]
    destinations = ["law-destination"]
  }

  data_sources {
    performance_counter {
      name                          = "perfCounters"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(_Total)\\% Processor Time",
        "\\Memory\\Available Bytes",
        "\\LogicalDisk(_Total)\\% Free Space",
        "\\Network Interface(*)\\Bytes Total/sec"
      ]
    }

    windows_event_log {
      name    = "eventLogs"
      streams = ["Microsoft-Event"]
      x_path_queries = [
        "System!*[System[(Level=1 or Level=2 or Level=3)]]",
        "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
        "Security!*[System[(EventID=4624 or EventID=4625 or EventID=4672)]]"
      ]
    }
  }
}

resource "azurerm_monitor_data_collection_rule" "linux" {
  name                        = "${module.naming.monitor_data_collection_rule.name}-linux"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this.id
  kind                        = "Linux"

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
      name                  = "law-destination"
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog", "Microsoft-Perf"]
    destinations = ["law-destination"]
  }

  data_sources {
    performance_counter {
      name                          = "perfCounters"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "Processor(*)\\% Processor Time",
        "Memory(*)\\% Used Memory",
        "Logical Disk(*)\\% Used Space",
        "Network(*)\\Total Bytes"
      ]
    }

    syslog {
      name           = "syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "cron", "daemon", "kern", "syslog", "user"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }
}
#endregion

#region utilities
resource "terraform_data" "key_vault_operations_complete" {
  input = {
    secret_adminpassword = azurerm_key_vault_secret.adminpassword.id
    secret_adminusername = azurerm_key_vault_secret.adminusername.id
    secret_spn_password  = azurerm_key_vault_secret.spn_password.id
  }
}

resource "terraform_data" "log_analytics_operations_complete" {
  input = {
    ampls_scope_log_analytics = azurerm_monitor_private_link_scoped_service.log_analytics.id
    ampls_scope_dce           = azurerm_monitor_private_link_scoped_service.dce.id
    ampls_private_endpoint    = azurerm_private_endpoint.ampls.id
    ampls_dns_zone_links      = join(",", [for l in azurerm_private_dns_zone_virtual_network_link.ampls : l.id])
    key_vault_diagnostics     = azurerm_monitor_diagnostic_setting.this.id
    adds1_dcr_association     = azurerm_monitor_data_collection_rule_association.adds1_dcr.id
    adds1_dce_association     = azurerm_monitor_data_collection_rule_association.adds1_dce.id
  }
}

resource "random_password" "adminpassword_middle_chars" {
  length           = 14
  special          = true
  min_special      = 1
  upper            = true
  min_upper        = 1
  lower            = true
  min_lower        = 1
  numeric          = true
  min_numeric      = 1
  override_special = ".+-="
}

resource "random_string" "adminpassword_first_char" {
  length  = 1
  upper   = true
  lower   = true
  numeric = false
  special = false
}

resource "random_string" "adminpassword_last_char" {
  length  = 1
  upper   = true
  lower   = true
  numeric = false
  special = false
}

resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.roles]
}
#endregion

#region modules
module "naming" {
  source      = "Azure/naming/azurerm"
  version     = "~> 0.4.3"
  suffix      = [var.tags["project"], var.tags["environment"]]
  unique-seed = var.unique_seed
}
#endregion
