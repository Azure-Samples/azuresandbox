locals {
  vm_devops_win_names = formatlist("${var.vm_devops_win_name}%s", range(1, var.vm_devops_win_instances + 1))
}

resource "azurerm_windows_virtual_machine" "vm_devops_win" {
  for_each                 = toset(local.vm_devops_win_names)
  name                     = each.key
  resource_group_name      = var.resource_group_name
  location                 = var.location
  size                     = var.vm_devops_win_size
  admin_username           = data.azurerm_key_vault_secret.adminuser.value
  admin_password           = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids    = [azurerm_network_interface.vm_devops_win_nic[each.key].id]
  enable_automatic_updates = true
  patch_mode               = "AutomaticByPlatform"
  tags                     = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_devops_win_storage_account_type
  }

  source_image_reference {
    publisher = var.vm_devops_win_image_publisher
    offer     = var.vm_devops_win_image_offer
    sku       = var.vm_devops_win_image_sku
    version   = var.vm_devops_win_image_version
  }

  # Note: To view provisioner output, use the Terraform nonsensitive() function when referencing key vault secrets or variables marked 'sensitive'
  provisioner "local-exec" {
    command     = <<EOT
        $params = @{
          TenantId                = "${var.aad_tenant_id}"
          SubscriptionId          = "${var.subscription_id}"
          ResourceGroupName       = "${var.resource_group_name}"
          Location                = "${var.location}"
          AutomationAccountName   = "${var.automation_account_name}"
          VirtualMachineName      = "${each.key}"
          AppId                   = "${var.arm_client_id}"
          AppSecret               = "${nonsensitive(var.arm_client_secret)}"
          DscConfigurationName    = "DevOpsAgentConfig"
        }
        ${path.root}/aadsc-register-node.ps1 @params 
   EOT
    interpreter = ["pwsh", "-Command"]
  }
}

# Nic
resource "azurerm_network_interface" "vm_devops_win_nic" {
  for_each            = toset(local.vm_devops_win_names)
  name                = "nic-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipc-${each.key}"
    subnet_id                     = var.vnet_app_01_subnets["snet-app-01"].id
    private_ip_address_allocation = "Dynamic"
  }
}
