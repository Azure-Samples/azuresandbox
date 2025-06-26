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
    type = "SystemAssigned"
  }

  custom_data = data.cloudinit_config.vm_jumpbox_linux.rendered
}

resource "azurerm_role_assignment" "this" {
  principal_id         = azurerm_linux_virtual_machine.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Storage Blob Data Contributor"
  scope                = var.storage_account_id
}
#endregion
