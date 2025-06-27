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

resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.roles]
}
#endregion

#region modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.2"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-include-numbers = true
  unique-length          = 8
}

module "vm_jumpbox_linux" {
  source = "./modules/vm-jumpbox-linux"

  enable_public_access = true
  key_vault_id         = azurerm_key_vault.this.id
  location             = azurerm_resource_group.this.location
  resource_group_name  = azurerm_resource_group.this.name
  storage_account_id   = azurerm_storage_account.this.id
  subnet_id            = azurerm_subnet.this.id
  tags                 = var.tags

  depends_on = [time_sleep.wait_for_roles]
}
#endregion
