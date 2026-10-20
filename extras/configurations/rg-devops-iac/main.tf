#region data
data "azurerm_client_config" "current" {}

data "azurerm_role_definition" "deployment_identity_assignable" {
  for_each = toset(local.deployment_identity_assignable_roles)

  name  = each.value
  scope = "/subscriptions/${var.subscription_id}"
}
#endregion

#region resources
resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name_unique
  location = var.location
  tags     = var.tags
}

resource "azurerm_key_vault" "this" {
  name                          = module.naming.key_vault.name_unique
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = var.entra_tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = true # Note: The barrier pattern will disable this on apply.

  lifecycle {
    ignore_changes = [public_network_access_enabled]
  }
}

# Audit events include secret reads, such as retrieval of the jumplinux2 break-glass SSH private key.
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "Audit Logs"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_role_assignment" "key_vault_secrets_officer" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Key Vault Secrets Officer"
  scope                = azurerm_key_vault.this.id
}

resource "time_sleep" "wait_for_roles" {
  create_duration = "2m"
  depends_on      = [azurerm_role_assignment.key_vault_secrets_officer]
}
#endregion

#region azure-monitor
resource "azurerm_log_analytics_workspace" "this" {
  name                           = module.naming.log_analytics_workspace.name_unique
  location                       = var.location
  resource_group_name            = azurerm_resource_group.this.name
  sku                            = "PerGB2018"
  retention_in_days              = var.log_analytics_workspace_retention_days
  internet_ingestion_access_type = "Enabled" # Note: The barrier pattern will disable this on apply.
  internet_query_access_type     = "Enabled" # Note: The barrier pattern will disable this on apply.
  tags                           = var.tags

  lifecycle {
    ignore_changes = [internet_ingestion_access_type, internet_query_access_type]
  }
}

# The Audit category records the queries run against the workspace (LAQueryLogs table).
resource "azurerm_monitor_diagnostic_setting" "log_analytics" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_log_analytics_workspace.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_private_link_scope" "this" {
  name                  = "ampls-${var.tags["project"]}-${var.tags["environment"]}"
  resource_group_name   = azurerm_resource_group.this.name
  ingestion_access_mode = "Open" # Note: The barrier pattern will set this to PrivateOnly on apply.
  query_access_mode     = "Open" # Note: The barrier pattern will set this to PrivateOnly on apply.
  tags                  = var.tags

  lifecycle {
    ignore_changes = [ingestion_access_mode, query_access_mode]
  }
}

resource "azurerm_monitor_private_link_scoped_service" "log_analytics" {
  name                = "ampls-scope-log-analytics"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = azurerm_log_analytics_workspace.this.id
}

resource "azurerm_monitor_private_link_scoped_service" "dce" {
  name                = "ampls-scope-dce"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = azurerm_monitor_data_collection_endpoint.this.id
}

resource "azurerm_monitor_data_collection_endpoint" "this" {
  name                = module.naming.monitor_data_collection_endpoint.name_unique
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  kind                = "Linux"
  tags                = var.tags
}

