#region data
data "azurerm_client_config" "current" {}
#endregion

#region utility-resources
resource "terraform_data" "storage_operations_complete" {
  input = values(azurerm_storage_blob.remote_scripts)[*].id
}

resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on = [
    azurerm_role_assignment.assignments
  ]
}
#endregion

#region modules
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.3"
  suffix  = [var.tags["project"], var.tags["environment"]]
}
#endregion
