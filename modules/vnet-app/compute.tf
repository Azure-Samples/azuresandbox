#region vm
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

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.vnet_app_links
  ]
}

resource "azurerm_role_assignment" "assignments_vm_win" {
  for_each = local.vm_win_roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = each.value.scope
}
#endregion

#region vm-configuration
resource "azurerm_virtual_machine_run_command" "install_windows_features" {
  name               = "${module.naming.virtual_machine_extension.name}-${var.vm_jumpbox_win_name}-InstallWindowsFeatures"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id

  source {
    script = file("${path.module}/scripts/Install-WindowsFeatures.ps1")
  }
}

resource "azurerm_virtual_machine_extension" "join_domain" {
  name                       = "${module.naming.virtual_machine_extension.name}-${var.vm_jumpbox_win_name}-JsonADDomainExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_run_command.install_windows_features]

  settings = jsonencode({
    Name    = var.adds_domain_name
    User    = "${local.adds_domain_name_netbios}\\${var.admin_username}"
    Restart = "true"
    Options = "3"
  })

  protected_settings = jsonencode({
    Password = var.admin_password
  })
}

resource "azurerm_virtual_machine_run_command" "install_software" {
  name               = "${module.naming.virtual_machine_extension.name}-${var.vm_jumpbox_win_name}-InstallSoftware"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [azurerm_virtual_machine_extension.configure_azure_files]

  source {
    script = file("${path.module}/scripts/Install-Software.ps1")
  }

  timeouts {
    create = "60m"
  }
}
#endregion

#region azure-files-configuration
resource "azurerm_virtual_machine_extension" "configure_azure_files" {
  name                       = "${module.naming.virtual_machine_extension.name}-${var.vm_jumpbox_win_name}-ConfigureAzureFiles"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_extension.join_domain]

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
#endregion

#region azure-monitor-agent
resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.2"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  # Install AMA after domain join and configuration extensions to avoid extension sequencing
  # conflicts (see AMPLS_IMPLEMENTATION_PLAN.md Section 10, risk table).
  depends_on = [azurerm_virtual_machine_extension.configure_azure_files]
}

resource "azurerm_monitor_data_collection_rule_association" "jumpwin1_dcr" {
  name                    = "${module.naming.monitor_data_collection_rule.name}-${var.vm_jumpbox_win_name}-association"
  target_resource_id      = azurerm_windows_virtual_machine.this.id
  data_collection_rule_id = var.data_collection_rule_windows_id

  depends_on = [azurerm_virtual_machine_extension.ama]
}

resource "azurerm_monitor_data_collection_rule_association" "jumpwin1_dce" {
  target_resource_id          = azurerm_windows_virtual_machine.this.id
  data_collection_endpoint_id = var.data_collection_endpoint_id

  depends_on = [azurerm_virtual_machine_extension.ama]
}
#endregion
