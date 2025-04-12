output "private_dns_zones" {
  value       = azurerm_private_dns_zone.zones
  description = "The private DNS zones used in the application virtual network."
}

output "resource_ids" {
  value = {
    storage_account = azurerm_storage_account.this.id
    virtual_machine_jumpwin1 = azurerm_windows_virtual_machine.this.id
    virtual_network_app = azurerm_virtual_network.this.id
  }
}

output "resource_names" {
  value = {
    storage_account = azurerm_storage_account.this.name
    virtual_machine_jumpwin1 = azurerm_windows_virtual_machine.this.name
    virtual_network_app = azurerm_virtual_network.this.name
  }
}

output "storage_share_name" {
  value       = azurerm_storage_share.this.name
  description = "The name of the storage share created in the application virtual network."
}

output "subnets" {
  value       = azurerm_subnet.subnets
  description = "The subnets created in the application virtual network."
}
