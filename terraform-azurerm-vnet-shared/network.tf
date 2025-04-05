# Shared services virtual network, subnets and network security groups
resource "azurerm_virtual_network" "vnet_shared_01" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  dns_servers         = [var.dns_server, "168.63.129.16"]
  tags                = var.tags
}

resource "azurerm_subnet" "vnet_shared_01_subnets" {
  for_each                          = local.subnets
  name                              = each.key
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet_shared_01.name
  address_prefixes                  = [each.value.address_prefix]
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  default_outbound_access_enabled   = false
}

resource "azurerm_network_security_group" "network_security_groups" {
  for_each = { for k, v in local.subnets : k => v if length(v.nsgrules) > 0 }

  name                = "nsg-${var.vnet_name}.${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "nsg_subnet_associations" {
  for_each = azurerm_network_security_group.network_security_groups

  subnet_id                 = azurerm_subnet.vnet_shared_01_subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.network_security_groups[each.key].id

  depends_on = [
    azurerm_subnet.vnet_shared_01_subnets,
    azurerm_bastion_host.bastion_host_01
  ]
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

# Bastion
resource "azurerm_bastion_host" "bastion_host_01" {
  name                = "bst-${var.random_id}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  depends_on          = [azurerm_subnet.vnet_shared_01_subnets]

  ip_configuration {
    name                 = "bst-${var.random_id}"
    subnet_id            = azurerm_subnet.vnet_shared_01_subnets["AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.bastion_host_01.id
  }
}

resource "azurerm_public_ip" "bastion_host_01" {
  name                = "pip-${var.random_id}-1"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Firewall
resource "azurerm_firewall" "firewall_01" {
  name                = "fw-${var.random_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.firewall_01.id

  ip_configuration {
    name                 = "fw-${var.random_id}"
    subnet_id            = azurerm_subnet.vnet_shared_01_subnets["AzureFirewallSubnet"].id
    public_ip_address_id = azurerm_public_ip.firewall_01.id
  }
}

resource "azurerm_firewall_policy" "firewall_01" {
  name                     = "fwp-${var.random_id}-1"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = "Standard"
  threat_intelligence_mode = "Deny"
}

resource "azurerm_firewall_policy_rule_collection_group" "firewall_01" {
  name               = "fwr-${var.random_id}-1"
  firewall_policy_id = azurerm_firewall_policy.firewall_01.id
  priority           = 500
  network_rule_collection {
    name     = "AllowOutboundInternet"
    priority = 400
    action   = "Allow"

    rule {
      name                  = "AllowAllOutbound"
      source_addresses      = ["*"]
      destination_addresses = ["0.0.0.0/0"]
      destination_ports     = ["80", "443","1688"]
      protocols             = ["Any"]
    }
  }
}

resource "azurerm_route_table" "firewall_01" {
  name                = "rt-${var.random_id}"
  resource_group_name = var.resource_group_name
  location            = var.location

  route {
    name                   = "route-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.firewall_01.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "firewall_01" {
  for_each = {
    for subnet_key, subnet in local.subnets : subnet_key => subnet if subnet.route_table == "firewall_01"
  }

  subnet_id      = azurerm_subnet.vnet_shared_01_subnets[each.key].id
  route_table_id = azurerm_route_table.firewall_01.id

  depends_on = [ azurerm_subnet_network_security_group_association.nsg_subnet_associations ]
}

resource "azurerm_public_ip" "firewall_01" {
  name                = "pip-${var.random_id}-2"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}
