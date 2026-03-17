#region resources
resource "azurerm_storage_blob" "this" {
  name                   = local.remote_scripts["configuration"].name
  storage_account_name   = var.storage_account_name
  storage_container_name = var.storage_container_name
  type                   = "Block"
  source                 = "./${path.module}/scripts/${local.remote_scripts["configuration"].name}"

}
#endregion
