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
  rbac_authorization_enabled    = true
  public_network_access_enabled = true # Note: The barrier pattern will disable this on apply.

  lifecycle {
    ignore_changes = [public_network_access_enabled]
  }
}

resource "azurerm_role_assignment" "keyvault_roles" {
  for_each = local.key_vault_roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = azurerm_key_vault.this.id
}

resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.keyvault_roles]
}
#endregion

#region public-access-management
resource "terraform_data" "key_vault_access_barrier" {
  input = {
    key_vault_id     = azurerm_key_vault.this.id
    vm_jumpbox_linux = module.vm_jumpbox_linux.key_vault_operations_complete
  }
}

resource "azapi_update_resource" "key_vault_disable_public_access" {
  type        = "Microsoft.KeyVault/vaults@2024-11-01"
  resource_id = terraform_data.key_vault_access_barrier.output.key_vault_id

  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }
}

resource "terraform_data" "storage_access_barrier" {
  input = {
    storage_account_id = azurerm_storage_account.this.id
    storage_container  = azurerm_storage_container.this.id
  }
}

resource "azapi_update_resource" "storage_disable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = terraform_data.storage_access_barrier.output.storage_account_id

  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }
}
#endregion

#region modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.3"
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
  subnet_id            = azurerm_subnet.devops.id
  tags                 = var.tags

  depends_on = [time_sleep.wait_for_roles]
}
#endregion
