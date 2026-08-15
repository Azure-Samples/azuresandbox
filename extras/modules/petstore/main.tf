#region resources
resource "azurerm_container_app" "this" {
  name                         = "petstore"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_virtual_machine_run_command.build_image,
    azurerm_role_assignment.acr_pull,
    azurerm_private_endpoint.this
  ]

  template {
    container {
      name   = "petstore"
      image  = local.image_reference
      cpu    = "1"
      memory = "2Gi"

      # Application Insights connection string (endpoint/resource pointer). Local
      # (instrumentation key) authentication is disabled on the shared Application
      # Insights resource, so the Java agent authenticates with Microsoft Entra ID
      # using the container app's system-assigned managed identity.
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.app_insights_connection_string
      }

      env {
        name  = "APPLICATIONINSIGHTS_AUTHENTICATION_STRING"
        value = "Authorization=AAD"
      }

      env {
        name  = "APPLICATIONINSIGHTS_ROLE_NAME"
        value = var.appinsights_role_name
      }
    }

    min_replicas = 0
  }

  registry {
    server   = local.login_server
    identity = "system-environment"
  }

  ingress {
    external_enabled           = true # "External" means this container app can be accessed from outside the container app environment
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
  name                               = module.naming.container_app_environment.name_unique
  location                           = var.location
  resource_group_name                = var.resource_group_name
  infrastructure_subnet_id           = var.container_apps_subnet_id
  infrastructure_resource_group_name = "ME_${module.naming.container_app_environment.name_unique}_${var.resource_group_name}_${var.location}"
  log_analytics_workspace_id         = var.log_analytics_workspace_id
  logs_destination                   = "log-analytics"
  internal_load_balancer_enabled     = true

  identity {
    type = "SystemAssigned"
  }

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

#region role-assignments
# The container app environment pulls the instrumented image from the private registry.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app_environment.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# jumplinux1 builds and pushes the instrumented image to the private registry.
resource "azurerm_role_assignment" "acr_push" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPush"
  principal_id         = var.jumplinux1_principal_id
  principal_type       = "ServicePrincipal"
}

# The container app publishes telemetry to the shared Application Insights resource
# using Microsoft Entra ID authentication (local auth is disabled).
resource "azurerm_role_assignment" "app_insights_publisher" {
  scope                = var.app_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_container_app.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
#endregion
#endregion

#region utility-resources
# Build the Application Insights-instrumented image on jumplinux1 (in-VNet Docker
# host) and push it to the network-isolated registry. Running the build inside the
# virtual network keeps the registry private. The run command re-executes whenever
# the generated script changes (e.g. a new agent version); the script itself is
# idempotent and skips the build when the tag already exists in the registry.
resource "azurerm_virtual_machine_run_command" "build_image" {
  name               = "BuildPetstoreImage"
  location           = var.location
  virtual_machine_id = var.jumplinux1_vm_id

  source {
    script = local.build_image_script
  }

  depends_on = [azurerm_role_assignment.acr_push]
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
