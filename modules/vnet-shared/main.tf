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
  enable_rbac_authorization     = true
  public_network_access_enabled = true # Note: Public access is enabled for demos and testing from internet clients, and should be disabled in production.
}

resource "azurerm_role_assignment" "roles" {
  for_each = local.key_vault_roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "spn_password" {
  name            = data.azurerm_client_config.current.client_id
  value           = var.arm_client_secret
  key_vault_id    = azurerm_key_vault.this.id
  expiration_date = timeadd(timestamp(), "8760h")
  depends_on      = [time_sleep.wait_for_roles]

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_key_vault_secret" "log_primary_shared_key" {
  name            = azurerm_log_analytics_workspace.this.workspace_id
  value           = azurerm_log_analytics_workspace.this.primary_shared_key
  key_vault_id    = azurerm_key_vault.this.id
  expiration_date = timeadd(timestamp(), "8760h")
  depends_on      = [time_sleep.wait_for_roles]

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_key_vault_secret" "adminpassword" {
  name            = var.admin_password_secret
  value           = "${random_string.adminpassword_first_char.result}${random_password.adminpassword_middle_chars.result}${random_string.adminpassword_last_char.result}"
  key_vault_id    = azurerm_key_vault.this.id
  expiration_date = timeadd(timestamp(), "8760h")
  depends_on      = [time_sleep.wait_for_roles]

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

#region automation-account
resource "azurerm_automation_account" "this" {
  name                = module.naming.automation_account.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"

  provisioner "local-exec" {
    command     = "$params = @{ ${join(" ", local.local_scripts["provisioner_automation_account"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["provisioner_automation_account"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
}
#endregion

#region log-analytics
resource "azurerm_log_analytics_workspace" "this" {
  name                = module.naming.log_analytics_workspace.name_unique
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_workspace_retention_days
}
#endregion

#region utilities
resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.roles]
}

resource "random_string" "adminpassword_first_char" {
  length  = 1
  upper   = true
  lower   = true
  numeric = false
  special = false
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

resource "random_string" "adminpassword_last_char" {
  length  = 1
  upper   = true
  lower   = true
  numeric = false
  special = false
}
#endregion

#region modules
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.2"
  suffix  = [var.tags["project"], var.tags["environment"]]
}
#endregion
