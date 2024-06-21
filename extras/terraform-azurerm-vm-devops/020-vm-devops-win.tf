locals {
  vm_devops_win_names                    = formatlist("${var.vm_devops_win_name}%03d", range(var.vm_devops_win_instances_start, (var.vm_devops_win_instances_start + var.vm_devops_win_instances)))
  vm_devops_win_config_script_uri        = "https://${var.storage_account_name}.blob.core.windows.net/${var.storage_container_name}/${var.vm_devops_win_config_script}"
  vm_devops_win_data_disk_count          = var.vm_devops_win_data_disk_size_gb == 0 ? 0 : 1
  automation_account_resource_group_name = split("/", var.automation_account_id)[4]
  automation_account_name                = split("/", var.automation_account_id)[8]
}

resource "azurerm_windows_virtual_machine" "vm_devops_win" {
  for_each                   = toset(local.vm_devops_win_names)
  name                       = each.key
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_devops_win_size
  admin_username             = data.azurerm_key_vault_secret.adminuser.value
  admin_password             = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids      = [azurerm_network_interface.vm_devops_win[each.key].id]
  encryption_at_host_enabled = true
  enable_automatic_updates   = true
  patch_mode                 = var.vm_devops_win_patch_mode
  license_type               = var.vm_devops_win_license_type
  tags                       = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_devops_win_storage_account_type
    disk_size_gb         = var.vm_devops_win_os_disk_size_gb
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
          TenantId              = "${var.aad_tenant_id}"
          SubscriptionId        = "${var.subscription_id}"
          ResourceGroupName     = "${var.resource_group_name}"
          Location              = "${var.location}"
          AutomationAccountId   = "${var.automation_account_id}"
          VirtualMachineName    = "${each.key}"
          AppId                 = "${var.arm_client_id}"
          AppSecret             = "${var.arm_client_secret}"
          DscConfigurationName  = "${var.vm_devops_win_dsc_config}"
        }
        ${path.root}/aadsc-register-node.ps1 @params 
   EOT
    interpreter = ["pwsh", "-Command"]
  }
}

# Nic
resource "azurerm_network_interface" "vm_devops_win" {
  for_each            = toset(local.vm_devops_win_names)
  name                = "nic-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipc-${each.key}"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

# Data disk
resource "azurerm_managed_disk" "vm_devops_win" {
  for_each             = local.vm_devops_win_data_disk_count == 1 ? azurerm_windows_virtual_machine.vm_devops_win : {}
  name                 = "datadisk-${each.value.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = var.vm_devops_win_storage_account_type
  create_option        = "Empty"
  disk_size_gb         = var.vm_devops_win_data_disk_size_gb
}

resource "azurerm_virtual_machine_data_disk_attachment" "vm_devops_win" {
  for_each           = local.vm_devops_win_data_disk_count == 1 ? azurerm_windows_virtual_machine.vm_devops_win : {}
  managed_disk_id    = azurerm_managed_disk.vm_devops_win[each.value.name].id
  virtual_machine_id = each.value.id
  lun                = 0
  caching            = "ReadWrite"
}

# Custom script extension
resource "azurerm_virtual_machine_extension" "vm_devops_win" {
  for_each                   = azurerm_windows_virtual_machine.vm_devops_win
  name                       = "vmext-${each.value.name}"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_data_disk_attachment.vm_devops_win]

  settings = <<SETTINGS
    {
      "fileUris": [ 
        "${local.vm_devops_win_config_script_uri}" 
      ],
      "commandToExecute": 
        "powershell.exe -ExecutionPolicy Unrestricted -File \"./${var.vm_devops_win_config_script}\""
    }    
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "storageAccountName": "${var.storage_account_name}",
      "storageAccountKey": "${data.azurerm_key_vault_secret.storage_account_key.value}"
    }
  PROTECTED_SETTINGS
}
