#region data
data "azurerm_client_config" "current" {}

data "azurerm_key_vault_secret" "adminpassword" {
  name         = azurerm_key_vault_secret.adminpassword.name
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "arm_client_secret" {
  name         = data.azurerm_client_config.current.client_id
  key_vault_id = var.key_vault_id
}
#endregion

#region resources
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

resource "azurerm_key_vault_secret" "adminpassword" {
  name            = var.admin_password_secret
  value           = "${random_string.adminpassword_first_char.result}${random_password.adminpassword_middle_chars.result}${random_string.adminpassword_last_char.result}"
  key_vault_id    = var.key_vault_id
  expiration_date = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_key_vault_secret" "adminusername" {
  name            = var.admin_username_secret
  value           = var.admin_username
  key_vault_id    = var.key_vault_id
  expiration_date = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

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

#region modules
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.2"
  suffix  = [var.tags["project"], var.tags["environment"]]
}
#endregion
