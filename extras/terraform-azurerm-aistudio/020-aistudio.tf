resource "random_id" "app_insights_01_name" {
  byte_length = 8
}

resource "azurerm_application_insights" "app_insights_01" {
  name                = "aic-${random_id.app_insights_01_name.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
}

resource "random_id" "container_registry_01_name" {
  byte_length = 8
}

resource "azurerm_container_registry" "container_registry_01" {
  name                     = "acr${random_id.container_registry_01_name.hex}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = "Premium"
  admin_enabled            = true
}

// AIServices
resource "random_id" "aistudio_name" {
  byte_length = 8
}

resource "azapi_resource" "ai_services_01" {
  type      = "Microsoft.CognitiveServices/accounts@2023-10-01-preview"
  name      = "ais-${random_id.aistudio_name.hex}"
  location  = var.location
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    name = "ais-${random_id.aistudio_name.hex}"
    properties = {
      //restore = true
      customSubDomainName = "ais-${random_id.aistudio_name.hex}"
      apiProperties = {
        statisticsEnabled = false
      }
    }
    kind = "AIServices"
    sku = {
      name = var.ai_services_sku
    }
  })

  response_export_values = ["*"]
}

// Azure AI Hub
resource "azapi_resource" "ai_hub_01" {
  type = "Microsoft.MachineLearningServices/workspaces@2024-04-01-preview"
  name = "aih-${random_id.aistudio_name.hex}"
  location = var.location
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    properties = {
      description = "Azure AI hub"
      friendlyName = "aih-${random_id.aistudio_name.hex}"
      storageAccount = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Storage/storageAccounts/${var.storage_account_name}"
      keyVault = var.key_vault_id

      applicationInsights = azurerm_application_insights.app_insights_01.id
      containerRegistry = azurerm_container_registry.container_registry_01.id

      /*Optional: To enable Customer Managed Keys, the corresponding 
      encryption = {
        status = var.encryption_status
        keyVaultProperties = {
            keyVaultArmId = azurerm_key_vault.default.id
            keyIdentifier = var.cmk_keyvault_key_uri
        }
      }
      */
      
    }
    kind = "hub"
  })
}

// Azure AI Project
resource "azapi_resource" "ai_project_01" {
  type = "Microsoft.MachineLearningServices/workspaces@2024-04-01-preview"
  name = "aip-${random_id.aistudio_name.hex}"
  location = var.location
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    properties = {
      description = "Azure AI Project"
      friendlyName = "aip-${random_id.aistudio_name.hex}"
      hubResourceId = azapi_resource.ai_hub_01.id
    }
    kind = "project"
  })
}

resource "azurerm_private_endpoint" "ai_hub_01" {
  name                = "pend-aih-${random_id.aistudio_name.hex}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.vnet_app_01_subnets["snet-privatelink-01"].id
  tags                = var.tags

  private_service_connection {
    name                           = "aih-${random_id.aistudio_name.hex}"
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
