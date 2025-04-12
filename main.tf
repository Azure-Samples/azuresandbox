#region data
data "azurerm_client_config" "current" {}
#endregion

#region utilities
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "0.4.2"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-include-numbers = true
  unique-length          = 8
}
#endregion

#region resource-group
resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name_unique
  location = var.location
  tags     = var.tags
}
#endregion

#region key-vault
resource "azurerm_key_vault" "this" {
  name                          = module.naming.key_vault.name_unique
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = var.aad_tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  public_network_access_enabled = true # Note:Required to demo sandbox using internet connection
}

resource "azurerm_role_assignment" "key_vault_roles" {
  for_each = local.key_vault_roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "spn_password" {
  name            = var.arm_client_id
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

resource "azurerm_monitor_diagnostic_setting" "kv_diagnostic_setting" {
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

#region log-analytics-workspace
resource "azurerm_log_analytics_workspace" "this" {
  name                = module.naming.log_analytics_workspace.name_unique
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_workspace_retention_days
}
#endregion

#region modules
module "vnet_shared" {
  source = "./modules/vnet-shared"

  key_vault_id        = azurerm_key_vault.this.id
  key_vault_name      = azurerm_key_vault.this.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  depends_on = [
    azurerm_key_vault_secret.spn_password,
    azurerm_key_vault_secret.log_primary_shared_key
  ]
}

module "vnet_app" {
  source = "./modules/vnet-app"

  count = var.create_vnet_app ? 1 : 0

  admin_password_secret       = module.vnet_shared.admin_password_secret
  admin_username_secret       = module.vnet_shared.admin_username_secret
  automation_account_name     = module.vnet_shared.resource_names["automation_account"]
  dns_server                  = module.vnet_shared.dns_server
  firewall_route_table_id     = module.vnet_shared.resource_ids["firewall_route_table"]
  key_vault_id                = azurerm_key_vault.this.id
  location                    = azurerm_resource_group.this.location
  resource_group_name         = azurerm_resource_group.this.name
  tags                        = var.tags
  unique_seed                 = module.naming.unique-seed
  user_object_id              = var.user_object_id
  virtual_network_shared_name = module.vnet_shared.resource_names["virtual_network_shared"]
  virtual_network_shared_id   = module.vnet_shared.resource_ids["virtual_network_shared"]

  depends_on = [ azurerm_key_vault_secret.spn_password ]
}
#endregion

#region utility-resources
resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.key_vault_roles]
}
#endregion
