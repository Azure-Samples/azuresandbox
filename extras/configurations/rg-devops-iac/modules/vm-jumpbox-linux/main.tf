#region data
data "azurerm_client_config" "current" {}
#endregion

#region resources
resource "azurerm_key_vault_secret" "adminuser" {
  name            = var.admin_username_secret
  value           = var.admin_username
  key_vault_id    = var.key_vault_id
  expiration_date = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "azurerm_key_vault_secret" "ssh_private_key" {
  name             = "${var.vm_jumpbox_linux_name}-ssh-private-key"
  value_wo         = tls_private_key.ssh_key.private_key_pem
  value_wo_version = var.ssh_private_key_version
  key_vault_id     = var.key_vault_id
  expiration_date  = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
#endregion

#region utilities

# Signal for the root ampls_access_barrier (public-access barrier pattern).
# These Azure Monitor writes need the AMPLS and workspace to still accept public traffic.
# The root closes public access only after this resource, via the log_analytics_operations_complete output.
resource "terraform_data" "log_analytics_operations_complete" {
  input = {
    ama             = azurerm_virtual_machine_extension.ama.id
    dcr_association = azurerm_monitor_data_collection_rule_association.dcr.id
    dce_association = azurerm_monitor_data_collection_rule_association.dce.id
  }
}
#endregion

#region modules
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.3"
  suffix  = [var.tags["project"], var.tags["environment"]]
}
#endregion
