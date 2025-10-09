#region virtual-network
resource "azurerm_virtual_network" "this" {
  name                = "${module.naming.virtual_network.name}-${var.vnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  dns_servers         = [cidrhost(var.subnet_adds_address_prefix, 4), "168.63.129.16"]
}

resource "azurerm_subnet" "subnets" {
  for_each                          = local.subnets
  name                              = each.key
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [each.value.address_prefix]
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  default_outbound_access_enabled   = false

  lifecycle {
    ignore_changes = [delegation]
  }
}

resource "azurerm_network_security_group" "groups" {
  for_each = { for k, v in local.subnets : k => v if length(v.nsg_rules) > 0 }

  name                = "${module.naming.network_security_group.name}.${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet_network_security_group_association" "associations" {
  for_each = azurerm_network_security_group.groups

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.groups[each.key].id

  depends_on = [
    azurerm_network_security_rule.rules,
    azurerm_bastion_host.this
  ]
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
#endregion

#region bastion
resource "azurerm_bastion_host" "this" {
  name                = module.naming.bastion_host.name
  location            = var.location
  resource_group_name = var.resource_group_name
  depends_on          = [azurerm_subnet.subnets]

  ip_configuration {
    name                 = "Primary"
    subnet_id            = azurerm_subnet.subnets["AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

resource "azurerm_public_ip" "bastion" {
  name                = "${module.naming.public_ip.name}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}
#endregion

#region firewall
resource "azurerm_firewall" "this" {
  name                = module.naming.firewall.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.this.id

  ip_configuration {
    name                 = "Primary"
    subnet_id            = azurerm_subnet.subnets["AzureFirewallSubnet"].id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

resource "azurerm_firewall_policy" "this" {
  name                     = module.naming.firewall_policy.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = "Standard"
  threat_intelligence_mode = "Deny"
}

resource "azurerm_firewall_policy_rule_collection_group" "this" {
  name               = module.naming.firewall_policy_rule_collection_group.name
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 500
  network_rule_collection {
    name     = "AllowOutboundInternet"
    priority = 400
    action   = "Allow"

    rule {
      name                  = "AllowAllOutbound"
      source_addresses      = ["*"]
      destination_addresses = ["0.0.0.0/0"]
      destination_ports     = ["80", "443", "1688"]
      protocols             = ["Any"]
    }
  }
}

resource "azurerm_route_table" "this" {
  name                = module.naming.route_table.name
  resource_group_name = var.resource_group_name
  location            = var.location

  route {
    name                   = "route-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.this.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "associations" {
  for_each = {
    for subnet_key, subnet in local.subnets : subnet_key => subnet if subnet.route_table == "firewall"
  }

  subnet_id      = azurerm_subnet.subnets[each.key].id
  route_table_id = azurerm_route_table.this.id

  depends_on = [azurerm_subnet_network_security_group_association.associations]
}

resource "azurerm_public_ip" "firewall" {
  name                = "${module.naming.public_ip.name}-firewall"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}
#endregion

#region private-endpoints
resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "link-${azurerm_private_dns_zone.this.name}-${azurerm_virtual_network.this.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

resource "azurerm_private_endpoint" "this" {
  name                = "${module.naming.private_endpoint.name}-key-vault"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = azurerm_subnet.subnets["snet-privatelink-02"].id
  depends_on          = [azapi_update_resource.key_vault_disable_public_access]

  private_service_connection {
    name                           = "key_vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this.id]
  }
}
#endregion

#region network-interfaces
resource "azurerm_network_interface" "this" {
  name                = "${module.naming.network_interface.name}-${var.vm_adds_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  depends_on          = [azurerm_subnet_route_table_association.associations]

  ip_configuration {
    name                          = "Primary"
    subnet_id                     = azurerm_subnet.subnets["snet-adds-01"].id
    private_ip_address_allocation = "Dynamic"
  }
}
#endregion
