#region domain controller vm
resource "azurerm_windows_virtual_machine" "vm_adds" {
  name                       = var.vm_adds_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_adds_size
  admin_username             = "onprem${var.admin_username}"
  admin_password             = var.admin_password
  network_interface_ids      = [azurerm_network_interface.vm_adds.id]
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
#endregion

#region domain controller vm configuration
resource "azurerm_virtual_machine_run_command" "configure_adds" {
  name               = "ConfigureAdds"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.vm_adds.id

  source {
    script = file("${path.module}/scripts/Configure-Adds.ps1")
  }

  parameter {
    name  = "Domain"
    value = var.adds_domain_name
  }

  parameter {
    name  = "AdminUsername"
    value = "onprem${var.admin_username}"
  }

  parameter {
    name  = "ComputerName"
    value = var.vm_adds_name
  }

  protected_parameter {
    name  = "AdminPwd"
    value = var.admin_password
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
  virtual_machine_id = azurerm_windows_virtual_machine.vm_adds.id
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
    value = "onprem${var.admin_username}"
  }

  parameter {
    name  = "ComputerName"
    value = var.vm_adds_name
  }

  parameter {
    name  = "DnsResolverCloud"
    value = cidrhost(var.subnets_cloud["snet-misc-01"].address_prefixes[0], 4)
  }

  parameter {
    name  = "AddsDomainNameCloud"
    value = var.adds_domain_name_cloud
  }
}
#endregion

#region jumpbox VM
resource "azurerm_windows_virtual_machine" "vm_jumpbox_win" {
  name                       = var.vm_jumpbox_win_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_jumpbox_win_size
  admin_username             = "onprem${var.admin_username}"
  admin_password             = var.admin_password
  network_interface_ids      = [azurerm_network_interface.vm_jumpbox_win.id]
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

  depends_on = [azurerm_windows_virtual_machine.vm_adds]
}
#endregion

#region jumpbox VM configuration
resource "azurerm_virtual_machine_run_command" "install_windows_features" {
  name               = "InstallWindowsFeatures"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.vm_jumpbox_win.id

  source {
    script = file("${path.module}/scripts/Install-WindowsFeatures.ps1")
  }
}

resource "azurerm_virtual_machine_extension" "join_domain" {
  name                       = "JsonADDomainExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm_jumpbox_win.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true

  depends_on = [
    azurerm_virtual_machine_run_command.install_windows_features,
    azurerm_virtual_machine_run_command.configure_adds_dns
  ]

  settings = jsonencode({
    Name    = var.adds_domain_name
    User    = "${upper(replace(var.adds_domain_name, ".local", ""))}\\onprem${var.admin_username}"
    Restart = "true"
    Options = "3"
  })

  protected_settings = jsonencode({
    Password = var.admin_password
  })
}

resource "azurerm_virtual_machine_run_command" "install_software" {
  name               = "InstallSoftware"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.vm_jumpbox_win.id
  depends_on         = [azurerm_virtual_machine_extension.join_domain]

  source {
    script = file("${path.module}/scripts/Install-Software.ps1")
  }

  timeouts {
    create = "60m"
  }
}
#endregion
