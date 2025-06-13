
output "resource_ids" {
  value = {
    ai_foundry         = azurerm_ai_foundry.this.id
    ai_services        = azurerm_ai_services.this.id
    app_insights       = azurerm_application_insights.this.id
    container_registry = azurerm_container_registry.this.id
    search_service     = azurerm_search_service.this.id
  }
}

output "resource_names" {
  value = {
    ai_foundry         = azurerm_ai_foundry.this.name
    ai_services        = azurerm_ai_services.this.name
    app_insights       = azurerm_application_insights.this.name
    container_registry = azurerm_container_registry.this.name
    search_service     = azurerm_search_service.this.name
  }
}
