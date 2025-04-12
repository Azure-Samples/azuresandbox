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
      route_table = "firewall"
    }

    snet-misc-01 = {
      address_prefix                    = var.subnet_misc_address_prefix
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall"
    }

    snet-misc-02 = {
      address_prefix                    = var.subnet_misc_02_address_prefix
      private_endpoint_network_policies = "Disabled"
      nsgrules = [
        "AllowVirtualNetworkInbound",
        "AllowVirtualNetworkOutbound",
        "AllowInternetOutbound"
      ]
      route_table = "firewall"
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
