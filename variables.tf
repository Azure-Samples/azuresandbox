variable "aad_tenant_id" {
  type        = string
  description = "The Microsoft Entra tenant id."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.aad_tenant_id))
    error_message = "The 'aad_tenant_id' must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "arm_client_id" {
  type        = string
  description = "The AppId of the service principal used for authenticating with Azure. Must have a 'Contributor' role assignment."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.arm_client_id))
    error_message = "The 'arm_client_id' must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "arm_client_secret" {
  type        = string
  description = "The password for the service principal used for authenticating with Azure. Set interactively or using an environment variable 'TF_VAR_arm_client_secret'."
  sensitive   = true

  validation {
    condition     = length(var.arm_client_secret) >= 8
    error_message = "The 'arm_client_secret' must be at least 8 characters long."
  }
}

variable "location" {
  type        = string
  description = "The name of the Azure Region where resources will be provisioned."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.location))
    error_message = "The 'location' must be a valid Azure region name. It should only contain lowercase letters, numbers, and dashes (e.g., 'eastus', 'westus2', 'centralus')."
  }
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "The 'subscription_id' must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."

  default = { costcenter = "MyCostCenter", division = "MyDivision", group = "MyGroup" }

  validation {
    condition = alltrue([
      for key, value in var.tags :
      can(regex("^[a-zA-Z0-9._-]{1,512}$", key)) &&
      can(regex("^[a-zA-Z0-9._ -]{0,256}$", value))
    ])
    error_message = "Each tag key must be 1-512 characters long and consist of alphanumeric characters, periods (.), underscores (_), or hyphens (-). Each tag value must be 0-256 characters long and consist of alphanumeric characters, periods (.), underscores (_), spaces, or hyphens (-)."
  }
}

variable "user_object_id" {
  type        = string
  description = "The object id of the user in Microsoft Entra ID."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.user_object_id))
    error_message = "The 'user_object_id' must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }

}
