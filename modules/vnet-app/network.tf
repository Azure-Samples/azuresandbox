#region virtual-network
resource "azurerm_virtual_network" "this" {
  name                = "${module.naming.virtual_network.name}-${var.vnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  dns_servers         = [var.dns_server, "168.63.129.16"]
}

resource "azurerm_subnet" "subnets" {
  for_each                          = local.subnets
  name                              = each.key
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
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

  lifecycle {
    ignore_changes = [delegation[0].service_delegation[0].actions]
  }
}

resource "azurerm_network_security_group" "groups" {
  for_each = azurerm_subnet.subnets

  name                = "${module.naming.network_security_group.name}.${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_network_security_rule" "rules" {
  for_each = { for network_security_group_rule in local.network_security_group_rules : "${network_security_group_rule.subnet_name}.${network_security_group_rule.nsg_rule_name}" => network_security_group_rule }

  access                      = each.value.access
  destination_address_prefix  = each.value.destination_address_prefix
  destination_port_range      = length(each.value.destination_port_ranges) == 1 ? each.value.destination_port_ranges[0] : null
  destination_port_ranges     = length(each.value.destination_port_ranges) > 1 ? each.value.destination_port_ranges : null
  direction                   = each.value.direction
  name                        = each.value.nsg_rule_name
  network_security_group_name = "${module.naming.network_security_group.name}.${each.value.subnet_name}"
  priority                    = each.value.priority
  protocol                    = each.value.protocol
  resource_group_name         = var.resource_group_name
  source_address_prefix       = each.value.source_address_prefix
  source_port_range           = length(each.value.source_port_ranges) == 1 ? each.value.source_port_ranges[0] : null
  source_port_ranges          = length(each.value.source_port_ranges) > 1 ? each.value.source_port_ranges : null

  depends_on = [
    azurerm_network_security_group.groups
  ]
}

resource "azurerm_subnet_network_security_group_association" "associations" {
  for_each = azurerm_subnet.subnets

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.groups[each.key].id
}

# Peering with shared services virtual network
resource "azurerm_virtual_network_peering" "shared_to_app" {
  name                         = "${module.naming.virtual_network_peering.name}-shared-to-app"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = var.virtual_network_shared_name
  remote_virtual_network_id    = azurerm_virtual_network.this.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  depends_on                   = [azurerm_subnet_network_security_group_association.associations]
}

resource "azurerm_virtual_network_peering" "app_to_shared" {
  name                         = "${module.naming.virtual_network_peering.name}-app-to-shared"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = var.virtual_network_shared_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  depends_on                   = [azurerm_virtual_network_peering.shared_to_app]
}
#endregion

#region private-dns-zones
resource "azurerm_private_dns_zone" "zones" {
  for_each            = toset(local.private_dns_zones)
  name                = each.value
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_app_links" {
  for_each              = azurerm_private_dns_zone.zones
  name                  = "link-${each.value.name}-${azurerm_virtual_network.this.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.this.id
  depends_on            = [azurerm_virtual_network_peering.app_to_shared, azurerm_virtual_network_peering.shared_to_app]
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_shared_links" {
  for_each              = azurerm_private_dns_zone.zones
  name                  = "link-${each.value.name}-${var.virtual_network_shared_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = var.virtual_network_shared_id
  depends_on            = [azurerm_virtual_network_peering.app_to_shared, azurerm_virtual_network_peering.shared_to_app]
}
#endregion

#region route-tables
resource "azurerm_subnet_route_table_association" "associations" {
  for_each = { for subnet_key, subnet in local.subnets : subnet_key => subnet if subnet.route_table == "firewall" }

  subnet_id      = azurerm_subnet.subnets[each.key].id
  route_table_id = var.firewall_route_table_id
}
#endregion 

#region private-endpoints
resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${module.naming.private_endpoint.name}-storage-blob"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = azurerm_subnet.subnets["snet-privatelink-01"].id

  private_service_connection {
    name                           = "azure_blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  depends_on = [
    azurerm_virtual_network_peering.app_to_shared,
    azurerm_virtual_network_peering.shared_to_app,
    azapi_update_resource.storage_account_disable_public_access
  ]
}

resource "azurerm_private_dns_a_record" "storage_blob" {
  name                = azurerm_storage_account.this.name
  zone_name           = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage_blob.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_endpoint" "storage_file" {
  name                = "${module.naming.private_endpoint.name}-storage-file"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = azurerm_subnet.subnets["snet-privatelink-01"].id

  private_service_connection {
    name                           = "azure_files"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["file"]
  }

  depends_on = [
    azurerm_virtual_network_peering.app_to_shared,
    azurerm_virtual_network_peering.shared_to_app,
    azapi_update_resource.storage_account_disable_public_access
  ]
}

resource "azurerm_private_dns_a_record" "storage_file" {
  name                = azurerm_storage_account.this.name
  zone_name           = "privatelink.file.core.windows.net"
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage_file.private_service_connection[0].private_ip_address]
}
#endregion

#region network-interfaces
resource "azurerm_network_interface" "this" {
  name                = "${module.naming.network_interface.name}-${var.vm_jumpbox_win_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  depends_on = [
    azurerm_virtual_network_peering.app_to_shared,
    azurerm_virtual_network_peering.shared_to_app
  ]

  ip_configuration {
    name                          = "Primary"
    subnet_id                     = azurerm_subnet.subnets["snet-app-01"].id
    private_ip_address_allocation = "Dynamic"
  }
}
#endregion
