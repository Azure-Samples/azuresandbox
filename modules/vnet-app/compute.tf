resource "azurerm_windows_virtual_machine" "this" {
  name                       = var.vm_jumpbox_win_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_jumpbox_win_size
  admin_username             = var.admin_username
  admin_password             = var.admin_password
  network_interface_ids      = [azurerm_network_interface.this.id]
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

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.vnet_app_links]

  provisioner "local-exec" {
    command     = "$params = @{ ${join(" ", local.local_scripts["provisioner_vm_windows"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["provisioner_vm_windows"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
}

resource "azurerm_role_assignment" "assignments_vm_win" {
  for_each = local.vm_win_roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = each.value.scope
}

resource "azurerm_virtual_machine_extension" "this" {
  name                       = "${module.naming.virtual_machine_extension.name}-${var.vm_jumpbox_win_name}-CustomScriptExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  depends_on                 = [time_sleep.wait_for_vm_win_roles]

  settings = jsonencode({
    fileUris = [
      for script_key, script in local.remote_scripts : "${azurerm_storage_account.this.primary_blob_endpoint}${azurerm_storage_container.this.name}/${script.name}"
    ]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -Command \"$params = @{ ${join(" ", local.remote_scripts["orchestrator"].parameters)}}; .\\${local.remote_scripts["orchestrator"].name} @params\""
    managedIdentity  = {}
  })
}

resource "time_sleep" "wait_for_vm_win_roles" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.assignments_vm_win]
}
