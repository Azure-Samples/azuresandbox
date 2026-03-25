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
}

#region vm-configuration
resource "azurerm_virtual_machine_run_command" "configure_adds" {
  name               = "ConfigureAdds"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id

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
#endregion
