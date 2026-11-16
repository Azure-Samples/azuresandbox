resource "azurerm_linux_virtual_machine" "this" {
  name                       = var.vm_jumpbox_linux_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_jumpbox_linux_size
  admin_username             = "${var.admin_username}local"
  network_interface_ids      = [azurerm_network_interface.this.id]
  encryption_at_host_enabled = true
  provision_vm_agent         = true
  source_image_id            = var.vm_image_gallery_id == null ? null : "${var.vm_image_gallery_id}/images/jumplinux"

  # Scheduled patching (Customer Managed Schedules): see the vnet-shared maintenance configuration.
  bypass_platform_safety_checks_on_user_schedule_enabled = true
  patch_assessment_mode                                  = "AutomaticByPlatform"
  patch_mode                                             = "AutomaticByPlatform"

  admin_ssh_key {
    username   = "${var.admin_username}local"
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_jumpbox_linux_storage_account_type
  }

  dynamic "source_image_reference" {
    for_each = var.vm_image_gallery_id == null ? [1] : []

    content {
      publisher = var.vm_jumpbox_linux_image_publisher
      offer     = var.vm_jumpbox_linux_image_offer
      sku       = var.vm_jumpbox_linux_image_sku
      version   = var.vm_jumpbox_linux_image_version
    }
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = data.cloudinit_config.vm_jumpbox_linux.rendered
}

resource "azurerm_role_assignment" "kv_secrets_user_vm_linux" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.this.identity[0].principal_id
}

#region azure-monitor-agent
# The AMA installer fails (exit code 56) if the package manager is locked for more than a few
# minutes, so wait for cloud-init package installs and first-boot apt activity to finish first.
resource "azurerm_virtual_machine_run_command" "wait_for_cloud_init" {
  name               = "${module.naming.names["virtual_machine_extension"].name}-${var.vm_jumpbox_linux_name}-WaitForCloudInit"
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

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.33"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  depends_on = [azurerm_virtual_machine_run_command.wait_for_cloud_init]
}

resource "azurerm_monitor_data_collection_rule_association" "jumplinux1_dcr" {
  name                    = "${module.naming.names["data_collection_rule_association"].name}-${var.vm_jumpbox_linux_name}"
  target_resource_id      = azurerm_linux_virtual_machine.this.id
  data_collection_rule_id = var.data_collection_rule_linux_id

  depends_on = [azurerm_virtual_machine_extension.ama]
}

resource "azurerm_monitor_data_collection_rule_association" "jumplinux1_dce" {
  target_resource_id          = azurerm_linux_virtual_machine.this.id
  data_collection_endpoint_id = var.data_collection_endpoint_id

  depends_on = [azurerm_virtual_machine_extension.ama]
}
#endregion

#region patching
# Assigned last, so scheduled installs and reboots can't interrupt deploy-time configuration.
resource "azurerm_maintenance_assignment_virtual_machine" "this" {
  location                     = var.location
  maintenance_configuration_id = var.maintenance_configuration_id
  virtual_machine_id           = azurerm_linux_virtual_machine.this.id

  depends_on = [
    azurerm_monitor_data_collection_rule_association.jumplinux1_dce,
    azurerm_monitor_data_collection_rule_association.jumplinux1_dcr,
  ]
}
#endregion
