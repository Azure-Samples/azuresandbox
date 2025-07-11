output "adds_domain_name" {
  value = var.adds_domain_name
}

output "admin_password_secret" {
  value = azurerm_key_vault_secret.adminpassword.name
}

output "admin_username_secret" {
  value = azurerm_key_vault_secret.adminusername.name
}

output "dns_server" {
  value = azurerm_virtual_network.this.dns_servers[0]
}

output "private_dns_zones" {
  value = { "privatelink.vaultcore.azure.net" = azurerm_private_dns_zone.this }
}

output "resource_ids" {
  value = {
    automation_account      = azurerm_automation_account.this.id
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
    automation_account      = azurerm_automation_account.this.name
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
