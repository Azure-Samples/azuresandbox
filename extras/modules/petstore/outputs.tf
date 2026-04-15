output "fqdns" {
  value = {
    petstore = azurerm_container_app.this.latest_revision_fqdn
  }
}

output "resource_ids" {
  value = {
    container_app_environment = azurerm_container_app_environment.this.id
  }
}

output "resource_names" {
  value = {
    container_app_environment = azurerm_container_app_environment.this.name
  }
}
