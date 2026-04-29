#region sql-vm
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
#endregion

#region sql-vm-configuration
resource "azurerm_virtual_machine_extension" "join_domain" {
  name                       = "${module.naming.virtual_machine_extension.name}-${var.vm_mssql_win_name}-JsonADDomainExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_data_disk_attachment.attachments]

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

resource "azurerm_virtual_machine_run_command" "configure_firewall_rules" {
  name               = "ConfigureFirewallRules"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [azurerm_virtual_machine_extension.join_domain]

  source {
    script = file("${path.module}/scripts/Configure-FirewallRules.ps1")
  }
}

resource "azurerm_virtual_machine_run_command" "configure_sql_login" {
  name               = "ConfigureSqlLogin"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [azurerm_virtual_machine_extension.join_domain]

  source {
    script = file("${path.module}/scripts/Configure-SqlLogin.ps1")
  }

  parameter {
    name  = "DomainAdminUser"
    value = "${local.adds_domain_name_netbios}\\${var.admin_username}"
  }
}
#endregion

resource "azurerm_virtual_machine_extension" "configure_sql_server" {
  name                       = "${module.naming.virtual_machine_extension.name}-${var.vm_mssql_win_name}-ConfigureSqlServer"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.attachments,
    azurerm_virtual_machine_run_command.configure_sql_login,
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
  depends_on = [azurerm_virtual_machine_extension.configure_sql_server]
}

resource "azurerm_monitor_data_collection_rule_association" "mssqlwin1_dcr" {
  name                    = "${module.naming.monitor_data_collection_rule.name}-${var.vm_mssql_win_name}-association"
  target_resource_id      = azurerm_windows_virtual_machine.this.id
  data_collection_rule_id = var.data_collection_rule_windows_id

  depends_on = [azurerm_virtual_machine_extension.ama]
}

resource "azurerm_monitor_data_collection_rule_association" "mssqlwin1_dce" {
  target_resource_id          = azurerm_windows_virtual_machine.this.id
  data_collection_endpoint_id = var.data_collection_endpoint_id

  depends_on = [azurerm_virtual_machine_extension.ama]
}
#endregion
