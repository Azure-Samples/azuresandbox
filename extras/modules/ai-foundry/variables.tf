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

variable "container_registry_sku" {
  type        = string
  description = "The sku name of the Azure Container Registry to create. Choose from: Basic, Standard, Premium. Premium is required for use with AI Studio hubs."
  default     = "Premium"
}

variable "key_vault_id" {
  type        = string
  description = "The existing key vault where secrets are stored"
}

# variable "key_vault_name" {
#   type        = string
#   description = "The existing key vault where secrets are stored"
# }

variable "location" {
  type        = string
  description = "The name of the Azure Region where resources will be provisioned."
}

variable "private_dns_zones" {
  type        = map(any)
  description = "The existing private dns zones defined in the application virtual network."
}

variable "resource_group_id" {
  type        = string
  description = "The id of the existing resource group for provisioning resources."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group for provisioning resources."
}

variable "storage_account_name" {
  type        = string
  description = "The name of the shared storage account."
}

variable "storage_account_id" {
  type        = string
  description = "The id of the shared storage account."
}

variable "storage_file_endpoint" {
  type        = string
  description = "The endpoint of the Azure Files share."
  
}

variable "storage_share_name" {
  type        = string
  description = "The name of the Azure Files share."
}

variable "subnets" {
  type        = map(any)
  description = "The existing subnets defined in the application virtual network."
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."
}

variable "unique_seed" {
  type        = string
  description = "A unique seed to be used for generating unique names for resources. This should be a string that is unique to the environment or deployment."

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.unique_seed))
    error_message = "Must only contain alphanumeric characters and hyphens (-), and must be between 1 and 32 characters long."
  }
}

variable "user_object_id" {
  type       = string
  description = "The object id of the interactive user."
}

