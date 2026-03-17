output "resource_ids" {
  value = {
    for k, vm in azurerm_windows_virtual_machine.virtual_machines : "virtual_machine_${k}" => vm.id
  }
}

output "resource_names" {
  value = {
    for k, vm in azurerm_windows_virtual_machine.virtual_machines : "virtual_machine_${k}" => vm.name
  }
}

output "storage_operations_complete" {
  value       = azurerm_storage_blob.this.id
  description = "Dependency signal: all storage data plane operations in this module are complete."
}
