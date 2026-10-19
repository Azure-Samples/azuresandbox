#region vnets-and-subnets
resource "azurerm_virtual_network" "this" {
  name                = "${module.naming.virtual_network.name}-${var.vnet_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_address_space]
  dns_servers         = ["168.63.129.16"]
}

resource "azurerm_monitor_diagnostic_setting" "virtual_network" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_subnet" "devops" {
  name                            = var.subnet_name
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.subnet_address_prefix]
  default_outbound_access_enabled = false

  lifecycle {
    ignore_changes = [delegation]
  }
}

resource "azurerm_subnet" "privatelink" {
  name                              = var.subnet_privatelink_name
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.subnet_privatelink_address_prefix]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet" # Name is fixed by Azure
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_bastion_address_prefix]
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

  ip_configuration {
    name                 = "Primary"
    subnet_id            = azurerm_subnet.bastion.id
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

resource "azurerm_monitor_diagnostic_setting" "public_ip_bastion" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_public_ip.bastion.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
#endregion

#region nsgs
resource "azurerm_network_security_group" "devops" {
  name                = "${module.naming.network_security_group.name}-${var.subnet_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22"]
    source_address_prefix      = var.subnet_bastion_address_prefix
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "devops" {
  subnet_id                 = azurerm_subnet.devops.id
  network_security_group_id = azurerm_network_security_group.devops.id
}

resource "azurerm_monitor_diagnostic_setting" "network_security_group_devops" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_network_security_group.devops.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }
}
#endregion

#region private-dns-zones
resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                = "link-${azurerm_private_dns_zone.key_vault.name}-${azurerm_virtual_network.this.name}"
  private_dns_zone_id = azurerm_private_dns_zone.key_vault.id
  virtual_network_id  = azurerm_virtual_network.this.id
  resolution_policy   = "NxDomainRedirect"
}


resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                = "link-${azurerm_private_dns_zone.storage_blob.name}-${azurerm_virtual_network.this.name}"
  private_dns_zone_id = azurerm_private_dns_zone.storage_blob.id
  virtual_network_id  = azurerm_virtual_network.this.id
  resolution_policy   = "NxDomainRedirect"
}

resource "azurerm_private_dns_zone" "ampls" {
  for_each = toset(local.ampls_private_dns_zones)

  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "ampls" {
  for_each = azurerm_private_dns_zone.ampls

  name                = "link-${each.value.name}-${azurerm_virtual_network.this.name}"
  private_dns_zone_id = each.value.id
  virtual_network_id  = azurerm_virtual_network.this.id
  resolution_policy   = "NxDomainRedirect"
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

resource "azurerm_monitor_diagnostic_setting" "public_ip_nat" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_public_ip.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_subnet_nat_gateway_association" "devops" {
  subnet_id      = azurerm_subnet.devops.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
#endregion

#region private-endpoints
resource "azurerm_private_endpoint" "key_vault" {
  name                = "${module.naming.private_endpoint.name}-key-vault"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "key_vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${module.naming.private_endpoint.name}-storage-blob"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "storage_blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }
}

resource "azurerm_private_endpoint" "ampls" {
  name                = "${module.naming.private_endpoint.name}-ampls"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "ampls"
    private_connection_resource_id = azurerm_monitor_private_link_scope.this.id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [for zone in local.ampls_private_dns_zones : azurerm_private_dns_zone.ampls[zone].id]
  }

  # Creating the private endpoint updates the AMPLS. If the scoped services or the jumplinux2 data collection
  # associations on the DCE are still being written, Azure returns 409 AnotherOperationInProgress, so these
  # writes are serialized.
  depends_on = [
    azurerm_monitor_private_link_scoped_service.dce,
    azurerm_monitor_private_link_scoped_service.log_analytics,
    azurerm_private_dns_zone_virtual_network_link.ampls,
    module.vm_jumpbox_linux,
  ]
}
#endregion
