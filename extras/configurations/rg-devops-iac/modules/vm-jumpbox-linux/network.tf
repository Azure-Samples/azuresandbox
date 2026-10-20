#region resources
resource "azurerm_network_interface" "this" {
  name                = "${module.naming.network_interface.name}-${var.vm_jumpbox_linux_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "Primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_monitor_diagnostic_setting" "network_interface" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_network_interface.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}
#endregion
