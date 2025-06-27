#region vnet
resource "azurerm_virtual_network" "this" {
  name                = "${module.naming.virtual_network.name}-${var.vnet_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_address_space]
  dns_servers         = ["168.63.129.16"]
}

resource "azurerm_subnet" "this" {
  name                            = var.subnet_name
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.subnet_address_prefix]
  default_outbound_access_enabled = false

  lifecycle {
    ignore_changes = [delegation]
  }
}

resource "azurerm_network_security_group" "this" {
  name                = "${module.naming.network_security_group.name}-${var.subnet_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}
#endregion

#region NAT gateway
resource "azurerm_nat_gateway" "this" {
  name                = module.naming.nat_gateway.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
}

resource "azurerm_public_ip" "this" {
  name                = "${module.naming.public_ip.name}-nat"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.this.id
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  subnet_id      = azurerm_subnet.this.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
#endregion
