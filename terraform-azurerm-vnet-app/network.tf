#region virtual-network
resource "azurerm_virtual_network" "vnet_app_01" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  dns_servers         = [var.dns_server, "168.63.129.16"]
  tags                = var.tags
}

resource "azurerm_subnet" "vnet_app_01_subnets" {
  for_each                          = local.subnets
  name                              = each.key
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet_app_01.name
  address_prefixes                  = [each.value.address_prefix]
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  default_outbound_access_enabled   = false
  dynamic "delegation" {
    for_each = each.value.delegation != "" ? [each.value.delegation] : []
    content {
      name = "delegation"
      service_delegation {
        name = each.value.delegation
      }
    }
  }
}

resource "azurerm_network_security_group" "network_security_groups" {
  for_each = azurerm_subnet.vnet_app_01_subnets

  name                = "nsg-${var.vnet_name}.${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "nsg_subnet_associations" {
  for_each = azurerm_subnet.vnet_app_01_subnets

  subnet_id                 = azurerm_subnet.vnet_app_01_subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.network_security_groups[each.key].id
}

resource "azurerm_network_security_rule" "network_security_rules" {
  for_each = {
    for network_security_group_rule in local.network_security_group_rules : "${network_security_group_rule.subnet_name}.${network_security_group_rule.nsgrule_name}" => network_security_group_rule
  }

  access                      = each.value.access
  destination_address_prefix  = each.value.destination_address_prefix
  destination_port_range      = length(each.value.destination_port_ranges) == 1 ? each.value.destination_port_ranges[0] : null
  destination_port_ranges     = length(each.value.destination_port_ranges) > 1 ? each.value.destination_port_ranges : null
  direction                   = each.value.direction
  name                        = each.value.nsgrule_name
  network_security_group_name = "nsg-${var.vnet_name}.${each.value.subnet_name}"
  priority                    = each.value.priority
  protocol                    = each.value.protocol
  resource_group_name         = var.resource_group_name
  source_address_prefix       = each.value.source_address_prefix
  source_port_range           = length(each.value.source_port_ranges) == 1 ? each.value.source_port_ranges[0] : null
  source_port_ranges          = length(each.value.source_port_ranges) > 1 ? each.value.source_port_ranges : null

  depends_on = [
    azurerm_network_security_group.network_security_groups
  ]
}

# Peering with shared services virtual network
resource "azurerm_virtual_network_peering" "vnet_shared_01_to_vnet_app_01_peering" {
  name                         = "vnet_shared_01_to_vnet_app_01_peering"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = var.remote_virtual_network_name
  remote_virtual_network_id    = azurerm_virtual_network.vnet_app_01.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  depends_on                   = [azurerm_subnet_network_security_group_association.nsg_subnet_associations]
}

resource "azurerm_virtual_network_peering" "vnet_app_01_to_vnet_shared_01_peering" {
  name                         = "vnet_app_01_to_vnet_shared_01_peering"
  resource_group_name          = azurerm_virtual_network.vnet_app_01.resource_group_name
  virtual_network_name         = azurerm_virtual_network.vnet_app_01.name
  remote_virtual_network_id    = var.remote_virtual_network_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  depends_on                   = [azurerm_virtual_network_peering.vnet_shared_01_to_vnet_app_01_peering]
}
#endregion

#region private-dns-zones
resource "azurerm_private_dns_zone" "private_dns_zones" {
  for_each            = toset(local.private_dns_zones)
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "private_dns_zone_virtual_network_links_vnet_app_01" {
  for_each              = azurerm_private_dns_zone.private_dns_zones
  name                  = "pdnslnk-${each.value.name}-${azurerm_virtual_network.vnet_app_01.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.vnet_app_01.id
  tags                  = var.tags
  depends_on            = [azurerm_virtual_network_peering.vnet_app_01_to_vnet_shared_01_peering, azurerm_virtual_network_peering.vnet_shared_01_to_vnet_app_01_peering]
}

resource "azurerm_private_dns_zone_virtual_network_link" "private_dns_zone_virtual_network_links_vnet_shared_01" {
  for_each              = azurerm_private_dns_zone.private_dns_zones
  name                  = "pdnslnk-${each.value.name}-${var.remote_virtual_network_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = var.remote_virtual_network_id
  tags                  = var.tags
  depends_on            = [azurerm_virtual_network_peering.vnet_app_01_to_vnet_shared_01_peering, azurerm_virtual_network_peering.vnet_shared_01_to_vnet_app_01_peering]
}
#endregion

#region route-tables
resource "azurerm_subnet_route_table_association" "firewall_01" {
  for_each = {
    for subnet_key, subnet in local.subnets : subnet_key => subnet if subnet.route_table == "firewall_01"
  }

  subnet_id      = azurerm_subnet.vnet_app_01_subnets[each.key].id
  route_table_id = var.firewall_01_route_table_id
}
#endregion 
