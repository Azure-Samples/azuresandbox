#region data
data "azurerm_client_config" "current" {}

data "azurerm_key_vault_secret" "adminpassword" {
  name         = var.admin_password_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "adminuser" {
  name         = var.admin_username_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "arm_client_secret" {
  name         = data.azurerm_client_config.current.client_id
  key_vault_id = var.key_vault_id
}
#endregion

#region modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.2"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-seed            = var.unique_seed
  unique-include-numbers = true
  unique-length          = 8
}
#endregion
