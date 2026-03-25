output "configure_azure_files_id" {
  value = azurerm_virtual_machine_extension.configure_azure_files.id
}

output "private_dns_zones" {
  value = azurerm_private_dns_zone.zones
}

output "resource_ids" {
  value = {
    container_registry       = azurerm_container_registry.this.id
    storage_account          = azurerm_storage_account.this.id
    storage_share            = azurerm_storage_share.this.id
    virtual_machine_jumpwin1 = azurerm_windows_virtual_machine.this.id
    virtual_network_app      = azurerm_virtual_network.this.id
  }
}

output "resource_names" {
  value = {
    container_registry       = azurerm_container_registry.this.name
    storage_account          = azurerm_storage_account.this.name
    storage_share            = azurerm_storage_share.this.name
    virtual_machine_jumpwin1 = azurerm_windows_virtual_machine.this.name
    virtual_network_app      = azurerm_virtual_network.this.name
  }
}

output "storage_container_name" {
  value = azurerm_storage_container.this.name
}

output "storage_endpoints" {
  value = {
    blob = azurerm_storage_account.this.primary_blob_endpoint
    file = azurerm_storage_account.this.primary_file_endpoint
  }
}

output "subnets" {
  value = azurerm_subnet.subnets
}

output "storage_operations_complete" {
  value       = terraform_data.storage_operations_complete.id
  description = "Dependency signal: all storage data plane operations in this module are complete."
}

output "vm_run_command_output" {
  value = {
    install_windows_features = azurerm_virtual_machine_run_command.install_windows_features.instance_view
    install_software         = azurerm_virtual_machine_run_command.install_software.instance_view
  }
  description = "Instance view output from VM run commands for troubleshooting."
}
