output "adds_domain_name" {
  value = var.adds_domain_name
}

output "admin_password" {
  value     = local.admin_password
  sensitive = true
}

output "admin_password_secret" {
  value = azurerm_key_vault_secret.adminpassword.name
}

output "admin_username" {
  value = var.admin_username
}

output "admin_username_secret" {
  value = azurerm_key_vault_secret.adminusername.name
}

output "dns_server" {
  value = azurerm_virtual_network.this.dns_servers[0]
}

output "fqdns" {
  value = {
    key_vault = trimsuffix(trimprefix(azurerm_key_vault.this.vault_uri, "https://"), "/")
  }
}

output "private_dns_zones" {
  value = { "privatelink.vaultcore.azure.net" = azurerm_private_dns_zone.this }
}

output "resource_ids" {
  value = {
    bastion_host            = azurerm_bastion_host.this.id
    firewall                = azurerm_firewall.this.id
    firewall_route_table    = azurerm_route_table.this.id
    key_vault               = azurerm_key_vault.this.id
    log_analytics_workspace = azurerm_log_analytics_workspace.this.id
    virtual_machine_adds1   = azurerm_windows_virtual_machine.this.id
    virtual_network_shared  = azurerm_virtual_network.this.id
  }
}

output "resource_names" {
  value = {
    bastion_host            = azurerm_bastion_host.this.name
    firewall                = azurerm_firewall.this.name
    firewall_route_table    = azurerm_route_table.this.name
    key_vault               = azurerm_key_vault.this.name
    log_analytics_workspace = azurerm_log_analytics_workspace.this.name
    virtual_machine_adds1   = azurerm_windows_virtual_machine.this.name
    virtual_network_shared  = azurerm_virtual_network.this.name
  }
}

output "subnets" {
  value = azurerm_subnet.subnets
}

output "key_vault_operations_complete" {
  value       = terraform_data.key_vault_operations_complete.id
  description = "Dependency signal: all key vault data plane operations in this module are complete."
}

# Use this output to trigger dependent modules to wait until the VM is fully configured and has rebooted after creating the domain
output "configure_adds_dns_id" {
  value = azurerm_virtual_machine_run_command.configure_adds_dns.id
}
