#region resources
resource "azurerm_network_interface" "nics" {
  for_each            = toset(local.vm_devops_win_names)
  name                = "${module.naming.network_interface.name}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "Primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}
#endregion
