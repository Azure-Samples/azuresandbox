output "resource_ids" {
  value = {
    avd_workspace                          = azurerm_virtual_desktop_workspace.this.id
    avd_application_group_personal         = azurerm_virtual_desktop_application_group.personal.id
    avd_application_group_remoteapp        = azurerm_virtual_desktop_application_group.remoteapp.id
    avd_host_pool_personal                 = azurerm_virtual_desktop_host_pool.personal.id
    avd_host_pool_remoteapp                = azurerm_virtual_desktop_host_pool.remoteapp.id
    virtual_machine_session_host_personal  = azurerm_windows_virtual_machine.personal.id
    virtual_machine_session_host_remoteapp = azurerm_windows_virtual_machine.remoteapp.id
  }
}

output "resource_names" {
  value = {
    avd_workspace                          = azurerm_virtual_desktop_workspace.this.name
    avd_application_group_personal         = azurerm_virtual_desktop_application_group.personal.name
    avd_application_group_remoteapp        = azurerm_virtual_desktop_application_group.remoteapp.name
    avd_host_pool_personal                 = azurerm_virtual_desktop_host_pool.personal.name
    avd_host_pool_remoteapp                = azurerm_virtual_desktop_host_pool.remoteapp.name
    virtual_machine_session_host_personal  = azurerm_windows_virtual_machine.personal.name
    virtual_machine_session_host_remoteapp = azurerm_windows_virtual_machine.remoteapp.name
  }
}
