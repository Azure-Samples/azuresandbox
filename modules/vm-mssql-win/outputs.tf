output "resource_ids" {
  value = {
    virtual_machine_mssqlwin1 = azurerm_windows_virtual_machine.this.id
  }
}

output "resource_names" {
  value = {
    virtual_machine_mssqlwin1 = azurerm_windows_virtual_machine.this.name
  }
}

output "storage_operations_complete" {
  value       = terraform_data.storage_operations_complete.id
  description = "Dependency signal: all storage data plane operations in this module are complete."
}

output "log_analytics_operations_complete" {
  value       = terraform_data.log_analytics_operations_complete.id
  description = "Dependency signal: AMA install and DCR/DCE associations on mssqlwin1 are complete. Consumed by the root ampls_access_barrier."
}

output "vm_run_command_output" {
  value = {
    configure_firewall_rules = azurerm_virtual_machine_run_command.configure_firewall_rules.instance_view
    configure_sql_login      = azurerm_virtual_machine_run_command.configure_sql_login.instance_view
  }
  description = "Instance view output from VM run commands for troubleshooting."
}
