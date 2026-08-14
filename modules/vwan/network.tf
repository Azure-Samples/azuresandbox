resource "azurerm_virtual_wan" "this" {
  name                = module.naming.virtual_wan.name
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_virtual_hub" "this" {
  name                = "${module.naming.virtual_wan.name}-hub"
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_wan_id      = azurerm_virtual_wan.this.id
  address_prefix      = var.vwan_hub_address_prefix
}

resource "azurerm_virtual_hub_connection" "connections" {
  for_each = var.virtual_networks

  name                      = each.key
  virtual_hub_id            = azurerm_virtual_hub.this.id
  remote_virtual_network_id = each.value
}

resource "azurerm_point_to_site_vpn_gateway" "this" {
  name                        = module.naming.point_to_site_vpn_gateway.name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  virtual_hub_id              = azurerm_virtual_hub.this.id
  vpn_server_configuration_id = azurerm_vpn_server_configuration.this.id
  scale_unit                  = 1
  dns_servers                 = [var.dns_server, "168.63.129.16"]

  connection_configuration {
    name = "Clients"

    vpn_client_address_pool {
      address_prefixes = [var.client_address_pool]
    }
  }
}

# Routes point-to-site VPN gateway diagnostic logs and metrics to the shared Log Analytics
# workspace owned by the vnet-shared module. Only the p2svpngateways resource type emits
# resource logs in this module; the virtual WAN and hub expose platform metrics only.
resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_point_to_site_vpn_gateway.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "GatewayDiagnosticLog"
  }

  enabled_log {
    category = "IKEDiagnosticLog"
  }

  enabled_log {
    category = "P2SDiagnosticLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_vpn_server_configuration" "this" {
  name                     = "${module.naming.point_to_site_vpn_gateway.name}-server-config"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  vpn_authentication_types = ["Certificate"]

  client_root_certificate {
    name             = "Self signed certificate"
    public_cert_data = local.public_cert_data
  }
}

