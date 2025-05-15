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

