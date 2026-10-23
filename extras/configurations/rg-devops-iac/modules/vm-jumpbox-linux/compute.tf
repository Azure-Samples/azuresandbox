#region data
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
resource "azurerm_linux_virtual_machine" "this" {
  name                       = var.vm_jumpbox_linux_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_jumpbox_linux_size
  admin_username             = var.admin_username
  encryption_at_host_enabled = true
  network_interface_ids      = [azurerm_network_interface.this.id]
  patch_assessment_mode      = "AutomaticByPlatform"
  provision_vm_agent         = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_jumpbox_linux_storage_account_type
  }

  source_image_reference {
    publisher = var.vm_jumpbox_linux_image_publisher
    offer     = var.vm_jumpbox_linux_image_offer
    sku       = var.vm_jumpbox_linux_image_sku
    version   = var.vm_jumpbox_linux_image_version
  }

  identity {
    type         = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  custom_data = data.cloudinit_config.vm_jumpbox_linux.rendered
}

resource "azurerm_virtual_machine_run_command" "wait_for_cloud_init" {
  name               = "${module.naming.virtual_machine_extension.name}-${var.vm_jumpbox_linux_name}-WaitForCloudInit"
  location           = var.location
  virtual_machine_id = azurerm_linux_virtual_machine.this.id

  source {
    script = file("${path.module}/scripts/wait-for-cloud-init.sh")
  }

  timeouts {
    create = "90m"
    update = "90m"
  }
}

resource "azurerm_role_assignment" "this" {
  principal_id         = azurerm_linux_virtual_machine.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Storage Blob Data Contributor"
  scope                = var.storage_account_id
}
#endregion

#region entra-id-ssh
# Enables Microsoft Entra ID sign-in over SSH using short-lived OpenSSH certificates, so operators sign in
# as their own Entra identity through Azure Bastion instead of the local admin account. Installing the
# extension uses apt, so it waits for cloud-init and the dpkg/apt locks to be released first.
resource "azurerm_virtual_machine_extension" "aad_ssh_login" {
  name                       = "${module.naming.virtual_machine_extension.name}-${var.vm_jumpbox_linux_name}-AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  depends_on = [azurerm_virtual_machine_run_command.wait_for_cloud_init]
}

# Grants the operator (the identity applying this configuration) Entra ID SSH sign-in with passwordless sudo.
resource "azurerm_role_assignment" "operator_vm_admin_login" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Virtual Machine Administrator Login"
  scope                = azurerm_linux_virtual_machine.this.id
}
#endregion

#region azure-monitor
# Installing the agent uses apt, so it waits for the Entra ID SSH extension (which waits for cloud-init)
# to avoid contending for the dpkg/apt locks.
resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.33"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  depends_on = [azurerm_virtual_machine_extension.aad_ssh_login]
}

resource "azurerm_monitor_data_collection_rule_association" "dcr" {
  name                    = "${module.naming.monitor_data_collection_rule.name}-${var.vm_jumpbox_linux_name}-association"
  target_resource_id      = azurerm_linux_virtual_machine.this.id
  data_collection_rule_id = var.data_collection_rule_linux_id

  depends_on = [azurerm_virtual_machine_extension.ama]
}

resource "azurerm_monitor_data_collection_rule_association" "dce" {
  target_resource_id          = azurerm_linux_virtual_machine.this.id
  data_collection_endpoint_id = var.data_collection_endpoint_id

  depends_on = [azurerm_virtual_machine_extension.ama]
}
#endregion

#region github-runner
# Optional: installs and registers the GitHub Actions self-hosted runner agent. Runs after cloud-init and
# the VM extensions, so the base VM is identical with or without the runner and nothing above depends on it.
# The GitHub token is passed as a protected parameter through the write-only sensitive_body argument, so it
# never lands in Terraform state, the saved plan, the VM custom data or Key Vault. It is sent only when the
# Run Command is created or var.github_runner_token_version changes; other updates re-run the script without
# it, and the script leaves an already registered runner as-is.
resource "azapi_resource" "github_runner" {
  count = var.enable_github_runner ? 1 : 0

  type      = "Microsoft.Compute/virtualMachines/runCommands@2025-04-01"
  name      = "${module.naming.virtual_machine_extension.name}-${var.vm_jumpbox_linux_name}-ConfigureGitHubRunner"
  parent_id = azurerm_linux_virtual_machine.this.id
  location  = var.location

  body = {
    properties = {
      source = {
        script = file("${path.module}/scripts/configure-github-runner.sh")
      }
      parameters = [
        { name = "RUNNER_URL", value = var.github_runner_url },
        { name = "RUNNER_NAME", value = local.github_runner_name },
        { name = "RUNNER_GROUP", value = var.github_runner_group },
        { name = "RUNNER_LABELS", value = join(",", var.github_runner_labels) },
        { name = "RUNNER_VERSION", value = var.github_runner_version },
        { name = "RUNNER_USER", value = var.github_runner_service_account },
        { name = "RUNNER_HOME", value = local.github_runner_home },
        { name = "RUNNER_TOKEN_TYPE", value = var.github_runner_token_type },
        { name = "RUNNER_VWAN_SUDOERS", value = tostring(var.github_runner_enable_vwan_sudoers) },
        { name = "AAD_TENANT_ID", value = data.azurerm_client_config.current.tenant_id }
      ]
      asyncExecution                  = false
      treatFailureAsDeploymentFailure = true
      timeoutInSeconds                = 3600
    }
  }

  sensitive_body = {
    properties = {
      protectedParameters = [
        { name = "RUNNER_TOKEN", value = var.github_runner_token }
      ]
    }
  }

  # Sends sensitive_body only on create or when var.github_runner_token_version changes. See that variable.
  sensitive_body_version = {
    "properties.protectedParameters" = tostring(var.github_runner_token_version)
  }

  timeouts {
    create = "90m"
    update = "90m"
  }

  # Installing the runner dependencies uses apt, so wait for the last apt-based extension to finish.
  depends_on = [azurerm_virtual_machine_extension.ama]

  lifecycle {
    precondition {
      condition     = var.github_runner_url != ""
      error_message = "var.github_runner_url must be set when var.enable_github_runner is true."
    }
  }
}
#endregion
