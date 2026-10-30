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

  # The system-assigned identity is always present. The SQL admin UAMI is added only when the
  # root module enables mssql.
  identity {
    type         = var.sql_admin_uami_id != null ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = var.sql_admin_uami_id != null ? [var.sql_admin_uami_id] : null
  }

  depends_on = [
    azurerm_virtual_network_peering.app_to_shared,
    azurerm_virtual_network_peering.shared_to_app
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
# Patch first: install pending Critical/Security updates (and reboot if required) before any run
# command or extension runs, so update-driven reboots don't interrupt guest configuration.
# The apply fails if the patch run reports status "Failed" (e.g. a patch failed to install or the
# maximumDuration window ran out with patches outstanding), so configuration never runs on a
# partially patched VM. The patch result is also exported.
resource "azapi_resource_action" "install_patches" {
  type        = "Microsoft.Compute/virtualMachines@2025-04-01"
  resource_id = azurerm_windows_virtual_machine.this.id
  action      = "installPatches"
  method      = "POST"

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

resource "azurerm_virtual_machine_run_command" "install_windows_features" {
  name               = "${module.naming.names["virtual_machine_extension"].name}-${var.vm_jumpbox_win_name}-InstallWindowsFeatures"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [azapi_resource_action.install_patches]

  source {
    script = file("${path.module}/scripts/Install-WindowsFeatures.ps1")
  }
}

resource "azurerm_virtual_machine_extension" "join_domain" {
  name                       = "${module.naming.names["virtual_machine_extension"].name}-${var.vm_jumpbox_win_name}-JsonADDomainExtension"
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
  name               = "${module.naming.names["virtual_machine_extension"].name}-${var.vm_jumpbox_win_name}-InstallSoftware"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [azurerm_virtual_machine_extension.configure_azure_files]

  source {
    script = file("${path.module}/scripts/Install-Software.ps1")
  }

  # Optional tools are driven by database module enablement. Changing a flag updates
  # this run command in place, which re-runs the script; already-installed packages
  # are treated as success, so only newly requested tools are installed.
  parameter {
    name  = "InstallSsms"
    value = tostring(var.install_ssms)
  }

  parameter {
    name  = "InstallMysqlWorkbench"
    value = tostring(var.install_mysql_workbench)
  }

  timeouts {
    create = "60m"
    update = "60m"
  }
}
#endregion

#region azure-files-configuration
resource "azurerm_virtual_machine_extension" "configure_azure_files" {
  name                       = "${module.naming.names["virtual_machine_extension"].name}-${var.vm_jumpbox_win_name}-ConfigureAzureFiles"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  depends_on = [
    azurerm_role_assignment.assignments_vm_win,
    azurerm_storage_blob.remote_scripts,
    azurerm_virtual_machine_extension.join_domain
  ]

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
  name                    = "${module.naming.names["data_collection_rule_association"].name}-${var.vm_jumpbox_win_name}"
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
