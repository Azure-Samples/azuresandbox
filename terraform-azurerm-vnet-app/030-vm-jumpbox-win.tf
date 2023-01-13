locals {
  commandParamParts = [
    "$params = @{",
      "TenantId = '${var.aad_tenant_id}'; ", 
      "SubscriptionId = '${var.subscription_id}'; ", 
      "AppId = '${var.arm_client_id}'; ",
      "AppSecret = '${nonsensitive(var.arm_client_secret)}'; ",
      "ResourceGroupName = '${var.resource_group_name}'; ",
      "StorageAccountName = '${var.storage_account_name}'; ",
      "StorageAccountKerbKey = '${nonsensitive(data.azurerm_key_vault_secret.storage_account_kerb_key.value)}'; ",
      "Domain = '${var.adds_domain_name}'; ",
      "AdminUser = '${nonsensitive(data.azurerm_key_vault_secret.adminuser.value)}'; ",
      "AdminUserSecret = '${nonsensitive(data.azurerm_key_vault_secret.adminpassword.value)}' ",
    "}"
  ]
}

# Windows jumpbox virtual machine
resource "azurerm_windows_virtual_machine" "vm_jumpbox_win" {
  name                     = var.vm_jumpbox_win_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  size                     = var.vm_jumpbox_win_size
  admin_username           = data.azurerm_key_vault_secret.adminuser.value
  admin_password           = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids    = [azurerm_network_interface.vm_jumpbox_win_nic_01.id]
  patch_mode               = "AutomaticByPlatform"
  tags                     = var.tags

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

  # Note: To view provisioner output, use the Terraform nonsensitive() function when referencing key vault secrets or variables marked 'sensitive'
  provisioner "local-exec" {
    command     = <<EOT
        $params = @{
          TenantId                = "${var.aad_tenant_id}"
          SubscriptionId          = "${var.subscription_id}"
          ResourceGroupName       = "${var.resource_group_name}"
          Location                = "${var.location}"
          AutomationAccountName   = "${var.automation_account_name}"
          VirtualMachineName      = "${var.vm_jumpbox_win_name}"
          AppId                   = "${var.arm_client_id}"
          AppSecret               = "${nonsensitive(var.arm_client_secret)}"
          DscConfigurationName    = "JumpBoxConfig"
        }
        ${path.root}/aadsc-register-node.ps1 @params 
   EOT
    interpreter = ["pwsh", "-Command"]
  }
}

# Nics
resource "azurerm_network_interface" "vm_jumpbox_win_nic_01" {
  name                = "nic-${var.vm_jumpbox_win_name}-1"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipc-${var.vm_jumpbox_win_name}-1"
    subnet_id                     = azurerm_subnet.vnet_app_01_subnets["snet-app-01"].id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.nsg_subnet_associations
  ]
}

# Virtual machine extensions
resource "azurerm_virtual_machine_extension" "vm_jumpbox_win_postdeploy_script" {
  name                       = "vmext-${azurerm_windows_virtual_machine.vm_jumpbox_win.name}-postdeploy-script"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm_jumpbox_win.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
      "fileUris": [ 
        "${var.vm_jumpbox_win_post_deploy_script_uri}", 
        "${var.vm_jumpbox_win_configure_storage_script_uri}" 
      ],
      "commandToExecute": 
        "powershell.exe -ExecutionPolicy Unrestricted -Command \"${join("", local.commandParamParts)}; .\\${var.vm_jumpbox_win_post_deploy_script} @params\""
    }    
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "storageAccountName": "${var.storage_account_name}",
      "storageAccountKey": "${data.azurerm_key_vault_secret.storage_account_key.value}"
    }
  PROTECTED_SETTINGS
}
