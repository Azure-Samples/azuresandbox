output "configure_azure_files_id" {
  value = azurerm_virtual_machine_extension.configure_azure_files.id
}

output "fqdns" {
  value = {
    container_registry   = trimsuffix(trimprefix(azurerm_container_registry.this.login_server, "https://"), "/")
    storage_account_blob = trimsuffix(trimprefix(azurerm_storage_account.this.primary_blob_endpoint, "https://"), "/")
    storage_account_file = trimsuffix(trimprefix(azurerm_storage_account.this.primary_file_endpoint, "https://"), "/")
  }
}

output "log_analytics_operations_complete" {
  value       = terraform_data.log_analytics_operations_complete.id
  description = "Dependency signal: AMA install and DCR/DCE associations on jumpwin1 are complete and AMPLS DNS zone links are in place. Consumed by the root ampls_access_barrier."
}

output "private_dns_zones" {
  value = azurerm_private_dns_zone.zones
}

output "resource_ids" {
  value = {
    container_registry       = azurerm_container_registry.this.id
    storage_account          = azurerm_storage_account.this.id
    storage_share            = azurerm_storage_share.this.id
    virtual_machine_jumpwin1 = azurerm_windows_virtual_machine.this.id
    virtual_network_app      = azurerm_virtual_network.this.id
  }
}

output "resource_names" {
  value = {
    container_registry       = azurerm_container_registry.this.name
    storage_account          = azurerm_storage_account.this.name
    storage_share            = azurerm_storage_share.this.name
    virtual_machine_jumpwin1 = azurerm_windows_virtual_machine.this.name
    virtual_network_app      = azurerm_virtual_network.this.name
  }
}

output "virtual_machine_jumpwin1_identity" {
  value = {
    principal_id = azurerm_windows_virtual_machine.this.identity[0].principal_id
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

output "storage_operations_complete" {
  value       = terraform_data.storage_operations_complete.id
  description = "Dependency signal: all storage data plane operations in this module are complete."
}
