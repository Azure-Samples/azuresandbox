#region storage-container
resource "azurerm_storage_blob" "remote_scripts" {
  for_each = local.remote_scripts

  name                 = each.value.name
  storage_container_id = var.storage_container_id
  type                 = "Block"
  source               = "./${path.module}/scripts/${each.value.name}"

  depends_on = [time_sleep.wait_for_roles]
}
#endregion
