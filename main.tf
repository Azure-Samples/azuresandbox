#region data
data "azurerm_client_config" "current" {}
#endregion

#region resources
resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name_unique
  location = var.location
  tags     = var.tags
}

resource "azurerm_key_vault" "this" {
  name                          = module.naming.key_vault.name_unique
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = var.aad_tenant_id
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

resource "azurerm_log_analytics_workspace" "this" {
  name                = module.naming.log_analytics_workspace.name_unique
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_workspace_retention_days
}

resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.roles]
}
#endregion

#region required-modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.2"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-include-numbers = true
  unique-length          = 8
}

module "vnet_shared" {
  source = "./modules/vnet-shared"

  key_vault_id        = azurerm_key_vault.this.id
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  depends_on = [azurerm_key_vault_secret.spn_password] # Ensure the SPN password key vault secret is provisioned
}
#endregion

#region optional-modules
module "vnet_app" {
  source = "./modules/vnet-app"

  count = var.enable_module_vnet_app ? 1 : 0

  adds_domain_name            = module.vnet_shared.adds_domain_name
  admin_password_secret       = module.vnet_shared.admin_password_secret
  admin_username_secret       = module.vnet_shared.admin_username_secret
  automation_account_name     = module.vnet_shared.resource_names["automation_account"]
  dns_server                  = module.vnet_shared.dns_server
  firewall_route_table_id     = module.vnet_shared.resource_ids["firewall_route_table"]
  key_vault_id                = azurerm_key_vault.this.id
  key_vault_name              = azurerm_key_vault.this.name
  location                    = azurerm_resource_group.this.location
  resource_group_name         = azurerm_resource_group.this.name
  tags                        = var.tags
  unique_seed                 = module.naming.unique-seed
  user_object_id              = var.user_object_id
  virtual_network_shared_id   = module.vnet_shared.resource_ids["virtual_network_shared"]
  virtual_network_shared_name = module.vnet_shared.resource_names["virtual_network_shared"]

  depends_on = [module.vnet_shared.resource_ids] # Ensure the domain controller VM is provisioned
}

module "vm_jumpbox_linux" {
  source = "./modules/vm-jumpbox-linux"

  count = var.enable_module_vm_jumpbox_linux ? 1 : 0

  adds_domain_name      = module.vnet_shared.adds_domain_name
  admin_username_secret = module.vnet_shared.admin_username_secret
  dns_server            = module.vnet_shared.dns_server
  key_vault_id          = azurerm_key_vault.this.id
  key_vault_name        = azurerm_key_vault.this.name
  location              = azurerm_resource_group.this.location
  resource_group_name   = azurerm_resource_group.this.name
  storage_account_name  = module.vnet_app[0].resource_names["storage_account"]
  storage_share_name    = module.vnet_app[0].storage_share_name
  subnet_id             = module.vnet_app[0].subnets["snet-app-01"].id
  tags                  = var.tags

  depends_on = [module.vnet_app[0].azure_files_config_vm_extension_id] # Ensure that Azure Files is configured
}

module "vm_mssql_win" {
  source = "./modules/vm-mssql-win"

  count = var.enable_module_vm_mssql_win ? 1 : 0

  adds_domain_name        = module.vnet_shared.adds_domain_name
  admin_password_secret   = module.vnet_shared.admin_password_secret
  admin_username_secret   = module.vnet_shared.admin_username_secret
  automation_account_name = module.vnet_shared.resource_names["automation_account"]
  key_vault_id            = azurerm_key_vault.this.id
  key_vault_name          = azurerm_key_vault.this.name
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  storage_account_id      = module.vnet_app[0].resource_ids["storage_account"]
  storage_account_name    = module.vnet_app[0].resource_names["storage_account"]
  storage_blob_endpoint   = module.vnet_app[0].storage_endpoints["blob"]
  storage_container_name  = module.vnet_app[0].storage_container_name
  subnet_id               = module.vnet_app[0].subnets["snet-db-01"].id
  tags                    = var.tags

  depends_on = [module.vnet_app[0].resource_ids] # Ensure vnet-app module resources are provisioned
}

module "mssql" {
  source = "./modules/mssql"

  count = var.enable_module_mssql ? 1 : 0

  admin_password_secret = module.vnet_shared.admin_password_secret
  admin_username_secret = module.vnet_shared.admin_username_secret
  key_vault_id          = azurerm_key_vault.this.id
  location              = azurerm_resource_group.this.location
  resource_group_name   = azurerm_resource_group.this.name
  subnet_id             = module.vnet_app[0].subnets["snet-privatelink-01"].id
  tags                  = var.tags
  unique_seed           = module.naming.unique-seed

  depends_on = [module.vnet_app[0].resource_ids] # Ensure vnet-app module resources are provisioned
}

module "mysql" {
  source = "./modules/mysql"

  count = var.enable_module_mysql ? 1 : 0

  admin_password_secret = module.vnet_shared.admin_password_secret
  admin_username_secret = module.vnet_shared.admin_username_secret
  key_vault_id          = azurerm_key_vault.this.id
  location              = azurerm_resource_group.this.location
  resource_group_name   = azurerm_resource_group.this.name
  subnet_id             = module.vnet_app[0].subnets["snet-privatelink-01"].id
  tags                  = var.tags
  unique_seed           = module.naming.unique-seed

  depends_on = [module.vnet_app[0].resource_ids] # Ensure vnet-app module resources are provisioned
}

module "vwan" {
  source = "./modules/vwan"

  count = var.enable_module_vwan ? 1 : 0

  dns_server          = module.vnet_shared.dns_server
  key_vault_id        = azurerm_key_vault.this.id
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  virtual_networks = {
    virtual_network_shared = module.vnet_shared.resource_ids["virtual_network_shared"]
    virtual_network_app    = module.vnet_app[0].resource_ids["virtual_network_app"]
  }

  depends_on = [module.vnet_app[0].resource_ids] # Ensure vnet-app module resources are provisioned
}
#endregion
