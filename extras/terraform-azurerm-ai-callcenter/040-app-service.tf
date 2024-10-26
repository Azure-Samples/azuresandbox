# Adapted from:
#   https://learn.microsoft.com/en-us/azure/app-service/provision-resource-terraform
#   https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration 
#   https://learn.microsoft.com/en-us/azure/app-service/overview-private-endpoint 

# App Service Web App
resource "random_id" "app_service_01" {
  byte_length = 8
}

resource "azurerm_service_plan" "app_service_01" {
  name                = "asp${random_id.app_service_01.hex}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.app_service_01_sku
  tags                = var.tags
}

resource "azurerm_linux_web_app" "ai-app-backend" {
  name                          = "ai-app-backend-${random_id.app_service_01.hex}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = azurerm_service_plan.app_service_01.id
  client_affinity_enabled       = false
  https_only                    = true
  public_network_access_enabled = true
  virtual_network_subnet_id     = var.vnet_app_01_subnets["snet-appservice-01"].id

  site_config {
    always_on           = false
    ftps_state          = "FtpsOnly"
    minimum_tls_version = "1.2"

    application_stack {
      node_version = var.web_app_node_version
    }
  }
}

output "ai-app-backend_hostname" {
  value = azurerm_linux_web_app.ai-app-backend.default_hostname
}

resource "azurerm_linux_web_app" "web-app-frontend" {
  name                          = "web-app-frontend-${random_id.app_service_01.hex}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = azurerm_service_plan.app_service_01.id
  client_affinity_enabled       = false
  https_only                    = true
  public_network_access_enabled = true
  virtual_network_subnet_id     = var.vnet_app_01_subnets["snet-appservice-01"].id

  site_config {
    always_on           = false
    ftps_state          = "FtpsOnly"
    minimum_tls_version = "1.2"

    application_stack {
      node_version = var.web_app_node_version
    }
  }
}

output "web-app-frontend_hostname" {
  value = azurerm_linux_web_app.web-app-frontend.default_hostname
}

