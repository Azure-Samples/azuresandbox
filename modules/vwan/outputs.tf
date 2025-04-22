output "vwan_01_id" {
  value       = azurerm_virtual_wan.vwan_01.id
  description = "The resource id of the virtual WAN."
}

output "vwan_01_hub_01_id" {
  value       = azurerm_virtual_hub.vwan_01_hub_01.id
  description = "The resource id of the virtual hub."
}
