locals {
  provider_auth = {
    client_id     = var.client_id
    client_secret = var.auth_mode == "client_secret" ? var.client_secret : null
    tenant_id     = var.entra_tenant_id
    use_msi       = var.auth_mode == "managed_identity"
    use_oidc      = var.auth_mode == "oidc"
  }

  tags = merge(var.tags, var.additional_tags)
}
