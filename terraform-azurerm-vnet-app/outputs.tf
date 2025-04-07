output "private_dns_zones" {
  value       = azurerm_private_dns_zone.private_dns_zones
  description = "The private DNS zones used in the application virtual network."
}

output "storage_share_name" {
  value       = azurerm_storage_share.storage_share_01.name
  description = "The name of the storage share created in the application virtual network."
}

output "vnet_app_01_id" {
  value       = azurerm_virtual_network.vnet_app_01.id
  description = "The resource ID of the application virtual network."
}

output "vnet_app_01_name" {
  value       = azurerm_virtual_network.vnet_app_01.name
  description = "The name of the application virtual network."
}

output "vnet_app_01_subnets" {
  value       = azurerm_subnet.vnet_app_01_subnets
  description = "The subnets created in the application virtual network."
}
