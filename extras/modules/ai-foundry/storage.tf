#region files
resource "azurerm_storage_share_directory" "this" {
  name             = "documents"
  storage_share_id = "${var.storage_file_endpoint}${var.storage_share_name}"
}

resource "azurerm_storage_share_file" "documents" {
  for_each = toset(local.documents)

  name             = each.value
  storage_share_id = "${var.storage_file_endpoint}${var.storage_share_name}"
  path             = "documents"
  source           = "./${path.module}/documents/${each.value}"

  depends_on = [azurerm_storage_share_directory.this]
}
#endregion

#region utilities
resource "terraform_data" "storage_operations_complete" {
  input = values(azurerm_storage_share_file.documents)[*].id
}
#endregion
