output "private_dns_zones" {
  value = azurerm_private_dns_zone.private_dns_zones
}

output "storage_share_name" {
  value = azurerm_storage_share.storage_share_01.name
}

output "vnet_app_01_id" {
  value = azurerm_virtual_network.vnet_app_01.id
}

output "vnet_app_01_name" {
  value = azurerm_virtual_network.vnet_app_01.name
}

output "vnet_app_01_subnets" {
  value = azurerm_subnet.vnet_app_01_subnets
}
