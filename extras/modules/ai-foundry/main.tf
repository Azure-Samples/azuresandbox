#region data
data "azurerm_client_config" "current" {}
#endregion

#region ai foundry
resource "azurerm_ai_foundry" "this" {
  name                    = "foundry-${var.tags["project"]}-${var.tags["environment"]}"
  location                = var.location
  resource_group_name     = var.resource_group_name
  application_insights_id = azurerm_application_insights.this.id
  container_registry_id   = azurerm_container_registry.this.id
  description             = "Network isolated AI Foundry hub."
  key_vault_id            = var.key_vault_id
  storage_account_id      = var.storage_account_id
  public_network_access   = "Disabled"

  depends_on = [
    azurerm_ai_services.this,
    azurerm_search_service.this
  ]

  identity {
    type = "SystemAssigned"
  }

  managed_network {
    isolation_mode = "AllowInternetOutbound"
  }
}

resource "azurerm_application_insights" "this" {
  name                = module.naming.application_insights.name
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
}

resource "azurerm_container_registry" "this" {
  name                          = module.naming.container_registry.name_unique
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.container_registry_sku
  admin_enabled                 = true
  public_network_access_enabled = false
}

resource "azapi_resource" "ai_services_connection" {
  type                      = "Microsoft.MachineLearningServices/workspaces/connections@2022-10-01"
  name                      = azurerm_ai_services.this.name
  parent_id                 = azurerm_ai_foundry.this.id
  schema_validation_enabled = false
  depends_on                = [azurerm_private_endpoint.ai_services]

  body = {
    properties = {
      authType      = "AAD"
      category      = "AIServices"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        Location   = var.location
        ResourceId = azurerm_ai_services.this.id
      }
      target = "${azurerm_ai_services.this.name}.cognitiveservices.azure.com"
    }
  }
}

resource "azapi_resource" "search_service_connection" {
  type                      = "Microsoft.MachineLearningServices/workspaces/connections@2022-10-01"
  name                      = azurerm_search_service.this.name
  parent_id                 = azurerm_ai_foundry.this.id
  schema_validation_enabled = false
  depends_on                = [azurerm_private_endpoint.search_service]

  body = {
    properties = {
      authType      = "AAD"
      category      = "CognitiveSearch"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_search_service.this.id
        type       = "azure_ai_search"
      }
      target = "${azurerm_search_service.this.name}.search.windows.net"
    }
  }
}
#endregion

#region ai services
resource "azurerm_ai_services" "this" {
  name                  = "ais-${var.tags["project"]}-${var.tags["environment"]}"
  location              = var.location
  resource_group_name   = var.resource_group_name
  sku_name              = var.ai_services_sku
  custom_subdomain_name = "ais-${var.tags["project"]}-${var.tags["environment"]}"
  public_network_access = "Disabled"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "ai_services" {
  for_each = local.ai_services_roles

  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}
#endregion

#region ai search
resource "azurerm_search_service" "this" {
  name                          = module.naming.search_service.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.ai_search_sku
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "search_service" {
  for_each = local.search_service_roles

  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
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
