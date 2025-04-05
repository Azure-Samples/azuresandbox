output "aad_tenant_id" {
  value = var.aad_tenant_id
}

output "adds_domain_name" {
  value = var.adds_domain_name
}

output "admin_password_secret" {
  value = var.admin_password_secret
}

output "admin_username_secret" {
  value = var.admin_username_secret
}

output "arm_client_id" {
  value = var.arm_client_id
}

output "automation_account_name" {
  value = azurerm_automation_account.automation_account_01.name
}

output "dns_server" {
  value = var.dns_server
}

output "firewall_01_route_table_id" {
  value = azurerm_route_table.firewall_01.id
}

output "key_vault_id" {
  value = var.key_vault_id
}

output "key_vault_name" {
  value = var.key_vault_name
}

output "log_analytics_workspace_01_name" {
  value = azurerm_log_analytics_workspace.log_analytics_workspace_01.name
}

output "log_analytics_workspace_01_workspace_id" {
  value = azurerm_log_analytics_workspace.log_analytics_workspace_01.workspace_id
}

output "location" {
  value = var.location
}

output "random_id" {
  value = var.random_id
}

output "resource_group_name" {
  value = var.resource_group_name
}

output "storage_account_name" {
  value = var.storage_account_name
}

output "storage_container_name" {
  value = var.storage_container_name
}

output "subscription_id" {
  value = var.subscription_id
}

output "tags" {
  value = var.tags
}

output "vnet_shared_01_id" {
  value = azurerm_virtual_network.vnet_shared_01.id
}

output "vnet_shared_01_name" {
  value = azurerm_virtual_network.vnet_shared_01.name
}

output "vnet_shared_01_subnets" {
  value = azurerm_subnet.vnet_shared_01_subnets
}
