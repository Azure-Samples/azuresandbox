output "resource_ids" {
  value = {
    private_dns_resolver = azurerm_private_dns_resolver.this.id
    virtual_network_onprem = azurerm_virtual_network.this.id
    virtual_machine_adds2 = azurerm_windows_virtual_machine.vm_adds.id
    virtual_machine_jumpwin2 = azurerm_windows_virtual_machine.vm_jumpbox_win.id
  }
}

output "resource_names" {
  value = {
    private_dns_resolver = azurerm_private_dns_resolver.this.name
    virtual_network_onprem = azurerm_virtual_network.this.name
    virtual_machine_adds2 = azurerm_windows_virtual_machine.vm_adds.name
    virtual_machine_jumpwin2 = azurerm_windows_virtual_machine.vm_jumpbox_win.name
  }
}
