variable "aad_tenant_id" {
  type        = string
  description = "The Microsoft Entra tenant id."
}

variable "ai_services_01_name" {
  type        = string
  description = "The name of the AI services resource ."  
}

variable "app_insights_01_name" {
  type        = string
  description = "The name of the Application Insights workspace."
}

variable "app_service_01_sku" {
  type        = string
  description = "The SKU of the service plan."
  default = "B1"
}

variable "arm_client_id" {
  type        = string
  description = "The AppId of the service principal used for authenticating with Azure. Must have a 'Contributor' role assignment."
}

variable "arm_client_secret" {
  type        = string
  description = "The password for the service principal used for authenticating with Azure. Set interactively or using an environment variable 'TF_VAR_arm_client_secret'."
  sensitive   = true
}

variable "container_registry_01_name" {
  type = string
  default = "The name of the Azure Container Registry."
}

variable "cosmos_db_01_name" {
  type = string
  description = "The name of the CosmosDB database."
  default = "AICallCenterDB"  
}

variable "key_vault_id" {
  type        = string
  description = "The existing key vault where secrets are stored"
}

variable "key_vault_name" {
  type        = string
  description = "The existing key vault where secrets are stored"
}

variable "location" {
  type        = string
  description = "The name of the Azure Region where resources will be provisioned."
}

variable "private_dns_zones" {
  type        = map(any)
  description = "The existing private dns zones defined in the application virtual network."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group for provisioning resources."
}

variable "search_service_01_name" {
  type        = string
  description = "The name of the Azure AI Search service."
  
}

variable "storage_account_name" {
  type        = string
  description = "The name of the shared storage account."
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."
}

variable "vnet_app_01_subnets" {
  type        = map(any)
  description = "The existing subnets defined in the application virtual network."
}

variable "web_app_node_version" {
  type = string
  description = "The node.js runtime version for the web app."
  default = "18-lts"
}
