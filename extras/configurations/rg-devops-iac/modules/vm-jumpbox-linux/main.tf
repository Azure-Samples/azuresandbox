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

  dynamic "part" {
    for_each = var.enable_github_runner ? [1] : []

    content {
      content_type = "text/cloud-config"
      content = templatefile(
        "./${path.module}/scripts/configure-github-runner.yaml", {
          aad_tenant_id                     = data.azurerm_client_config.current.tenant_id
          github_runner_enable_vwan_sudoers = var.github_runner_enable_vwan_sudoers
          github_runner_group               = var.github_runner_group
          github_runner_home                = local.github_runner_home
          github_runner_labels              = join(",", var.github_runner_labels)
          github_runner_name                = local.github_runner_name
          github_runner_service_account     = var.github_runner_service_account
          github_runner_token_secret        = var.github_runner_token_secret
          github_runner_token_type          = var.github_runner_token_type
          github_runner_url                 = var.github_runner_url
          github_runner_version             = var.github_runner_version
          key_vault_name                    = var.key_vault_name
        }
      )
      filename = "configure-github-runner.yaml"
    }
  }

  dynamic "part" {
    for_each = var.enable_github_runner ? [1] : []

    content {
      content_type = "text/x-shellscript"
      content      = file("./${path.module}/scripts/configure-github-runner.sh")
      filename     = "configure-github-runner.sh"
    }
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

#region github-runner
# The registration secret is stored as a write-only key vault secret so it never lands in Terraform
# state. The VM reads it at provisioning time using its managed identity.
resource "azurerm_key_vault_secret" "github_runner_token" {
  count = var.enable_github_runner ? 1 : 0

  name             = var.github_runner_token_secret
  value_wo         = var.github_runner_token
  value_wo_version = var.github_runner_token_secret_version
  key_vault_id     = var.key_vault_id
  expiration_date  = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expiration_date]

    precondition {
      condition     = var.github_runner_token != ""
      error_message = "var.github_runner_token must be set when var.enable_github_runner is true. Set it using the 'TF_VAR_github_runner_token' environment variable."
    }

    precondition {
      condition     = var.github_runner_url != ""
      error_message = "var.github_runner_url must be set when var.enable_github_runner is true."
    }
  }
}

resource "azurerm_role_assignment" "github_runner_key_vault" {
  count = var.enable_github_runner ? 1 : 0

  principal_id         = azurerm_linux_virtual_machine.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Key Vault Secrets User"
  scope                = var.key_vault_id
}
#endregion

#region locals
locals {
  github_runner_home = "/opt/actions-runner"
  github_runner_name = var.github_runner_name != "" ? var.github_runner_name : var.vm_jumpbox_linux_name
}
#endregion

#region modules
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.3"
  suffix  = [var.tags["project"], var.tags["environment"]]
}
#endregion
