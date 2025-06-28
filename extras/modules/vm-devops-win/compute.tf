#region virtual-machines
resource "azurerm_windows_virtual_machine" "virtual_machines" {
  for_each                   = toset(local.vm_devops_win_names)
  name                       = each.key
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_devops_win_size
  admin_username             = data.azurerm_key_vault_secret.adminuser.value
  admin_password             = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids      = [azurerm_network_interface.nics[each.key].id]
  patch_assessment_mode      = "AutomaticByPlatform"
  patch_mode                 = var.vm_devops_win_patch_mode
  provision_vm_agent         = true
  encryption_at_host_enabled = true
  license_type               = var.vm_devops_win_license_type

  depends_on = [null_resource.this]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_devops_win_storage_account_type
    disk_size_gb         = var.vm_devops_win_os_disk_size_gb
  }

  source_image_reference {
    publisher = var.vm_devops_win_image_publisher
    offer     = var.vm_devops_win_image_offer
    sku       = var.vm_devops_win_image_sku
    version   = var.vm_devops_win_image_version
  }

  identity {
    type = "SystemAssigned"
  }

  provisioner "local-exec" {
    command     = "$params = @{ ${join(" ", local.local_scripts["vm_provisioner"].parameters, ["VirtualMachineName = '${each.key}';"])}}; ./${path.module}/scripts/${local.local_scripts["vm_provisioner"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
}
#endregion

#region disks
resource "azurerm_managed_disk" "disks" {
  for_each             = local.vm_devops_win_data_disk_count == 1 ? azurerm_windows_virtual_machine.virtual_machines : {}
  name                 = "${module.naming.managed_disk.name}-${each.value.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = var.vm_devops_win_storage_account_type
  create_option        = "Empty"
  disk_size_gb         = var.vm_devops_win_data_disk_size_gb
}

resource "azurerm_virtual_machine_data_disk_attachment" "attachments" {
  for_each           = local.vm_devops_win_data_disk_count == 1 ? azurerm_windows_virtual_machine.virtual_machines : {}
  managed_disk_id    = azurerm_managed_disk.disks[each.value.name].id
  virtual_machine_id = each.value.id
  lun                = 0
  caching            = "ReadWrite"
}
#endregion

#region extensions
resource "azurerm_virtual_machine_extension" "extensions" {
  for_each                   = azurerm_windows_virtual_machine.virtual_machines
  name                       = "${module.naming.virtual_machine_extension.name}-${each.value.name}"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.attachments,
    time_sleep.wait_for_roles
  ]

  settings = jsonencode({
    fileUris = ["${var.storage_blob_endpoint}${var.storage_container_name}/${local.remote_scripts["configuration"].name}"]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -File \"./${local.remote_scripts["configuration"].name}\""
    managedIdentity  = {}
  })
}
#endregion

#region roles
resource "azurerm_role_assignment" "assignments" {
  for_each             = azurerm_windows_virtual_machine.virtual_machines
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_windows_virtual_machine.virtual_machines[each.value.name].identity[0].principal_id
}

resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.assignments]
}
#endregion
