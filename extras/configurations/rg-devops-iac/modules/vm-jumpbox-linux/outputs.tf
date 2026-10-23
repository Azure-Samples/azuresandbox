output "resource_ids" {
  value = {
    virtual_machine_jumplinux2 = azurerm_linux_virtual_machine.this.id
  }
}

output "resource_names" {
  value = {
    virtual_machine_jumplinux2 = azurerm_linux_virtual_machine.this.name
  }
}

output "key_vault_operations_complete" {
  value = azurerm_key_vault_secret.ssh_private_key.id
}

output "log_analytics_operations_complete" {
  value       = terraform_data.log_analytics_operations_complete.id
  description = "Dependency signal: the Azure Monitor Agent and the data collection rule and endpoint associations are complete. Consumed by the root ampls_access_barrier."
}
