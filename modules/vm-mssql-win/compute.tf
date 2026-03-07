#region resources
resource "azurerm_windows_virtual_machine" "this" {
  name                = var.vm_mssql_win_name
  resource_group_name = var.resource_group_name
  location            = var.location
  zone                = var.vm_mssql_win_zone 

  admin_username             = var.admin_username
  admin_password             = var.admin_password
  disk_controller_type       = "NVMe"
  encryption_at_host_enabled = true
  network_interface_ids      = [azurerm_network_interface.this.id]
  patch_assessment_mode      = "AutomaticByPlatform"
  secure_boot_enabled        = true
  size                       = var.vm_mssql_win_size
  vtpm_enabled               = true

  depends_on = [null_resource.this]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_mssql_win_storage_account_type_os_disk
  }

  source_image_reference {
    publisher = var.vm_mssql_win_image_publisher
    offer     = var.vm_mssql_win_image_offer
    sku       = var.vm_mssql_win_image_sku
    version   = var.vm_mssql_win_image_version
  }

  identity {
    type = "SystemAssigned"
  }

  provisioner "local-exec" {
    command     = "$params = @{ ${join(" ", local.local_scripts["provisioner"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["provisioner"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
}

resource "azurerm_managed_disk" "disks" {
  for_each = local.disks

  resource_group_name = var.resource_group_name
  name                = "${module.naming.managed_disk.name}-${each.value.name}"
  location            = var.location
  zone                = var.vm_mssql_win_zone

  create_option        = "Empty"
  disk_size_gb         = each.value.disk_size_gb
  disk_iops_read_write = each.value.disk_iops_read_write
  disk_mbps_read_write = each.value.disk_mbps_read_write
  storage_account_type = var.vm_mssql_win_storage_account_type_data_disks
}

resource "azurerm_virtual_machine_data_disk_attachment" "attachments" {
  for_each = local.disks

  managed_disk_id    = azurerm_managed_disk.disks[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  lun                = each.value.lun
  caching            = each.value.caching
}

resource "azurerm_role_assignment" "assignments" {
  for_each = local.roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = each.value.scope
}

resource "azurerm_virtual_machine_extension" "this" {
  name                       = "${module.naming.virtual_machine_extension.name}-${var.vm_mssql_win_name}-CustomScriptExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.attachments,
    time_sleep.wait_for_roles_and_public_access,
    azurerm_storage_blob.remote_scripts
  ]

  settings = jsonencode({
    fileUris = [
      for script_key, script in local.remote_scripts : "${var.storage_blob_endpoint}${var.storage_container_name}/${script.name}"
    ]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -Command \"$params = @{ ${join(" ", local.remote_scripts["orchestrator"].parameters)}}; .\\${local.remote_scripts["orchestrator"].name} @params\""
    managedIdentity  = {}
  })
}
#endregion
