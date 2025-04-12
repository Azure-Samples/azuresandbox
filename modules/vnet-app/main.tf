#region utilities
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "0.4.2"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-seed            = var.unique_seed
  unique-include-numbers = true
  unique-length          = 8
}
#endregion

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

# data "azurerm_key_vault_secret" "storage_account_kerb_key" {
#   name         = "${var.storage_account_name}-kerb1"
#   key_vault_id = var.key_vault_id
# }

# data "cloudinit_config" "vm_jumpbox_linux" {
#   gzip          = true
#   base64_encode = true

#   part {
#     content_type = "text/cloud-config"
#     content = templatefile(
#       "${path.root}/scripts/configure-vm-jumpbox-linux.yaml", {
#         adds_domain_name     = var.adds_domain_name,
#         dns_server           = var.dns_server,
#         key_vault_name       = var.key_vault_name,
#         storage_account_name = var.storage_account_name,
#         storage_share_name   = var.storage_share_name
#       }
#     )
#     filename = "configure-vm-jumpbox-linux.yaml"
#   }

#   part {
#     content_type = "text/x-shellscript"
#     content      = file("${path.root}/scripts/configure-vm-jumpbox-linux.sh")
#     filename     = "configure-vm-jumpbox-linux.sh"
#   }
# }
#endregion
