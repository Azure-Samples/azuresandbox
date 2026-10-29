resource "azurerm_windows_virtual_machine" "this" {
  name                       = var.vm_adds_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_adds_size
  admin_username             = var.admin_username
  admin_password             = local.admin_password
  network_interface_ids      = [azurerm_network_interface.this.id]
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

  identity {
    type = "SystemAssigned"
  }
}

#region vm-configuration
# Patch first: install pending Critical/Security updates (and reboot if required) before any run
# command or extension runs, so update-driven reboots don't interrupt guest configuration.
# Best-effort: only an API/operation error fails the apply; the patch result is exported.
resource "azapi_resource_action" "install_patches" {
  type        = "Microsoft.Compute/virtualMachines@2025-04-01"
  resource_id = azurerm_windows_virtual_machine.this.id
  action      = "installPatches"
  method      = "POST"

  body = {
    maximumDuration = "PT1H"
    rebootSetting   = "IfRequired"
    windowsParameters = {
      classificationsToInclude = ["Critical", "Security"]
    }
  }

  response_export_values = ["status", "rebootStatus", "installedPatchCount", "failedPatchCount", "pendingPatchCount", "maintenanceWindowExceeded"]

  timeouts {
    create = "75m"
  }
}

resource "azurerm_virtual_machine_run_command" "configure_adds" {
  name               = "ConfigureAdds"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [azapi_resource_action.install_patches]

  source {
    script = file("${path.module}/scripts/Configure-Adds.ps1")
  }

  parameter {
    name  = "Domain"
    value = var.adds_domain_name
  }

  parameter {
    name  = "AdminUsername"
    value = var.admin_username
  }

  parameter {
    name  = "ComputerName"
    value = var.vm_adds_name
  }

  protected_parameter {
    name  = "AdminPwd"
    value = local.admin_password
  }
}

resource "time_sleep" "wait_for_adds_reboot" {
  create_duration = "2m"
  depends_on      = [azurerm_virtual_machine_run_command.configure_adds]

  triggers = {
    configure_adds_id = azurerm_virtual_machine_run_command.configure_adds.id
  }
}

resource "azurerm_virtual_machine_run_command" "configure_adds_dns" {
  name               = "ConfigureAddsDns"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  depends_on         = [time_sleep.wait_for_adds_reboot]

  source {
    script = file("${path.module}/scripts/Configure-AddsDns.ps1")
  }

  parameter {
    name  = "Domain"
    value = var.adds_domain_name
  }

  parameter {
    name  = "AdminUsername"
    value = var.admin_username
  }

  parameter {
    name  = "ComputerName"
    value = var.vm_adds_name
  }
}

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.2"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  depends_on = [azurerm_virtual_machine_run_command.configure_adds_dns]
}

resource "azurerm_monitor_data_collection_rule_association" "adds1_dcr" {
  name                    = "${module.naming.names["data_collection_rule_association"].name}-${var.vm_adds_name}"
  target_resource_id      = azurerm_windows_virtual_machine.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.windows.id

  depends_on = [azurerm_virtual_machine_extension.ama]
}

resource "azurerm_monitor_data_collection_rule_association" "adds1_dce" {
  target_resource_id          = azurerm_windows_virtual_machine.this.id
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this.id

  depends_on = [azurerm_virtual_machine_extension.ama]
}
#endregion
