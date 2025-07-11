#region domain controller vm
resource "azurerm_windows_virtual_machine" "vm_adds" {
  name                       = var.vm_adds_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_adds_size
  admin_username             = "onprem${data.azurerm_key_vault_secret.adminuser.value}"
  admin_password             = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids      = [azurerm_network_interface.vm_adds.id]
  patch_assessment_mode      = "AutomaticByPlatform"
  patch_mode                 = "AutomaticByPlatform"
  provision_vm_agent         = true
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_adds_storage_account_type
  }

  source_image_reference {
    publisher = var.vm_adds_image_publisher
    offer     = var.vm_adds_image_offer
    sku       = var.vm_adds_image_sku
    version   = var.vm_adds_image_version
  }

  provisioner "local-exec" {
    command     = "$params = @{ ${join(" ", local.local_scripts["provisioner_vm_adds"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["provisioner_vm_adds"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
}
#endregion

#region jumpbox VM
resource "azurerm_windows_virtual_machine" "vm_jumpbox_win" {
  name                       = var.vm_jumpbox_win_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_jumpbox_win_size
  admin_username             = "onprem${data.azurerm_key_vault_secret.adminuser.value}"
  admin_password             = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids      = [azurerm_network_interface.vm_jumpbox_win.id]
  patch_assessment_mode      = "AutomaticByPlatform"
  patch_mode                 = "AutomaticByPlatform"
  provision_vm_agent         = true
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_jumpbox_win_storage_account_type
  }

  source_image_reference {
    publisher = var.vm_jumpbox_win_image_publisher
    offer     = var.vm_jumpbox_win_image_offer
    sku       = var.vm_jumpbox_win_image_sku
    version   = var.vm_jumpbox_win_image_version
  }

  depends_on = [azurerm_windows_virtual_machine.vm_adds]

  provisioner "local-exec" {
    command     = "$params = @{ ${join(" ", local.local_scripts["provisioner_vm_jumpbox_win"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["provisioner_vm_jumpbox_win"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
}
#endregion
