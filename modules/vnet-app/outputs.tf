output "azure_files_config_vm_extension_id" {
  value       = azurerm_virtual_machine_extension.this.id
  description = "Dependent modules can reference this output to determine if Azure Files configuration is complete."
}

output "private_dns_zones" {
  value = azurerm_private_dns_zone.zones
}

output "resource_ids" {
  value = {
    storage_account          = azurerm_storage_account.this.id
    storage_share            = azurerm_storage_share.this.id
    virtual_machine_jumpwin1 = azurerm_windows_virtual_machine.this.id
    virtual_network_app      = azurerm_virtual_network.this.id
  }
}

output "resource_names" {
  value = {
    storage_account          = azurerm_storage_account.this.name
    storage_share            = azurerm_storage_share.this.name
    virtual_machine_jumpwin1 = azurerm_windows_virtual_machine.this.name
    virtual_network_app      = azurerm_virtual_network.this.name
  }
}

output "storage_container_name" {
  value = azurerm_storage_container.this.name
}

output "storage_endpoints" {
  value = {
    blob = azurerm_storage_account.this.primary_blob_endpoint
    file = azurerm_storage_account.this.primary_file_endpoint
  }
}

output "subnets" {
  value = azurerm_subnet.subnets
}