resource "azurerm_monitor_data_collection_rule" "linux" {
  name                        = "${module.naming.monitor_data_collection_rule.name}-linux"
  location                    = var.location
  resource_group_name         = azurerm_resource_group.this.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this.id
  kind                        = "Linux"
  tags                        = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
      name                  = "law-destination"
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog", "Microsoft-Perf"]
    destinations = ["law-destination"]
  }

  data_sources {
    performance_counter {
      name                          = "perfCounters"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "Processor(*)\\% Processor Time",
        "Memory(*)\\% Used Memory",
        "Logical Disk(*)\\% Used Space",
        "Network(*)\\Total Bytes"
      ]
    }

    # Sign-in and sudo activity (sshd, sudo) is logged at the Info level.
    syslog {
      name           = "syslog-auth"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv"]
      log_levels     = ["Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
    }

    syslog {
      name           = "syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["cron", "daemon", "kern", "syslog", "user"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "data_collection_rule_linux" {
  name                       = "Diagnostic Logs"
  target_resource_id         = azurerm_monitor_data_collection_rule.linux.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
#endregion

#region deployment-identity
# Identity used by root sandbox applies. With deployment_identity = "managed_identity" it holds standing roles and is
# attached to the VM alongside the system-assigned identity, which remains the default identity for cloud-init and the
# state backend. With deployment_identity = "oidc" it is not attached to the VM, holds only standing Reader, and is
# reachable only from approved GitHub Actions jobs through federated identity credentials. The operator grants it
# time-bound Contributor and conditioned Role Based Access Control Administrator before each workflow run.
resource "azurerm_user_assigned_identity" "deployment" {
  count = var.deployment_identity != "none" ? 1 : 0

  name                = module.naming.user_assigned_identity.name_unique
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "deployment_identity_contributor" {
  count = var.deployment_identity == "managed_identity" ? 1 : 0

  principal_id         = azurerm_user_assigned_identity.deployment[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Contributor"
  scope                = "/subscriptions/${var.subscription_id}"
}

# Allows the deployment identity to assign and remove only the roles in local.deployment_identity_assignable_roles.
resource "azurerm_role_assignment" "deployment_identity_rbac_admin" {
  count = var.deployment_identity == "managed_identity" ? 1 : 0

  condition            = local.deployment_identity_rbac_condition
  condition_version    = "2.0"
  principal_id         = azurerm_user_assigned_identity.deployment[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Role Based Access Control Administrator"
  scope                = "/subscriptions/${var.subscription_id}"
}

resource "azurerm_role_assignment" "deployment_identity_reader" {
  count = var.deployment_identity == "oidc" ? 1 : 0

  principal_id         = azurerm_user_assigned_identity.deployment[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Reader"
  scope                = "/subscriptions/${var.subscription_id}"
}

resource "azurerm_federated_identity_credential" "deployment_identity_github" {
  for_each = local.github_oidc_subjects

  name                      = "github-${each.key}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value
  user_assigned_identity_id = azurerm_user_assigned_identity.deployment[0].id
}
#endregion

#region public-access-management
resource "terraform_data" "key_vault_access_barrier" {
  input = {
    key_vault_id     = azurerm_key_vault.this.id
    vm_jumpbox_linux = module.vm_jumpbox_linux.key_vault_operations_complete
  }
}

resource "azapi_update_resource" "key_vault_disable_public_access" {
  type        = "Microsoft.KeyVault/vaults@2024-11-01"
  resource_id = terraform_data.key_vault_access_barrier.output.key_vault_id

  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }
}

resource "terraform_data" "storage_access_barrier" {
  input = {
    storage_account_id = azurerm_storage_account.this.id
    storage_container  = azurerm_storage_container.this.id
  }
}

resource "azapi_update_resource" "storage_disable_public_access" {
  type        = "Microsoft.Storage/storageAccounts@2023-05-01"
  resource_id = terraform_data.storage_access_barrier.output.storage_account_id

  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }
}

# Waits for every Azure Monitor write that targets the AMPLS, data collection endpoint or workspace
# (scoped services, private endpoint, DNS zone links, diagnostic settings, jumplinux2 agent and
# associations) before switching the AMPLS to PrivateOnly and closing the workspace to public networks.
resource "terraform_data" "ampls_access_barrier" {
  input = {
    ampls_id                   = azurerm_monitor_private_link_scope.this.id
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
    ampls_scope_log_analytics  = azurerm_monitor_private_link_scoped_service.log_analytics.id
    ampls_scope_dce            = azurerm_monitor_private_link_scoped_service.dce.id
    ampls_private_endpoint     = azurerm_private_endpoint.ampls.id
    ampls_dns_zone_links       = join(",", [for link in azurerm_private_dns_zone_virtual_network_link.ampls : link.id])
    diagnostic_settings = join(",", [
      azurerm_monitor_diagnostic_setting.bastion.id,
      azurerm_monitor_diagnostic_setting.data_collection_rule_linux.id,
      azurerm_monitor_diagnostic_setting.key_vault.id,
      azurerm_monitor_diagnostic_setting.log_analytics.id,
      azurerm_monitor_diagnostic_setting.network_security_group_devops.id,
      azurerm_monitor_diagnostic_setting.public_ip_bastion.id,
      azurerm_monitor_diagnostic_setting.public_ip_nat.id,
      azurerm_monitor_diagnostic_setting.storage_account.id,
      azurerm_monitor_diagnostic_setting.storage_blob.id,
      azurerm_monitor_diagnostic_setting.virtual_network.id,
    ])
    vm_jumpbox_linux = module.vm_jumpbox_linux.log_analytics_operations_complete
  }
}

# Agents must use the AMPLS private endpoint for ingestion, and queries must come from the devops virtual network.
resource "azapi_update_resource" "ampls_disable_public_access" {
  type        = "microsoft.insights/privateLinkScopes@2021-07-01-preview"
  resource_id = terraform_data.ampls_access_barrier.output.ampls_id

  body = {
    properties = {
      accessModeSettings = {
        ingestionAccessMode = "PrivateOnly"
        queryAccessMode     = "PrivateOnly"
      }
    }
  }
}

# AMPLS PrivateOnly alone does not block ingestion or queries from outside the scope; this closes that path too.
resource "azapi_update_resource" "log_analytics_disable_public_access" {
  type        = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  resource_id = terraform_data.ampls_access_barrier.output.log_analytics_workspace_id

  body = {
    properties = {
      publicNetworkAccessForIngestion = "Disabled"
      publicNetworkAccessForQuery     = "Disabled"
    }
  }
}
#endregion

#region modules
module "naming" {
  source                 = "Azure/naming/azurerm"
  version                = "~> 0.4.3"
  suffix                 = [var.tags["project"], var.tags["environment"]]
  unique-include-numbers = true
  unique-length          = 8
}

module "vm_jumpbox_linux" {
  source = "./modules/vm-jumpbox-linux"

  data_collection_endpoint_id        = azurerm_monitor_data_collection_endpoint.this.id
  data_collection_rule_linux_id      = azurerm_monitor_data_collection_rule.linux.id
  enable_github_runner               = var.enable_github_runner
  github_runner_labels               = var.github_runner_labels
  github_runner_token                = var.github_runner_token
  github_runner_token_secret_version = var.github_runner_token_secret_version
  github_runner_token_type           = var.github_runner_token_type
  github_runner_url                  = var.github_runner_url
  key_vault_id                       = azurerm_key_vault.this.id
  key_vault_name                     = azurerm_key_vault.this.name
  location                           = azurerm_resource_group.this.location
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.this.id
  resource_group_name                = azurerm_resource_group.this.name
  storage_account_id                 = azurerm_storage_account.this.id
  subnet_id                          = azurerm_subnet.devops.id
  tags                               = var.tags
  user_assigned_identity_ids         = var.deployment_identity == "managed_identity" ? azurerm_user_assigned_identity.deployment[*].id : []
  vm_jumpbox_linux_size              = var.vm_jumpbox_linux_size

  depends_on = [time_sleep.wait_for_roles]
}
#endregion
