output "petstore_fqdn" {
  description = "The FQDN of the container app"
  value       = azurerm_container_app.this.latest_revision_fqdn
}
