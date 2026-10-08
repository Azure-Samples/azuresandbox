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
  value = join(",", concat(
    [azurerm_key_vault_secret.ssh_private_key.id],
    azurerm_key_vault_secret.github_runner_token[*].id
  ))
}

output "github_runner_name" {
  value       = var.enable_github_runner ? local.github_runner_name : null
  description = "The name the GitHub Actions self-hosted runner is registered with, or null when the runner is disabled."
}
