#region data
data "azurerm_client_config" "current" {}

data "cloudinit_config" "vm_jumpbox_linux" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile(
      "./${path.module}/scripts/configure-vm-jumpbox-linux.yaml", {
        aad_tenant_id = data.azurerm_client_config.current.tenant_id
      }
    )
    filename = "configure-vm-jumpbox-linux.yaml"
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("./${path.module}/scripts/configure-powershell.ps1")
    filename     = "configure-powershell.ps1"
  }
}
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
  name            = "${var.vm_jumpbox_linux_name}-ssh-private-key"
  value           = tls_private_key.ssh_key.private_key_pem
  key_vault_id    = var.key_vault_id
  expiration_date = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expiration_date]
  }
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#endregion

#region modules
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.2"
  suffix  = [var.tags["project"], var.tags["environment"]]
}
#endregion
