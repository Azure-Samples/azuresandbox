resource "azurerm_windows_virtual_machine" "this" {
  name                       = var.vm_adds_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_adds_size
  admin_username             = var.admin_username
  admin_password             = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids      = [azurerm_network_interface.this.id]
  patch_assessment_mode      = "AutomaticByPlatform"
  patch_mode                 = "AutomaticByPlatform"
  provision_vm_agent         = true
  encryption_at_host_enabled = true
  depends_on                 = [azurerm_automation_account.this]

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

  provisioner "local-exec" {
    command     = <<EOT
      $params = @{
        TenantId = "${data.azurerm_client_config.current.tenant_id}"
        SubscriptionId = "${data.azurerm_client_config.current.subscription_id}"
        ResourceGroupName = "${var.resource_group_name}"
        Location = "${var.location}"
        AutomationAccountName = "${azurerm_automation_account.this.name}"
        VirtualMachineName = "${var.vm_adds_name}"
        AppId = "${data.azurerm_client_config.current.client_id}"
        AppSecret = "${data.azurerm_key_vault_secret.arm_client_secret.value}"
        DscConfigurationName = "LabDomainConfig"
      }
      ./${path.module}/scripts/aadsc-register-node.ps1 @params 
      EOT
    interpreter = ["pwsh", "-Command"]
  }
}
