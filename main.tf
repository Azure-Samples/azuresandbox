#region data
data "azuread_service_principal" "this" {
  count     = var.enable_module_mssql ? 1 : 0
  client_id = var.arm_client_id
}

#endregion

#region resources
resource "azuread_group" "sql_admins" {
  count            = var.enable_module_mssql ? 1 : 0
  display_name     = "grp-sql-admins-${var.tags["project"]}-${var.tags["environment"]}-${element(split("-", azurerm_resource_group.this.name), length(split("-", azurerm_resource_group.this.name)) - 1)}"
  security_enabled = true
  members          = [var.user_object_id, data.azuread_service_principal.this[0].object_id]
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name_unique
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_machine_run_command" "create_mssql_db_user" {
  count              = var.enable_module_mssql ? 1 : 0
  name               = "${module.naming.virtual_machine_extension.name}-${module.vnet_app[0].resource_names.virtual_machine_jumpwin1}-CreateMssqlDbUser"
  location           = azurerm_resource_group.this.location
  virtual_machine_id = module.vnet_app[0].resource_ids.virtual_machine_jumpwin1

  source {
    script = file("${path.module}/scripts/Create-AzSqlDbUser.ps1")
  }

  parameter {
    name  = "ArmClientId"
    value = var.arm_client_id
  }

  parameter {
    name  = "AadTenantId"
    value = var.aad_tenant_id
  }

  parameter {
    name  = "MssqlServerFqdn"
    value = module.mssql[0].fqdns.mssql_server
  }

  parameter {
    name  = "MssqlDatabaseName"
    value = module.mssql[0].resource_names.mssql_db
  }

  parameter {
    name  = "VmName"
    value = module.vnet_app[0].resource_names.virtual_machine_jumpwin1
  }

  protected_parameter {
    name  = "ArmClientSecret"
    value = var.arm_client_secret
  }

  depends_on = [
    module.mssql,
    module.vnet_app,
  ]
}
#endregion

#region public-access-management

# Centralized disable of public access on shared resources using implicit dependency barriers.
# Each barrier collects completion signals from all modules that perform data plane operations
# requiring public access. The disable resource references the barrier's output, creating an
# implicit dependency chain — no explicit depends_on needed.

resource "terraform_data" "key_vault_access_barrier" {
  input = {
    key_vault_id     = module.vnet_shared.resource_ids["key_vault"]
    vnet_shared      = module.vnet_shared.key_vault_operations_complete
    vm_jumpbox_linux = var.enable_module_vm_jumpbox_linux ? module.vm_jumpbox_linux[0].key_vault_operations_complete : null
    vwan             = var.enable_module_vwan ? module.vwan[0].key_vault_operations_complete : null
  }
}

resource "azapi_update_resource" "key_vault_disable_public_access" {
  type        = "Microsoft.KeyVault/vaults@2024-11-01"
  resource_id = terraform_data.key_vault_access_barrier.output.key_vault_id

  body = { properties = { publicNetworkAccess = "Disabled" } }
}

resource "terraform_data" "storage_access_barrier" {
  count = var.enable_module_vnet_app ? 1 : 0

  input = {
    storage_account_id = module.vnet_app[0].resource_ids["storage_account"]
    vnet_app           = module.vnet_app[0].storage_operations_complete
    vm_mssql_win       = var.enable_module_vm_mssql_win ? module.vm_mssql_win[0].storage_operations_complete : null
    # ai_foundry         = var.enable_module_ai_foundry ? module.ai_foundry[0].storage_operations_complete : null
    # vm_devops_win      = var.enable_module_vm_devops_win ? module.vm_devops_win[0].storage_operations_complete : null
  }
}

resource "azapi_update_resource" "storage_disable_public_access" {
  count = var.enable_module_vnet_app ? 1 : 0

  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = terraform_data.storage_access_barrier[0].output.storage_account_id

  body = { properties = { publicNetworkAccess = "Disabled" } }
}

