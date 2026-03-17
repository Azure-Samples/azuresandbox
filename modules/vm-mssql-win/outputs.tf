output "resource_ids" {
  value = {
    virtual_machine_mssqlwin1 = azurerm_windows_virtual_machine.this.id
  }
}

output "resource_names" {
  value = {
    virtual_machine_mssqlwin1 = azurerm_windows_virtual_machine.this.name
  }
}

output "storage_operations_complete" {
  value       = terraform_data.storage_operations_complete.id
  description = "Dependency signal: all storage data plane operations in this module are complete."
}

