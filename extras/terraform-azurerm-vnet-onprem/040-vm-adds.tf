# AD DS virtual machine
# Important: For production use you should deploy two domain controller VMs in an availability set or in different Availablity Groups.

resource "azurerm_windows_virtual_machine" "vm_adds" {
  name                       = var.vm_adds_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_adds_size
  admin_username             = data.azurerm_key_vault_secret.adminuser.value
  admin_password             = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids      = [azurerm_network_interface.vm_adds_nic_01.id]
  patch_assessment_mode      = "AutomaticByPlatform"
  patch_mode                 = "AutomaticByPlatform"
  provision_vm_agent         = true
  encryption_at_host_enabled = true
  tags                       = var.tags

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

  # Apply domain controller configuration using Azure Automation DSC
  # Note: To view provisioner output, use the Terraform nonsensitive() function when referencing key vault secrets or variables marked 'sensitive'
  provisioner "local-exec" {
    command     = <<EOT
        $params = @{
        TenantId = "${var.aad_tenant_id}"
        SubscriptionId = "${var.subscription_id}"
        ResourceGroupName = "${var.resource_group_name}"
        Location = "${var.location}"
        AutomationAccountName = "${var.automation_account_name}"
        VirtualMachineName = "${var.vm_adds_name}"
        AppId = "${var.arm_client_id}"
        AppSecret = "${var.arm_client_secret}"
        DscConfigurationName = "OnPremDomainConfig"
        }
        ${path.root}/aadsc-register-node.ps1 @params 
   EOT
    interpreter = ["pwsh", "-Command"]
  }
}

# Nics
resource "azurerm_network_interface" "vm_adds_nic_01" {
  name                = "nic-${var.vm_adds_name}-1"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipc-${var.vm_adds_name}-1"
    subnet_id                     = azurerm_subnet.vnet_shared_02_subnets["snet-adds-02"].id
    private_ip_address_allocation = "Dynamic"
  }
}
