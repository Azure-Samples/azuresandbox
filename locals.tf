locals {
  # Provider authentication settings by auth_mode:
  #   azure_cli        - use_cli; signed-in Azure CLI user, no client_id
  #   client_secret    - client_id + client_secret; service principal
  #   managed_identity - client_id + use_msi; user-assigned managed identity on the host
  #   oidc             - client_id + use_oidc; GitHub Actions OIDC token
  provider_auth = {
    client_id     = var.auth_mode == "azure_cli" ? null : var.client_id
    client_secret = var.auth_mode == "client_secret" ? var.client_secret : null
    tenant_id     = var.entra_tenant_id
    use_cli       = var.auth_mode == "azure_cli"
    use_msi       = var.auth_mode == "managed_identity"
    use_oidc      = var.auth_mode == "oidc"
  }

  # Principal type of the identity Terraform authenticates as, used for its data-plane role assignments.
  deployment_identity_principal_type = var.auth_mode == "azure_cli" ? "User" : "ServicePrincipal"

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
