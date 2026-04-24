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

output "key_vault_operations_complete" {
  value       = azurerm_key_vault_secret.ssh_private_key.id
  description = "Dependency signal: all key vault data plane operations in this module are complete."
}

output "log_analytics_operations_complete" {
  value       = terraform_data.log_analytics_operations_complete.id
  description = "Dependency signal: AMA install and DCR/DCE associations on jumplinux1 are complete. Consumed by the root ampls_access_barrier."
}
