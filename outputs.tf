output "resource_names" {
  value = {
    key_vault      = azurerm_key_vault.this.name
    resource_group = azurerm_resource_group.this.name
  }
}

output "resource_ids" {
  value = {
    key_vault      = azurerm_key_vault.this.name
    resource_group = azurerm_resource_group.this.id
  }
}
