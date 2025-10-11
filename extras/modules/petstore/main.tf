#region data
data "azurerm_client_config" "current" {}
#endregion

#region resources
resource "azurerm_container_app" "this" {
  name                         = "petstore"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  depends_on = [
    null_resource.this,
    azurerm_role_assignment.this
  ]

  template {
    container {
      name   = local.image_name
      image  = "${local.login_server}/${local.image_name}:latest"
      cpu    = "1"
      memory = "2Gi"
    }

    min_replicas = 0
  }

  registry {
    server   = local.login_server
    identity = "system-environment"
  }

  ingress {
    external_enabled           = true
    transport                  = "auto"
    allow_insecure_connections = false
    target_port                = 8080

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

resource "azurerm_container_app_environment" "this" {
  name                           = module.naming.container_app_environment.name_unique
  location                       = var.location
  resource_group_name            = var.resource_group_name
  infrastructure_subnet_id       = var.container_apps_subnet_id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  logs_destination               = "log-analytics"
  internal_load_balancer_enabled = true

  identity {
    type = "SystemAssigned"
  }

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_role_assignment" "this" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app_environment.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
#endregion

#region utility-resources
resource "null_resource" "this" {
  provisioner "local-exec" {
    command     = "$params = @{ ${join(" ", local.local_scripts["configure_registry"].parameters)}}; ./${path.module}/scripts/${local.local_scripts["configure_registry"].name} @params"
    interpreter = ["pwsh", "-Command"]
  }
}
#endregion

#region modules
module "naming" {
  source      = "Azure/naming/azurerm"
  version     = "~> 0.4.2"
  suffix      = [var.tags["project"], var.tags["environment"]]
  unique-seed = var.unique_seed
}
#endregion
