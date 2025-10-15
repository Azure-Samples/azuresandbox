#region resources
resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name_unique
  location = var.location
  tags     = var.tags
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

  adds_domain_name              = module.vnet_shared.adds_domain_name
  admin_password                = module.vnet_shared.admin_password
  admin_password_secret         = module.vnet_shared.admin_password_secret
  admin_username                = module.vnet_shared.admin_username
  admin_username_secret         = module.vnet_shared.admin_username_secret
  arm_client_secret             = var.arm_client_secret
  automation_account_name       = module.vnet_shared.resource_names["automation_account"]
  dns_server                    = module.vnet_shared.dns_server
  firewall_route_table_id       = module.vnet_shared.resource_ids["firewall_route_table"]
  key_vault_id                  = module.vnet_shared.resource_ids["key_vault"]
  key_vault_name                = module.vnet_shared.resource_names["key_vault"]
  location                      = azurerm_resource_group.this.location
  log_analytics_workspace_id    = module.vnet_shared.resource_ids["log_analytics_workspace"]
  private_dns_zones_vnet_shared = module.vnet_shared.private_dns_zones
  resource_group_name           = azurerm_resource_group.this.name
  tags                          = var.tags
  unique_seed                   = module.naming.unique-seed
  user_object_id                = var.user_object_id
  virtual_network_shared_id     = module.vnet_shared.resource_ids["virtual_network_shared"]
  virtual_network_shared_name   = module.vnet_shared.resource_names["virtual_network_shared"]

  depends_on = [module.vnet_shared.resource_ids] # Ensure the domain controller VM is provisioned
}

module "vm_jumpbox_linux" {
  source = "./modules/vm-jumpbox-linux"

  count = var.enable_module_vm_jumpbox_linux ? 1 : 0

  adds_domain_name     = module.vnet_shared.adds_domain_name
  admin_username       = module.vnet_shared.admin_username
  dns_server           = module.vnet_shared.dns_server
  key_vault_id         = module.vnet_shared.resource_ids["key_vault"]
  key_vault_name       = module.vnet_shared.resource_names["key_vault"]
  location             = azurerm_resource_group.this.location
  resource_group_name  = azurerm_resource_group.this.name
  storage_account_name = module.vnet_app[0].resource_names["storage_account"]
  storage_share_name   = module.vnet_app[0].resource_names["storage_share"]
  subnet_id            = module.vnet_app[0].subnets["snet-app-01"].id
  tags                 = var.tags

  depends_on = [module.vnet_app[0].azure_files_config_vm_extension_id] # Ensure that Azure Files is configured
}

module "vm_mssql_win" {
  source = "./modules/vm-mssql-win"

  count = var.enable_module_vm_mssql_win ? 1 : 0

  adds_domain_name        = module.vnet_shared.adds_domain_name
  admin_password          = module.vnet_shared.admin_password
  admin_password_secret   = module.vnet_shared.admin_password_secret
  admin_username          = module.vnet_shared.admin_username
  admin_username_secret   = module.vnet_shared.admin_username_secret
  arm_client_secret       = var.arm_client_secret
  automation_account_name = module.vnet_shared.resource_names["automation_account"]
  key_vault_id            = module.vnet_shared.resource_ids["key_vault"]
  key_vault_name          = module.vnet_shared.resource_names["key_vault"]
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

  admin_password      = module.vnet_shared.admin_password
  admin_username      = module.vnet_shared.admin_username
  location            = azurerm_resource_group.this.location
  private_dns_zone_id = module.vnet_app[0].private_dns_zones["privatelink.database.windows.net"].id
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.vnet_app[0].subnets["snet-privatelink-01"].id
  tags                = var.tags
  unique_seed         = module.naming.unique-seed

  depends_on = [module.vnet_app[0].resource_ids] # Ensure vnet-app module resources are provisioned
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

  depends_on = [module.vnet_app[0].resource_ids] # Ensure vnet-app module resources are provisioned
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

  depends_on = [module.vnet_app[0].resource_ids] # Ensure vnet-app module resources are provisioned
}
#endregion

#region extra-modules
module "vnet_onprem" {
  source = "./extras/modules/vnet-onprem"

  count = var.enable_module_vnet_onprem ? 1 : 0

  adds_domain_name_cloud  = module.vnet_shared.adds_domain_name
  admin_password          = module.vnet_shared.admin_password
  admin_username          = module.vnet_shared.admin_username
  arm_client_secret       = var.arm_client_secret
  automation_account_name = module.vnet_shared.resource_names["automation_account"]
  dns_server_cloud        = module.vnet_shared.dns_server
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  subnets_cloud           = module.vnet_shared.subnets
  tags                    = var.tags

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

module "ai_foundry" {
  source = "./extras/modules/ai-foundry"

  count = var.enable_module_ai_foundry ? 1 : 0

  key_vault_id          = module.vnet_shared.resource_ids["key_vault"]
  location              = azurerm_resource_group.this.location
  private_dns_zones     = module.vnet_app[0].private_dns_zones
  resource_group_name   = azurerm_resource_group.this.name
  storage_account_id    = module.vnet_app[0].resource_ids["storage_account"]
  storage_file_endpoint = module.vnet_app[0].storage_endpoints["file"]
  storage_share_name    = module.vnet_app[0].resource_names["storage_share"]
  subnets               = module.vnet_app[0].subnets
  tags                  = var.tags
  unique_seed           = module.naming.unique-seed
  user_object_id        = var.user_object_id

  depends_on = [module.vnet_app[0].azure_files_config_vm_extension_id] # Ensure that Azure Files is configured
}

module "vm_devops_win" {
  source = "./extras/modules/vm-devops-win"

  count = var.enable_module_vm_devops_win ? 1 : 0

  admin_password          = module.vnet_shared.admin_password
  admin_username          = module.vnet_shared.admin_username
  arm_client_secret       = var.arm_client_secret
  automation_account_name = module.vnet_shared.resource_names["automation_account"]
  key_vault_id            = module.vnet_shared.resource_ids["key_vault"]
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  storage_account_id      = module.vnet_app[0].resource_ids["storage_account"]
  storage_account_name    = module.vnet_app[0].resource_names["storage_account"]
  storage_blob_endpoint   = module.vnet_app[0].storage_endpoints["blob"]
  storage_container_name  = module.vnet_app[0].storage_container_name
  vm_devops_win_instances = 1
  subnet_id               = module.vnet_app[0].subnets["snet-app-01"].id
  tags                    = var.tags

  depends_on = [module.vnet_app[0].azure_files_config_vm_extension_id] # Ensure that Azure Files is configured
}

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
#endregion
