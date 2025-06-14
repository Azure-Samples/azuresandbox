#region private endpoints
resource "azurerm_private_endpoint" "ai_services" {
  name                = "${module.naming.private_endpoint.name}-ais"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = azurerm_ai_services.this.name
    private_connection_resource_id = azurerm_ai_services.this.id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  private_dns_zone_group {
    name = "ai_services_01"
    private_dns_zone_ids = [
      var.private_dns_zones["privatelink.cognitiveservices.azure.com"].id,
      var.private_dns_zones["privatelink.openai.azure.com"].id
    ]
  }
}

resource "azurerm_private_endpoint" "search_service" {
  name                = "${module.naming.private_endpoint.name}-srch"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = azurerm_search_service.this.name
    private_connection_resource_id = azurerm_search_service.this.id
    is_manual_connection           = false
    subresource_names              = ["searchService"]
  }

  private_dns_zone_group {
    name = "search_service_01"
    private_dns_zone_ids = [
      var.private_dns_zones["privatelink.search.windows.net"].id
    ]
  }
}

resource "azurerm_private_endpoint" "container_registry" {
  name                = "${module.naming.private_endpoint.name}-acr"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = azurerm_container_registry.this.name
    private_connection_resource_id = azurerm_container_registry.this.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name = "container_registry_01"
    private_dns_zone_ids = [
      var.private_dns_zones["privatelink.azurecr.io"].id
    ]
  }
}

resource "azurerm_private_endpoint" "ai_foundry" {
  name                = "${module.naming.private_endpoint.name}-aif"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = azurerm_ai_foundry.this.name
    private_connection_resource_id = azurerm_ai_foundry.this.id
    is_manual_connection           = false
    subresource_names              = ["amlworkspace"]
  }

  private_dns_zone_group {
    name = "aml_workspace_01"
    private_dns_zone_ids = [
      var.private_dns_zones["privatelink.api.azureml.ms"].id,
      var.private_dns_zones["privatelink.notebooks.azure.net"].id
    ]
  }
}
#endregion
