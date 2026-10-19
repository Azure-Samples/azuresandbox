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

  # The runner registration secret must exist in key vault before cloud-init reads it on first boot.
  depends_on = [azurerm_key_vault_secret.github_runner_token]
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
