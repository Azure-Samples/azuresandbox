#region data
data "azurerm_client_config" "current" {}
#endregion

#region resources

resource "null_resource" "this" { 
  provisioner "local-exec" { 
    command     = "$params = @{ ${join(" ", local.local_scripts["configure_automation"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["configure_automation"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
} # Configures the automation account for the DevOps VMs
#endregion

#region modules
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.2"
  suffix  = [var.tags["project"], var.tags["environment"]]
}
#endregion