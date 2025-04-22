#region resources
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

resource "azurerm_vpn_server_configuration" "this" {
  name                     = "${module.naming.point_to_site_vpn_gateway.name}-server-config"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  vpn_authentication_types = ["Certificate"]
  tags                     = var.tags

  client_root_certificate {
    name             = "Self signed certificate"
    public_cert_data = join("\n", slice(split("\n", trimspace(file("${path.root}/MyP2SVPNRootCert_Base64_Encoded.cer"))), 1, length(split("\n", trimspace(file("${path.root}/MyP2SVPNRootCert_Base64_Encoded.cer")))) - 1)) 
  }
}
#endregion

#region modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.2"
  suffix                 = [var.tags["project"], var.tags["environment"]]
}
#endregion
