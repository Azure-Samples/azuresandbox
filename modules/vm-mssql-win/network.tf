resource "azurerm_network_interface" "this" {
  name                = "${module.naming.network_interface.name}-${var.vm_mssql_win_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "Primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

