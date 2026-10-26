#region vnets-and-subnets
resource "azurerm_virtual_network" "this" {
  name                = module.naming.virtual_network.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_address_space]
  dns_servers         = ["168.63.129.16"]
}

resource "azurerm_subnet" "subnets" {
  for_each                          = local.subnets
  name                              = each.key
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [each.value.address_prefix]
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  default_outbound_access_enabled   = false

  lifecycle {
    ignore_changes = [delegation]
  }
}
#endregion

#region bastion
resource "azurerm_bastion_host" "this" {
  name                = module.naming.bastion_host.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  # The Standard SKU is required for native client support (tunneling_enabled), which the
  # 'az network bastion tunnel' / VS Code Remote-SSH workflow depends on, and to emit
  # BastionAuditLogs via a diagnostic setting; the Basic SKU supports neither. Standard also
  # requires an AzureBastionSubnet of /26 or larger (see subnet_bastion_address_prefix).
  sku               = "Standard"
  tunneling_enabled = true

  depends_on = [azurerm_subnet.subnets]

  ip_configuration {
    name                 = "Primary"
    subnet_id            = azurerm_subnet.subnets["AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  # Standard SKU Bastion provisioning routinely exceeds the azurerm provider's default 30m
  # create timeout, which aborts the apply with "context deadline exceeded" even though Azure
  # finishes creating the host. Extend the create/update/delete timeouts to accommodate it.
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# BastionAuditLogs record who connected to which VM, when, from where, and with which authentication type.
# log_analytics_destination_type is not set: BastionAuditLogs only writes to the resource-specific
# MicrosoftAzureBastionAuditLogs table, and setting it would cause a perpetual diff.
resource "azurerm_monitor_diagnostic_setting" "bastion" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_bastion_host.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "BastionAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_public_ip" "bastion" {
  name                = "${module.naming.public_ip.name}-bastion"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    # Azure injects ip_tags such as 'FirstPartyUsage' after creation; ip_tags forces replacement.
    ignore_changes = [ip_tags]
  }
}
#endregion

#region nsgs
resource "azurerm_network_security_group" "groups" {
  for_each = { for k, v in local.subnets : k => v if length(v.nsg_rules) > 0 }

  name                = "${module.naming.network_security_group.name}.${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

# Associating an NSG with AzureBastionSubnet before the Bastion host exists causes the Bastion
# deployment to fail, so every association waits for the Bastion host and the NSG rules.
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
  resource_group_name         = azurerm_resource_group.this.name
  source_address_prefix       = each.value.source_address_prefix
  source_port_range           = length(each.value.source_port_ranges) == 1 ? each.value.source_port_ranges[0] : null
  source_port_ranges          = length(each.value.source_port_ranges) > 1 ? each.value.source_port_ranges : null

  depends_on = [
    azurerm_network_security_group.groups
  ]
}
#endregion

#region private-dns-zones
resource "azurerm_private_dns_zone" "zones" {
  for_each = toset(local.private_dns_zones)

  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "zones" {
  for_each = azurerm_private_dns_zone.zones

  name                = "link-${each.value.name}-${azurerm_virtual_network.this.name}"
  private_dns_zone_id = each.value.id
  virtual_network_id  = azurerm_virtual_network.this.id
  resolution_policy   = "NxDomainRedirect" # Enables fallback to internet when a zone has no record for a name.
}

# Dependency signal consumed by the private endpoints, so they are not created until every private DNS zone
# virtual network link exists.
resource "terraform_data" "private_dns_zone_links_complete" {
  input = join(",", [for link in azurerm_private_dns_zone_virtual_network_link.zones : link.id])
}
#endregion

#region nat-gateway
resource "azurerm_nat_gateway" "this" {
  name                = module.naming.nat_gateway.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
}

resource "azurerm_public_ip" "this" {
  name                = "${module.naming.public_ip.name}-nat"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    # Azure injects ip_tags such as 'FirstPartyUsage' after creation. Since ip_tags forces
    # replacement, reconciling that drift would destroy and recreate the public IP on every
    # subsequent apply, which also forces replacement of the NAT gateway association below.
    ignore_changes = [ip_tags]
  }
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.this.id
}

resource "azurerm_subnet_nat_gateway_association" "devops" {
  subnet_id      = azurerm_subnet.subnets[var.subnet_devops_name].id
  nat_gateway_id = azurerm_nat_gateway.this.id

  depends_on = [azurerm_subnet_network_security_group_association.associations]
}
#endregion

#region private-endpoints
resource "azurerm_private_endpoint" "key_vault" {
  name                = "${module.naming.private_endpoint.name}-key-vault"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.subnets[var.subnet_privatelink_name].id
  tags                = var.tags

  private_service_connection {
    name                           = "key_vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.vaultcore.azure.net"].id]
  }

  depends_on = [terraform_data.private_dns_zone_links_complete]
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${module.naming.private_endpoint.name}-storage-blob"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.subnets[var.subnet_privatelink_name].id
  tags                = var.tags

  private_service_connection {
    name                           = "storage_blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.blob.core.windows.net"].id]
  }

  depends_on = [terraform_data.private_dns_zone_links_complete]
}

resource "azurerm_private_endpoint" "ampls" {
  name                = "${module.naming.private_endpoint.name}-ampls"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.subnets[var.subnet_privatelink_name].id
  tags                = var.tags

  private_service_connection {
    name                           = "ampls"
    private_connection_resource_id = azurerm_monitor_private_link_scope.this.id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [for zone in local.ampls_private_dns_zones : azurerm_private_dns_zone.zones[zone].id]
  }

  # Creating the private endpoint updates the AMPLS. If the scoped services or the jumplinux2 data collection
  # associations on the DCE are still being written, Azure returns 409 AnotherOperationInProgress, so these
  # writes are serialized.
  depends_on = [
    azurerm_monitor_private_link_scoped_service.dce,
    azurerm_monitor_private_link_scoped_service.log_analytics,
    module.vm_jumpbox_linux,
    terraform_data.private_dns_zone_links_complete,
  ]
}
#endregion
