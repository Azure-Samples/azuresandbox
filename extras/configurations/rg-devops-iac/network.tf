#region vnets-and-subnets
resource "azurerm_virtual_network" "this" {
  name                = "${module.naming.virtual_network.name}-${var.vnet_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_address_space]
  dns_servers         = ["168.63.129.16"]
}

resource "azurerm_subnet" "devops" {
  name                            = var.subnet_name
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.subnet_address_prefix]
  default_outbound_access_enabled = false

  lifecycle {
    ignore_changes = [delegation]
  }
}

resource "azurerm_subnet" "privatelink" {
  name                              = var.subnet_privatelink_name
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.subnet_privatelink_address_prefix]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}
#endregion

#region nsgs
resource "azurerm_network_security_group" "devops" {
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

resource "azurerm_subnet_network_security_group_association" "devops" {
  subnet_id                 = azurerm_subnet.devops.id
  network_security_group_id = azurerm_network_security_group.devops.id
}
#endregion

#region private-dns-zones
resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "link-${azurerm_private_dns_zone.key_vault.name}-${azurerm_virtual_network.this.name}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.this.id
}


resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                  = "link-${azurerm_private_dns_zone.storage_blob.name}-${azurerm_virtual_network.this.name}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
}
#endregion

#region nat-gateway
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

resource "azurerm_subnet_nat_gateway_association" "devops" {
  subnet_id      = azurerm_subnet.devops.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
#endregion

#region private-endpoints
resource "azurerm_private_endpoint" "key_vault" {
  name                = "${module.naming.private_endpoint.name}-key-vault"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "key_vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${module.naming.private_endpoint.name}-storage-blob"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "storage_blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }
}
#endregion
