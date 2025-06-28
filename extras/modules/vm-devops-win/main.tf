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

#region resources

resource "null_resource" "this" { 
  provisioner "local-exec" { 
    command     = "$params = @{ ${join(" ", local.local_scripts["configure_automation"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["configure_automation"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
} # Configures the automation account for the DevOps VMs
#endregion

#region modules
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.2"
  suffix  = [var.tags["project"], var.tags["environment"]]
}
#endregion