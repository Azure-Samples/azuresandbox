#region data
data "azurerm_client_config" "current" {}

resource "terraform_data" "storage_operations_complete" {
  input = values(azurerm_storage_blob.remote_scripts)[*].id
}

resource "terraform_data" "log_analytics_operations_complete" {
  input = {
    mssqlwin1_ama             = azurerm_virtual_machine_extension.ama.id
    mssqlwin1_dcr_association = azurerm_monitor_data_collection_rule_association.mssqlwin1_dcr.id
    mssqlwin1_dce_association = azurerm_monitor_data_collection_rule_association.mssqlwin1_dce.id
  }
}
#endregion

#region utility-resources
resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on = [
    azurerm_role_assignment.assignments
  ]
}
#endregion

#region modules
module "naming" {
  source        = "Azure/avm-utl-naming/azure"
  version       = "~> 0.3.0"
  suffix        = [var.tags["project"], var.tags["environment"]]
  unique_length = 0
}
#endregion