# Barrier for AMPLS + Log Analytics public-access disable. Collects completion signals from
# every module that installs Azure Monitor Agent or wires diagnostic settings into the
# shared workspace. Downstream `azapi_update_resource` blocks reference this barrier's
# output, creating an implicit dependency chain — no explicit depends_on needed.
# Do not flip AMPLS/LA to PrivateOnly until every enabled module has confirmed its
# telemetry pipeline is wired up, otherwise agents cannot complete initial onboarding.
#
# NOTE: This is root batch #1 of the incremental rollout (see AMPLS_IMPLEMENTATION_PLAN.md
# Section 9, step 1f). Only `vnet_shared` is wired in at this stage. Subsequent batches
# (1j, 1m, 1p) will append `vnet_app`, `vm_jumpbox_linux`, and `vm_mssql_win` signals as
# each module is onboarded with AMA + DCR/DCE associations.
resource "terraform_data" "ampls_access_barrier" {
  input = {
    ampls_id                   = module.vnet_shared.resource_ids["monitor_private_link_scope"]
    log_analytics_workspace_id = module.vnet_shared.resource_ids["log_analytics_workspace"]

    # Signal from vnet-shared: AMPLS scoped services + AMA/DCR/DCE on adds1 + Key Vault diag setting.
    vnet_shared = module.vnet_shared.log_analytics_operations_complete

    # Signal from vnet-app (conditional): AMPLS DNS zone links on vnet-app + AMA/DCR/DCE on jumpwin1 + ACR diag setting.
    vnet_app = var.enable_module_vnet_app ? module.vnet_app[0].log_analytics_operations_complete : null

    # Signal from vm-mssql-win (conditional): AMA/DCR/DCE on mssqlwin1.
    vm_mssql_win = var.enable_module_vm_mssql_win ? module.vm_mssql_win[0].log_analytics_operations_complete : null

    # Signal from vm-jumpbox-linux (conditional): AMA/DCR/DCE on jumplinux1.
    vm_jumpbox_linux = var.enable_module_vm_jumpbox_linux ? module.vm_jumpbox_linux[0].log_analytics_operations_complete : null
  }
}

# Flip AMPLS access mode to PrivateOnly. All AMA agents must use the private endpoint for
# ingestion and queries from this point on.
resource "azapi_update_resource" "ampls_disable_public_access" {
  type        = "microsoft.insights/privateLinkScopes@2021-07-01-preview"
  resource_id = terraform_data.ampls_access_barrier.output.ampls_id

  body = {
    properties = {
      accessModeSettings = {
        ingestionAccessMode = "PrivateOnly"
        queryAccessMode     = "PrivateOnly"
      }
    }
  }
}

# Disable public network access on the Log Analytics workspace itself. AMPLS PrivateOnly
# alone does not prevent ingestion from outside the scope; this closes that path too.
resource "azapi_update_resource" "log_analytics_disable_public_ingestion" {
  type        = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  resource_id = terraform_data.ampls_access_barrier.output.log_analytics_workspace_id

  body = {
    properties = {
      publicNetworkAccessForIngestion = "Disabled"
      publicNetworkAccessForQuery     = "Disabled"
    }
  }
}
#endregion

#region required-modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.3"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-include-numbers = true
  unique-length          = 8
}

module "vnet_shared" {
  source = "./modules/vnet-shared"

  arm_client_secret   = var.arm_client_secret
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
  unique_seed         = module.naming.unique-seed
  user_object_id      = var.user_object_id
}
#endregion

#region optional-modules
module "vnet_app" {
  source = "./modules/vnet-app"

  count = var.enable_module_vnet_app ? 1 : 0

  adds_domain_name                = module.vnet_shared.adds_domain_name
  admin_password                  = module.vnet_shared.admin_password
  admin_password_secret           = module.vnet_shared.admin_password_secret
  admin_username                  = module.vnet_shared.admin_username
  admin_username_secret           = module.vnet_shared.admin_username_secret
  data_collection_endpoint_id     = module.vnet_shared.resource_ids["data_collection_endpoint"]
  data_collection_rule_windows_id = module.vnet_shared.resource_ids["data_collection_rule_windows"]
  dns_server                      = module.vnet_shared.dns_server
  firewall_route_table_id         = module.vnet_shared.resource_ids["firewall_route_table"]
  key_vault_id                    = module.vnet_shared.resource_ids["key_vault"]
  key_vault_name                  = module.vnet_shared.resource_names["key_vault"]
  location                        = azurerm_resource_group.this.location
  log_analytics_workspace_id      = module.vnet_shared.resource_ids["log_analytics_workspace"]
  private_dns_zones_vnet_shared   = module.vnet_shared.private_dns_zones
  resource_group_name             = azurerm_resource_group.this.name
  tags                            = var.tags
  unique_seed                     = module.naming.unique-seed
  user_object_id                  = var.user_object_id
  virtual_network_shared_id       = module.vnet_shared.resource_ids["virtual_network_shared"]
  virtual_network_shared_name     = module.vnet_shared.resource_names["virtual_network_shared"]

  depends_on = [module.vnet_shared.configure_adds_dns_id] # Ensures that the AD DS configuration is complete. Limits taint blast radius.
}

module "vm_jumpbox_linux" {
  source = "./modules/vm-jumpbox-linux"

  count = var.enable_module_vm_jumpbox_linux ? 1 : 0

