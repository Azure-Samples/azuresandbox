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

#region utilities
module "naming" {
  source      = "Azure/naming/azurerm"
  version     = "0.4.2"
  suffix      = [var.tags["project"], var.tags["environment"]]
}
#endregion

#region key-vault-secrets
resource "random_string" "first_letter" {
  length  = 1
  upper   = true
  lower   = true
  numeric = false
  special = false
}

resource "random_string" "last_letter" {
  length  = 1
  upper   = true
  lower   = true
  numeric = false
  special = false
}

resource "random_password" "adminpassword" {
  length           = 14 # Reduced by 2 to account for the first and last letters
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

resource "azurerm_key_vault_secret" "adminpassword" {
  name            = var.admin_password_secret
  value           = "${random_string.first_letter.result}${random_password.adminpassword.result}${random_string.last_letter.result}" # Combine first letter, password, and last letter
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
#endregion

#region automation-account
resource "azurerm_automation_account" "this" {
  name                = module.naming.automation_account.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"

  provisioner "local-exec" {
    command     = <<EOT
        $params = @{
          TenantId = "${data.azurerm_client_config.current.tenant_id}"
          SubscriptionId = "${data.azurerm_client_config.current.subscription_id}"
          ResourceGroupName = "${var.resource_group_name}"
          AutomationAccountName = "${azurerm_automation_account.this.name}"
          Domain = "${var.adds_domain_name}"
          VmAddsName = "${var.vm_adds_name}"
          AdminUserName = "${var.admin_username_secret}"
          AdminPwd = "${data.azurerm_key_vault_secret.adminpassword.value}"
          AppId = "${data.azurerm_client_config.current.client_id}"
          AppSecret = "${data.azurerm_key_vault_secret.arm_client_secret.value}"
        }
        ./${path.module}/scripts/configure-automation.ps1 @params 
   EOT
    interpreter = ["pwsh", "-Command"]
  }
}
#endregion
