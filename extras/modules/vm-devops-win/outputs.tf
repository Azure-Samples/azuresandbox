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
