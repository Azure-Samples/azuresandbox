# Secrets
data "azurerm_key_vault_secret" "adminpassword" {
  name         = var.admin_password_secret
  key_vault_id = var.key_vault_id
}

data "azurerm_key_vault_secret" "adminuser" {
  name         = var.admin_username_secret
  key_vault_id = var.key_vault_id
}

# Shared log analytics workspace
resource "azurerm_log_analytics_workspace" "log_analytics_workspace_01" {
  name                = "log-${var.random_id}-01"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_workspace_retention_days
  tags                = var.tags
}

resource "azurerm_key_vault_secret" "log_analytics_workspace_01_primary_shared_key" {
  name            = azurerm_log_analytics_workspace.log_analytics_workspace_01.workspace_id
  value           = azurerm_log_analytics_workspace.log_analytics_workspace_01.primary_shared_key
  key_vault_id    = var.key_vault_id
  expiration_date = timeadd(timestamp(), "8760h")
}

resource "azurerm_monitor_diagnostic_setting" "key_vault_01" {
  name                       = "key-vault-01"
  target_resource_id         = var.key_vault_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace_01.id

  enabled_log {
    category_group = "audit"
  }
}

# Azure Automation Account
resource "azurerm_automation_account" "automation_account_01" {
  name                = "auto-${var.random_id}-01"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"
  tags                = var.tags

  # Bootstrap automation account
  # Note: To view provisioner output, use the Terraform nonsensitive() function when referencing key vault secrets or variables marked 'sensitive'
  provisioner "local-exec" {
    command     = <<EOT
        $params = @{
          TenantId = "${var.aad_tenant_id}"
          SubscriptionId = "${var.subscription_id}"
          ResourceGroupName = "${var.resource_group_name}"
          AutomationAccountName = "${azurerm_automation_account.automation_account_01.name}"
          Domain = "${var.adds_domain_name}"
          VmAddsName = "${var.vm_adds_name}"
          AdminUserName = "${data.azurerm_key_vault_secret.adminuser.value}"
          AdminPwd = "${data.azurerm_key_vault_secret.adminpassword.value}"
          AppId = "${var.arm_client_id}"
          AppSecret = "${var.arm_client_secret}"
        }
        ${path.root}/scripts/configure-automation.ps1 @params 
   EOT
    interpreter = ["pwsh", "-Command"]
  }
}
