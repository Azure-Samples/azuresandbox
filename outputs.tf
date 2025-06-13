output "client_cert_pem" {
  description = "Client certificate in PEM format for use with point-to-site VPN clients."
  value       = length(module.vwan) == 1 ? module.vwan[0].client_cert_pem : null
}


output "resource_ids" {
  value = merge(
    {
      key_vault               = azurerm_key_vault.this.id
      log_analytics_workspace = azurerm_log_analytics_workspace.this.id
      resource_group          = azurerm_resource_group.this.id
    },
    module.vnet_shared.resource_ids,
    length(module.vnet_app) > 0 ? module.vnet_app[0].resource_ids : {},
    length(module.vm_jumpbox_linux) > 0 ? module.vm_jumpbox_linux[0].resource_ids : {},
    length(module.vm_mssql_win) > 0 ? module.vm_mssql_win[0].resource_ids : {},
    length(module.mssql) > 0 ? module.mssql[0].resource_ids : {},
    length(module.mysql) > 0 ? module.mysql[0].resource_ids : {},
    length(module.vwan) > 0 ? module.vwan[0].resource_ids : {},
    length(module.vnet_onprem) > 0 ? module.vnet_onprem[0].resource_ids : {},
    length(module.ai_foundry) > 0 ? module.ai_foundry[0].resource_ids : {}
  )
}

output "resource_names" {
  value = merge(
    {
      key_vault               = azurerm_key_vault.this.name
      log_analytics_workspace = azurerm_log_analytics_workspace.this.name
      resource_group          = azurerm_resource_group.this.name
    },
    module.vnet_shared.resource_names,
    length(module.vnet_app) > 0 ? module.vnet_app[0].resource_names : {},
    length(module.vm_jumpbox_linux) > 0 ? module.vm_jumpbox_linux[0].resource_names : {},
    length(module.vm_mssql_win) > 0 ? module.vm_mssql_win[0].resource_names : {},
    length(module.mssql) > 0 ? module.mssql[0].resource_names : {},
    length(module.mysql) > 0 ? module.mysql[0].resource_names : {},
    length(module.vwan) > 0 ? module.vwan[0].resource_names : {},
    length(module.vnet_onprem) > 0 ? module.vnet_onprem[0].resource_names : {},
    length(module.ai_foundry) > 0 ? module.ai_foundry[0].resource_names : {}
  )
}

output "root_cert_pem" {
  description = "Self signed root certificate in PEM format for use with point-to-site VPN clients."
  value       = length(module.vwan) == 1 ? module.vwan[0].root_cert_pem : null
}
