output "resource_ids" {
  value = {
    container_registry = azurerm_container_registry.this.id
  }
}

output "resource_names" {
  value = {
    container_registry = azurerm_container_registry.this.name
  }
}
