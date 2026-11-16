resource "azurerm_windows_virtual_machine" "this" {
  name                       = var.vm_adds_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_adds_size
  admin_username             = var.admin_username
  admin_password             = local.admin_password
  network_interface_ids      = [azurerm_network_interface.this.id]
  provision_vm_agent         = true
  encryption_at_host_enabled = true
  source_image_id            = var.vm_image_gallery_id == null ? null : "${var.vm_image_gallery_id}/images/adds"

  # Scheduled patching (Customer Managed Schedules): see azurerm_maintenance_configuration.this.
  bypass_platform_safety_checks_on_user_schedule_enabled = true
  patch_assessment_mode                                  = "AutomaticByPlatform"
  patch_mode                                             = "AutomaticByPlatform"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_adds_storage_account_type
  }

  dynamic "source_image_reference" {
    for_each = var.vm_image_gallery_id == null ? [1] : []

    content {
      publisher = var.vm_adds_image_publisher
      offer     = var.vm_adds_image_offer
      sku       = var.vm_adds_image_sku
      version   = var.vm_adds_image_version
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

#region vm-configuration
# A new VM's guest agent may self-update at first boot and skip goal states meanwhile, so an
# installPatches request issued then is failed by the platform (#1023). This run command is itself a
# goal state, so it completes only once the agent is processing goal states again.
resource "azurerm_virtual_machine_run_command" "wait_for_guest_agent" {
  name               = "WaitForGuestAgent"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id

  source {
    script = file("${path.module}/scripts/Wait-GuestAgentReady.ps1")
  }

  timeouts {
    create = "30m"
    update = "30m"
  }
}

# Opt in to Microsoft Update before patching, so deploy-time and scheduled patching also cover other Microsoft products.
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
# Runs after the guest agent readiness gate and the Microsoft Update opt-in.
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

# Assigned last, so scheduled installs and reboots can't interrupt deploy-time configuration.
resource "azurerm_maintenance_assignment_virtual_machine" "this" {
  location                     = var.location
  maintenance_configuration_id = azurerm_maintenance_configuration.this.id
  virtual_machine_id           = azurerm_windows_virtual_machine.this.id

  depends_on = [
    azurerm_monitor_data_collection_rule_association.adds1_dce,
    azurerm_monitor_data_collection_rule_association.adds1_dcr,
  ]
}
#endregion

#region patching
# One Azure Update Manager schedule patches every sandbox VM (Windows and Linux, platform images and custom images).
# Each VM module assigns its VMs as its last deployment step. See the root README "Patching" section.
resource "time_static" "patch_schedule" {}

resource "azurerm_maintenance_configuration" "this" {
  name                     = module.naming.names["maintenance_configuration"].name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  scope                    = "InGuestPatch"
  in_guest_user_patch_mode = "User"
  visibility               = "Custom"

  # The first run is on or after two days from creation, which keeps the start at least 15 minutes in the future in
  # any time zone. time_static keeps the start date stable on later applies.
  window {
    start_date_time = "${formatdate("YYYY-MM-DD", timeadd(time_static.patch_schedule.rfc3339, "48h"))} ${var.patch_schedule.start_time}"
    time_zone       = var.patch_schedule.time_zone
    duration        = var.patch_schedule.duration
    recur_every     = var.patch_schedule.recurrence
  }

  install_patches {
    reboot = var.patch_schedule.reboot

    linux {
      classifications_to_include = var.patch_schedule.linux_classifications
    }

    windows {
      classifications_to_include = var.patch_schedule.windows_classifications
    }
  }
}
#endregion
