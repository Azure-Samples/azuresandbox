output "aad_tenant_id" {
  value       = var.aad_tenant_id
  description = "The Microsoft Entra Tenant id used to provision the sandbox."
}

output "adds_domain_name" {
  value       = var.adds_domain_name
  description = "The Active Directory Domain Services domain name used in the sandbox."
}

output "admin_password_secret" {
  value       = var.admin_password_secret
  description = "The name of the key vault secret containing the admin password."
}

output "admin_username_secret" {
  value       = var.admin_username_secret
  description = "The name of the key vault secret containing the admin username."
}

output "arm_client_id" {
  value       = var.arm_client_id
  description = "The id of the service principal used for authenticating with Azure."
}

output "automation_account_name" {
  value       = azurerm_automation_account.automation_account_01.name
  description = "The name of the shared Azure Automation Account."
}

output "dns_server" {
  value       = var.dns_server
  description = "The IP address of the DNS server."
}

output "firewall_01_route_table_id" {
  value       = azurerm_route_table.firewall_01.id
  description = "The resource id of the firewall route table."
}

output "key_vault_id" {
  value       = var.key_vault_id
  description = "The resource id of the shared key vault."
}

output "key_vault_name" {
  value       = var.key_vault_name
  description = "The name of the shared key vault."
}

output "log_analytics_workspace_01_name" {
  value       = azurerm_log_analytics_workspace.log_analytics_workspace_01.name
  description = "The name of the shared Log Analytics Workspace."
}

output "log_analytics_workspace_01_workspace_id" {
  value       = azurerm_log_analytics_workspace.log_analytics_workspace_01.workspace_id
  description = "The id of the shared Log Analytics Workspace."
}

output "location" {
  value       = var.location
  description = "The Azure region where the sandbox is provisioned."
}

output "random_id" {
  value       = var.random_id
  description = "The random id used to create unique resource names."
}

output "resource_group_name" {
  value       = var.resource_group_name
  description = "The name of the resource group where the sandbox is provisioned."
}

output "storage_account_name" {
  value       = var.storage_account_name
  description = "The name of the shared storage account."
}

output "storage_container_name" {
  value       = var.storage_container_name
  description = "The name of the Azure Blob storage container where scripts are stored."
}

output "subscription_id" {
  value       = var.subscription_id
  description = "The name of the Azure subscription used to provision the sandbox."
}

output "tags" {
  value       = var.tags
  description = "The tags used when provisioning resources."
}

output "vnet_shared_01_id" {
  value       = azurerm_virtual_network.vnet_shared_01.id
  description = "The resource id of the shared services virtual network."
}

output "vnet_shared_01_name" {
  value       = azurerm_virtual_network.vnet_shared_01.name
  description = "The name of the shared services virtual network."
}

output "vnet_shared_01_subnets" {
  value       = azurerm_subnet.vnet_shared_01_subnets
  description = "The subnets defined in the shared services virtual network."
}
