#region data
data "azurerm_client_config" "current" {}
#endregion

#region resources
resource "null_resource" "this" {
  provisioner "local-exec" {
    command     = "$params = @{ ${join(" ", local.local_scripts["configure_automation"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["configure_automation"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
} # Configures the automation account for the SQL Server VM
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
