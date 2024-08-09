data "cloudinit_config" "vm_jumpbox_linux" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = file("${path.root}/onfigure-vm-jumpbox-linux.yaml")
    filename     = "cloud-init.yaml"
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.root}/install-pyjwt.sh")
    filename     = "install-pyjwt.sh"
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.root}/configure-powershell.ps1")
    filename     = "configure-powershell.ps1"
  }
}

# Linux virtual machine
resource "azurerm_linux_virtual_machine" "vm_jumpbox_linux" {
  name                       = var.vm_name
  resource_group_name        = azurerm_network_interface.vm_jumpbox_linux_nic_01.resource_group_name
  location                   = azurerm_network_interface.vm_jumpbox_linux_nic_01.location
  size                       = var.vm_size
  admin_username             = data.azurerm_key_vault_secret.adminuser.value
  network_interface_ids      = [azurerm_network_interface.vm_jumpbox_linux_nic_01.id]
  encryption_at_host_enabled = true
  patch_assessment_mode      = "AutomaticByPlatform"
  provision_vm_agent         = true
  tags                       = merge(var.tags, { keyvault = var.key_vault_name })

  admin_ssh_key {
    username   = data.azurerm_key_vault_secret.adminuser.value
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_storage_account_type
  }

  source_image_reference {
    publisher = var.vm_image_publisher
    offer     = var.vm_image_offer
    sku       = var.vm_image_sku
    version   = var.vm_image_version
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = data.cloudinit_config.vm_jumpbox_linux.rendered
}

# Nics
resource "azurerm_network_interface" "vm_jumpbox_linux_nic_01" {
  name                = "nic-${var.vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipc-${var.vm_name}"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_key_vault_access_policy" "vm_jumpbox_linux_secrets_reader" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_linux_virtual_machine.vm_jumpbox_linux.identity[0].tenant_id
  object_id    = azurerm_linux_virtual_machine.vm_jumpbox_linux.identity[0].principal_id

  secret_permissions = [
    "Get"
  ]
}
