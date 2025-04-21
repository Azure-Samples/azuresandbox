resource "azurerm_linux_virtual_machine" "this" {
  name                       = var.vm_jumpbox_linux_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_jumpbox_linux_size
  admin_username             = "${data.azurerm_key_vault_secret.adminuser.value}local"
  network_interface_ids      = [azurerm_network_interface.this.id]
  encryption_at_host_enabled = true
  patch_assessment_mode      = "AutomaticByPlatform"
  provision_vm_agent         = true

  admin_ssh_key {
    username   = "${data.azurerm_key_vault_secret.adminuser.value}local"
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

  # lifecycle {
  #   ignore_changes = [
  #     admin_username,
  #     admin_ssh_key,
  #     custom_data
  #   ]
  # }
}

resource "azurerm_role_assignment" "kv_secrets_user_vm_linux" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.this.identity[0].principal_id
}
