#region onprem vnets and subnets
resource "azurerm_virtual_network" "this" {
  name                = "${module.naming.virtual_network.name}-${var.vnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  dns_servers         = [cidrhost(var.subnet_adds_address_prefix, 4), "168.63.129.16"]
}

resource "azurerm_subnet" "subnets" {
  for_each                        = local.subnets
  name                            = each.key
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [each.value.address_prefix]
  default_outbound_access_enabled = false
}
#endregion

#region onprem VPN Gateway
resource "azurerm_virtual_network_gateway" "this" {
  name                       = module.naming.virtual_network_gateway.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  type                       = "Vpn"
  vpn_type                   = "RouteBased"
  active_active              = false
  enable_bgp                 = true
  sku                        = "VpnGw1"
  generation                 = "Generation1"
  private_ip_address_enabled = false

  depends_on = [ azurerm_subnet.subnets ]

  ip_configuration {
    name                          = "Primary"
    subnet_id                     = azurerm_subnet.subnets["GatewaySubnet"].id
    public_ip_address_id          = azurerm_public_ip.vpn.id
    private_ip_address_allocation = "Dynamic"
  }

  bgp_settings {
    asn = var.vnet_asn
  }
}

resource "azurerm_public_ip" "vpn" {
  name                = "${module.naming.public_ip.name}-vpn"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_local_network_gateway" "this" {
  name                = module.naming.local_network_gateway.name
  resource_group_name = var.resource_group_name
  location            = var.location
  gateway_address     = tolist(azurerm_vpn_gateway.this.bgp_settings[0].instance_0_bgp_peering_address[0].tunnel_ips)[1]

  depends_on = [ azurerm_subnet.subnets ]

  bgp_settings {
    asn                 = azurerm_vpn_gateway.this.bgp_settings[0].asn
    bgp_peering_address = tolist(azurerm_vpn_gateway.this.bgp_settings[0].instance_0_bgp_peering_address[0].default_ips)[0]
  }
}

resource "azurerm_virtual_network_gateway_connection" "this" {
  name                       = module.naming.virtual_network_gateway_connection.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  virtual_network_gateway_id = azurerm_virtual_network_gateway.this.id
  local_network_gateway_id   = azurerm_local_network_gateway.this.id
  type                       = "IPsec"
  connection_protocol        = "IKEv2"
  enable_bgp                 = true
  shared_key                 = var.admin_password

  depends_on = [ azurerm_subnet.subnets ]
}
#endregion

#region onprem NAT gateway
resource "azurerm_nat_gateway" "this" {
  name                = module.naming.nat_gateway.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
}

resource "azurerm_public_ip" "nat" {
  name                = "${module.naming.public_ip.name}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "associations" {
  for_each = {
    for k, v in local.subnets : k => azurerm_subnet.subnets[k]
    if v.associate_nat_gateway
  }
  subnet_id      = each.value.id
  nat_gateway_id = azurerm_nat_gateway.this.id

  depends_on = [azurerm_local_network_gateway.this]
}
#endregion

#region onprem nics
resource "azurerm_network_interface" "vm_adds" {
  name                = "${module.naming.network_interface.name}-${var.vm_adds_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "Primary"
    subnet_id                     = azurerm_subnet.subnets["snet-adds-02"].id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [azurerm_subnet_nat_gateway_association.associations]
}

resource "azurerm_network_interface" "vm_jumpbox_win" {
  name                = "${module.naming.network_interface.name}-${var.vm_jumpbox_win_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "Primary"
    subnet_id                     = azurerm_subnet.subnets["snet-misc-04"].id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [azurerm_subnet_nat_gateway_association.associations]
}
#endregion

#region cloud VPN Gateway
resource "azurerm_vpn_gateway" "this" {
  name                = "${module.naming.virtual_wan.name}-vpn"
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_hub_id      = var.vwan_hub_id
}

resource "azurerm_vpn_site" "this" {
  name                = "${module.naming.virtual_wan.name}-site"
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_wan_id      = var.vwan_id

  link {
    name       = "onprem"
    ip_address = azurerm_virtual_network_gateway.this.bgp_settings[0].peering_addresses[0].tunnel_ip_addresses[0]
    bgp {
      asn             = var.vnet_asn
      peering_address = azurerm_virtual_network_gateway.this.bgp_settings[0].peering_addresses[0].default_addresses[0]
    }
  }
}

resource "azurerm_vpn_gateway_connection" "this" {
  name               = "cloud-to-onprem"
  vpn_gateway_id     = azurerm_vpn_gateway.this.id
  remote_vpn_site_id = azurerm_vpn_site.this.id

  vpn_link {
    name             = "onprem"
    vpn_site_link_id = azurerm_vpn_site.this.link[0].id
    bgp_enabled      = true
    protocol         = "IKEv2"
    shared_key       = var.admin_password
  }
}
#endregion

#region cloud dns private resolver
resource "azurerm_private_dns_resolver" "this" {
  name                = "pdnsr-${var.tags["project"]}-${var.tags["environment"]}"
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_network_id  = var.virtual_networks_cloud["virtual_network_shared"].id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "this" {
  name                    = "pdnsri-${var.tags["project"]}-${var.tags["environment"]}"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = var.subnets_cloud["snet-misc-01"].id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "this" {
  name                    = "pdnsro-${var.tags["project"]}-${var.tags["environment"]}"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location
  subnet_id               = var.subnets_cloud["snet-misc-02"].id
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "this" {
  name                                       = "rset-${var.tags["project"]}-${var.tags["environment"]}"
  resource_group_name                        = var.resource_group_name
  location                                   = var.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.this.id]
}

resource "azurerm_private_dns_resolver_forwarding_rule" "rule_onprem" {
  name                      = "rule-onprem"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  domain_name               = "${var.adds_domain_name}."
  enabled                   = true
  target_dns_servers {
    ip_address = cidrhost(var.subnet_adds_address_prefix, 4)
    port       = 53
  }
}

resource "azurerm_private_dns_resolver_forwarding_rule" "rule_cloud" {
  name                      = "rule-cloud"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  domain_name               = "${var.adds_domain_name_cloud}."
  enabled                   = true
  target_dns_servers {
    ip_address = var.dns_server_cloud
    port       = 53
  }
}

resource "azurerm_private_dns_resolver_virtual_network_link" "vnet_shared" {
  name                      = "link-${var.virtual_networks_cloud["virtual_network_shared"].name}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  virtual_network_id        = var.virtual_networks_cloud["virtual_network_shared"].id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "vnet_app" {
  name                      = "link-${var.virtual_networks_cloud["virtual_network_app"].name}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  virtual_network_id        = var.virtual_networks_cloud["virtual_network_app"].id
}
#endregion
