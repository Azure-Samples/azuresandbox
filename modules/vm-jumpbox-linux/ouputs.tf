output "resource_ids" {
  value = {
    virtual_machine_jumplinux1 = azurerm_linux_virtual_machine.this.id
  }
}

output "resource_names" {
  value = {
    virtual_machine_jumplinux1 = azurerm_linux_virtual_machine.this.name
  }
}
