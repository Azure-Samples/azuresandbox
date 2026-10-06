output "resource_ids" {
  value = merge(
    {
      key_vault       = azurerm_key_vault.this.id
      resource_group  = azurerm_resource_group.this.id
      storage_account = azurerm_storage_account.this.id
      virtual_network = azurerm_virtual_network.this.id
    },
    module.vm_jumpbox_linux.resource_ids
  )
}

output "resource_names" {
  value = merge(
    {
      key_vault       = azurerm_key_vault.this.name
      resource_group  = azurerm_resource_group.this.name
      storage_account = azurerm_storage_account.this.name
      virtual_network = azurerm_virtual_network.this.name
    },
    module.vm_jumpbox_linux.resource_names
  )
}

output "github_runner_name" {
  value       = module.vm_jumpbox_linux.github_runner_name
  description = "The name the GitHub Actions self-hosted runner is registered with, or null when var.enable_github_runner is false."
}
