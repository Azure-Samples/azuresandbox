#region modules
module "naming" {
  source      = "Azure/naming/azurerm"
  version     = "~> 0.4.2"
  suffix      = [var.tags["project"], var.tags["environment"]]
  unique-seed = var.unique_seed
}
#endregion