  adds_domain_name              = module.vnet_shared.adds_domain_name
  admin_username                = module.vnet_shared.admin_username
  data_collection_endpoint_id   = module.vnet_shared.resource_ids["data_collection_endpoint"]
  data_collection_rule_linux_id = module.vnet_shared.resource_ids["data_collection_rule_linux"]
  dns_server                    = module.vnet_shared.dns_server
  key_vault_id                  = module.vnet_shared.resource_ids["key_vault"]
  key_vault_name                = module.vnet_shared.resource_names["key_vault"]
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  storage_account_name          = module.vnet_app[0].resource_names["storage_account"]
  storage_share_name            = module.vnet_app[0].resource_names["storage_share"]
  subnet_id                     = module.vnet_app[0].subnets["snet-app-01"].id
  tags                          = var.tags

  depends_on = [module.vnet_app[0].configure_azure_files_id] # Ensures that Azure Files is configured
}

module "vm_mssql_win" {
  source = "./modules/vm-mssql-win"

  count = var.enable_module_vm_mssql_win ? 1 : 0

  adds_domain_name                = module.vnet_shared.adds_domain_name
  admin_password                  = module.vnet_shared.admin_password
  admin_password_secret           = module.vnet_shared.admin_password_secret
  admin_username                  = module.vnet_shared.admin_username
  admin_username_secret           = module.vnet_shared.admin_username_secret
  data_collection_endpoint_id     = module.vnet_shared.resource_ids["data_collection_endpoint"]
  data_collection_rule_windows_id = module.vnet_shared.resource_ids["data_collection_rule_windows"]
  key_vault_id                    = module.vnet_shared.resource_ids["key_vault"]
  key_vault_name                  = module.vnet_shared.resource_names["key_vault"]
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  storage_account_id              = module.vnet_app[0].resource_ids["storage_account"]
  storage_account_name            = module.vnet_app[0].resource_names["storage_account"]
  storage_blob_endpoint           = module.vnet_app[0].storage_endpoints["blob"]
  storage_container_name          = module.vnet_app[0].storage_container_name
  subnet_id                       = module.vnet_app[0].subnets["snet-db-01"].id
  tags                            = var.tags

  depends_on = [module.vnet_app[0].configure_azure_files_id] # Ensures that Azure Files is configured
}

module "mssql" {
  source = "./modules/mssql"

  count = var.enable_module_mssql ? 1 : 0

  location             = azurerm_resource_group.this.location
  private_dns_zone_id  = module.vnet_app[0].private_dns_zones["privatelink.database.windows.net"].id
  resource_group_name  = azurerm_resource_group.this.name
  sql_admin_login_name = azuread_group.sql_admins[0].display_name
  sql_admin_object_id  = azuread_group.sql_admins[0].object_id
  subnet_id            = module.vnet_app[0].subnets["snet-privatelink-01"].id
  tags                 = var.tags
  unique_seed          = module.naming.unique-seed

  depends_on = [module.vnet_app[0].configure_azure_files_id] # Ensures that Azure Files is configured
}

module "mysql" {
  source = "./modules/mysql"

  count = var.enable_module_mysql ? 1 : 0

  admin_password      = module.vnet_shared.admin_password
  admin_username      = module.vnet_shared.admin_username
  location            = azurerm_resource_group.this.location
  private_dns_zone_id = module.vnet_app[0].private_dns_zones["privatelink.mysql.database.azure.com"].id
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.vnet_app[0].subnets["snet-privatelink-01"].id
  tags                = var.tags
  unique_seed         = module.naming.unique-seed

  depends_on = [module.vnet_app[0].configure_azure_files_id] # Ensures that Azure Files is configured
}

module "vwan" {
  source = "./modules/vwan"

  count = var.enable_module_vwan ? 1 : 0

  dns_server          = module.vnet_shared.dns_server
  key_vault_id        = module.vnet_shared.resource_ids["key_vault"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  virtual_networks = {
    virtual_network_shared = module.vnet_shared.resource_ids["virtual_network_shared"]
    virtual_network_app    = module.vnet_app[0].resource_ids["virtual_network_app"]
  }

  depends_on = [module.vnet_app[0].configure_azure_files_id] # Ensures that Azure Files is configured
}
#endregion

#region extra-modules
module "petstore" {
  source = "./extras/modules/petstore"

  count = var.enable_module_petstore ? 1 : 0

  arm_client_secret          = var.arm_client_secret
  container_apps_subnet_id   = module.vnet_app[0].subnets["snet-containerapps-01"].id
  container_registry_id      = module.vnet_app[0].resource_ids["container_registry"]
  location                   = azurerm_resource_group.this.location
  log_analytics_workspace_id = module.vnet_shared.resource_ids["log_analytics_workspace"]
  private_dns_zone_id        = module.vnet_app[0].private_dns_zones["privatelink.${var.location}.azurecontainerapps.io"].id
  private_endpoint_subnet_id = module.vnet_app[0].subnets["snet-privatelink-01"].id
  resource_group_name        = azurerm_resource_group.this.name
  tags                       = var.tags
  unique_seed                = module.naming.unique-seed

