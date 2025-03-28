variable "location" {
  description = "The Azure region where the resources will be created."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group to be created."
  type        = string
}

variable "subscription_id" {
  description = "The ID of the Azure subscription where the resources will be created."
  type        = string
}

variable "vnet_address_space" {
  description = "The address space for the virtual network."
  type        = string
}

variable "vnet_name" {
  description = "The name of the virtual network to be created."
  type        = string  
}

variable "workspace" {
  description = "The name of the workspace (environment) to be created."
  type = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.workspace)
    error_message = "The workspace must be one of the following: dev, stage, prod."
  }
}
