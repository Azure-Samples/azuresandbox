#region modules
module "naming" {
  source        = "Azure/avm-utl-naming/azure"
  version       = "~> 0.3.0"
  suffix        = [var.tags["project"], var.tags["environment"]]
  unique_length = 0
}
#endregion
