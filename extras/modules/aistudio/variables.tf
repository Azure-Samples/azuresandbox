variable "aad_tenant_id" {
  type        = string
  description = "The Microsoft Entra tenant id."
}

variable "ai_search_sku" {
  type        = string
  description = "The sku name of the Azure AI Search service to create. Choose from: Free, Basic, Standard, StorageOptimized. See https://docs.microsoft.com/en-us/azure/search/search-sku-tier"
  default     = "basic"
}

variable "ai_services_sku" {
  type        = string
  description = "The sku name of the AI Services sku. Choose from: S0, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10. See https://docs.microsoft.com/en-us/azure/cognitive-services/cognitive-services-apis-create-account-cli?tabs=multiservice%2Cwindows"
  default     = "S0"
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

variable "container_registry_sku" {
  type        = string
  description = "The sku name of the Azure Container Registry to create. Choose from: Basic, Standard, Premium. Premium is required for use with AI Studio hubs."
  default     = "Premium"
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

variable "owner_object_id" {
  type       = string
  description = "The object id of the owner of the resources."
}

variable "private_dns_zones" {
  type        = map(any)
  description = "The existing private dns zones defined in the application virtual network."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group for provisioning resources."
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
