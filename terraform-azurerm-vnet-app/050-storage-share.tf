# Azure blob private endpoint
resource "azurerm_private_endpoint" "storage_account_01_blob" {
  name                = "pend-${var.storage_account_name}-blob"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = "azure_blob"
    private_connection_resource_id = local.storage_account_id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  depends_on = [
    azurerm_virtual_network_peering.vnet_app_01_to_vnet_shared_01_peering,
    azurerm_virtual_network_peering.vnet_shared_01_to_vnet_app_01_peering
  ]
}

resource "azurerm_private_dns_a_record" "storage_account_01_blob" {
  name                = var.storage_account_name
  zone_name           = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage_account_01_blob.private_service_connection[0].private_ip_address]
}

# Azure Files share
resource "azapi_update_resource" "storage_account_enable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = local.storage_account_id

  body = {
    properties = {
      allowSharedKeyAccess = true 
      publicNetworkAccess = "Enabled"
    }
  }
}

resource "time_sleep" "wait_60_seconds" {
  create_duration = "60s"
  depends_on      = [azapi_update_resource.storage_account_enable_public_access]
}

resource "azurerm_storage_share" "storage_share_01" {
  name                 = var.storage_share_name
  storage_account_name = var.storage_account_name
  quota                = var.storage_share_quota_gb

  depends_on = [time_sleep.wait_60_seconds]
}

output "storage_share_name" {
  value = azurerm_storage_share.storage_share_01.name
}

resource "azapi_update_resource" "storage_account_disable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = local.storage_account_id

  body = {
    properties = {
      allowSharedKeyAccess = false 
      publicNetworkAccess = "Disabled"
    }
  }

  depends_on = [azurerm_storage_share.storage_share_01]
}

# Azure Files private endpoint
resource "azurerm_private_endpoint" "storage_account_01_file" {
  name                = "pend-${var.storage_account_name}-file"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = azurerm_subnet.vnet_app_01_subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = "azure_files"
    private_connection_resource_id = local.storage_account_id
    is_manual_connection           = false
    subresource_names              = ["file"]
  }

  depends_on = [
    azurerm_virtual_network_peering.vnet_app_01_to_vnet_shared_01_peering,
    azurerm_virtual_network_peering.vnet_shared_01_to_vnet_app_01_peering
  ]
}

resource "azurerm_private_dns_a_record" "storage_account_01_file" {
  name                = var.storage_account_name
  zone_name           = "privatelink.file.core.windows.net"
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage_account_01_file.private_service_connection[0].private_ip_address]
}
