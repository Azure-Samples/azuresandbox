locals {
  provider_auth = {
    client_id     = var.client_id
    client_secret = var.auth_mode == "client_secret" ? var.client_secret : null
    tenant_id     = var.entra_tenant_id
    use_msi       = var.auth_mode == "managed_identity"
    use_oidc      = var.auth_mode == "oidc"
  }

  tags = merge(var.tags, var.additional_tags)

  # Custom images (var.vm_image_gallery_id set): image definitions required by the enabled modules.
  vm_image_gallery = var.vm_image_gallery_id == null ? null : {
    name                = split("/", var.vm_image_gallery_id)[8]
    resource_group_name = split("/", var.vm_image_gallery_id)[4]
  }

  vm_image_definitions = var.vm_image_gallery_id == null ? {} : merge(
    { adds = "vnet_shared" },
    var.enable_module_vnet_app ? { jumpwin = "vnet_app" } : {},
    var.enable_module_vm_jumpbox_linux ? { jumplinux = "vm_jumpbox_linux" } : {},
    var.enable_module_vm_mssql_win ? { mssqlwin = "vm_mssql_win" } : {},
  )
}
