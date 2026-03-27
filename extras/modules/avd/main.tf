#region data
data "azurerm_client_config" "current" {}
#endregion

#region common
resource "azurerm_virtual_desktop_workspace" "this" {
  name                = module.naming.virtual_desktop_workspace.name_unique
  location            = var.location
  resource_group_name = var.resource_group_name
  friendly_name       = "AVD Quickstart Workspace"
}

resource "azurerm_role_assignment" "vm_users" {
  for_each           = toset(var.security_principal_object_ids)
  scope              = var.resource_group_id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.vm_user_login_role}"
  principal_id       = each.value
}
#endregion

#region personal
resource "azurerm_virtual_desktop_application_group" "personal" {
  name                = "${module.naming.virtual_desktop_application_group.name_unique}-personal"
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "Desktop"
  host_pool_id        = azurerm_virtual_desktop_host_pool.personal.id
  friendly_name       = "Personal Desktop"
  description         = "Personal Desktop Application Group created through the AVD Quickstart"
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "personal" {
  workspace_id         = azurerm_virtual_desktop_workspace.this.id
  application_group_id = azurerm_virtual_desktop_application_group.personal.id
}

resource "azurerm_role_assignment" "personal" {
  for_each           = toset(var.security_principal_object_ids)
  scope              = azurerm_virtual_desktop_application_group.personal.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.desktop_virtualization_user_role}"
  principal_id       = each.value
}

resource "azurerm_virtual_desktop_host_pool" "personal" {
  name                     = "${module.naming.virtual_desktop_host_pool.name_unique}-personal"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = 2
  preferred_app_group_type = "Desktop"
  validate_environment     = false
  custom_rdp_properties    = local.rdp_properties
  start_vm_on_connect      = false
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "personal" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.personal.id
  expiration_date = time_offset.this.rfc3339 # Registration token with 2 hour expiration
}
#endregion

#region remoteapp
resource "azurerm_virtual_desktop_application_group" "remoteapp" {
  name                = "${module.naming.virtual_desktop_application_group.name_unique}-remoteapp"
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "RemoteApp"
  host_pool_id        = azurerm_virtual_desktop_host_pool.remoteapp.id
  friendly_name       = "RemoteApp Group"
  description         = "RemoteApp Application Group"
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "remoteapp" {
  workspace_id         = azurerm_virtual_desktop_workspace.this.id
  application_group_id = azurerm_virtual_desktop_application_group.remoteapp.id
}

resource "azurerm_role_assignment" "remoteapp" {
  for_each           = toset(var.security_principal_object_ids)
  scope              = azurerm_virtual_desktop_application_group.remoteapp.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.desktop_virtualization_user_role}"
  principal_id       = each.value
}

resource "azurerm_virtual_desktop_host_pool" "remoteapp" {
  name                     = "${module.naming.virtual_desktop_host_pool.name_unique}-remoteapp"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = 10
  preferred_app_group_type = "RailApplications"
  validate_environment     = false
  custom_rdp_properties    = local.rdp_properties
  start_vm_on_connect      = false
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "remoteapp" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.remoteapp.id
  expiration_date = time_offset.this.rfc3339 # Registration token with 2 hour expiration
}

resource "azurerm_virtual_desktop_application" "edge" {
  name                         = "MicrosoftEdge"
  application_group_id         = azurerm_virtual_desktop_application_group.remoteapp.id
  friendly_name                = "Microsoft Edge"
  description                  = "Microsoft Edge Browser"
  path                         = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
  command_line_argument_policy = "DoNotAllow"
  show_in_portal               = true
  icon_path                    = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
  icon_index                   = 0
}
#endregion

#region utilities
resource "time_offset" "this" {
  offset_hours = 2
}
#endregion

#region modules
module "naming" {
  source      = "Azure/naming/azurerm"
  version     = "~> 0.4.3"
  suffix      = [var.tags["project"], var.tags["environment"]]
  unique-seed = var.unique_seed
}
#endregion
