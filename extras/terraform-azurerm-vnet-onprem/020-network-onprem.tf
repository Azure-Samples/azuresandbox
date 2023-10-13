locals {
  subnets = {
    AzureBastionSubnet = {
      address_prefix                            = var.subnet_AzureBastionSubnet_address_prefix
      private_endpoint_network_policies_enabled = false
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
    }

    snet-adds-02 = {
      address_prefix                            = var.subnet_adds_address_prefix
      private_endpoint_network_policies_enabled = false
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
    }

    snet-misc-03 = {
      address_prefix                            = var.subnet_misc_address_prefix
      private_endpoint_network_policies_enabled = false
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
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
resource "azurerm_virtual_network" "vnet_shared_02" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  dns_servers         = [var.dns_server, "168.63.129.16"]
  tags                = var.tags
}

output "vnet_shared_02_id" {
  value = azurerm_virtual_network.vnet_shared_02.id
}

output "vnet_shared_02_name" {
  value = azurerm_virtual_network.vnet_shared_02.name
}

resource "azurerm_subnet" "vnet_shared_02_GatewaySubnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_shared_02.name
  address_prefixes     = [var.subnet_GatewaySubnet_address_prefix]
}

resource "azurerm_subnet" "vnet_shared_02_subnets" {
  for_each                                  = local.subnets
  name                                      = each.key
  resource_group_name                       = var.resource_group_name
  virtual_network_name                      = azurerm_virtual_network.vnet_shared_02.name
  address_prefixes                          = [each.value.address_prefix]
  private_endpoint_network_policies_enabled = each.value.private_endpoint_network_policies_enabled

  depends_on = [azurerm_subnet.vnet_shared_02_GatewaySubnet]
}

output "vnet_shared_02_subnets" {
  value = azurerm_subnet.vnet_shared_02_subnets
}

resource "azurerm_network_security_group" "network_security_groups" {
  for_each = azurerm_subnet.vnet_shared_02_subnets

  name                = "nsg-${var.vnet_name}.${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "nsg_subnet_associations" {
  for_each = azurerm_subnet.vnet_shared_02_subnets

  subnet_id                 = azurerm_subnet.vnet_shared_02_subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.network_security_groups[each.key].id

  # Note: This depedency is a workaround for an issue that arises when existing NSG rules do not exactly match what Azure Bastion wants, even if the rules are correct.
  # The NSG rules in this configuration functionally match what is reccomended, however the name and priority of the rules are different.
  # See https://docs.microsoft.com/en-us/azure/bastion/bastion-nsg?msclkid=b12f8b18ac6e11ecb11e8f00c2bce23d for more information.
  depends_on = [azurerm_virtual_network_gateway_connection.onprem_to_cloud]
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
resource "random_id" "bastion_host_02_name" {
  byte_length = 8
}

resource "azurerm_bastion_host" "bastion_host_02" {
  name                = "bst-${random_id.bastion_host_02_name.hex}-2"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                 = "ipc-${random_id.bastion_host_02_name.hex}-1"
    subnet_id            = azurerm_subnet.vnet_shared_02_subnets["AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.bastion_host_02.id
  }
}

resource "random_id" "public_ip_bastion_host_02_name" {
  byte_length = 8
}

resource "azurerm_public_ip" "bastion_host_02" {
  name                = "pip-${random_id.public_ip_bastion_host_02_name.hex}-2"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Virtual Network Gateway

resource "azurerm_public_ip" "vnet_shared_02_gateway_ip" {
  name                = "pip-${var.vnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "vnet_shared_02_gateway" {
  name                       = "gw-${var.vnet_name}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  type                       = "Vpn"
  vpn_type                   = "RouteBased"
  active_active              = false
  enable_bgp                 = true
  sku                        = "VpnGw1"
  generation                 = "Generation1"
  private_ip_address_enabled = false
  tags                       = var.tags
  depends_on                 = [azurerm_subnet.vnet_shared_02_subnets]

  ip_configuration {
    name                          = "gw-${var.vnet_name}-ipconfig"
    subnet_id                     = azurerm_subnet.vnet_shared_02_GatewaySubnet.id
    public_ip_address_id          = azurerm_public_ip.vnet_shared_02_gateway_ip.id
    private_ip_address_allocation = "Dynamic"
  }

  bgp_settings {
    asn = var.vnet_asn
  }
}

resource "azurerm_local_network_gateway" "cloud_network" {
  name                = "lng-cloud"
  resource_group_name = var.resource_group_name
  location            = var.location
  gateway_address     = tolist(azurerm_vpn_gateway.site_to_site_vpn_gateway_01.bgp_settings[0].instance_0_bgp_peering_address[0].tunnel_ips)[1]

  bgp_settings {
    asn                 = azurerm_vpn_gateway.site_to_site_vpn_gateway_01.bgp_settings[0].asn
    bgp_peering_address = tolist(azurerm_vpn_gateway.site_to_site_vpn_gateway_01.bgp_settings[0].instance_0_bgp_peering_address[0].default_ips)[0]
  }
}

resource "azurerm_virtual_network_gateway_connection" "onprem_to_cloud" {
  name                       = "onprem-to-cloud"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vnet_shared_02_gateway.id
  local_network_gateway_id   = azurerm_local_network_gateway.cloud_network.id
  type                       = "IPsec"
  connection_protocol        = "IKEv2"
  enable_bgp                 = true
  shared_key                 = data.azurerm_key_vault_secret.adminpassword.value
}
