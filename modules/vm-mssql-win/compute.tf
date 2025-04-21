resource "azurerm_windows_virtual_machine" "this" {
  name                       = var.vm_mssql_win_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_mssql_win_size
  admin_username             = data.azurerm_key_vault_secret.adminuser.value
  admin_password             = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids      = [azurerm_network_interface.this.id]
  patch_assessment_mode      = "AutomaticByPlatform"
  provision_vm_agent         = true
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_mssql_win_storage_account_type
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

  lifecycle {
    ignore_changes = [
      admin_username,
      admin_password
    ]
  }
}

resource "azurerm_managed_disk" "disks" {
  for_each = local.disks

  name                 = "${module.naming.managed_disk.name}-${each.value.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = var.vm_mssql_win_storage_account_type
  create_option        = "Empty"
  disk_size_gb         = each.value.disk_size_gb
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
    time_sleep.wait_for_roles,
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

resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on = [
    azurerm_role_assignment.assignments
  ]
}
