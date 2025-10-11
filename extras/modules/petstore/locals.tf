locals {
  image_name = split("/",split(":", var.source_container_image)[0])[1]
  
  local_scripts = {
    configure_registry = {
      name = "Set-ContainerRegistryConfiguration.ps1"
      parameters = [
        "TenantId = '${data.azurerm_client_config.current.tenant_id}';",
        "SubscriptionId = '${data.azurerm_client_config.current.subscription_id}';",
        "ResourceGroupName = '${var.resource_group_name}';",
        "ContainerRegistryId = '${var.container_registry_id}';",
        "SourceContainerImage = '${var.source_container_image}';",
        "SourceContainerRegistry = '${var.source_container_registry}';",
        "AppId = '${data.azurerm_client_config.current.client_id}';",
        "AppSecret = '${var.arm_client_secret}';"
      ]
    }
  }

  login_server  = "${local.registry_name}.azurecr.io"
  registry_name = split("/", var.container_registry_id)[8]  
}
