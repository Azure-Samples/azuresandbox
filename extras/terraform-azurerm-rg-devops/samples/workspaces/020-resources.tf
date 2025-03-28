resource "azurerm_resource_group" "resource_group_01" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet_spoke_01" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.resource_group_01.name
  address_space       = [var.vnet_address_space]
  dns_servers         = ["168.63.129.16"]
  tags = {
    costcenter = "IT"
  }
}
