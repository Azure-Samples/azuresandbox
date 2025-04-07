locals {
  commandParamParts = [
    "$params = @{",
    "TenantId = '${var.aad_tenant_id}'; ",
    "SubscriptionId = '${var.subscription_id}'; ",
    "AppId = '${var.arm_client_id}'; ",
    "ResourceGroupName = '${var.resource_group_name}'; ",
    "KeyVaultName = '${var.key_vault_name}'; ",
    "Domain = '${var.adds_domain_name}'; ",
    "AdminUsernameSecret = '${var.admin_username_secret}'; ",
    "AdminPwdSecret = '${var.admin_password_secret}'; ",
    "TempDiskSizeMb = '${var.temp_disk_size_mb}'; ",
    "}"
  ]

  storage_account_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Storage/storageAccounts/${var.storage_account_name}"
}
