#region resources
resource "azurerm_network_interface" "personal" {
  name                           = "${module.naming.names["network_interface"].name}-${var.vm_name_personal}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

# Network Interface - RemoteApp
resource "azurerm_network_interface" "remoteapp" {
  name                           = "${module.naming.names["network_interface"].name}-${var.vm_name_remoteapp}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}
#endregion
