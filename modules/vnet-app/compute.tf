# #region windows-virtual-machine
resource "azurerm_windows_virtual_machine" "this" {
  name                       = var.vm_jumpbox_win_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  size                       = var.vm_jumpbox_win_size
  admin_username             = data.azurerm_key_vault_secret.adminuser.value
  admin_password             = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids      = [azurerm_network_interface.vm_windows.id]
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

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.vnet_app_links]

#   provisioner "local-exec" {
#     command     = <<EOT
#         $params = @{
#           TenantId = "${data.azurerm_client_config.current.tenant_id}"
#           SubscriptionId = "${data.azurerm_client_config.current.subscription_id}"
#           ResourceGroupName = "${var.resource_group_name}"
#           Location = "${var.location}"
#           AutomationAccountName = "${var.automation_account_name}"
#           VirtualMachineName = "${var.vm_jumpbox_win_name}"
#           AppId = "${data.azurerm_client_config.current.client_id}"
#           AppSecret = "${data.azurerm_key_vault_secret.arm_client_secret.value}"
#           DscConfigurationName = "JumpBoxConfig"
#         }
#         ${module.root}/scripts/aadsc-register-node.ps1 @params 
#    EOT
#     interpreter = ["pwsh", "-Command"]
#   }
}

resource "azurerm_role_assignment" "vm_windows_roles" {
  for_each = local.vm_windows_roles

  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  role_definition_name = each.value.role_definition_name
  scope                = each.value.scope
}

# # Virtual machine extensions
# resource "azurerm_virtual_machine_extension" "vm_jumpbox_win_postdeploy_script" {
#   name                       = "vmext-${azurerm_windows_virtual_machine.vm_jumpbox_win.name}-postdeploy-script"
#   virtual_machine_id         = azurerm_windows_virtual_machine.vm_jumpbox_win.id
#   publisher                  = "Microsoft.Compute"
#   type                       = "CustomScriptExtension"
#   type_handler_version       = "1.10"
#   auto_upgrade_minor_version = true
#   depends_on                 = [time_sleep.vm_jumpbox_win_role_assignments]

#   settings = jsonencode({
#     fileUris = [
#       var.vm_jumpbox_win_post_deploy_script_uri,
#       var.vm_jumpbox_win_configure_storage_script_uri
#     ]
#   })

#   protected_settings = jsonencode({
#     commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -Command \"${join("", local.commandParamParts)}; .\\${var.vm_jumpbox_win_post_deploy_script} @params\""
#     managedIdentity  = {}
#   })
# }
#endregion 

# #region jumplinux1
# resource "azurerm_linux_virtual_machine" "vm_jumpbox_linux" {
#   name                       = var.vm_jumpbox_linux_name
#   resource_group_name        = var.resource_group_name
#   location                   = var.location
#   size                       = var.vm_jumpbox_linux_size
#   admin_username             = "${data.azurerm_key_vault_secret.adminuser.value}local"
#   network_interface_ids      = [azurerm_network_interface.vm_jumbox_linux_nic_01.id]
#   encryption_at_host_enabled = true
#   patch_assessment_mode      = "AutomaticByPlatform"
#   provision_vm_agent         = true
#   depends_on                 = [azurerm_virtual_machine_extension.vm_jumpbox_win_postdeploy_script]
#   tags                       = var.tags

#   admin_ssh_key {
#     username   = "${data.azurerm_key_vault_secret.adminuser.value}local"
#     public_key = var.ssh_public_key
#   }

#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = var.vm_jumpbox_linux_storage_account_type
#   }

#   source_image_reference {
#     publisher = var.vm_jumpbox_linux_image_publisher
#     offer     = var.vm_jumpbox_linux_image_offer
#     sku       = var.vm_jumpbox_linux_image_sku
#     version   = var.vm_jumpbox_linux_image_version
#   }

#   identity {
#     type = "SystemAssigned"
#   }

#   custom_data = data.cloudinit_config.vm_jumpbox_linux.rendered
# }

# # Nics
# resource "azurerm_network_interface" "vm_jumbox_linux_nic_01" {
#   name                = "nic-${var.vm_jumpbox_linux_name}"
#   location            = var.location
#   resource_group_name = var.resource_group_name
#   tags                = var.tags

#   ip_configuration {
#     name                          = "ipc-${var.vm_jumpbox_linux_name}"
#     subnet_id                     = azurerm_subnet.vnet_app_01_subnets["snet-app-01"].id
#     private_ip_address_allocation = "Dynamic"
#   }

#   depends_on = [
#     azurerm_virtual_network_peering.vnet_app_01_to_vnet_shared_01_peering,
#     azurerm_virtual_network_peering.vnet_shared_01_to_vnet_app_01_peering
#   ]
# }

# # Role assignment for key vault
# resource "azurerm_role_assignment" "vm_jumpbox_linux_key_vault_role_assignment" {
#   scope                = var.key_vault_id
#   role_definition_name = "Key Vault Secrets User"
#   principal_id         = azurerm_linux_virtual_machine.vm_jumpbox_linux.identity[0].principal_id
# }
# #endregion 

#region utility-resources
# resource "time_sleep" "wait_for_roles_vm_windows" {
#   create_duration = "2m"
#   depends_on = [ azurerm_role_assignment.vm_windows_roles ]
# }
#endregion