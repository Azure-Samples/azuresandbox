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
  secure_boot_enabled        = true
  size                       = var.vm_mssql_win_size
  source_image_id            = var.vm_image_gallery_id == null ? null : "${var.vm_image_gallery_id}/images/mssqlwin"
  vtpm_enabled               = true

  # Scheduled patching (Customer Managed Schedules): see the vnet-shared maintenance configuration.
  bypass_platform_safety_checks_on_user_schedule_enabled = true
  patch_assessment_mode                                  = "AutomaticByPlatform"
  patch_mode                                             = "AutomaticByPlatform"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_mssql_win_storage_account_type_os_disk
  }

  dynamic "source_image_reference" {
    for_each = var.vm_image_gallery_id == null ? [1] : []

    content {
      publisher = var.vm_mssql_win_image_publisher
      offer     = var.vm_mssql_win_image_offer
      sku       = var.vm_mssql_win_image_sku
      version   = var.vm_mssql_win_image_version
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_managed_disk" "disks" {
  for_each = local.disks

  resource_group_name = var.resource_group_name
  name                = "${module.naming.names["disk"].name}-${each.value.name}"
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
# A new VM's guest agent may self-update at first boot and skip goal states meanwhile, so an
# installPatches request issued then is failed by the platform (#1023). This run command is itself a
# goal state, so it completes only once the agent is processing goal states again. It runs after the
# data disk attachments so those VM operations don't conflict with it or with patching.
resource "azurerm_virtual_machine_run_command" "wait_for_guest_agent" {
  name               = "WaitForGuestAgent"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [azurerm_virtual_machine_data_disk_attachment.attachments]

  source {
    script = file("${path.module}/scripts/Wait-GuestAgentReady.ps1")
  }

  timeouts {
    create = "30m"
    update = "30m"
  }
}

# Opt in to Microsoft Update before patching, so deploy-time and scheduled patching also cover SQL Server.
resource "azurerm_virtual_machine_run_command" "enable_microsoft_update" {
  name               = "EnableMicrosoftUpdate"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [azurerm_virtual_machine_run_command.wait_for_guest_agent]

  source {
    script = file("${path.module}/scripts/Enable-MicrosoftUpdate.ps1")
  }
}

# Patch first: install pending Critical/Security updates (and reboot if required) before any run
# command or extension runs, so update-driven reboots don't interrupt guest configuration.
# Runs after the guest agent readiness gate (and so after the data disk attachments) and the Microsoft Update opt-in.
# The apply fails if the patch run reports status "Failed" (e.g. a patch failed to install or the
# maximumDuration window ran out with patches outstanding), so configuration never runs on a
# partially patched VM. The patch result is also exported.
resource "azapi_resource_action" "install_patches" {
  type        = "Microsoft.Compute/virtualMachines@2025-04-01"
  resource_id = azurerm_windows_virtual_machine.this.id
  action      = "installPatches"
  method      = "POST"
  depends_on  = [azurerm_virtual_machine_run_command.enable_microsoft_update]

  body = {
    maximumDuration = "PT2H"
    rebootSetting   = "IfRequired"
    windowsParameters = {
      classificationsToInclude = ["Critical", "Security"]
    }
  }

  response_export_values = ["status", "rebootStatus", "installedPatchCount", "failedPatchCount", "pendingPatchCount", "maintenanceWindowExceeded"]

  timeouts {
    create = "135m"
  }

  lifecycle {
    postcondition {
      condition     = try(self.output.status, "") != "Failed"
      error_message = "Patch installation on ${azurerm_windows_virtual_machine.this.name} reported status Failed (maintenanceWindowExceeded=${try(self.output.maintenanceWindowExceeded, "unknown")}, installed=${try(self.output.installedPatchCount, "unknown")}, failed=${try(self.output.failedPatchCount, "unknown")}, pending=${try(self.output.pendingPatchCount, "unknown")}, rebootStatus=${try(self.output.rebootStatus, "unknown")})."
    }
  }
}

resource "azurerm_virtual_machine_extension" "join_domain" {
  name                       = "${module.naming.names["virtual_machine_extension"].name}-${var.vm_mssql_win_name}-JsonADDomainExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true
  depends_on                 = [azapi_resource_action.install_patches]

  settings = jsonencode({
    Name    = var.adds_domain_name
    User    = "${local.adds_domain_name_netbios}\\${var.admin_username}"
    Restart = "false"
    Options = "3"
  })

  protected_settings = jsonencode({
    Password = var.admin_password
  })
}

# The domain join requires a reboot. With Restart = "true" the extension only schedules it and
# reports success, so run commands started next can be killed mid-run by the shutdown (#1024).
# Instead, restart synchronously and wait for the guest agent and WMI to settle before configuring.
resource "azapi_resource_action" "restart_after_domain_join" {
  type        = "Microsoft.Compute/virtualMachines@2025-04-01"
  resource_id = azurerm_windows_virtual_machine.this.id
  action      = "restart"
  method      = "POST"
  depends_on  = [azurerm_virtual_machine_extension.join_domain]

  timeouts {
    create = "30m"
  }
}

resource "time_sleep" "wait_for_domain_join_restart" {
  create_duration = "2m"
  depends_on      = [azapi_resource_action.restart_after_domain_join]
}

resource "azurerm_virtual_machine_run_command" "configure_firewall_rules" {
  name               = "ConfigureFirewallRules"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [time_sleep.wait_for_domain_join_restart]

  source {
    script = file("${path.module}/scripts/Configure-FirewallRules.ps1")
  }
}

resource "azurerm_virtual_machine_run_command" "configure_sql_login" {
  name               = "ConfigureSqlLogin"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [time_sleep.wait_for_domain_join_restart]

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
  name                       = "${module.naming.names["virtual_machine_extension"].name}-${var.vm_mssql_win_name}-ConfigureSqlServer"
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
  name                    = "${module.naming.names["data_collection_rule_association"].name}-${var.vm_mssql_win_name}"
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

#region patching
# Assigned last, so scheduled installs and reboots can't interrupt deploy-time configuration.
resource "azurerm_maintenance_assignment_virtual_machine" "this" {
  location                     = var.location
  maintenance_configuration_id = var.maintenance_configuration_id
  virtual_machine_id           = azurerm_windows_virtual_machine.this.id

  depends_on = [
    azurerm_monitor_data_collection_rule_association.mssqlwin1_dce,
    azurerm_monitor_data_collection_rule_association.mssqlwin1_dcr,
    azurerm_virtual_machine_run_command.configure_firewall_rules,
  ]
}
#endregion
