output "resource_ids" {
  value = {
    virtual_wan = azurerm_virtual_wan.this.id
    virtual_wan_hub = azurerm_virtual_hub.this.id
  }
}

output "resource_names" {
  value = {
    virtual_wan = azurerm_virtual_wan.this.name
    virtual_wan_hub = azurerm_virtual_hub.this.name
  }
}
