locals {
  subnets = {
    GatewaySubnet = {
      address_prefix                            = var.subnet_GatewaySubnet_address_prefix
    }

    snet-adds-02 = {
      address_prefix                            = var.subnet_adds_address_prefix
    }

    snet-misc-03 = {
      address_prefix                            = var.subnet_misc_address_prefix
    }
  }
}

# Shared services virtual network and subnets
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

resource "azurerm_subnet" "vnet_shared_02_subnets" {
  for_each                                  = local.subnets
  name                                      = each.key
  resource_group_name                       = var.resource_group_name
  virtual_network_name                      = azurerm_virtual_network.vnet_shared_02.name
  address_prefixes                          = [each.value.address_prefix]
}

output "vnet_shared_02_subnets" {
  value = azurerm_subnet.vnet_shared_02_subnets
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
    subnet_id                     = azurerm_subnet.vnet_shared_02_subnets["GatewaySubnet"].id
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
