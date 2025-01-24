locals {
  subnets = {
    AzureBastionSubnet = {
      address_prefix                    = var.subnet_AzureBastionSubnet_address_prefix
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowHttpsInbound",
        "AllowGatewayManagerInbound",
        "AllowAzureLoadBalancerInbound",
        "AllowBastionCommunicationInbound",
        "AllowSshRdpOutbound",
        "AllowAzureCloudOutbound",
        "AllowBastionCommunicationOutbound",
        "AllowGetSessionInformationOutbound"
      ]
      route_table = null
    }

    snet-adds-01 = {
      address_prefix                    = var.subnet_adds_address_prefix
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall_01"
    }

    snet-misc-01 = {
      address_prefix                    = var.subnet_misc_address_prefix
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall_01"
    }

    snet-misc-02 = {
      address_prefix                    = var.subnet_misc_02_address_prefix
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall_01"
    }

    AzureFirewallSubnet = {
      address_prefix                    = var.subnet_AzureFirewallSubnet_address_prefix
      private_endpoint_network_policies = "Disabled"
      nsgrules                          = []
      route_table                       = null
    }
  }

  nsgrules = {
    AllowAzureCloudOutbound = {
      access                     = "Allow"
      destination_address_prefix = "AzureCloud"
      destination_port_ranges    = ["443"]
      direction                  = "Outbound"
      protocol                   = "Tcp"
      source_address_prefix      = "*"
      source_port_ranges         = ["*"]
    }

    AllowAzureLoadBalancerInbound = {
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_ranges    = ["443"]
      direction                  = "Inbound"
      protocol                   = "Tcp"
      source_address_prefix      = "AzureLoadBalancer"
      source_port_ranges         = ["*"]
    }

    AllowBastionCommunicationInbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["8080", "5701"]
      direction                  = "Inbound"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_ranges         = ["*"]
    }

    AllowBastionCommunicationOutbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["8080", "5701"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_ranges         = ["*"]
    }

    AllowGetSessionInformationOutbound = {
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_ranges    = ["80"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_ranges         = ["*"]
    }

    AllowGatewayManagerInbound = {
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_ranges    = ["443"]
      direction                  = "Inbound"
      protocol                   = "Tcp"
      source_address_prefix      = "GatewayManager"
      source_port_ranges         = ["*"]
    }

    AllowHttpsInbound = {
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_ranges    = ["443"]
      direction                  = "Inbound"
      protocol                   = "Tcp"
      source_address_prefix      = "Internet"
      source_port_ranges         = ["*"]
    }

    AllowInternetOutbound = {
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_ranges    = ["*"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_ranges         = ["*"]
    }

    AllowSshRdpOutbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["22", "3389"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_ranges         = ["*"]
    }

    AllowVirtualNetworkInbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["*"]
      direction                  = "Inbound"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_ranges         = ["*"]
    }

    AllowVirtualNetworkOutbound = {
      access                     = "Allow"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["*"]
      direction                  = "Outbound"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_ranges         = ["*"]
    }
  }

  network_security_group_rules = flatten([
    for subnet_key, subnet in local.subnets : [
      for nsgrule_key in subnet.nsgrules : {
        subnet_name                = subnet_key
        nsgrule_name               = nsgrule_key
        access                     = local.nsgrules[nsgrule_key].access
        destination_address_prefix = local.nsgrules[nsgrule_key].destination_address_prefix
        destination_port_ranges    = local.nsgrules[nsgrule_key].destination_port_ranges
        direction                  = local.nsgrules[nsgrule_key].direction
        priority                   = 100 + (index(subnet.nsgrules, nsgrule_key) * 10)
        protocol                   = local.nsgrules[nsgrule_key].protocol
        source_address_prefix      = local.nsgrules[nsgrule_key].source_address_prefix
        source_port_ranges         = local.nsgrules[nsgrule_key].source_port_ranges
      }
    ]
  ])
}

# Shared services virtual network, subnets and network security groups
resource "azurerm_virtual_network" "vnet_shared_01" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  dns_servers         = [var.dns_server, "168.63.129.16"]
  tags                = var.tags
}

output "vnet_shared_01_id" {
  value = azurerm_virtual_network.vnet_shared_01.id
}

output "vnet_shared_01_name" {
  value = azurerm_virtual_network.vnet_shared_01.name
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

output "vnet_shared_01_subnets" {
  value = azurerm_subnet.vnet_shared_01_subnets
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
resource "random_id" "bastion_host_01_name" {
  byte_length = 8
}

resource "azurerm_bastion_host" "bastion_host_01" {
  name                = "bst-${random_id.bastion_host_01_name.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  depends_on          = [azurerm_subnet.vnet_shared_01_subnets]

  ip_configuration {
    name                 = "ipc-${random_id.bastion_host_01_name.hex}"
    subnet_id            = azurerm_subnet.vnet_shared_01_subnets["AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.bastion_host_01.id
  }
}

resource "azurerm_public_ip" "bastion_host_01" {
  name                = "pip-${random_id.bastion_host_01_name.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Firewall
resource "random_id" "firewall_01" {
  byte_length = 8
}

resource "azurerm_firewall" "firewall_01" {
  name                = "fw-${random_id.firewall_01.hex}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.firewall_01.id

  ip_configuration {
    name                 = "fw-${random_id.firewall_01.hex}"
    subnet_id            = azurerm_subnet.vnet_shared_01_subnets["AzureFirewallSubnet"].id
    public_ip_address_id = azurerm_public_ip.firewall_01.id
  }
}

resource "azurerm_firewall_policy" "firewall_01" {
  name                     = "fwp-${random_id.firewall_01.hex}-1"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = "Standard"
  threat_intelligence_mode = "Deny"
}

resource "azurerm_firewall_policy_rule_collection_group" "firewall_01" {
  name               = "fwr-${random_id.firewall_01.hex}-1"
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
      destination_ports     = ["80", "443"]
      protocols             = ["Any"]
    }
  }
}

resource "azurerm_route_table" "firewall_01" {
  name                = "rt-${random_id.firewall_01.hex}"
  resource_group_name = var.resource_group_name
  location            = var.location

  route {
    name                   = "route-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.firewall_01.ip_configuration[0].private_ip_address
  }
}

output "firewall_01_route_table_id" {
  value = azurerm_route_table.firewall_01.id
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
  name                = "pip-${random_id.firewall_01.hex}-1"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}
