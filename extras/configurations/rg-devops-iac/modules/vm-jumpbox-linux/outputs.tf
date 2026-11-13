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
  value       = azurerm_key_vault_secret.ssh_private_key.id
  description = "Dependency signal: the SSH private key Key Vault secret write is complete. Consumed by the root key_vault_access_barrier."
}

output "log_analytics_operations_complete" {
  value       = terraform_data.log_analytics_operations_complete.id
  description = "Dependency signal: the Azure Monitor Agent and the data collection rule and endpoint associations are complete. Consumed by the root ampls_access_barrier."
}

output "virtual_machine_extensions_complete" {
  value       = azurerm_linux_virtual_machine.this.id
  description = "Dependency signal: the VM id, available only after cloud-init and the VM extensions (the last apt-based one is the Azure Monitor Agent) are complete. Consumed by the optional github-runner module, so installing the runner doesn't contend for the dpkg/apt locks."
  depends_on  = [azurerm_virtual_machine_extension.ama]
}
