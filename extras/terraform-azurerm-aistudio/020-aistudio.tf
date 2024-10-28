# Adapted from:
# https://learn.microsoft.com/en-us/azure/ai-studio/how-to/create-hub-terraform?tabs=azure-cli
# https://learn.microsoft.com/en-us/azure/ai-studio/how-to/configure-private-link?tabs=cli#create-a-hub-that-uses-a-private-endpoint 
# https://learn.microsoft.com/en-us/azure/ai-studio/how-to/configure-managed-network?tabs=python
# https://learn.microsoft.com/en-us/azure/ai-studio/how-to/develop/create-hub-project-sdk?tabs=azurecli#tabpanel_2_azurecli
# https://learn.microsoft.com/en-us/azure/ai-studio/how-to/secure-data-playground?view=azureml-api-2 
# https://learn.microsoft.com/en-us/azure/ai-studio/how-to/troubleshoot-secure-connection-project 
# https://learn.microsoft.com/en-us/azure/ai-services/cognitive-services-virtual-networks?tabs=portal#use-private-endpoints 
# https://learn.microsoft.com/en-us/azure/ai-services/cognitive-services-custom-subdomains
# https://learn.microsoft.com/en-us/azure/machine-learning/how-to-enable-studio-virtual-network?view=azureml-api-2 
# https://gmusumeci.medium.com/how-to-deploy-azure-ai-search-with-a-private-endpoint-using-terraform-3b63c8b84f41

locals {
  resource_group_id  = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  storage_account_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Storage/storageAccounts/${var.storage_account_name}"
}

resource "random_id" "aistudio_name" {
  byte_length = 8
}

# AI Services
# Note: opted to not use azurerm provider for AI Services to reduce deployment time
resource "azapi_resource" "ai_services_01" {
  type      = "Microsoft.CognitiveServices/accounts@2024-06-01-preview"
  name      = "ais${random_id.aistudio_name.hex}"
  location  = var.location
  parent_id = local.resource_group_id

  identity {
    type = "SystemAssigned"
  }

  body = {
    name = "ais${random_id.aistudio_name.hex}"
    kind = "AIServices"
    properties = {
      customSubDomainName = "ais${random_id.aistudio_name.hex}"
      publicNetworkAccess = "Disabled"
    }
    sku = {
      name = var.ai_services_sku
    }
  }

  response_export_values = ["*"]
}

output "ai_services_01_name" {
  value = azapi_resource.ai_services_01.name
}

resource "azurerm_private_endpoint" "ai_services_01" {
  name                = "pend-ais${random_id.aistudio_name.hex}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.vnet_app_01_subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = "ais${random_id.aistudio_name.hex}"
    private_connection_resource_id = azapi_resource.ai_services_01.id
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

# Azure AI Search
resource "azurerm_search_service" "search_service_01" {
  name                          = "search${random_id.aistudio_name.hex}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.ai_search_sku
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }
}

output "search_service_01_name" {
  value = azurerm_search_service.search_service_01.name
}

resource "azurerm_private_endpoint" "search_service_01" {
  name                = "pend-search${random_id.aistudio_name.hex}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.vnet_app_01_subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = "search${random_id.aistudio_name.hex}"
    private_connection_resource_id = azurerm_search_service.search_service_01.id
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

# Application Insights workspace
resource "azurerm_application_insights" "app_insights_01" {
  name                = "aiw${random_id.aistudio_name.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
}

output "app_insights_01_name" {
  value = azurerm_application_insights.app_insights_01.name
}

# Container Registry
resource "azurerm_container_registry" "container_registry_01" {
  name                          = "acr${random_id.aistudio_name.hex}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.container_registry_sku
  admin_enabled                 = true
  public_network_access_enabled = false
}

output "container_registry_01_name" {
  value = azurerm_container_registry.container_registry_01.name
}

resource "azurerm_private_endpoint" "container_registry_01" {
  name                = "pend-acr${random_id.aistudio_name.hex}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.vnet_app_01_subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = "acr${random_id.aistudio_name.hex}"
    private_connection_resource_id = azurerm_container_registry.container_registry_01.id
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

# AI Studio Hub
resource "azapi_resource" "ai_hub_01" {
  type      = "Microsoft.MachineLearningServices/workspaces@2024-07-01-preview"
  name      = "aih${random_id.aistudio_name.hex}"
  location  = var.location
  parent_id = local.resource_group_id
  depends_on = [
    azurerm_private_endpoint.ai_services_01,
    azurerm_private_endpoint.search_service_01
  ]

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "Hub"
    properties = {
      applicationInsights = azurerm_application_insights.app_insights_01.id
      containerRegistry   = azurerm_container_registry.container_registry_01.id
      description         = "Network isolated Azure AI hub."
      enableDataIsolation = true
      friendlyName        = "aih${random_id.aistudio_name.hex}"
      keyVault            = var.key_vault_id
      managedNetwork = {
        isolationMode = "AllowInternetOutbound"
        outboundRules = {
          AISearch = {
            category = "UserDefined"
            destination = {
              serviceResourceId = azurerm_search_service.search_service_01.id
              sparkEnabled      = false
              subresourceTarget = "searchService"
            }
            type = "PrivateEndpoint"
          }
          AIServices = {
            category = "UserDefined"
            destination = {
              serviceResourceId = azapi_resource.ai_services_01.id
              sparkEnabled      = false
              subresourceTarget = "account"
            }
            type = "PrivateEndpoint"
          }
        }
      }
      publicNetworkAccess      = "Disabled"
      storageAccount           = local.storage_account_id
      systemDatastoresAuthMode = "identity"
    }
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_private_endpoint" "ai_hub_01" {
  name                = "pend-aih${random_id.aistudio_name.hex}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.vnet_app_01_subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = "aih${random_id.aistudio_name.hex}"
    private_connection_resource_id = azapi_resource.ai_hub_01.id
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

resource "azapi_resource" "ai_hub_01_connection_aiservices" {
  type      = "Microsoft.MachineLearningServices/workspaces/connections@2024-07-01-preview"
  name      = "ais${random_id.aistudio_name.hex}"
  parent_id = azapi_resource.ai_hub_01.id
  depends_on = [
    azurerm_private_endpoint.ai_services_01,
    azapi_resource.ai_hub_01
  ]

  body = {
    properties = {
      authType = "AAD"
      category = "AIServices"
      isSharedToAll = true
      metadata = {
        ApiType = "Azure"
        Location = var.location
        ResourceId = azapi_resource.ai_services_01.id
      }
      target = "${azapi_resource.ai_services_01.name}.cognitiveservices.azure.com" 
    }
  }
}

resource "azapi_resource" "ai_hub_01_connection_aisearch" {
  type      = "Microsoft.MachineLearningServices/workspaces/connections@2024-07-01-preview"
  name      = "search${random_id.aistudio_name.hex}"
  parent_id = azapi_resource.ai_hub_01.id
  depends_on = [
    azurerm_private_endpoint.search_service_01,
    azapi_resource.ai_hub_01
  ]

  body = {
    properties = {
      authType = "AAD"
      category = "CognitiveSearch"
      isSharedToAll = true
      metadata = {
        ApiType = "Azure"
        Location = var.location
        ResourceId = azurerm_search_service.search_service_01.id
      }
      target = "${azurerm_search_service.search_service_01.name}.search.windows.net" 
    }
  }
}
