# S2S VPN Gateway
resource "azurerm_vpn_gateway" "site_to_site_vpn_gateway_01" {
  name                = "site_to_site_vpn_gateway_01"
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_hub_id      = var.vwan_01_hub_01_id
}

resource "azurerm_vpn_site" "vpn_site_onprem" {
  name                = "onprem"
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_wan_id      = var.vwan_01_id

  link {
    name       = "link1"
    ip_address = azurerm_virtual_network_gateway.vnet_shared_02_gateway.bgp_settings[0].peering_addresses[0].tunnel_ip_addresses[0]
    bgp {
      asn             = var.vnet_asn
      peering_address = azurerm_virtual_network_gateway.vnet_shared_02_gateway.bgp_settings[0].peering_addresses[0].default_addresses[0]
    }
  }
}

resource "azurerm_vpn_gateway_connection" "cloud_to_onprem" {
  name               = "cloud-to-onprem"
  vpn_gateway_id     = azurerm_vpn_gateway.site_to_site_vpn_gateway_01.id
  remote_vpn_site_id = azurerm_vpn_site.vpn_site_onprem.id

  vpn_link {
    name             = "link1"
    vpn_site_link_id = azurerm_vpn_site.vpn_site_onprem.link[0].id
    bgp_enabled      = true
    protocol         = "IKEv2"
    shared_key       = data.azurerm_key_vault_secret.adminpassword.value
  }
}

# Private DNS Resolver
resource "random_id" "random_id_pdnsr_01_name" {
  byte_length = 8
}

resource "azurerm_private_dns_resolver" "pdnsr_01" {
  name                = "pdnsr-${random_id.random_id_pdnsr_01_name.hex}-01"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  virtual_network_id  = var.vnet_shared_01_id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "pdnsr_inbound_01" {
  name                    = "pdnsri-${azurerm_private_dns_resolver.pdnsr_01.name}"
  private_dns_resolver_id = azurerm_private_dns_resolver.pdnsr_01.id
  location                = var.location
  tags                    = var.tags

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = var.vnet_shared_01_subnets["snet-misc-01"].id
  }
}

output "pdnsr_inbound_01_private_ip_address" {
  value = azurerm_private_dns_resolver_inbound_endpoint.pdnsr_inbound_01.ip_configurations[0].private_ip_address
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "pdnsr_outbound_01" {
  name                    = "pdnsro-${azurerm_private_dns_resolver.pdnsr_01.name}"
  private_dns_resolver_id = azurerm_private_dns_resolver.pdnsr_01.id
  location                = var.location
  subnet_id               = var.vnet_shared_01_subnets["snet-misc-02"].id
  tags                    = var.tags
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "rset-pdnsr-01" {
  name                                       = "rset-${azurerm_private_dns_resolver.pdnsr_01.name}"
  resource_group_name                        = var.resource_group_name
  location                                   = var.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.pdnsr_outbound_01.id]
  tags                                       = var.tags
}

resource "azurerm_private_dns_resolver_forwarding_rule" "rule-onprem" {
  name                      = "rule-onprem"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01.id
  domain_name               = "${var.adds_domain_name}."
  enabled                   = true
  target_dns_servers {
    ip_address = var.dns_server
    port       = 53
  }
}

resource "azurerm_private_dns_resolver_forwarding_rule" "rule-cloud" {
  name                      = "rule-cloud"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01.id
  domain_name               = "${var.adds_domain_name_cloud}."
  enabled                   = true
  target_dns_servers {
    ip_address = var.dns_server_cloud
    port       = 53
  }
}

resource "azurerm_private_dns_resolver_virtual_network_link" "vnet_shared_01" {
  name                      = "link-${var.vnet_shared_01_name}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01.id
  virtual_network_id        = var.vnet_shared_01_id
}

resource "azurerm_private_dns_resolver_virtual_network_link" "vnet_app_01" {
  name                      = "link-${var.vnet_app_01_name}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.rset-pdnsr-01.id
  virtual_network_id        = var.vnet_app_01_id
}