  depends_on = [module.vnet_app[0].azure_files_config_vm_extension_id] # Ensure that Azure Files is configured
}

module "avd" {
  source = "./extras/modules/avd"

  count = var.enable_module_avd ? 1 : 0

  admin_password                = module.vnet_shared.admin_password
  admin_username                = module.vnet_shared.admin_username
  key_vault_id                  = module.vnet_shared.resource_ids["key_vault"]
  location                      = azurerm_resource_group.this.location
  resource_group_id             = azurerm_resource_group.this.id
  resource_group_name           = azurerm_resource_group.this.name
  security_principal_object_ids = [var.user_object_id]
  subnet_id                     = module.vnet_app[0].subnets["snet-app-01"].id
  tags                          = var.tags
  unique_seed                   = module.naming.unique-seed

  depends_on = [module.vnet_app[0].azure_files_config_vm_extension_id] # Ensure that Azure Files is configured
}

module "vnet_onprem" {
  source = "./extras/modules/vnet-onprem"

  count = var.enable_module_vnet_onprem ? 1 : 0

  adds_domain_name_cloud = module.vnet_shared.adds_domain_name
  admin_password         = module.vnet_shared.admin_password
  admin_username         = module.vnet_shared.admin_username
  dns_server_cloud       = module.vnet_shared.dns_server
  location               = azurerm_resource_group.this.location
  resource_group_name    = azurerm_resource_group.this.name
  subnets_cloud          = module.vnet_shared.subnets
  tags                   = var.tags

  virtual_networks_cloud = {
    virtual_network_shared = {
      id   = module.vnet_shared.resource_ids["virtual_network_shared"]
      name = module.vnet_shared.resource_names["virtual_network_shared"]
    }
    virtual_network_app = {
      id   = module.vnet_app[0].resource_ids["virtual_network_app"]
      name = module.vnet_app[0].resource_names["virtual_network_app"]
    }
  }

  vwan_hub_id = module.vwan[0].resource_ids["virtual_wan_hub"]
  vwan_id     = module.vwan[0].resource_ids["virtual_wan"]

  depends_on = [module.vwan[0].resource_ids] # Ensure vwan module resources are provisioned
}

# ai-foundry is currently unavailable due to dependencies on retired features. It will be re-enabled in a future update with a redesigned implementation.

# module "ai_foundry" {
#   source = "./extras/modules/ai-foundry"

#   count = var.enable_module_ai_foundry ? 1 : 0

#   key_vault_id          = module.vnet_shared.resource_ids["key_vault"]
#   location              = azurerm_resource_group.this.location
#   private_dns_zones     = module.vnet_app[0].private_dns_zones
#   resource_group_name   = azurerm_resource_group.this.name
#   storage_account_id    = module.vnet_app[0].resource_ids["storage_account"]
#   storage_file_endpoint = module.vnet_app[0].storage_endpoints["file"]
#   storage_share_name    = module.vnet_app[0].resource_names["storage_share"]
#   subnets               = module.vnet_app[0].subnets
#   tags                  = var.tags
#   unique_seed           = module.naming.unique-seed
#   user_object_id        = var.user_object_id

#   depends_on = [module.vnet_app[0].azure_files_config_vm_extension_id] # Ensure that Azure Files is configured
# }


# vm-devops-win is currently unavailable due to dependencies on retired features. It will be re-enabled in a future update with a redesigned implementation.
# module "vm_devops_win" {
#   source = "./extras/modules/vm-devops-win"

#   count = var.enable_module_vm_devops_win ? 1 : 0

#   admin_password          = module.vnet_shared.admin_password
#   admin_username          = module.vnet_shared.admin_username
#   arm_client_secret       = var.arm_client_secret
#   automation_account_name = module.vnet_shared.resource_names["automation_account"]
#   key_vault_id            = module.vnet_shared.resource_ids["key_vault"]
#   location                = azurerm_resource_group.this.location
#   resource_group_name     = azurerm_resource_group.this.name
#   storage_account_id      = module.vnet_app[0].resource_ids["storage_account"]
#   storage_account_name    = module.vnet_app[0].resource_names["storage_account"]
#   storage_blob_endpoint   = module.vnet_app[0].storage_endpoints["blob"]
#   storage_container_name  = module.vnet_app[0].storage_container_name
#   vm_devops_win_instances = 1
#   subnet_id               = module.vnet_app[0].subnets["snet-app-01"].id
#   tags                    = var.tags

#   depends_on = [module.vnet_app[0].azure_files_config_vm_extension_id] # Ensure that Azure Files is configured
# }

#endregion
