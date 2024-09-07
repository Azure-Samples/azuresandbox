locals {
  commandParamParts = [
    "$params = @{",
    "TenantId = '${var.aad_tenant_id}'; ",
    "SubscriptionId = '${var.subscription_id}'; ",
    "AppId = '${var.arm_client_id}'; ",
    "ResourceGroupName = '${var.resource_group_name}'; ",
    "KeyVaultName = '${var.key_vault_name}'; ",
    "Domain = '${var.adds_domain_name}'; ",
    "AdminUsernameSecret = '${var.admin_username_secret}'; ",
    "AdminPwdSecret = '${var.admin_password_secret}'; ",
    "TempDiskSizeMb = '${var.temp_disk_size_mb}'; ",
    "}"
  ]
}

# Database server virtual machine
resource "azurerm_windows_virtual_machine" "vm_mssql_win" {
  name                       = var.vm_mssql_win_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_mssql_win_size
  admin_username             = data.azurerm_key_vault_secret.adminuser.value
  admin_password             = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids      = [azurerm_network_interface.vm_mssql_win_nic_01.id]
  encryption_at_host_enabled = true
  patch_assessment_mode      = "AutomaticByPlatform"
  provision_vm_agent         = true
  tags                       = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_mssql_win_storage_account_type
  }

  source_image_reference {
    publisher = var.vm_mssql_win_image_publisher
    offer     = var.vm_mssql_win_image_offer
    sku       = var.vm_mssql_win_image_sku
    version   = var.vm_mssql_win_image_version
  }

  identity {
    type = "SystemAssigned"
  }

  # Apply configuration using Azure Automation DSC
  # Note: To view provisioner output, use the Terraform nonsensitive() function when referencing key vault secrets or variables marked 'sensitive'
  provisioner "local-exec" {
    command     = <<EOT
        $params = @{
          TenantId                = "${var.aad_tenant_id}"
          SubscriptionId          = "${var.subscription_id}"
          ResourceGroupName       = "${var.resource_group_name}"
          Location                = "${var.location}"
          AutomationAccountName   = "${var.automation_account_name}"
          VirtualMachineName      = "${var.vm_mssql_win_name}"
          AppId                   = "${var.arm_client_id}"
          AppSecret               = "${nonsensitive(var.arm_client_secret)}"
          DscConfigurationName    = "MssqlVmConfig"
        }
        ${path.root}/aadsc-register-node.ps1 @params 
   EOT
    interpreter = ["pwsh", "-Command"]
  }
}

# Nics
resource "azurerm_network_interface" "vm_mssql_win_nic_01" {
  name                = "nic-${var.vm_mssql_win_name}-1"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipc-${var.vm_mssql_win_name}-1"
    subnet_id                     = var.vnet_app_01_subnets["snet-db-01"].id
    private_ip_address_allocation = "Dynamic"
  }
}

# Data disks
resource "azurerm_managed_disk" "vm_mssql_win_data_disks" {
  for_each = var.vm_mssql_win_data_disk_config

  name                 = "disk-${var.vm_mssql_win_name}-${each.value.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = var.vm_mssql_win_storage_account_type
  create_option        = "Empty"
  disk_size_gb         = each.value.disk_size_gb
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "vm_mssql_win_data_disk_attachments" {
  for_each = var.vm_mssql_win_data_disk_config

  managed_disk_id    = azurerm_managed_disk.vm_mssql_win_data_disks[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.vm_mssql_win.id
  lun                = each.value.lun
  caching            = each.value.caching
}

# Virtual machine extensions
resource "azurerm_virtual_machine_extension" "vm_mssql_win_postdeploy_script" {
  name                       = "vmext-${azurerm_windows_virtual_machine.vm_mssql_win.name}-postdeploy-script"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm_mssql_win.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.vm_mssql_win_data_disk_attachments,
    azurerm_key_vault_access_policy.vm_mssql_win_secrets_get
  ]

  protected_settings = <<PROTECTED_SETTINGS
    {
      "commandToExecute": 
        "powershell.exe -ExecutionPolicy Unrestricted -Command \"${join("", local.commandParamParts)}; .\\${var.vm_mssql_win_post_deploy_script} @params\"",
      "storageAccountName": "${var.storage_account_name}",
      "storageAccountKey": "${data.azurerm_key_vault_secret.storage_account_key.value}",
      "fileUris": [ 
        "${var.vm_mssql_win_post_deploy_script_uri}", 
        "${var.vm_mssql_win_configure_mssql_script_uri}",
        "${var.vm_mssql_win_sql_startup_script_uri}" 
      ]
    }
  PROTECTED_SETTINGS
}

resource "azurerm_key_vault_access_policy" "vm_mssql_win_secrets_get" {
  key_vault_id       = var.key_vault_id
  tenant_id          = azurerm_windows_virtual_machine.vm_mssql_win.identity[0].tenant_id
  object_id          = azurerm_windows_virtual_machine.vm_mssql_win.identity[0].principal_id
  secret_permissions = ["Get"]
}
