#region resources
resource "azurerm_network_interface" "this" {
  name                = "${module.naming.network_interface.name}-${var.vm_jumpbox_linux_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "Primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_access ? azurerm_public_ip.this[0].id : null
  }
}

resource "azurerm_public_ip" "this" {
  count               = var.enable_public_access ? 1 : 0
  name                = "${module.naming.public_ip.name}-${var.vm_jumpbox_linux_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}
#endregion
