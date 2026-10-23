#region data

# Used to get the signed-in operator's object ID for role assignments
data "azurerm_client_config" "current" {}

# Looks up the role definition ID (GUID) for each allow-listed role name.
data "azurerm_role_definition" "deployment_identity_assignable" {
  for_each = toset(local.deployment_identity_assignable_roles)

  name  = each.value
  scope = "/subscriptions/${var.subscription_id}"
}

# Looks up the numeric repository and owner ids used in the GitHub OIDC subjects, when they aren't set in variables.
# The request is anonymous, because a token would be saved in state, so it works only for public repositories and is rate-limited.
# For a private repository, set github_repository_id and github_repository_owner_id in terraform.tfvars.
data "http" "github_repository" {
  count = local.github_repository_lookup ? 1 : 0

  url = "https://api.github.com/repos/${trimprefix(var.github_runner_url, "https://github.com/")}"

  request_headers = {
    Accept                 = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Could not look up ${var.github_runner_url} anonymously (HTTP ${self.status_code}). For a private repository, or if the GitHub API rate limit is exceeded, set github_repository_id and github_repository_owner_id."
    }
  }
}
#endregion

#region key-vault
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

# Audit events include secret reads
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

  lifecycle {
    ignore_changes = [internet_ingestion_access_type, internet_query_access_type]
  }
}

# The "audit" category records the queries run against the workspace (LAQueryLogs table).
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

# User-assigned managed identity (UAMI) used by the Azure Sandbox configuration's azurerm, azapi and azuread providers.
# The VM's (jumplinux2) system-assigned managed identity, not the UAMI, is used for the Terraform state backend.
# The UAMI and its roles depend on the deployment_identity setting:
# - "none" (default): no deployment UAMI is created.
# - "managed_identity": the deployment UAMI is attached to jumplinux2 and holds standing Contributor and Role Based Access Control Administrator, restricted by the allow-list ABAC condition.
# - "oidc": the deployment UAMI is NOT attached to jumplinux2. Instead, it is used by approved GitHub Actions jobs on jumplinux2's self-hosted runner through federated identity credentials.
#   It holds only standing Reader; before approving each workflow run, the operator grants time-bound Contributor and Role Based Access Control Administrator, restricted by the allow-list ABAC condition.
resource "azurerm_user_assigned_identity" "deployment" {
  count = var.deployment_identity != "none" ? 1 : 0

  name                = "${module.naming.user_assigned_identity.name}-deployment"
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

# Trusts GitHub Actions OIDC tokens for the oidc deployment identity, one credential per subject in local.github_oidc_subjects.
# A workflow job can exchange its GitHub token for an Azure token only if the token's issuer, audience and subject exactly match a credential.
# This limits sign-in to jobs from this repository that run in one of the allowed GitHub environments, with no stored secret.
resource "azurerm_federated_identity_credential" "deployment_identity_github" {
  for_each = local.github_oidc_subjects

  name                      = "github-${each.key}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value
  user_assigned_identity_id = azurerm_user_assigned_identity.deployment[0].id
}
#endregion

#region runner-power-state-identity

# UAMI used by the Azure Sandbox deployment workflow's start_runner and stop_runner jobs, which run on GitHub-hosted runners, to start jumplinux2 before an approved run and deallocate it afterwards.
# Created only when deployment_identity is "oidc"; jumplinux2 stays deallocated between runs to reduce cost and exposure.
# The UAMI isn't attached to any VM and is reachable only from jobs in its own GitHub environment, which must differ from the deployment identity's environments, so neither identity's credentials match the other's subjects.
# It holds a standing 'Desktop Virtualization Power On Off Contributor' role assignment scoped to jumplinux2, which allows reading the VM and changing its power state but not running commands, changing extensions or deleting it.
resource "azurerm_user_assigned_identity" "runner_power_state" {
  count = var.deployment_identity == "oidc" ? 1 : 0

  name                = "${module.naming.user_assigned_identity.name}-runner"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "runner_power_state" {
  count = var.deployment_identity == "oidc" ? 1 : 0

  principal_id         = azurerm_user_assigned_identity.runner_power_state[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Desktop Virtualization Power On Off Contributor"
  scope                = module.vm_jumpbox_linux.resource_ids["virtual_machine_jumplinux2"]
}

# Trusts GitHub Actions OIDC tokens for the runner power state UAMI.
# Only one credential is needed, because the UAMI accepts one subject: local.github_runner_power_state_subject, for var.github_runner_power_state_environment.
# A workflow job can exchange its GitHub token for an Azure token only if the token's issuer, audience and subject exactly match the credential.
# This limits sign-in to jobs from this repository that run in the runner power state environment, with no stored secret.
resource "azurerm_federated_identity_credential" "runner_power_state_github" {
  count = var.deployment_identity == "oidc" ? 1 : 0

  name                      = "github-${var.github_runner_power_state_environment}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = local.github_runner_power_state_subject
  user_assigned_identity_id = azurerm_user_assigned_identity.runner_power_state[0].id
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
    ampls_dns_zone_links       = terraform_data.private_dns_zone_links_complete.id
    diagnostic_settings = join(",", [
      azurerm_monitor_diagnostic_setting.bastion.id,
      azurerm_monitor_diagnostic_setting.data_collection_rule_linux.id,
      azurerm_monitor_diagnostic_setting.key_vault.id,
      azurerm_monitor_diagnostic_setting.log_analytics.id,
      join(",", [for setting in azurerm_monitor_diagnostic_setting.network_security_groups : setting.id]),
      azurerm_monitor_diagnostic_setting.storage_account.id,
      azurerm_monitor_diagnostic_setting.storage_blob.id,
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

  data_collection_endpoint_id   = azurerm_monitor_data_collection_endpoint.this.id
  data_collection_rule_linux_id = azurerm_monitor_data_collection_rule.linux.id
  enable_github_runner          = var.enable_github_runner
  github_runner_labels          = var.github_runner_labels
  github_runner_token           = var.github_runner_token
  github_runner_token_version   = var.github_runner_token_version
  github_runner_url             = var.github_runner_url
  key_vault_id                  = azurerm_key_vault.this.id
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  storage_account_id            = azurerm_storage_account.this.id
  subnet_id                     = azurerm_subnet.subnets[var.subnet_devops_name].id
  tags                          = var.tags
  user_assigned_identity_ids    = var.deployment_identity == "managed_identity" ? azurerm_user_assigned_identity.deployment[*].id : []
  vm_jumpbox_linux_size         = var.vm_jumpbox_linux_size

  # The VM needs the NAT gateway for outbound access during cloud-init, and its NIC must not be created while the
  # subnet associations are still being written.
  depends_on = [
    azurerm_subnet_nat_gateway_association.devops,
    time_sleep.wait_for_roles
  ]
}
#endregion

#region checks
# The runner token is needed only when the runner is registered, so a missing token is a warning, not an error.
check "github_runner_token" {
  assert {
    condition     = !var.enable_github_runner || var.github_runner_token != ""
    error_message = "github_runner_token is empty. It is required to register the GitHub Actions runner (on first deployment or when github_runner_token_version changes): run 'source scripts/new-runner-registration-token.sh'. Ignore this warning if the runner is already registered."
  }
}
#endregion
